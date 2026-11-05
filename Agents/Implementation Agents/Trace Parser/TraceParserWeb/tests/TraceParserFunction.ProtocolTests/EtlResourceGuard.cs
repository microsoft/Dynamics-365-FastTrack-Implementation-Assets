using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text.Json;
using System.Text.RegularExpressions;
using Microsoft.Data.SqlClient;

// Read-only monitoring of this disposable fixture and host headroom. Cancellation
// joins the real parser consumer; it never kills SQL/processes or changes settings.
internal sealed class EtlResourceGuard : IAsyncDisposable
{
    private const long GiB=1L<<30;
    private readonly SqlConnection _connection;
    private readonly CancellationTokenSource _operation;
    private readonly CancellationTokenSource _stop=new();
    private readonly Process _process=Process.GetCurrentProcess();
    private readonly Stopwatch _clock=Stopwatch.StartNew();
    private Task? _monitor;
    private string? _failure;
    private int _samples;
    private long _managedPeak,_privatePeak,_workingPeak,_dataPeak,_usedDataPeak,_logPeak;
    private ulong _minimumFreeMemory=ulong.MaxValue;
    private long _minimumDiskFree=long.MaxValue;

    private EtlResourceGuard(string connectionString,CancellationTokenSource operation)
    {
        var cs=new SqlConnectionStringBuilder(connectionString);
        if(cs.DataSource!=@"(localdb)\TPImporterTests_c100bb02" ||
            !Regex.IsMatch(cs.InitialCatalog,"^TPImporterProtocol_[0-9a-f]{32}$"))
            throw new InvalidOperationException("Unsafe resource-monitor target.");
        _connection=new SqlConnection(connectionString);
        _operation=operation;
    }

    public static async Task<EtlResourceGuard> StartAsync(string connectionString,CancellationTokenSource operation)
    {
        var guard=new EtlResourceGuard(connectionString,operation);
        try
        {
            await guard._connection.OpenAsync(operation.Token);
            await guard.SampleAsync(initial:true);
            guard._monitor=Task.Run(guard.MonitorAsync);
            return guard;
        }
        catch
        {
            await guard.DisposeAsync();
            throw;
        }
    }

    private async Task MonitorAsync()
    {
        try
        {
            while(true)
            {
                await Task.Delay(TimeSpan.FromSeconds(1),_stop.Token);
                await SampleAsync(initial:false);
            }
        }
        catch(OperationCanceledException) when(_stop.IsCancellationRequested) { }
        catch(Exception ex)
        {
            _failure=ex.Message;
            Console.WriteLine("RESOURCE_GUARD_STOP: "+ex.Message);
            _operation.Cancel();
        }
    }

    private async Task SampleAsync(bool initial)
    {
        var memory=new MemoryStatus { Length=(uint)Marshal.SizeOf<MemoryStatus>() };
        if(!GlobalMemoryStatusEx(ref memory))
            throw new InvalidOperationException("Unable to verify system memory headroom.");
        _process.Refresh();
        var managed=GC.GetTotalMemory(false);
        _managedPeak=Math.Max(_managedPeak,managed);
        _privatePeak=Math.Max(_privatePeak,_process.PrivateMemorySize64);
        _workingPeak=Math.Max(_workingPeak,_process.WorkingSet64);
        _minimumFreeMemory=Math.Min(_minimumFreeMemory,memory.AvailablePhysical);
        if(memory.AvailablePhysical<(ulong)((initial?8:4)*GiB) ||
            managed>2*GiB || _process.PrivateMemorySize64>3*GiB || _process.WorkingSet64>3*GiB)
            throw new InvalidOperationException("Memory safety threshold reached; cancelling only this test.");

        long data=0,used=0,log=0;
        using var command=_connection.CreateCommand();
        command.CommandTimeout=5;
        command.CommandText="SELECT type,CONVERT(bigint,size)*8192,CONVERT(bigint,FILEPROPERTY(name,'SpaceUsed'))*8192,physical_name FROM sys.database_files;";
        using var reader=await command.ExecuteReaderAsync(_stop.Token);
        while(await reader.ReadAsync(_stop.Token))
        {
            if(reader.GetByte(0)==0)
            {
                data+=reader.GetInt64(1);
                if(!reader.IsDBNull(2)) used+=reader.GetInt64(2);
            }
            else if(reader.GetByte(0)==1) log+=reader.GetInt64(1);
            var free=new DriveInfo(Path.GetPathRoot(reader.GetString(3))!).AvailableFreeSpace;
            _minimumDiskFree=Math.Min(_minimumDiskFree,free);
            if(free<(initial?32:16)*GiB)
                throw new InvalidOperationException("Database-drive free-space safety threshold reached; cancelling only this test.");
        }
        _dataPeak=Math.Max(_dataPeak,data);
        _usedDataPeak=Math.Max(_usedDataPeak,used);
        _logPeak=Math.Max(_logPeak,log);
        _samples++;
        if(data>=8*GiB || data+log>=16*GiB)
            throw new InvalidOperationException("Owned database growth safety threshold reached before Express's 10 GiB data limit.");
    }

    public async ValueTask DisposeAsync()
    {
        _stop.Cancel();
        if(_monitor is not null) await _monitor;
        await _connection.DisposeAsync();
        _process.Dispose();
        _stop.Dispose();
        Console.WriteLine(JsonSerializer.Serialize(new {
            Kind="EtlResourceSamples",ElapsedSeconds=_clock.Elapsed.TotalSeconds,Samples=_samples,
            ManagedPeakBytes=_managedPeak,PrivatePeakBytes=_privatePeak,WorkingSetPeakBytes=_workingPeak,
            DataAllocatedPeakBytes=_dataPeak,DataUsedPeakBytes=_usedDataPeak,LogAllocatedPeakBytes=_logPeak,
            MinimumAvailablePhysicalBytes=_minimumFreeMemory,MinimumDatabaseDriveFreeBytes=_minimumDiskFree,
            Aborted=_failure is not null,Failure=_failure,
            Limits="1s samples; managed 2 GiB, process private/working 3 GiB, physical free 8 GiB initially/4 GiB thereafter, disk free 32 GiB initially/16 GiB thereafter, data allocated <8 GiB, data+log allocated <16 GiB. No resource/settings changes."
        }));
        if(_failure is not null) throw new InvalidOperationException("Resource guard blocked completion: "+_failure);
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct MemoryStatus
    {
        public uint Length,MemoryLoad;
        public ulong TotalPhysical,AvailablePhysical,TotalPageFile,AvailablePageFile,
            TotalVirtual,AvailableVirtual,AvailableExtendedVirtual;
    }

    [DllImport("kernel32.dll",SetLastError=true)]
    [return:MarshalAs(UnmanagedType.Bool)]
    private static extern bool GlobalMemoryStatusEx(ref MemoryStatus status);
}
