using System.Data;
using System.Diagnostics;
using System.Security.Cryptography;
using System.Text.Json;
using System.Text.RegularExpressions;
using Microsoft.Data.SqlClient;
using Microsoft.Extensions.Logging.Abstractions;
using TraceParserFunction;

internal static class StorageBenchmark
{
    private const string Instance = @"(localdb)\TPImporterTests_c100bb02";
    private sealed record Sample(string Phase, double Seconds, long DataAllocated, long DataUsed,
        long LogAllocated, long LogUsed);
    private sealed record TableSize(string Name, long Rows, long UsedBytes, long ReservedBytes,
        long NonclusteredUsedBytes);

    public static async Task RunAsync(string input)
    {
        var path = Path.GetFullPath(input);
        var (bytes, hash, groups) = Path.GetFileName(path) switch
        {
            "synthetic-small.etl" => (131072L, "42799A8122EBE56EC89B23FC8B8F8AFA537E775F0925E98DF2D2667E087EF624", 1),
            "synthetic-large.etl" => (79626240L, "944D9187531D294286C18EA92407647B6FF4A9C5E89F57AC76315C71F16F54EE", 30000),
            _ => throw new ArgumentException("Only the two bounded, pinned synthetic fixtures are permitted.")
        };
        if (new FileInfo(path).Length != bytes) throw new InvalidOperationException("Fixture size mismatch.");
        await using (var file = File.OpenRead(path))
            if (Convert.ToHexString(await SHA256.HashDataAsync(file)) != hash)
                throw new InvalidOperationException("Fixture hash mismatch.");

        var database = "TPImporterProtocol_" + Guid.NewGuid().ToString("N");
        var masterString = new SqlConnectionStringBuilder
        {
            DataSource = Instance, InitialCatalog = "master", IntegratedSecurity = true,
            Encrypt = false, Pooling = false, ConnectRetryCount = 0, ConnectTimeout = 15
        }.ConnectionString;
        var connectionString = new SqlConnectionStringBuilder(masterString) { InitialCatalog = database }.ConnectionString;
        using var budget = new CancellationTokenSource(TimeSpan.FromMinutes(15));
        await using var master = new SqlConnection(masterString);
        await master.OpenAsync(budget.Token);
        var created = false;
        string? report = null;
        try
        {
            await Exec(master, $"CREATE DATABASE [{database}];", budget.Token);
            created = true;
            Console.WriteLine($"CREATED {database}");
            await Exec(master, $"ALTER DATABASE [{database}] SET RECOVERY SIMPLE;", budget.Token);
            await using var importerConnection = new SqlConnection(connectionString);
            await importerConnection.OpenAsync(budget.Token);
            foreach (var script in new[] { "Fixture.sql", "safe-importer.sql", "durable-deletion.sql",
                         "sp_DeleteTrace.sql", "duration-import-v2.sql", "Duration units.sql", "duration-aggregates.sql" })
            {
                var sql = await File.ReadAllTextAsync(Path.Combine(AppContext.BaseDirectory, script), budget.Token);
                if (script == "sp_DeleteTrace.sql") sql = sql.Replace("\r\n", "\n");
                foreach (var batch in Regex.Split(sql, @"^\s*GO\s*(?:--[^\r\n]*)?\r?$",
                             RegexOptions.Multiline | RegexOptions.IgnoreCase))
                    if (!string.IsNullOrWhiteSpace(batch)) await Exec(importerConnection, batch, budget.Token);
            }
            // Checkpoint setup; the baseline records any log space still in use.
            await Exec(importerConnection, "CHECKPOINT;", budget.Token);
            await using var resources = await EtlResourceGuard.StartAsync(connectionString, budget);
            await using var monitor = new Monitor(connectionString, budget);
            await monitor.StartAsync();
            var baselineTables = await Tables(importerConnection, budget.Token);
            var timings = new Dictionary<string, double>();
            var clock = Stopwatch.StartNew();
            var id = Guid.NewGuid();
            var name = $"_imports/{id:D}/{Path.GetFileName(path)}";
            using (var register = importerConnection.CreateCommand())
            {
                register.CommandText = """
                    EXEC dbo.tp_RegisterUpload @id,N'account',N'etl-uploads',@name,
                        N'synthetic-storage-benchmark',@ParserVersion='safe-import-v2';
                    """;
                register.Parameters.Add("@id", SqlDbType.UniqueIdentifier).Value = id;
                register.Parameters.Add("@name", SqlDbType.NVarChar, 1024).Value = name;
                await register.ExecuteNonQueryAsync(budget.Token);
            }
            var importer = new SqlImporter(NullLogger<SqlImporter>.Instance);
            var receipt = await importer.BeginImportAsync(importerConnection, "account", "etl-uploads",
                name, "\"synthetic-storage-v1\"", budget.Token, waitForOwnership: false, contentLength: bytes);
            await importer.SetContentHashAsync(importerConnection, Convert.FromHexString(hash));
            var parse = Stopwatch.StartNew();
            var stats = new EtlParser(importer, NullLogger<EtlParser>.Instance)
                .Parse(path, receipt.TraceId, importerConnection);
            timings["ParseAndStageSeconds"] = parse.Elapsed.TotalSeconds;
            if (stats.Staged != groups * 8 || stats.Enter != groups * 2 || stats.Stmt != groups * 2 ||
                stats.Mismatch != 0) throw new InvalidOperationException("Unexpected parser counts.");
            await monitor.CaptureAsync("Ready");
            await AssertCounts(importerConnection, id, groups * 8, groups, "Ready", budget.Token);
            var readyTables = await Tables(importerConnection, budget.Token);

            var promotion = Stopwatch.StartNew();
            await importer.PromoteStageToTraceLines(importerConnection);
            timings["PromotionAndBindingSeconds"] = promotion.Elapsed.TotalSeconds;
            await monitor.CaptureAsync("Finalizing");
            var promotedTables = await Tables(importerConnection, budget.Token);
            var completion = Stopwatch.StartNew();
            await importer.CompleteImportAsync(importerConnection);
            timings["AggregationAndCompletionSeconds"] = completion.Elapsed.TotalSeconds;
            await monitor.CaptureAsync("CompleteBeforeCleanup");
            await AssertCounts(importerConnection, id, groups * 8, groups, "Complete", budget.Token);

            var cleanup = Stopwatch.StartNew();
            await importer.CleanupCompletedAsync(importerConnection);
            timings["StageCleanupSeconds"] = cleanup.Elapsed.TotalSeconds;
            await monitor.CaptureAsync("AfterCleanup");
            var finalTables = await Tables(importerConnection, budget.Token);
            if (finalTables.Where(t => t.Name is "TPImportLines" or "TPImportBinds" or "TPImportThreads")
                .Any(t => t.Rows != 0)) throw new InvalidOperationException("Staging cleanup was incomplete.");
            if (finalTables.Single(t => t.Name == "TraceLines").Rows != groups * 8 ||
                finalTables.Single(t => t.Name == "QueryBindParameters").Rows != groups)
                throw new InvalidOperationException("Final line/bind counts differ.");
            using (var verify = importerConnection.CreateCommand())
            {
                verify.CommandText = """
                    IF EXISTS(SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID('dbo.TraceLines') AND is_disabled=1)
                        THROW 51290,'Disabled index in storage benchmark.',1;
                    IF (SELECT COUNT_BIG(*) FROM dbo.TraceLines)<>@rows
                        OR (SELECT COUNT_BIG(*) FROM dbo.QueryBindParameters)<>@binds
                        OR EXISTS(SELECT 1 FROM dbo.TPImportLines)
                        OR EXISTS(SELECT 1 FROM dbo.TPImportBinds)
                        OR EXISTS(SELECT 1 FROM dbo.TPImportThreads)
                        THROW 51290,'Final row counts or staging cleanup differ.',1;
                    IF (SELECT COUNT_BIG(*) FROM dbo.SessionMetrics)<>1
                        OR EXISTS(SELECT 1 FROM dbo.SessionMetrics
                            WHERE TotalTraceLines IS NULL OR TotalTraceLines<>@rows
                                OR TotalDurationMs IS NULL OR TotalDurationMs<>@ms)
                        THROW 51290,'Physical aggregate count/duration differs.',1;
                    """;
                verify.Parameters.AddWithValue("@rows", groups * 8);
                verify.Parameters.AddWithValue("@binds", groups);
                verify.Parameters.AddWithValue("@ms", groups * 80L);
                await verify.ExecuteNonQueryAsync(budget.Token);
            }
            timings["ImportThroughCleanupSeconds"] = clock.Elapsed.TotalSeconds;
            // Post-checkpoint reclamation is reported separately, not as a natural peak.
            await Exec(importerConnection, "CHECKPOINT;", budget.Token);
            await monitor.CaptureAsync("AfterExplicitCheckpoint");
            var checkpointTables = await Tables(importerConnection, budget.Token);
            await monitor.StopAsync();
            report = JsonSerializer.Serialize(new
            {
                Kind = "IsolatedStorageBenchmark", Status = "Passed", Database = database,
                Fixture = Path.GetFileName(path),
                FixtureBytes = bytes, FixtureSha256 = hash, Groups = groups, TraceLines = groups * 8,
                BindRows = groups, ParserVersion = receipt.ParserVersion, RecoveryModel = "SIMPLE",
                SqlVersion = master.ServerVersion, Timings = timings, Samples = monitor.Samples,
                BaselineTables = baselineTables, ReadyTables = readyTables,
                PromotedTables = promotedTables, FinalTables = finalTables, CheckpointTables = checkpointTables,
                Scope = "Fresh synthetic indexed LocalDB fixture; real parser/staging/promotion/aggregation/cleanup; dbo test connection.",
                Limits = "250ms sampled log/data peaks are lower bounds, not cumulative log bytes. Allocated files differ from active log/used pages. Baseline includes residual setup allocations/log. Empty staging tables can retain used/reserved pages; immediate snapshots do not establish steady-state reclamation. Explicit final checkpoint labeled, not a guarantee of full log reclamation. Tempdb, Azure/storage/network/host costs, retry overhead, original partner workload and native parity are not measured. Repeated strings, one session/thread."
            });
        }
        finally
        {
            if (created)
            {
                await Exec(master, $"ALTER DATABASE [{database}] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [{database}];", CancellationToken.None);
                await Exec(master, $"IF DB_ID(N'{database}') IS NOT NULL THROW 51290,'Benchmark database remains after cleanup.',1;", CancellationToken.None);
                Console.WriteLine($"CLEANED {database}");
            }
        }
        // Report success only after both monitors dispose successfully and the owned database is absent.
        Console.WriteLine(report ?? throw new InvalidOperationException("Benchmark report was not produced."));
    }

    private static async Task Exec(SqlConnection db, string sql, CancellationToken ct)
    {
        using var cmd = new SqlCommand(sql, db) { CommandTimeout = 120 };
        await cmd.ExecuteNonQueryAsync(ct);
    }

    private static async Task AssertCounts(SqlConnection db, Guid id, int rows, int binds, string phase, CancellationToken ct)
    {
        using var cmd = db.CreateCommand();
        cmd.CommandText = """
            IF NOT EXISTS(SELECT 1 FROM dbo.TPImportReceipts WHERE ImportId=@id AND Phase=@phase
                AND ExpectedRows=@rows AND ExpectedBinds=@binds AND ParserVersion='safe-import-v2')
                THROW 51290,'Unexpected storage benchmark receipt.',1;
            """;
        cmd.Parameters.AddWithValue("@id", id);
        cmd.Parameters.AddWithValue("@phase", phase);
        cmd.Parameters.AddWithValue("@rows", rows);
        cmd.Parameters.AddWithValue("@binds", binds);
        await cmd.ExecuteNonQueryAsync(ct);
    }

    private static async Task<List<TableSize>> Tables(SqlConnection db, CancellationToken ct)
    {
        using var cmd = db.CreateCommand();
        cmd.CommandText = """
            SELECT t.name,SUM(CASE WHEN p.index_id IN (0,1) THEN p.row_count ELSE 0 END),
                SUM(p.used_page_count)*8192,SUM(p.reserved_page_count)*8192,
                SUM(CASE WHEN p.index_id>1 THEN p.used_page_count ELSE 0 END)*8192
            FROM sys.tables t JOIN sys.dm_db_partition_stats p ON p.object_id=t.object_id
            WHERE t.is_ms_shipped=0 GROUP BY t.name ORDER BY t.name;
            """;
        var values = new List<TableSize>();
        using var reader = await cmd.ExecuteReaderAsync(ct);
        while (await reader.ReadAsync(ct))
            values.Add(new(reader.GetString(0), reader.GetInt64(1), reader.GetInt64(2),
                reader.GetInt64(3), reader.GetInt64(4)));
        return values;
    }

    private sealed class Monitor(string connectionString, CancellationTokenSource budget) : IAsyncDisposable
    {
        private readonly SqlConnection connection = new(connectionString);
        private readonly CancellationTokenSource stop = new();
        private readonly SemaphoreSlim gate = new(1);
        private readonly Stopwatch clock = Stopwatch.StartNew();
        private Task? loop;
        public List<Sample> Samples { get; } = [];

        public async Task StartAsync()
        {
            await connection.OpenAsync(budget.Token);
            await CaptureAsync("Baseline");
            loop = Task.Run(async () =>
            {
                try
                {
                    while (true)
                    {
                        await Task.Delay(250, stop.Token);
                        await CaptureAsync("Interval");
                    }
                }
                catch (OperationCanceledException) when (stop.IsCancellationRequested) { }
                catch { budget.Cancel(); throw; }
            });
        }

        public async Task CaptureAsync(string phase)
        {
            await gate.WaitAsync(budget.Token);
            try
            {
                using var cmd = connection.CreateCommand();
                cmd.CommandTimeout = 5;
                cmd.CommandText = """
                    SELECT
                      (SELECT SUM(CONVERT(bigint,size))*8192 FROM sys.database_files WHERE type=0),
                      (SELECT SUM(CONVERT(bigint,FILEPROPERTY(name,'SpaceUsed')))*8192 FROM sys.database_files WHERE type=0),
                      total_log_size_in_bytes,used_log_space_in_bytes
                    FROM sys.dm_db_log_space_usage;
                    """;
                using var reader = await cmd.ExecuteReaderAsync(budget.Token);
                if (!await reader.ReadAsync(budget.Token)) throw new InvalidOperationException("No log-space sample.");
                Samples.Add(new(phase, clock.Elapsed.TotalSeconds, reader.GetInt64(0), reader.GetInt64(1),
                    reader.GetInt64(2), reader.GetInt64(3)));
            }
            finally { gate.Release(); }
        }

        public async Task StopAsync()
        {
            stop.Cancel();
            if (loop is not null) await loop;
        }

        public async ValueTask DisposeAsync()
        {
            try { await StopAsync(); }
            finally { await connection.DisposeAsync(); stop.Dispose(); gate.Dispose(); }
        }
    }
}
