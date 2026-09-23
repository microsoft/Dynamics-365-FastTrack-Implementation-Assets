using System.Security.Cryptography;
using System.Text.Json;
using System.Text.RegularExpressions;
using Microsoft.Data.SqlClient;
using Microsoft.Diagnostics.Tracing;
using Microsoft.Extensions.Logging.Abstractions;
using TraceParserFunction;

static class AnalysisChecks
{
    public static async Task<int> RunAsync(SqlConnection connection, string? etlPath)
    {
        if (etlPath is not null && (Path.GetFileName(etlPath) != "synthetic-small.etl"
            || new FileInfo(etlPath).Length != 131072))
            throw new InvalidOperationException("Duration analysis accepts only the 128 KiB synthetic-small ETL.");
        var checks = 0;
        void Check(bool ok, string name)
        {
            if (!ok) throw new Exception(name);
            checks++;
        }
        async Task Exec(string sql)
        {
            using var cmd = new SqlCommand(sql, connection) { CommandTimeout = 30 };
            await cmd.ExecuteNonQueryAsync();
        }
        async Task<decimal> Number(string sql)
        {
            using var cmd = new SqlCommand(sql, connection) { CommandTimeout = 30 };
            return Convert.ToDecimal(await cmd.ExecuteScalarAsync());
        }

        var mcp = Path.GetFullPath(Path.Combine(AppContext.BaseDirectory,
            "..", "..", "..", "..", "..", "..", "TraceParserMCP"));
        var views = await File.ReadAllTextAsync(Path.Combine(mcp, "Create Views.sql"));
        await Exec("ALTER TABLE dbo.Traces ADD AxVersion nvarchar(50) NULL;");
        foreach (var batch in Regex.Split(views, @"^\s*GO\s*$", RegexOptions.Multiline | RegexOptions.IgnoreCase))
            if (!string.IsNullOrWhiteSpace(batch)) await Exec(batch);
        using (var config = JsonDocument.Parse(await File.ReadAllTextAsync(Path.Combine(mcp, "dab-config.json"))))
            foreach (var entity in new[] { "SessionSummary", "SessionMetrics", "TopMethodsBySession" })
                Check(config.RootElement.GetProperty("entities").GetProperty(entity).GetProperty("source")
                    .GetProperty("key-fields").EnumerateArray().Any(x => x.GetString() == "TraceId"),
                    entity + " pagination key must include trace identity.");

        await Exec("""
            SET IDENTITY_INSERT dbo.Traces ON;
            INSERT dbo.Traces(TraceId,TraceName,TraceFile,TimeStampBegin,TimeStampEnd,TraceParserVersion)
            VALUES(9001,N'synthetic analysis A',N'synthetic',GETUTCDATE(),GETUTCDATE(),N'known-nanoseconds'),
                  (9002,N'synthetic analysis B',N'synthetic',GETUTCDATE(),GETUTCDATE(),N'known-nanoseconds');
            SET IDENTITY_INSERT dbo.Traces OFF;
            INSERT dbo.Users VALUES(N'synthetic analysis');
            INSERT dbo.Customers VALUES(N'synthetic analysis');
            INSERT dbo.UserSessions
            SELECT s.SessionId,s.TraceId,u.UserId,N'synthetic session',c.CustomerId
            FROM (VALUES(1,9001),(2,9001),(3,9001),(1,9002)) s(SessionId,TraceId)
            CROSS JOIN dbo.Users u CROSS JOIN dbo.Customers c;
            SET IDENTITY_INSERT dbo.UserSessionProcessThreads ON;
            INSERT dbo.UserSessionProcessThreads(UserSessionProcessThreadId,RequestId,ActivityId,RelatedActivityId,SessionId,TraceId)
            SELECT id,NEWID(),NEWID(),NEWID(),session,trace
            FROM (VALUES(9101,1,9001),(9102,1,9001),(9103,2,9001),(9104,3,9001),(9105,1,9002)) t(id,session,trace);
            SET IDENTITY_INSERT dbo.UserSessionProcessThreads OFF;
            INSERT dbo.MethodNames VALUES(123,N'Synthetic.RepeatedMethod',1);
            """);

        // Actual query shape, not DISTINCT names/counters: 36 inclusive X++ callers
        // surround the same 101 SQL executions, giving the previously reported 37:1.
        async Task Line(int thread, int sequence, int? parent, int type, int calls, long db, long duration = 0)
        {
            using var cmd = new SqlCommand("""
                INSERT dbo.TraceLines(UserSessionProcessThreadId,CallTypeId,Sequence,SequenceEnd,[TimeStamp],
                TimeStampEnd,InclusiveDurationNano,ExclusiveDurationNano,DatabaseDurationNano,ParentSequence,
                InclusiveRpc,DatabaseCalls,PrepDurationNano,BindDurationNano,RowFetchDurationNano,RowFetchCount,
                MethodHash,HasChildren,FileName,EventId,EventType,LineNumber)
                VALUES(@thread,@type,@sequence,@sequence,0,0,@duration,0,@db,@parent,0,@calls,0,0,0,0,
                CASE WHEN @type=8 THEN 123 ELSE NULL END,0,N'synthetic',0,0,0)
                """, connection);
            cmd.Parameters.AddWithValue("@thread", thread);
            cmd.Parameters.AddWithValue("@sequence", sequence);
            cmd.Parameters.AddWithValue("@type", type);
            cmd.Parameters.AddWithValue("@parent", (object?)parent ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@duration", duration);
            cmd.Parameters.AddWithValue("@db", db);
            cmd.Parameters.AddWithValue("@calls", calls);
            await cmd.ExecuteNonQueryAsync();
        }
        for (var i = 1; i <= 36; i++) await Line(9101, i, i == 1 ? null : i - 1, 8, 101, 101_000_000, 800_000_000);
        for (var i = 1; i <= 101; i++) await Line(9101, 100 + i, 36, 64, 1, 1_000_000, 1_000_000);
        Check(await Number("SELECT SUM(DatabaseCalls) FROM dbo.TraceLines") == 3737, "Inclusive 37:1 reproduction.");
        Check(await Number("SELECT COUNT(*) FROM dbo.TraceLines WHERE DatabaseCalls>100 AND DatabaseDurationNano/1000000.0/DatabaseCalls<5") == 36,
            "Original N+1 filter produces 36 contexts for one chain.");
        Check(await Number("SELECT COUNT(*) FROM dbo.vw_NPlusOnePatterns") == 1
            && await Number("SELECT Sequence FROM dbo.vw_NPlusOnePatterns") == 36, "Keep the deepest identical-work context.");
        Check(await Number("SELECT TotalDatabaseCalls FROM dbo.vw_SessionMetrics WHERE TraceId=9001 AND SessionId=1") == 101
            && await Number("SELECT TotalDatabaseMs FROM dbo.vw_SessionMetrics WHERE TraceId=9001 AND SessionId=1") == 101,
            "Session SQL totals count execution rows once, not inclusive ancestors.");
        Check(await Number("SELECT RootCalls FROM dbo.vw_SessionMetrics WHERE TraceId=9001 AND SessionId=3") == 0
            && await Number("SELECT TotalDurationMs+TotalDatabaseMs+TotalDatabaseCalls+TotalRpcCalls+TotalRowsFetched FROM dbo.vw_SessionMetrics WHERE TraceId=9001 AND SessionId=3") == 0,
            "Empty left join does not invent a root or null statistics.");

        foreach (var (thread, start) in new[] { (9101, 1000), (9102, 1), (9103, 1), (9105, 1) })
        {
            await Line(thread, start, null, 8, 101, 101_000_000);
            await Line(thread, start + 1, start, 8, 101, 101_000_000);
        }
        Check(await Number("SELECT COUNT(*) FROM dbo.vw_NPlusOnePatterns") == 5,
            "Equal methods/metrics on different invocations, threads, sessions and traces survive.");
        Check(await Number("SELECT TotalTraceLines FROM dbo.vw_SessionMetrics WHERE TraceId=9001 AND SessionId=1") == 141
            && await Number("SELECT TotalTraceLines FROM dbo.vw_SessionMetrics WHERE TraceId=9002 AND SessionId=1") == 2,
            "Composite session identity prevents cross-trace join multiplication.");
        await Line(9103, 100, null, 8, 202, 202_000_000);
        await Line(9103, 101, 100, 8, 101, 101_000_000);
        Check(await Number("SELECT COUNT(*) FROM dbo.vw_NPlusOnePatterns WHERE UserSessionProcessThreadId=9103 AND Sequence>=100") == 2,
            "Caller with additional DB work retains its distinct context.");
        await Line(9103, 200, null, 8, 100, 100_000_000);
        await Line(9103, 201, null, 8, 101, 505_000_000);
        await Line(9103, 202, null, 8, 101, 504_999_999);
        await Line(9103, 203, null, 8, 101, -1);
        await Line(9103, 204, null, 8, 0, 0);
        await Line(9103, 205, null, 8, 101, 0);
        Check(await Number("SELECT COUNT(*) FROM dbo.vw_NPlusOnePatterns WHERE UserSessionProcessThreadId=9103 AND Sequence>=200") == 2,
            "N+1 strict >100/<5 boundaries and invalid negative/zero-count inputs.");
        await Line(9104, 1, 0, 64, 1, 1_234_500, 1_234_500);
        Check(await Number("SELECT InclusiveMs FROM dbo.vw_TraceLineDetails WHERE UserSessionProcessThreadId=9104") == 1.23m,
            "Known nanoseconds convert to rounded milliseconds.");
        Check(await Number("SELECT RootCalls FROM dbo.vw_SessionMetrics WHERE TraceId=9001 AND SessionId=3") == 1,
            "Parser zero-parent SQL root is recognized.");
        await Line(9104, 2, null, 8, 0, 0, -2_500_000);
        Check(await Number("SELECT InclusiveMs FROM dbo.vw_TraceLineDetails WHERE UserSessionProcessThreadId=9104 AND Sequence=2") == -2.5m,
            "Negative raw duration is not silently rescaled or clamped by the detail view.");
        await Exec("ALTER TABLE dbo.TraceLines ALTER COLUMN ExclusiveDurationNano bigint NULL;");
        await Exec("UPDATE dbo.TraceLines SET ExclusiveDurationNano=NULL WHERE UserSessionProcessThreadId=9104 AND Sequence=2;");
        Check(await Number("SELECT COUNT(*) FROM dbo.vw_TraceLineDetails WHERE UserSessionProcessThreadId=9104 AND Sequence=2 AND ExclusiveMs IS NULL") == 1,
            "Unknown detail duration remains null.");
        Check(await Number("SELECT COUNT(*) FROM dbo.vw_NPlusOnePatterns") ==
            await Number("SELECT COUNT(DISTINCT TraceLineId) FROM dbo.vw_NPlusOnePatterns"), "N+1 DAB key is unique.");

        if (etlPath is not null)
        {
            var secondsToTicks = typeof(EtlParser).GetMethod("ConvertSecToTicks",
                System.Reflection.BindingFlags.NonPublic | System.Reflection.BindingFlags.Static)!;
            foreach (var (input, ticks) in new (string?, long)[] { (null, 0), ("", 0), ("0", 0),
                ("0.001", 10000), ("-0.002", -20000) })
                Check((long)secondsToTicks.Invoke(null, [input])! == ticks,
                    "Seconds conversion preserves its internal tick contract for null/empty/zero/signed values.");
            var hash = Convert.ToHexString(SHA256.HashData(await File.ReadAllBytesAsync(etlPath)));
            if (hash != "42799A8122EBE56EC89B23FC8B8F8AFA537E775F0925E98DF2D2667E087EF624")
                throw new InvalidOperationException("Duration known-answer test requires the pinned synthetic-small ETL.");
            var entries = new Dictionary<string, DateTime>();
            var elapsed = new Dictionary<string, double>();
            var preparations = new List<double>();
            var executions = new List<double>();
            using (var source = new ETWTraceEventSource(etlPath))
            {
                source.Dynamic.ReadAllManifests(Path.Combine(AppContext.BaseDirectory, "Manifests"));
                source.Dynamic.All += e =>
                {
                    if ((int)e.ID == 24500) entries[(string)e.PayloadByName("methodName")] = e.TimeStamp;
                    if ((int)e.ID == 24501)
                    {
                        var name = (string)e.PayloadByName("methodName");
                        elapsed[name] = (e.TimeStamp - entries[name]).TotalMilliseconds;
                    }
                    if ((int)e.ID == 4922)
                    {
                        preparations.Add(Convert.ToDouble(e.PayloadByName("preparationTimeSeconds")));
                        executions.Add(Convert.ToDouble(e.PayloadByName("executionTimeSeconds")));
                    }
                };
                source.Process();
            }
            Check(elapsed["SyntheticFixture.Outer"] == 80 && elapsed["SyntheticFixture.Inner"] == 30
                && preparations.SequenceEqual(new[] { 0.001, 0.001 }) && executions.SequenceEqual(new[] { 0.002, 0.004 }),
                "Independent ETW decode agrees with the generator's 80/30 ms elapsed time and seconds payloads.");
            var id = Guid.NewGuid();
            var blob = $"_imports/{id:D}/sample.etl";
            // The analytical rows above were seeded outside the importer, in this disposable DB only.
            await Exec("UPDATE dbo.TraceLineIDControls SET NextTraceLineId=(SELECT MAX(TraceLineId)+1 FROM dbo.TraceLines);");
            await Exec($"EXEC dbo.tp_RegisterUpload '{id}',N'account',N'etl-uploads',N'{blob}',N'synthetic units';");
            var importer = new SqlImporter(NullLogger<SqlImporter>.Instance);
            using var budget = new CancellationTokenSource(TimeSpan.FromSeconds(30));
            var receipt = await importer.BeginImportAsync(connection, "account", "etl-uploads", blob, "\"units\"", budget.Token);
            await importer.SetContentHashAsync(connection, Convert.FromHexString(hash));
            var parsed = new EtlParser(importer, NullLogger<EtlParser>.Instance).Parse(etlPath, receipt.TraceId, connection);
            Check(parsed.Staged == 8, "Actual parser/channel staged all eight known-answer rows.");
            var rawOuter = await Number($"SELECT InclusiveDurationNano FROM dbo.TPImportLines WHERE ImportId='{id}' AND Sequence=1");
            var rawPreparation = await Number($"SELECT PrepDurationNano FROM dbo.TPImportLines WHERE ImportId='{id}' AND Sequence=5");
            var rawExecution = await Number($"SELECT ExclusiveDurationNano FROM dbo.TPImportLines WHERE ImportId='{id}' AND Sequence=5");
            var rawFetch = await Number($"SELECT RowFetchDurationNano FROM dbo.TPImportLines WHERE ImportId='{id}' AND Sequence=5");
            Check(rawOuter == 800000 && rawPreparation == 10000 && rawExecution == 20000 && rawFetch == 30000,
                "Characterize the frozen importer: fields named Nano actually store 100ns ticks.");
            await importer.PromoteStageToTraceLines(connection);
            await importer.CompleteImportAsync(connection);
            var displayed = await Number($"SELECT InclusiveMs FROM dbo.vw_TraceLineDetails WHERE TraceId={receipt.TraceId} AND Sequence=1");
            Check(displayed == 0.8m && displayed * 100 == (decimal)elapsed["SyntheticFixture.Outer"],
                "Known defect reproduced end-to-end: 80ms is shown as 0.8ms, not a timing inference.");
            Console.WriteLine(JsonSerializer.Serialize(new {
                Kind = "DurationKnownAnswer", FixtureSha256 = hash, IndependentElapsedMs = 80,
                ExpectedNanoseconds = 80000000, ActualStoredNanoField = rawOuter, ActualViewMs = displayed,
                Status = "BLOCKED: unit-versioned replay/cutover strategy requires approval; importer contract unchanged",
                PreparationSeconds = 0.001, ActualPreparationNanoField = rawPreparation,
                ExecutionSeconds = 0.002, ActualExecutionNanoField = rawExecution, ActualFetchNanoField = rawFetch
            }));
        }
        Console.WriteLine($"PASS {checks} analytical checks; 37:1 inclusive inflation reproduced; " +
            (etlPath is null ? "ETL unit checks SKIPPED." : "unit mismatch characterized, NOT corrected."));
        return checks;
    }
}
