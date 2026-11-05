using System.Threading.Channels;
using Microsoft.Data.SqlClient;

namespace TraceParserFunction;

/// <summary>Owns the parser's SQL consumer until it has stopped, including producer failure.</summary>
internal sealed class StageBatchWriter : IDisposable
{
    private readonly SqlImporter _importer;
    private readonly CancellationToken _invocationToken;
    private readonly CancellationTokenSource _stop;
    private readonly Channel<(List<StageRow> Rows, List<BindParamRow> Binds)> _channel =
        Channel.CreateBounded<(List<StageRow>, List<BindParamRow>)>(
            new BoundedChannelOptions(3) { FullMode = BoundedChannelFullMode.Wait });
    private readonly Task _consumer;
    private Exception? _failure;
    private bool _disposed;

    public CancellationToken Token => _stop.Token;
    internal bool ConsumerCompleted => _consumer.IsCompleted;

    public StageBatchWriter(SqlImporter importer, SqlConnection connection)
    {
        _importer = importer;
        _invocationToken = importer.ImportCancellation;
        _stop = CancellationTokenSource.CreateLinkedTokenSource(_invocationToken);
        importer.UseCancellation(_stop.Token);
        _consumer = Task.Run(async () =>
        {
            try
            {
                await foreach (var batch in _channel.Reader.ReadAllAsync(_stop.Token))
                    importer.FlushStageBatch(connection, batch.Rows, batch.Binds);
            }
            catch (Exception ex) { _failure = ex; _stop.Cancel(); }
        });
    }

    public void Write(List<StageRow> rows, List<BindParamRow> binds)
    {
        rows = rows.Select(row => DurationContract.Encode(row, _importer.ParserVersion)).ToList();
        try { _channel.Writer.WriteAsync((rows, binds), _stop.Token).AsTask().GetAwaiter().GetResult(); }
        catch (OperationCanceledException) when (_failure is not null && !_invocationToken.IsCancellationRequested)
        { throw new InvalidOperationException("SQL stage consumer failed.", _failure); }
    }

    public void Complete()
    {
        _channel.Writer.Complete();
        _consumer.GetAwaiter().GetResult();
        _invocationToken.ThrowIfCancellationRequested();
        if (_failure is not null) throw new InvalidOperationException("SQL stage consumer failed.", _failure);
    }

    public void CheckCancellation()
    {
        if (!_stop.IsCancellationRequested) return;
        _invocationToken.ThrowIfCancellationRequested();
        if (_failure is not null) throw new InvalidOperationException("SQL stage consumer failed.", _failure);
        _stop.Token.ThrowIfCancellationRequested();
    }

    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;
        _channel.Writer.TryComplete();
        _stop.Cancel();
        try { _consumer.GetAwaiter().GetResult(); }
        finally
        {
            _importer.UseCancellation(_invocationToken);
            _stop.Dispose();
        }
    }
}
