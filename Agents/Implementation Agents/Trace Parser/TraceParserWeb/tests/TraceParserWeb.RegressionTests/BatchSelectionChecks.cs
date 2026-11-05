using System.Data;
using System.Diagnostics;
using System.Text.Json;
using System.Text.RegularExpressions;
using System.Xml.Linq;
using Microsoft.Data.SqlClient;
using TraceParserWeb.Services;
using static DeletionChecks;

static class BatchSelectionChecks
{
    const string Server = @"(localdb)\TPImporterTests_c100bb02";
    const string Prefix = "TPDeleteSelection_";

    public static async Task RunAsync()
    {
        var database = Prefix + Guid.NewGuid().ToString("N");
        var builder = new SqlConnectionStringBuilder
        {
            DataSource = Server, InitialCatalog = "master", IntegratedSecurity = true,
            Encrypt = false, Pooling = false, ConnectRetryCount = 0
        };
        Check(Regex.IsMatch(database, "^TPDeleteSelection_[0-9a-f]{32}$"), "Unsafe fixture name");
        await using var master = new SqlConnection(builder.ConnectionString);
        await master.OpenAsync();
        var created = false;
        try
        {
            await Exec(master, $"CREATE DATABASE [{database}]");
            created = true;
            builder.InitialCatalog = database;
            await using var sql = new SqlConnection(builder.ConnectionString);
            await sql.OpenAsync();
            var source = Path.GetFullPath(Path.Combine(AppContext.BaseDirectory, "..", "..", "..", "..", ".."));
            foreach (var file in new[] { Path.Combine(source, "tests", "TraceParserFunction.ProtocolTests", "Fixture.sql"),
                Path.Combine(source, "sql", "safe-importer.sql") })
                foreach (var batch in Regex.Split(await File.ReadAllTextAsync(file), @"(?im)^\s*GO\s*$"))
                    if (!string.IsNullOrWhiteSpace(batch)) await Exec(sql, batch);
            var migration = await File.ReadAllTextAsync(Path.Combine(source, "sql", "sp_DeleteTrace.sql"));
            await Exec(sql, migration);
            var definition = (string)(await Scalar(sql, "SELECT OBJECT_DEFINITION(OBJECT_ID('dbo.sp_DeleteTrace'))"))!;
            await GuardChecks(sql, migration, definition);
            var start = definition.IndexOf("DECLARE @batch TABLE", StringComparison.Ordinal);
            var end = definition.IndexOf("IF EXISTS (SELECT 1 FROM @batch)", start, StringComparison.Ordinal);
            Check(start >= 0 && end > start, "Cannot locate actual selection");
            var selection = definition[start..end];
            const string oldSelection = """
                DECLARE @batch TABLE (Id bigint PRIMARY KEY);
                INSERT @batch SELECT TOP (@BatchSize) tl.TraceLineId
                FROM dbo.TraceLines tl JOIN dbo.UserSessionProcessThreads u
                    ON u.UserSessionProcessThreadId=tl.UserSessionProcessThreadId
                WHERE u.TraceId=@TraceId;
                """;
            await Exec(sql, """
                CREATE USER SelectionWeb WITHOUT LOGIN;
                GRANT EXECUTE ON dbo.sp_DeleteTrace TO SelectionWeb;
                GRANT SELECT ON dbo.Traces TO SelectionWeb;
                INSERT dbo.Users(UserName) VALUES(N'synthetic');
                INSERT dbo.Customers(CustomerName) VALUES(N'synthetic');
                SELECT TOP(100000) CONVERT(int,ROW_NUMBER() OVER(ORDER BY(SELECT NULL))) n
                    INTO #numbers FROM sys.all_objects a CROSS JOIN sys.all_objects b;
                """);
            var unrelated = await Seed(sql, 3000000, 337, false);
            var sparse = await Seed(sql, 1000, 337, true);
            await Probe(sql, "sparse-old", oldSelection, sparse, 2000, false);
            // LocalDB can choose a good plan for the old query. Separately reproduce
            // the production scan/hash shape, without claiming a natural local regression.
            var primaryKey = (string)(await Scalar(sql, """
                SELECT QUOTENAME(name) FROM sys.indexes WHERE object_id=OBJECT_ID('dbo.TraceLines') AND is_primary_key=1
                """))!;
            var scanSelection = $"""
                DECLARE @batch TABLE (Id bigint PRIMARY KEY);
                INSERT @batch SELECT TOP (@BatchSize) tl.TraceLineId
                FROM dbo.TraceLines tl WITH(INDEX({primaryKey}),FORCESCAN)
                INNER HASH JOIN dbo.UserSessionProcessThreads u
                    ON u.UserSessionProcessThreadId=tl.UserSessionProcessThreadId
                WHERE u.TraceId=@TraceId OPTION(FORCE ORDER);
                """;
            await Probe(sql, "sparse-production-scan-shape", scanSelection, sparse, 2000, false);
            var sparseReads = await Probe(sql, "sparse-new", selection, sparse, 2000, true);
            // Add another large unrelated trace: target reads must not grow with its rows.
            var unrelated2 = await Seed(sql, 1000000, 337, false);
            var moreReads = await Probe(sql, "sparse-more-unrelated", selection, sparse, 2000, true);
            Check(moreReads <= sparseReads * 1.1 + 32, "Target reads scaled with unrelated rows");
            await Delete(sql, sparse, 1000);
            var large = await Seed(sql, 2580000, 337, true);
            await Probe(sql, "large-old", oldSelection, large, 2000, false);
            await Probe(sql, "large-production-scan-shape", scanSelection, large, 2000, false);
            foreach (var size in new[] { 1, 2000, 10000 })
                await Probe(sql, $"large-new-{size}", selection, large, size, true);
            await Delete(sql, large, 2580000, async batches =>
            {
                if (batches is 130 or 1289)
                    await Probe(sql, $"post-partial-{batches}", selection, large, 2000, true);
            });
            var empty = await Seed(sql, 0, 337, false);
            await Probe(sql, "empty-threads", selection, empty, 2000, true);
            await Delete(sql, empty, 0);
            foreach (var (trace, rows) in new[] { (unrelated, 3000000L), (unrelated2, 1000000L) })
                Check(Convert.ToInt64(await Scalar(sql, $"""
                    SELECT COUNT_BIG(*) FROM dbo.TraceLines tl JOIN dbo.UserSessionProcessThreads u
                    ON tl.UserSessionProcessThreadId=u.UserSessionProcessThreadId WHERE u.TraceId={trace}
                    """)) == rows, "Unrelated trace changed");
            Console.WriteLine("PASS batch-selection guards, plans, bounded reads, scale deletion and preservation");
        }
        finally
        {
            if (created)
            {
                await Exec(master, $"ALTER DATABASE [{database}] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [{database}]");
                Console.WriteLine($"CLEANED {database}");
            }
        }
    }

    static async Task GuardChecks(SqlConnection sql, string migration, string original)
    {
        await Exec(sql, """
            DROP INDEX IX_USPT_TraceId ON dbo.UserSessionProcessThreads;
            CREATE INDEX SelectionWrongLeading ON dbo.UserSessionProcessThreads(SessionId,TraceId);
            CREATE INDEX SelectionFiltered ON dbo.UserSessionProcessThreads(TraceId) WHERE TraceId>0;
            """);
        await Refuse();
        await Exec(sql, "CREATE INDEX SelectionRenamed ON dbo.UserSessionProcessThreads(TraceId)");
        await Exec(sql, migration);
        await Exec(sql, "ALTER INDEX SelectionRenamed ON dbo.UserSessionProcessThreads DISABLE");
        await Refuse();
        await Exec(sql, """
            ALTER INDEX SelectionRenamed ON dbo.UserSessionProcessThreads REBUILD;
            DROP INDEX SelectionWrongLeading ON dbo.UserSessionProcessThreads;
            DROP INDEX SelectionFiltered ON dbo.UserSessionProcessThreads;
            ALTER TABLE dbo.TraceLines DROP CONSTRAINT UQ_SessionUser;
            ALTER INDEX IX_Usp_ParentSequence ON dbo.TraceLines DISABLE;
            ALTER INDEX IX_USP_QUERY ON dbo.TraceLines DISABLE;
            ALTER INDEX IX_USP_METHOD ON dbo.TraceLines DISABLE;
            ALTER INDEX IX_TL_USPT_Aggregation ON dbo.TraceLines DISABLE;
            """);
        await Refuse();
        await Exec(sql, """
            ALTER TABLE dbo.TraceLines ADD CONSTRAINT UQ_SessionUser UNIQUE CLUSTERED(UserSessionProcessThreadId,Sequence);
            ALTER INDEX ALL ON dbo.TraceLines REBUILD;
            """);
        await Exec(sql, migration);
        async Task Refuse()
        {
            try { await Exec(sql, migration); throw new Exception("Missing seek index accepted"); }
            catch (SqlException ex) when (ex.Number == 51007) { }
            Check((string)(await Scalar(sql, "SELECT OBJECT_DEFINITION(OBJECT_ID('dbo.sp_DeleteTrace'))"))! == original,
                "Rejected migration changed definition");
            Check(Convert.ToInt32(await Scalar(sql, """
                SELECT COUNT(*) FROM sys.extended_properties WHERE major_id=OBJECT_ID('dbo.sp_DeleteTrace')
                AND name='TraceParserImporterDeletionHash'
                AND CONVERT(varbinary(32),value)=HASHBYTES('SHA2_256',OBJECT_DEFINITION(OBJECT_ID('dbo.sp_DeleteTrace')))
                """)) == 1, "Rejected migration changed fingerprint");
        }
    }

    static async Task<int> Seed(SqlConnection sql, int rows, int threads, bool skew)
    {
        var trace = Convert.ToInt32(await Scalar(sql, """
            INSERT dbo.Traces(TraceName,TraceFile,TimeStampBegin,TimeStampEnd)
            VALUES(N'synthetic-selection',N'synthetic',GETUTCDATE(),GETUTCDATE()); SELECT CONVERT(int,SCOPE_IDENTITY());
            """));
        await Exec(sql, $"""
            INSERT dbo.UserSessions VALUES(1,{trace},1,N'synthetic',1);
            INSERT dbo.UserSessionProcessThreads(RequestId,ActivityId,RelatedActivityId,SessionId,TraceId)
            SELECT NEWID(),NEWID(),NEWID(),1,{trace} FROM #numbers WHERE n<={threads};
            SELECT UserSessionProcessThreadId, ROW_NUMBER() OVER(ORDER BY UserSessionProcessThreadId) n
                INTO #threads FROM dbo.UserSessionProcessThreads WHERE TraceId={trace};
            """);
        for (var offset = 0; offset < rows; offset += 100000)
            await Exec(sql, $"""
                INSERT dbo.TraceLines(UserSessionProcessThreadId,CallTypeId,Sequence,SequenceEnd,[TimeStamp],TimeStampEnd,
                    InclusiveDurationNano,ExclusiveDurationNano,DatabaseDurationNano,InclusiveRpc,DatabaseCalls,
                    PrepDurationNano,BindDurationNano,RowFetchDurationNano,RowFetchCount,HasChildren,FileName,EventId,EventType,LineNumber)
                SELECT t.UserSessionProcessThreadId,0,n.n+{offset},n.n+{offset},0,0,0,0,0,0,0,0,0,0,0,0,N'synthetic',0,0,0
                FROM #numbers n JOIN #threads t ON t.n=
                    {(skew ? $"CASE WHEN n.n+{offset}>{rows / 10} THEN {threads} ELSE 1+(n.n+{offset}-1)%{threads} END" : $"1+(n.n+{offset}-1)%{threads}")}
                WHERE n.n<={Math.Min(100000, rows - offset)};
                """);
        await Exec(sql, "DROP TABLE #threads");
        Console.WriteLine(JsonSerializer.Serialize(new { Kind = "SelectionSeed", trace, rows, threads, skew }));
        return trace;
    }

    static async Task<long> Probe(SqlConnection sql, string name, string selection, int trace, int size, bool bounded)
    {
        var reads = 0L;
        var messages = new List<string>();
        SqlInfoMessageEventHandler handler = (_, e) => messages.Add(e.Message);
        sql.InfoMessage += handler;
        var watch = Stopwatch.StartNew();
        var plans = new List<XDocument>();
        var count = -1;
        try
        {
            using var command = sql.CreateCommand();
            command.CommandTimeout = 60;
            command.CommandText = $"""
                SET STATISTICS IO ON; SET STATISTICS XML ON;
                DECLARE @TraceId int={trace}, @BatchSize int={size};
                {selection}
                SELECT COUNT(*) AS SelectedRows FROM @batch;
                SET STATISTICS XML OFF; SET STATISTICS IO OFF;
                """;
            await using var reader = await command.ExecuteReaderAsync();
            do
            {
                while (await reader.ReadAsync())
                    if (reader.GetName(0) == "SelectedRows") count = reader.GetInt32(0);
                    else if (reader.GetValue(0) is string xml && xml.Contains("<ShowPlanXML"))
                        plans.Add(XDocument.Parse(xml));
            } while (await reader.NextResultAsync());
        }
        finally
        {
            sql.InfoMessage -= handler;
            await Exec(sql, "SET STATISTICS XML OFF; SET STATISTICS IO OFF");
        }
        foreach (var message in messages)
            foreach (Match match in Regex.Matches(message, @"Table '(?:TraceLines|UserSessionProcessThreads)'.*?logical reads (\d+)"))
                reads += long.Parse(match.Groups[1].Value);
        XNamespace ns = "http://schemas.microsoft.com/sqlserver/2004/07/showplan";
        var access = plans.SelectMany(p => p.Descendants(ns + "RelOp"))
            .Where(r => r.Element(ns + "IndexScan")?.Element(ns + "Object") is { } o
                && ((string?)o.Attribute("Table") is "[TraceLines]" or "[UserSessionProcessThreads]"))
            .Select(r => (string?)r.Attribute("PhysicalOp")).ToArray();
        Console.WriteLine(JsonSerializer.Serialize(new { Kind = "SelectionProbe", name, size, count, reads,
            elapsedMs = watch.Elapsed.TotalMilliseconds, access }));
        Check(count >= 0 && count <= size && reads > 0, "Missing selection/IO evidence");
        if (bounded)
        {
            Check(access.Length >= 2 && access.All(a => a is "Index Seek" or "Clustered Index Seek"),
                "Selection scanned instead of seeking");
            Check(reads < 20000, "Selection exceeded fixture logical-read bound");
        }
        return reads;
    }

    static async Task Delete(SqlConnection sql, int trace, long expectedLines, Func<int, Task>? afterBatch = null)
    {
        var watch = Stopwatch.StartNew();
        var batches = 0;
        long lines = 0;
        var maxMs = 0d;
        var store = new CallbackStore(async (id, ct) =>
        {
            var batchWatch = Stopwatch.StartNew();
            var result = await SqlTraceDeletionStore.ExecuteBatchAsync(sql, id, ct);
            maxMs = Math.Max(maxMs, batchWatch.Elapsed.TotalMilliseconds);
            Check(result.RowsDeleted is >= 0 and <= 2000, "Batch exceeded write bound");
            if (result.Phase == "TraceLines") lines += result.RowsDeleted!.Value;
            batches++;
            return result;
        });
        await Exec(sql, "EXECUTE AS USER='SelectionWeb'");
        try
        {
            await DeletionChecks.Service(store).DeleteTraceAsync(trace, default, async _ =>
            {
                if (afterBatch is not null)
                {
                    await Exec(sql, "REVERT");
                    try { await afterBatch(batches); }
                    finally { await Exec(sql, "EXECUTE AS USER='SelectionWeb'"); }
                }
            });
        }
        finally { await Exec(sql, "REVERT"); }
        Check(lines == expectedLines && watch.Elapsed < TimeSpan.FromMinutes(5), "Deletion incomplete or exceeded existing budget");
        Check(Convert.ToInt32(await Scalar(sql, $"SELECT COUNT(*) FROM dbo.Traces WHERE TraceId={trace}")) == 0,
            "Deleted root remains");
        Console.WriteLine(JsonSerializer.Serialize(new { Kind = "RestrictedServiceDeletion", trace, lines, batches, maxMs,
            elapsedSeconds = watch.Elapsed.TotalSeconds, azureS4Prediction = false }));
    }

    static async Task Exec(SqlConnection sql, string text)
    {
        using var command = sql.CreateCommand();
        command.CommandTimeout = 120;
        command.CommandText = text;
        await command.ExecuteNonQueryAsync();
    }

    static async Task<object?> Scalar(SqlConnection sql, string text)
    {
        using var command = sql.CreateCommand();
        command.CommandTimeout = 120;
        command.CommandText = text;
        return await command.ExecuteScalarAsync();
    }
}
