using System.Data;
using System.Diagnostics;
using System.Text.Json;
using Microsoft.Data.SqlClient;
using Microsoft.Extensions.Options;
using TraceParserWeb.Services;
using static DeletionChecks;

static class DeletionSqlChecks
{
    const string Server = @"(localdb)\TPImporterTests_c100bb02";
    const string Prefix = "TPBoundedDelete_c100bb02_";
    static readonly string[] Tables = { "QueryBindParameters", "XppParameters", "TraceLines",
        "TopMethods", "StageTraceLines", "SessionMetrics", "TopMethodsBySession",
        "UserSessionProcessThreads", "UserSessions", "MethodAotLayers", "TraceInformations", "Traces" };

    public static async Task RunAsync()
    {
        var database = Prefix + Guid.NewGuid().ToString("N");
        var created = false;
        var cleaned = false;
        var checks = 0;
        var phases = new Dictionary<string, (int Batches, long Rows)>();
        var providerCancellations = new List<object>();
        var watch = Stopwatch.StartNew();
        double populatedSeconds = 0;
        double maxBatchSeconds = 0;
        string? tlsResult = null;
        await using var master = await OpenAsync("master");
        try
        {
            await GuardAsync(master, "master");
            Check(database.StartsWith(Prefix, StringComparison.Ordinal) && database.Length == Prefix.Length + 32,
                "Unsafe integration database name");
            await ExecuteAsync(master, $"CREATE DATABASE [{database}]");
            created = true;
            await using (var connection = await OpenAsync(database))
            {
                await GuardAsync(connection, database);
                await ExecuteAsync(connection, Schema);
                var sqlPath = Path.GetFullPath(Path.Combine(AppContext.BaseDirectory,
                    "..", "..", "..", "..", "..", "sql", "sp_DeleteTrace.sql"));
                var migration = await File.ReadAllTextAsync(sqlPath);
                await ExecuteAsync(connection, "CREATE PROCEDURE dbo.sp_DeleteTrace @TraceId int AS SELECT 17 AS Sentinel");
                var original = (string)(await ScalarAsync(connection, "SELECT OBJECT_DEFINITION(OBJECT_ID('dbo.sp_DeleteTrace'))"))!;
                await ExecuteAsync(connection, "EXEC sp_rename 'dbo.XppParameters.TraceLineId', 'UnexpectedColumn', 'COLUMN'");
                await ExpectSqlAsync(() => ExecuteAsync(connection, migration), 51001);
                Check((string)(await ScalarAsync(connection, "SELECT OBJECT_DEFINITION(OBJECT_ID('dbo.sp_DeleteTrace'))"))! == original,
                    "Failed preflight changed existing procedure");
                await ExecuteAsync(connection, "EXEC sp_rename 'dbo.XppParameters.UnexpectedColumn', 'TraceLineId', 'COLUMN'");
                checks++;
                await ExecuteAsync(connection, "CREATE TRIGGER dbo.SyntheticTrigger ON dbo.Traces AFTER DELETE AS RETURN");
                await ExpectSqlAsync(() => ExecuteAsync(connection, migration), 51002);
                await ExecuteAsync(connection, "DROP TRIGGER dbo.SyntheticTrigger");
                checks++;
                await ExecuteAsync(connection, "CREATE TABLE dbo.UnexpectedChild (TraceId int REFERENCES dbo.Traces(TraceId))");
                await ExpectSqlAsync(() => ExecuteAsync(connection, migration), 51003);
                await ExecuteAsync(connection, "DROP TABLE dbo.UnexpectedChild");
                checks++;
                foreach (var table in new[] { "MethodAotLayers", "TraceInformations" })
                {
                    await ExecuteAsync(connection, $"EXEC sp_rename 'dbo.{table}.TraceId', 'UnexpectedTraceId', 'COLUMN'");
                    await ExpectSqlAsync(() => ExecuteAsync(connection, migration), 51001);
                    await ExecuteAsync(connection, $"EXEC sp_rename 'dbo.{table}.UnexpectedTraceId', 'TraceId', 'COLUMN'");
                    checks++;
                    var key = table == "MethodAotLayers" ? "Id" : "InfoId";
                    await ExecuteAsync(connection, $"CREATE TABLE dbo.UnexpectedChild (Id int REFERENCES dbo.{table}({key}))");
                    await ExpectSqlAsync(() => ExecuteAsync(connection, migration), 51003);
                    await ExecuteAsync(connection, "DROP TABLE dbo.UnexpectedChild");
                    checks++;
                }
                await ExecuteAsync(connection, "EXEC sp_rename 'dbo.TopMethods.EndUspId', 'UnexpectedEndpoint', 'COLUMN'");
                await ExpectSqlAsync(() => ExecuteAsync(connection, migration), 51001);
                await ExecuteAsync(connection, "EXEC sp_rename 'dbo.TopMethods.UnexpectedEndpoint', 'EndUspId', 'COLUMN'");
                checks++;
                await ExecuteAsync(connection, """
                    DROP TABLE dbo.TraceInformations;
                    CREATE TABLE dbo.TraceInformations (InfoId int NOT NULL PRIMARY KEY,
                        TraceId int NOT NULL REFERENCES dbo.Traces(TraceId)) AS NODE;
                    """);
                await ExpectSqlAsync(() => ExecuteAsync(connection, migration), 51001);
                await ExecuteAsync(connection, """
                    DROP TABLE dbo.TraceInformations;
                    CREATE TABLE dbo.TraceInformations (InfoId int NOT NULL PRIMARY KEY, TraceId int NOT NULL REFERENCES dbo.Traces(TraceId),
                        SystemName nvarchar(200) NULL, UserName nvarchar(200) NULL, AxVersion nvarchar(50) NULL, TraceSessionNotes nvarchar(max) NULL);
                    """);
                checks++;
                checks += await CheckCompositeGuardsAsync(connection, migration);
                await ExecuteAsync(connection, migration);
                await ExecuteAsync(connection, """
                    CREATE USER BoundedDeleteExecutor WITHOUT LOGIN;
                    GRANT EXECUTE ON OBJECT::dbo.sp_DeleteTrace TO BoundedDeleteExecutor;
                    GRANT SELECT ON OBJECT::dbo.Traces TO BoundedDeleteExecutor;
                    """);
                await ExecuteAsync(connection, Seed);
                var unrelated = await SnapshotUnrelatedAsync(connection);
                Check((int)(await ScalarAsync(connection,
                    "SELECT COUNT(*) FROM dbo.UserSessions WHERE SessionId = 1 AND TraceId IN (1,2)"))! == 2,
                    "Fixture did not exercise the same SessionId in different traces");
                checks++;
                Check((int)(await ScalarAsync(connection, "SELECT COUNT(*) FROM dbo.TraceLines WHERE UserSessionProcessThreadId = 1"))! == 250001,
                    "Large synthetic fixture missing");
                checks++;

                await ExecuteAsync(connection, "EXECUTE AS USER = 'BoundedDeleteExecutor'");
                try
                {
                    await ExpectSqlAsync(() => ExecuteAsync(connection, "DELETE FROM dbo.Traces WHERE TraceId = -1"), 229);
                    await ExpectSqlAsync(() => ExecuteAsync(connection, "SELECT TOP (1) * FROM dbo.TraceLines"), 229);
                    checks++;
                    foreach (var batchSize in new[] { 0, -1, 10001 })
                        await ExpectSqlAsync(() => DeleteAsync(connection, 1, batchSize), 51011);
                    await ExpectSqlAsync(() => DeleteAsync(connection, 0, 2), 51010);
                    checks++;

                    // Actual partial deletion, then caller cancellation, then retry.
                    using var stop = new CancellationTokenSource();
                    var store = new CallbackStore((id, ct) => SqlTraceDeletionStore.ExecuteBatchAsync(connection, id, ct));
                    try
                    {
                        await DeletionChecks.Service(store).DeleteTraceAsync(1, stop.Token, p =>
                        {
                            Check(!p.Complete && p.ConfirmedRowsDeleted > 0, "Populated trace completed too early");
                            if (p.Batches == 3) stop.Cancel();
                            return Task.CompletedTask;
                        });
                        throw new Exception("Expected partial caller cancellation");
                    }
                    catch (OperationCanceledException ex) { Check(ex.Message.Contains("partial"), "Missing partial feedback"); }
                    Check((int)(await ScalarAsync(connection, "SELECT COUNT(*) FROM dbo.Traces WHERE TraceId = 1"))! == 1,
                        "Cancelled trace root disappeared");
                    checks++;
                }
                finally { await ExecuteAsync(connection, "REVERT"); }

                // Attention during a blocked statement must not leak an open transaction or lose the root.
                await using (var blocker = await OpenAsync(database))
                {
                    await ExecuteAsync(blocker, "BEGIN TRAN; SELECT TraceId FROM dbo.Traces WITH (XLOCK, HOLDLOCK) WHERE TraceId = 1");
                    await using var cancelled = await OpenAsync(database);
                    await ExecuteAsync(cancelled, "EXECUTE AS USER = 'BoundedDeleteExecutor'");
                    using var stop = new CancellationTokenSource(TimeSpan.FromMilliseconds(250));
                    var interrupted = false;
                    try { await SqlTraceDeletionStore.ExecuteBatchAsync(cancelled, 1, stop.Token); }
                    catch (Exception ex) when (ex is OperationCanceledException or SqlException)
                    {
                        Check(stop.IsCancellationRequested && TraceDeletionService.IsCancellation(ex),
                            "Provider cancellation was misclassified");
                        providerCancellations.Add(CancellationEvidence("BlockedRoot", ex));
                        interrupted = true;
                    }
                    Check(interrupted, "Blocked SQL did not cancel");
                    // Disposing a cancelled pooled connection rolls back any attention-interrupted transaction.
                    await cancelled.CloseAsync();
                    await ExecuteAsync(blocker, "ROLLBACK");
                    checks++;
                }

                var deleteWatch = Stopwatch.StartNew();
                await ExecuteAsync(connection, "EXECUTE AS USER = 'BoundedDeleteExecutor'");
                try
                {
                    using var budget = new CancellationTokenSource(TimeSpan.FromMinutes(3));
                    for (var batch = 0; ; batch++)
                    {
                        Check(batch < 1500, "Deletion did not converge within fixture limit");
                        var batchWatch = Stopwatch.StartNew();
                        var result = await SqlTraceDeletionStore.ExecuteBatchAsync(connection, 1, budget.Token);
                        maxBatchSeconds = Math.Max(maxBatchSeconds, batchWatch.Elapsed.TotalSeconds);
                        Check(result.RowsDeleted is >= 0 and <= 2000 && result.Phase is not null,
                            "Default batch exceeded row bound or lost progress contract");
                        var previous = phases.GetValueOrDefault(result.Phase!);
                        phases[result.Phase!] = (previous.Batches + 1, previous.Rows + result.RowsDeleted!.Value);
                        if (!result.HasMore) break;
                    }
                    populatedSeconds = deleteWatch.Elapsed.TotalSeconds;
                    Check(Tables.All(phases.ContainsKey), "Not all deletion phases ran");
                    Check(phases["SessionMetrics"].Batches > 1 && phases["UserSessions"].Batches > 1
                        && phases["UserSessionProcessThreads"].Batches > 1
                        && phases["TopMethodsBySession"].Batches > 1 && phases["StageTraceLines"].Batches > 1
                        && phases["MethodAotLayers"].Batches > 1 && phases["TraceInformations"].Batches > 1,
                        "Parent/aggregate/staging phases were not exercised across batches");
                    checks++;
                    var missing = await SqlTraceDeletionStore.ExecuteBatchAsync(connection, 1, default);
                    Check(!missing.HasMore && missing.RowsDeleted == 0 && missing.Phase == "Complete", "Repeat deletion was not idempotent");
                    var empty = await SqlTraceDeletionStore.ExecuteBatchAsync(connection, 3, default);
                    Check(!empty.HasMore && empty.RowsDeleted == 1, "Empty trace did not complete");
                    checks++;
                }
                finally { await ExecuteAsync(connection, "REVERT"); }
                Check(unrelated == await SnapshotUnrelatedAsync(connection), "Unrelated trace/descendants changed");
                foreach (var table in Tables)
                    Check((int)(await ScalarAsync(connection, $"SELECT COUNT(*) FROM dbo.[{table}]"))! == 1,
                        $"Requested trace left rows in {table}");
                checks++;
                Check((int)(await ScalarAsync(connection, "SELECT COUNT(*) FROM dbo.MethodNames"))! == 1
                    && (int)(await ScalarAsync(connection, """
                        SELECT COUNT(*) FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.TraceLines')
                        AND name IN ('IX_USP_METHOD', 'IX_TL_USPT_Aggregation') AND is_disabled = 1
                        """))! == 2, "Deletion changed a shared dimension or disabled secondary indexes");
                checks++;
                checks += await CheckAmbiguousMethodsAsync(connection);

                // Caller-specified bounds include parameter fan-out and final root cleanup.
                await ExecuteAsync(connection, SmallSeed);
                var beforeCancellation = (int)(await ScalarAsync(connection, "SELECT COUNT(*) FROM dbo.TopMethods WHERE BeginUspId = 4"))!;
                // Test-only trigger pauses AFTER mutation, so attention tests rollback, not just a blocked read.
                await ExecuteAsync(connection, """
                    CREATE TRIGGER dbo.PauseSyntheticDelete ON dbo.TopMethods AFTER DELETE AS
                    BEGIN
                        WAITFOR DELAY '00:00:30';
                    END
                    """);
                try
                {
                    await using (var interrupted = await OpenAsync(database))
                    {
                        await ExecuteAsync(interrupted, "EXECUTE AS USER = 'BoundedDeleteExecutor'");
                        using var stop = new CancellationTokenSource(TimeSpan.FromSeconds(15));
                        var session = Convert.ToInt32(await ScalarAsync(interrupted, "SELECT @@SPID"));
                        var deletion = SqlTraceDeletionStore.ExecuteBatchAsync(interrupted, 4, stop.Token);
                        var waiting = false;
                        for (var attempt = 0; attempt < 100; attempt++)
                        {
                            // Local fixture admin only: prove the AFTER DELETE trigger is running
                            // before cancellation, rather than racing against the final commit.
                            if (await ScalarAsync(connection,
                                $"SELECT wait_type FROM sys.dm_exec_requests WHERE session_id = {session}") is string wait
                                && wait == "WAITFOR")
                            {
                                waiting = true;
                                break;
                            }
                            await Task.Delay(25);
                        }
                        Check(waiting, "Synthetic post-mutation WAITFOR was not reached");
                        stop.Cancel();
                        try
                        {
                            await deletion;
                            throw new Exception("Expected attention during synthetic post-delete delay");
                        }
                        catch (Exception ex) when (ex is OperationCanceledException or SqlException)
                        {
                            Check(stop.IsCancellationRequested && TraceDeletionService.IsCancellation(ex),
                                "Post-mutation cancellation did not produce a provider cancellation");
                            providerCancellations.Add(CancellationEvidence("AfterMutation", ex));
                        }
                    }
                    Check((int)(await ScalarAsync(connection, "SELECT COUNT(*) FROM dbo.TopMethods WHERE BeginUspId = 4"))! == beforeCancellation,
                        "Interrupted statement committed partial mutation");
                    checks++;
                }
                finally { await ExecuteAsync(connection, "DROP TRIGGER dbo.PauseSyntheticDelete"); }
                var boundedRows = 0;
                for (var i = 0; ; i++)
                {
                    Check(i < 60, "Small-batch trace did not converge");
                    var before = await CountRowsAsync(connection);
                    var result = await DeleteAsync(connection, 4, 2);
                    Check(result.RowsDeleted is >= 0 and <= 2, "Explicit batch size exceeded");
                    Check(before - await CountRowsAsync(connection) == result.RowsDeleted,
                        "Reported row count did not match actual persisted mutations");
                    boundedRows += result.RowsDeleted!.Value;
                    if (!result.HasMore) break;
                }
                Check(boundedRows == 39, "Small-batch affected row counts do not match fixture");
                checks++;

                // Old no-result and HasMore-only versions; ignore false HasMore until root is absent.
                foreach (var legacyResult in new[] { "", "SELECT CAST(0 AS int) AS HasMore;" })
                {
                    await ExecuteAsync(connection, $"CREATE OR ALTER PROCEDURE dbo.sp_DeleteTrace @TraceId int AS BEGIN SET NOCOUNT ON; {legacyResult} END");
                    var remains = await SqlTraceDeletionStore.ExecuteBatchAsync(connection, 2, default);
                    Check(remains.HasMore && remains.Phase is null && remains.RowsDeleted is null,
                        "Legacy result incorrectly confirmed deletion or invented progress");
                    var absent = await SqlTraceDeletionStore.ExecuteBatchAsync(connection, 999, default);
                    Check(!absent.HasMore, "Legacy absent root was not detected");
                    checks++;
                }
                await ExecuteAsync(connection, "CREATE OR ALTER PROCEDURE dbo.sp_DeleteTrace @TraceId int AS THROW 51099, 'Synthetic SQL error', 1");
                await ExpectSqlAsync(() => SqlTraceDeletionStore.ExecuteBatchAsync(connection, 2, default), 51099);
                checks++;
                await ExecuteAsync(connection, migration);
                Check((int)(await ScalarAsync(connection, """
                    SELECT COUNT(*) FROM sys.database_permissions WHERE grantee_principal_id = USER_ID('BoundedDeleteExecutor')
                    AND permission_name = 'EXECUTE' AND major_id = OBJECT_ID('dbo.sp_DeleteTrace')
                    """))! == 1, "CREATE OR ALTER lost existing execute grant");
                checks++;

                // Never loosen production TLS to make LocalDB tests pass. Record the real limit.
                var production = new SqlTraceDeletionStore(Options.Create(new TraceAdministrationOptions {
                    SqlConnectionString = ConnectionString(database) }));
                try
                {
                    var result = await production.DeleteBatchAsync(999, default);
                    Check(!result.HasMore, "Production TLS store failed absent-root confirmation");
                    tlsResult = "Production TLS store connected to LocalDB and confirmed absent root.";
                }
                catch (SqlException ex) when (ex.Message.Contains("certificate", StringComparison.OrdinalIgnoreCase)
                    || ex.Message.Contains("SSL", StringComparison.OrdinalIgnoreCase))
                {
                    tlsResult = $"Production TLS rejected LocalDB: {ex.Message}";
                }
                checks++;
            }
        }
        finally
        {
            if (created)
            {
                await GuardAsync(master, "master");
                Check(database.StartsWith(Prefix, StringComparison.Ordinal) && database.Length == Prefix.Length + 32,
                    "Unsafe cleanup database name");
                await ExecuteAsync(master, $"ALTER DATABASE [{database}] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [{database}];");
                cleaned = (int)(await ScalarAsync(master, "SELECT COUNT(*) FROM sys.databases WHERE name = @name", database))! == 0;
            }
            Console.WriteLine(JsonSerializer.Serialize(new {
                Kind = "IsolatedDeletionIntegration", Server, Database = database, Created = created, Cleaned = cleaned,
                Checks = checks, ElapsedSeconds = watch.Elapsed.TotalSeconds, PopulatedDeletionSeconds = populatedSeconds,
                MaxBatchSeconds = maxBatchSeconds, SyntheticTraceLines = 250001, DefaultBatchSize = 2000,
                Phases = phases.ToDictionary(p => p.Key, p => new { p.Value.Batches, p.Value.Rows }),
                ProviderCancellations = providerCancellations,
                ProductionTls = tlsResult, Limit = "LocalDB timings are not Azure SQL S4 performance estimates."
            }));
        }
        Check(cleaned, "Integration database cleanup did not complete");
        Console.WriteLine($"{checks} isolated SQL integration checks passed; disposable database removed.");
    }

    static string ConnectionString(string database) => new SqlConnectionStringBuilder {
        DataSource = Server, InitialCatalog = database, IntegratedSecurity = true,
        Encrypt = true, TrustServerCertificate = true, ConnectTimeout = 10, Pooling = false
    }.ConnectionString; // Only this local fixture trusts a local self-signed certificate.

    static async Task<SqlConnection> OpenAsync(string database)
    {
        Check(database == "master" || database.StartsWith(Prefix, StringComparison.Ordinal), "Unsafe database");
        var connection = new SqlConnection(ConnectionString(database));
        await connection.OpenAsync();
        await GuardAsync(connection, database);
        return connection;
    }

    static async Task GuardAsync(SqlConnection connection, string database)
    {
        Check(connection.DataSource.Equals(Server, StringComparison.OrdinalIgnoreCase)
            && (database == "master" || database.StartsWith(Prefix, StringComparison.Ordinal)),
            "Integration DDL may target only the dedicated LocalDB instance and test database prefix");
        Check((int)(await ScalarAsync(connection, """
            SELECT CASE WHEN CONVERT(int, SERVERPROPERTY('IsLocalDB')) = 1 AND DB_NAME() = @name THEN 1 ELSE 0 END
            """, database))! == 1, "Actual SQL connection failed instance/database guard");
    }

    static async Task ExecuteAsync(SqlConnection connection, string sql)
    {
        await using var command = connection.CreateCommand();
        command.CommandText = sql;
        command.CommandTimeout = 120;
        await command.ExecuteNonQueryAsync();
    }

    static async Task<object?> ScalarAsync(SqlConnection connection, string sql, string? name = null)
    {
        await using var command = connection.CreateCommand();
        command.CommandText = sql;
        command.CommandTimeout = 30;
        if (name is not null) command.Parameters.Add("@name", SqlDbType.NVarChar, 128).Value = name;
        return await command.ExecuteScalarAsync();
    }

    static async Task ExpectSqlAsync(Func<Task> action, int number)
    {
        try { await action(); throw new Exception($"Expected SQL error {number}"); }
        catch (SqlException ex) when (ex.Errors.Cast<SqlError>().Any(e => e.Number == number)) { }
    }

    static async Task<TraceDeletionBatch> DeleteAsync(SqlConnection connection, int traceId, int batchSize)
    {
        await using var command = connection.CreateCommand();
        command.CommandText = "dbo.sp_DeleteTrace";
        command.CommandType = CommandType.StoredProcedure;
        command.Parameters.Add("@TraceId", SqlDbType.Int).Value = traceId;
        command.Parameters.Add("@BatchSize", SqlDbType.Int).Value = batchSize;
        await using var reader = await command.ExecuteReaderAsync();
        Check(await reader.ReadAsync(), "Missing bounded deletion result");
        return new(reader.GetInt32(0) != 0, reader.GetString(1), reader.GetInt32(2));
    }

    static async Task<string> SnapshotUnrelatedAsync(SqlConnection connection)
    {
        var counts = new List<int>();
        foreach (var table in Tables)
        {
            var filter = table switch {
                "QueryBindParameters" or "XppParameters" => "TraceLineId = 9000001",
                "TraceLines" or "StageTraceLines" => "UserSessionProcessThreadId = 1000001",
                "TopMethods" => "BeginUspId = 1000001",
                _ => "TraceId = 2"
            };
            counts.Add((int)(await ScalarAsync(connection, $"SELECT COUNT(*) FROM dbo.[{table}] WHERE {filter}"))!);
        }
        return string.Join(",", counts);
    }

    static async Task<int> CountRowsAsync(SqlConnection connection) =>
        (int)(await ScalarAsync(connection, "SELECT " +
            string.Join(" + ", Tables.Select(t => $"(SELECT COUNT(*) FROM dbo.[{t}])"))))!;

    static async Task<int> CheckCompositeGuardsAsync(SqlConnection connection, string migration)
    {
        const string drop = "ALTER TABLE dbo.UserSessionProcessThreads DROP CONSTRAINT UserSessionUserSessionProcessThread;";
        const string restore = """
            ALTER TABLE dbo.UserSessionProcessThreads ADD CONSTRAINT UserSessionUserSessionProcessThread
                FOREIGN KEY (SessionId, TraceId) REFERENCES dbo.UserSessions(SessionId, TraceId);
            """;
        await ExecuteAsync(connection, drop + """
            ALTER TABLE dbo.UserSessionProcessThreads ADD CONSTRAINT UnexpectedComposite
                FOREIGN KEY (TraceId, SessionId) REFERENCES dbo.UserSessions(SessionId, TraceId);
            """);
        await ExpectSqlAsync(() => ExecuteAsync(connection, migration), 51003);
        await ExecuteAsync(connection, """
            ALTER TABLE dbo.UserSessionProcessThreads DROP CONSTRAINT UnexpectedComposite;
            CREATE UNIQUE INDEX SyntheticSingleSessionId ON dbo.UserSessions(SessionId);
            ALTER TABLE dbo.UserSessionProcessThreads ADD CONSTRAINT UnexpectedSingle
                FOREIGN KEY (SessionId) REFERENCES dbo.UserSessions(SessionId);
            """);
        await ExpectSqlAsync(() => ExecuteAsync(connection, migration), 51003);
        await ExecuteAsync(connection, """
            ALTER TABLE dbo.UserSessionProcessThreads DROP CONSTRAINT UnexpectedSingle;
            DROP INDEX SyntheticSingleSessionId ON dbo.UserSessions;
            ALTER TABLE dbo.UserSessions ADD Extra int NOT NULL;
            ALTER TABLE dbo.UserSessionProcessThreads ADD Extra int NOT NULL;
            CREATE UNIQUE INDEX SyntheticTriple ON dbo.UserSessions(SessionId, TraceId, Extra);
            ALTER TABLE dbo.UserSessionProcessThreads ADD CONSTRAINT UnexpectedTriple
                FOREIGN KEY (SessionId, TraceId, Extra) REFERENCES dbo.UserSessions(SessionId, TraceId, Extra);
            """);
        await ExpectSqlAsync(() => ExecuteAsync(connection, migration), 51003);
        await ExecuteAsync(connection, """
            ALTER TABLE dbo.UserSessionProcessThreads DROP CONSTRAINT UnexpectedTriple;
            DROP INDEX SyntheticTriple ON dbo.UserSessions;
            ALTER TABLE dbo.UserSessionProcessThreads DROP COLUMN Extra;
            ALTER TABLE dbo.UserSessions DROP COLUMN Extra;
            ALTER TABLE dbo.UserSessions DROP CONSTRAINT PK_UserSessions;
            ALTER TABLE dbo.UserSessions ADD CONSTRAINT PK_UserSessions PRIMARY KEY(TraceId, SessionId);
            """);
        await ExpectSqlAsync(() => ExecuteAsync(connection, migration), 51005);
        await ExecuteAsync(connection, """
            ALTER TABLE dbo.UserSessions DROP CONSTRAINT PK_UserSessions;
            ALTER TABLE dbo.UserSessions ADD CONSTRAINT PK_UserSessions PRIMARY KEY(SessionId, TraceId);
            """ + restore);
        return 4;
    }

    static async Task<int> CheckAmbiguousMethodsAsync(SqlConnection connection)
    {
        await ExecuteAsync(connection, """
            INSERT dbo.Traces VALUES (5, N'synthetic-ambiguous-endpoints');
            INSERT dbo.UserSessions VALUES (1, 5);
            INSERT dbo.UserSessionProcessThreads VALUES (5, 1, 5);
            """);
        foreach (var (begin, end, disabled) in new[] {
            (5, 1000001, ""), (1000001, 5, ""),
            (5, 9000999, "FK_TopMethod_UserSessionProcesses1"),
            (9000999, 5, "FK_TopMethod_UserSessionProcesses") })
        {
            if (disabled != "") await ExecuteAsync(connection, $"ALTER TABLE dbo.TopMethods NOCHECK CONSTRAINT {disabled}");
            await ExecuteAsync(connection, $"INSERT dbo.TopMethods VALUES (9000002, {begin}, {end}), (9000003, 5, 5)");
            var before = await CountRowsAsync(connection);
            var unrelated = await SnapshotUnrelatedAsync(connection);
            await ExecuteAsync(connection, "EXECUTE AS USER = 'BoundedDeleteExecutor'");
            try
            {
                try
                {
                    await DeleteAsync(connection, 5, 2);
                    throw new Exception("Ambiguous TopMethods row was silently accepted");
                }
                catch (SqlException ex) when (ex.Number == 51013)
                {
                    Check(ex.Message.Contains("owner review is required"), "Ambiguous endpoint error was not actionable");
                }
            }
            finally { await ExecuteAsync(connection, "REVERT"); }
            Check(await CountRowsAsync(connection) == before && unrelated == await SnapshotUnrelatedAsync(connection),
                "Ambiguous endpoint deletion mutated this or another trace");
            Check((int)(await ScalarAsync(connection, "SELECT COUNT(*) FROM dbo.TopMethods WHERE Id IN (9000002,9000003)"))! == 2,
                "Ambiguous row or safe companion was removed from the rejected batch");
            await ExecuteAsync(connection, "DELETE FROM dbo.TopMethods WHERE Id IN (9000002,9000003)");
            if (disabled != "") await ExecuteAsync(connection, $"ALTER TABLE dbo.TopMethods WITH CHECK CHECK CONSTRAINT {disabled}");
        }
        // Only after synthetic ownership ambiguity is explicitly corrected can retry finish.
        for (var i = 0; ; i++)
        {
            Check(i < 4, "Resolved synthetic trace did not finish");
            var result = await DeleteAsync(connection, 5, 1);
            if (!result.HasMore) break;
        }
        return 5;
    }

    static object CancellationEvidence(string phase, Exception ex) => new {
        Phase = phase, ExceptionType = ex.GetType().FullName,
        SqlErrors = ex is SqlException sql
            ? sql.Errors.Cast<SqlError>().Select(e => new { e.Number, e.Class }).ToArray()
            : null
    };

    // Only deletion-relevant columns. Types and TraceLines clustered/nonclustered key
    // shape follow captured deployed metadata. Enabled FKs are deliberately stricter.
    const string Schema = """
        CREATE TABLE dbo.Traces (TraceId int NOT NULL PRIMARY KEY, TraceName nvarchar(100) NOT NULL);
        CREATE TABLE dbo.UserSessions (SessionId int NOT NULL, TraceId int NOT NULL REFERENCES dbo.Traces(TraceId),
            CONSTRAINT PK_UserSessions PRIMARY KEY(SessionId, TraceId));
        CREATE TABLE dbo.UserSessionProcessThreads (UserSessionProcessThreadId int NOT NULL PRIMARY KEY,
            SessionId int NOT NULL, TraceId int NOT NULL,
            CONSTRAINT UserSessionUserSessionProcessThread FOREIGN KEY(SessionId, TraceId) REFERENCES dbo.UserSessions(SessionId, TraceId));
        CREATE INDEX IX_USPT_TraceId ON dbo.UserSessionProcessThreads(TraceId, SessionId);
        CREATE TABLE dbo.TraceLines (TraceLineId bigint NOT NULL PRIMARY KEY NONCLUSTERED,
            UserSessionProcessThreadId int NOT NULL REFERENCES dbo.UserSessionProcessThreads(UserSessionProcessThreadId),
            Sequence int NOT NULL, CONSTRAINT UQ_SessionUser UNIQUE CLUSTERED (UserSessionProcessThreadId, Sequence));
        CREATE INDEX IX_USP_METHOD ON dbo.TraceLines(UserSessionProcessThreadId, Sequence);
        CREATE INDEX IX_TL_USPT_Aggregation ON dbo.TraceLines(UserSessionProcessThreadId, Sequence);
        ALTER INDEX IX_USP_METHOD ON dbo.TraceLines DISABLE;
        ALTER INDEX IX_TL_USPT_Aggregation ON dbo.TraceLines DISABLE;
        CREATE TABLE dbo.QueryBindParameters (QueryBindParameterId int IDENTITY NOT NULL, TraceLineId bigint NOT NULL REFERENCES dbo.TraceLines(TraceLineId),
            ParameterIndex int NULL, BindValue nvarchar(100) NULL);
        CREATE TABLE dbo.XppParameters (TraceLineId bigint NOT NULL REFERENCES dbo.TraceLines(TraceLineId));
        CREATE TABLE dbo.TopMethods (Id int NOT NULL PRIMARY KEY,
            BeginUspId int NOT NULL CONSTRAINT FK_TopMethod_UserSessionProcesses REFERENCES dbo.UserSessionProcessThreads(UserSessionProcessThreadId),
            EndUspId int NOT NULL CONSTRAINT FK_TopMethod_UserSessionProcesses1 REFERENCES dbo.UserSessionProcessThreads(UserSessionProcessThreadId));
        CREATE TABLE dbo.StageTraceLines (TraceLineId bigint NOT NULL PRIMARY KEY,
            UserSessionProcessThreadId int NULL REFERENCES dbo.UserSessionProcessThreads(UserSessionProcessThreadId));
        CREATE INDEX IX_Stage_ThreadId ON dbo.StageTraceLines(UserSessionProcessThreadId);
        CREATE TABLE dbo.SessionMetrics (SessionId int NOT NULL,
            TraceId int NOT NULL REFERENCES dbo.Traces(TraceId), PRIMARY KEY (TraceId, SessionId));
        CREATE TABLE dbo.TopMethodsBySession (Id int IDENTITY NOT NULL PRIMARY KEY,
            SessionId int NOT NULL, TraceId int NOT NULL REFERENCES dbo.Traces(TraceId));
        CREATE TABLE dbo.MethodNames (MethodHash bigint NOT NULL PRIMARY KEY);
        CREATE TABLE dbo.MethodAotLayers (Id int NOT NULL PRIMARY KEY, TraceId int NOT NULL REFERENCES dbo.Traces(TraceId),
            MethodHash bigint NOT NULL REFERENCES dbo.MethodNames(MethodHash), AotLayer int NOT NULL);
        CREATE INDEX IX_TracelLineId_MethodHash ON dbo.MethodAotLayers(TraceId, MethodHash);
        CREATE TABLE dbo.TraceInformations (InfoId int NOT NULL PRIMARY KEY, TraceId int NOT NULL REFERENCES dbo.Traces(TraceId),
            SystemName nvarchar(200) NULL, UserName nvarchar(200) NULL, AxVersion nvarchar(50) NULL, TraceSessionNotes nvarchar(max) NULL);
        """;

    const string Seed = """
        INSERT dbo.Traces VALUES (1, N'synthetic-large'), (2, N'synthetic-preserve'), (3, N'synthetic-empty');
        SELECT TOP (250001) CONVERT(int, ROW_NUMBER() OVER (ORDER BY (SELECT NULL))) AS n
        INTO #numbers FROM sys.all_objects a CROSS JOIN sys.all_objects b;
        INSERT dbo.UserSessions SELECT n, 1 FROM #numbers WHERE n <= 6001;
        INSERT dbo.UserSessions VALUES (1, 2);
        INSERT dbo.UserSessionProcessThreads SELECT n, n, 1 FROM #numbers WHERE n <= 6001;
        INSERT dbo.UserSessionProcessThreads VALUES (1000001, 1, 2);
        INSERT dbo.TraceLines SELECT CONVERT(bigint, n), 1, n FROM #numbers;
        INSERT dbo.TraceLines VALUES (9000001, 1000001, 1);
        INSERT dbo.QueryBindParameters(TraceLineId, ParameterIndex, BindValue) SELECT n, 1, N'synthetic' FROM #numbers;
        INSERT dbo.QueryBindParameters(TraceLineId, ParameterIndex, BindValue) SELECT 1, n, N'fan-out' FROM #numbers WHERE n <= 6001;
        INSERT dbo.QueryBindParameters(TraceLineId) VALUES (9000001);
        INSERT dbo.XppParameters SELECT 1 FROM #numbers WHERE n <= 6001;
        INSERT dbo.XppParameters VALUES (9000001);
        INSERT dbo.TopMethods(Id, BeginUspId, EndUspId) SELECT n, 1, 2 FROM #numbers WHERE n <= 6001;
        INSERT dbo.TopMethods(Id, BeginUspId, EndUspId) VALUES (9000001, 1000001, 1000001);
        INSERT dbo.StageTraceLines SELECT n, 1 FROM #numbers WHERE n <= 6001;
        INSERT dbo.StageTraceLines VALUES (9000001, 1000001);
        INSERT dbo.SessionMetrics SELECT n, 1 FROM #numbers WHERE n <= 6001;
        INSERT dbo.SessionMetrics VALUES (1, 2);
        INSERT dbo.TopMethodsBySession(SessionId, TraceId) SELECT n, 1 FROM #numbers WHERE n <= 6001;
        INSERT dbo.TopMethodsBySession(SessionId, TraceId) VALUES (1, 2);
        INSERT dbo.MethodNames VALUES (1);
        INSERT dbo.MethodAotLayers SELECT n, 1, 1, 1 FROM #numbers WHERE n <= 6001;
        INSERT dbo.MethodAotLayers VALUES (9000001, 2, 1, 1);
        INSERT dbo.TraceInformations(InfoId, TraceId) SELECT n, 1 FROM #numbers WHERE n <= 6001;
        INSERT dbo.TraceInformations(InfoId, TraceId) VALUES (9000001, 2);
        DROP TABLE #numbers;
        """;

    const string SmallSeed = """
        INSERT dbo.Traces VALUES (4, N'synthetic-small-batches');
        INSERT dbo.UserSessions VALUES (4, 4);
        INSERT dbo.UserSessionProcessThreads VALUES (4, 4, 4);
        INSERT dbo.TraceLines VALUES (4, 4, 1);
        INSERT dbo.QueryBindParameters(TraceLineId) SELECT 4 FROM (VALUES(1),(2),(3),(4),(5)) n(n);
        INSERT dbo.XppParameters SELECT 4 FROM (VALUES(1),(2),(3),(4),(5)) n(n);
        INSERT dbo.TopMethods(Id, BeginUspId, EndUspId) SELECT n, 4, 4 FROM (VALUES(1),(2),(3),(4),(5)) n(n);
        INSERT dbo.StageTraceLines SELECT n, 4 FROM (VALUES(1),(2),(3),(4),(5)) n(n);
        INSERT dbo.SessionMetrics VALUES (4, 4);
        INSERT dbo.TopMethodsBySession(SessionId, TraceId) SELECT 4, 4 FROM (VALUES(1),(2),(3),(4)) n(n);
        INSERT dbo.MethodAotLayers SELECT n, 4, 1, 1 FROM (VALUES(1),(2),(3),(4),(5)) n(n);
        INSERT dbo.TraceInformations(InfoId, TraceId) SELECT n, 4 FROM (VALUES(1),(2),(3),(4),(5)) n(n);
        """;
}
