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
        await Exec("IF COL_LENGTH('dbo.Traces','AxVersion') IS NULL ALTER TABLE dbo.Traces ADD AxVersion nvarchar(50) NULL;");
        foreach (var batch in Regex.Split(await File.ReadAllTextAsync(Path.Combine(mcp,"Duration units.sql")),
            @"^\s*GO\s*$",RegexOptions.Multiline|RegexOptions.IgnoreCase))
            if (!string.IsNullOrWhiteSpace(batch)) await Exec(batch);
        foreach (var batch in Regex.Split(views, @"^\s*GO\s*$", RegexOptions.Multiline | RegexOptions.IgnoreCase))
            if (!string.IsNullOrWhiteSpace(batch)) await Exec(batch);
        foreach(var batch in Regex.Split(await File.ReadAllTextAsync(Path.Combine(mcp,"Create Keyword Search SPs.sql")),
            @"^\s*GO\s*$",RegexOptions.Multiline|RegexOptions.IgnoreCase))
            if(batch.Contains("CREATE OR ALTER PROCEDURE dbo.sp_Search")) await Exec(batch);
        using (var config = JsonDocument.Parse(await File.ReadAllTextAsync(Path.Combine(mcp, "dab-config.json"))))
            foreach (var entity in new[] { "SessionSummary", "SessionMetrics", "TopMethodsBySession" })
                Check(config.RootElement.GetProperty("entities").GetProperty(entity).GetProperty("source")
                    .GetProperty("key-fields").EnumerateArray().Any(x => x.GetString() == "TraceId"),
                    entity + " pagination key must include trace identity.");

        await Exec("""
            SET IDENTITY_INSERT dbo.Traces ON;
            INSERT dbo.Traces(TraceId,TraceName,TraceFile,TimeStampBegin,TimeStampEnd,TraceParserVersion)
            VALUES(9001,N'synthetic analysis A',N'synthetic',GETUTCDATE(),GETUTCDATE(),N'safe-import-v2'),
                  (9002,N'synthetic analysis B',N'synthetic',GETUTCDATE(),GETUTCDATE(),N'safe-import-v2');
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
                MethodHash,HasChildren,FileName,EventId,EventType,LineNumber,IsComplete)
                VALUES(@thread,@type,@sequence,@sequence,0,0,@duration,0,@db,@parent,0,@calls,0,0,0,0,
                CASE WHEN @type=8 THEN 123 ELSE NULL END,0,N'synthetic',0,0,0,1)
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

        // Unit and threshold decisions use recorded provenance, not plausible numbers.
        await Exec("UPDATE dbo.Traces SET TraceParserVersion='safe-import-v1' WHERE TraceId=9002;");
        Check(await Number("SELECT COUNT(*) FROM dbo.vw_NPlusOnePatterns WHERE TraceId=9002")==0,
            "v1's 100ms average cannot pass the 5ms N+1 threshold as a fake 1ms average");
        await Exec("UPDATE dbo.Traces SET TraceParserVersion='7.0.7697.0' WHERE TraceId=9002;");
        Check(await Number("SELECT COUNT(*) FROM dbo.vw_TraceLineDetails WHERE TraceId=9002 AND InclusiveMs IS NULL AND StoredDurationUnit='unknown'")==2
            && await Number("SELECT COUNT(*) FROM dbo.vw_NPlusOnePatterns WHERE TraceId=9002")==0,
            "unclassified native version retains rows but has no pretend duration/threshold classification");
        foreach(var version in new[]{"safe-import-v1 ","SAFE-IMPORT-V1","unclassified"})
        {
            await Exec($"UPDATE dbo.Traces SET TraceParserVersion='{version}' WHERE TraceId=9002;");
            Check(await Number("SELECT COUNT(*) FROM dbo.vw_TraceDurationUnits WHERE TraceId=9002 AND NanosecondsPerStoredUnit IS NULL")==1,
                "provenance matching is exact, never case/whitespace inference");
        }
        await Exec("INSERT dbo.QueryStatements VALUES(777,'SELECT synthetic');");
        await Line(9105,3,null,64,1,60_000_000,60_000_000);
        await Exec("UPDATE dbo.TraceLines SET QueryStatementHash=777 WHERE UserSessionProcessThreadId=9105 AND Sequence=3;");
        Check(await Number("SELECT COUNT(*) FROM dbo.vw_SlowSqlStatements WHERE TraceId=9002")==0,
            "unknown units do not pass the slow-SQL threshold");
        await Exec("UPDATE dbo.Traces SET TraceParserVersion='safe-import-v1' WHERE TraceId=9002;");
        Check(await Number("SELECT ExecutionMs FROM dbo.vw_SlowSqlStatements WHERE TraceId=9002")==6000,
            "known v1 60 million ticks means 6000ms and correctly passes slow SQL");
        await Line(9105,4,null,8,0,0,long.MaxValue);
        Check(await Number("SELECT InclusiveDurationNano FROM dbo.vw_UnitAwareTraceLines WHERE TraceId=9002 AND Sequence=4")==922337203685477580700m,
            "read normalization converts before multiplication and cannot overflow bigint");

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
            foreach (var version in new[] { "safe-import-v1", "safe-import-v2" })
            {
            var factor = version == "safe-import-v1" ? 1 : 100;
            var id = Guid.NewGuid();
            var blob = $"_imports/{id:D}/sample.etl";
            // The analytical rows above were seeded outside the importer, in this disposable DB only.
            await Exec("UPDATE dbo.TraceLineIDControls SET NextTraceLineId=(SELECT MAX(TraceLineId)+1 FROM dbo.TraceLines);");
            await Exec($"EXEC dbo.tp_RegisterUpload '{id}',N'account',N'etl-uploads',N'{blob}',N'synthetic units','{version}';");
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
            Check(receipt.ParserVersion == version && rawOuter == 800000*factor && rawPreparation == 10000*factor
                && rawExecution == 20000*factor && rawFetch == 30000*factor,
                "Versioned output: v1 unchanged ticks, v2 correct nanoseconds for known independent timings.");
            var oraclePath=Path.Combine(Path.GetDirectoryName(etlPath)!,"synthetic-small.etl.rows.json");
            if(new FileInfo(oraclePath).Length>50000 ||
                Convert.ToHexString(SHA256.HashData(await File.ReadAllBytesAsync(oraclePath))) !=
                "90D573987FF4C76D278A02B7304E42557C7B930576694AD04BC1C8AF72A01D1D")
                throw new InvalidOperationException("Expected pinned, pre-change eight-row parser capture.");
            using(var oracle=JsonDocument.Parse(await File.ReadAllTextAsync(oraclePath)))
            foreach(var item in oracle.RootElement.GetProperty("rows").EnumerateArray())
            {
                var options=new JsonSerializerOptions { IncludeFields=true };
                var expected=JsonSerializer.Deserialize<StageRow>(item.GetRawText(),options)!;
                // Independent baseline row capture, not the implementation's encoder.
                expected.IncNano*=factor; expected.ExcNano*=factor; expected.DbNano*=factor;
                expected.PrepNano*=factor; expected.BindNano*=factor; expected.FetchNano*=factor;
                var fingerprint=Convert.ToHexString(SHA256.HashData(JsonSerializer.SerializeToUtf8Bytes(expected,options)));
                Check(await Number($"SELECT COUNT(*) FROM dbo.TPImportLines WHERE ImportId='{id}' AND Sequence={expected.Seq} AND PayloadHash=0x{fingerprint}")==1,
                    $"{version} exact payload fingerprint incl all duration fields, FILETIME and non-duration fields.");
            }
            await importer.PromoteStageToTraceLines(connection);
            await importer.CompleteImportAsync(connection);
            var displayed = await Number($"SELECT InclusiveMs FROM dbo.vw_TraceLineDetails WHERE TraceId={receipt.TraceId} AND Sequence=1");
            Check(displayed == 80m && displayed == (decimal)elapsed["SyntheticFixture.Outer"],
                "Known v1/v2 read normalization both show independently encoded 80ms without rewriting raw rows.");
            Console.WriteLine(JsonSerializer.Serialize(new {
                Kind = "DurationKnownAnswer", FixtureSha256 = hash, IndependentElapsedMs = 80,
                ExpectedNanoseconds = 80000000, ActualStoredNanoField = rawOuter, ActualViewMs = displayed,
                Status = "Correct versioned import/read; no historical rewrite", ParserVersion=version,
                PreparationSeconds = 0.001, ActualPreparationNanoField = rawPreparation,
                ExecutionSeconds = 0.002, ActualExecutionNanoField = rawExecution, ActualFetchNanoField = rawFetch
            }));
            }
        }
        // Reconcile actual materialized readers, not only reference raw aggregation.
        foreach(var batch in Regex.Split(await File.ReadAllTextAsync(Path.Combine(AppContext.BaseDirectory,"duration-aggregates.sql")),
            @"^\s*GO\s*$",RegexOptions.Multiline|RegexOptions.IgnoreCase).Skip(1))
            if(!string.IsNullOrWhiteSpace(batch)) await Exec(batch);
        await Exec("""
            INSERT dbo.SessionMetrics(TraceId,SessionId,TotalTraceLines,RootCalls,TotalDurationMs,
                TotalDatabaseMs,TotalDatabaseCalls,TotalRpcCalls,TotalRowsFetched)
                VALUES(9002,1,4,2,0.8,0.1,3737,0,0);
            INSERT dbo.TopMethodsBySession(SessionId,TraceId,MethodName,CallCount,TotalInclusiveMs,
                TotalExclusiveMs,AvgInclusiveMs,TotalDbCalls,TotalDbMs)
                VALUES(1,9002,'legacy synthetic',1,0.8,0.5,0.8,101,0.1);
            """);
        Check(await Number("SELECT COUNT(*) FROM dbo.vw_SessionMetrics WHERE TraceId=9002 AND TotalDurationMs IS NULL AND TotalDatabaseCalls IS NULL AND AggregationVersion='legacy-unverified' AND TotalTraceLines=4")==1,
            "legacy physical session aggregates retain counts and explicitly withhold unreliable totals");
        Check(await Number("SELECT TotalInclusiveMs FROM dbo.vw_TopMethodsBySession WHERE TraceId=9002")==80
            && await Number("SELECT TotalPrecisionMs FROM dbo.vw_TopMethodsBySession WHERE TraceId=9002")==1,
            "legacy physical v1 method totals normalize on read with honest 1ms precision");
        await Exec("UPDATE dbo.Traces SET TraceParserVersion='native-unclassified' WHERE TraceId=9002;");
        Check(await Number("SELECT COUNT(*) FROM dbo.vw_TopMethodsBySession WHERE TraceId=9002 AND TotalInclusiveMs IS NULL")==1,
            "unclassified physical method aggregate times are NULL");
        Check(await Number("SELECT TotalInclusiveMs FROM dbo.TopMethodsBySession WHERE TraceId=9002")==0.8m
            && await Number("SELECT TotalDatabaseCalls FROM dbo.SessionMetrics WHERE TraceId=9002")==3737,
            "original historical aggregate numbers remain untouched");
        if(etlPath is not null)
            Check(await Number("SELECT COUNT(*) FROM dbo.vw_SessionMetrics s JOIN dbo.Traces t ON t.TraceId=s.TraceId WHERE t.TraceName='synthetic units' AND s.TotalDurationMs=80 AND s.AggregationVersion='sql-execution-v2'")==2,
                "both genuine v1/v2 imports publish correct 80ms materialized session metrics");
        await Line(9103,9000,null,8,0,0,0);
        await Exec("UPDATE dbo.TraceLines SET IsComplete=0 WHERE UserSessionProcessThreadId=9103 AND Sequence=9000; EXEC dbo.sp_PopulateSessionAggregations 9001;");
        Check(await Number("SELECT COUNT(*) FROM dbo.vw_SessionMetrics WHERE TraceId=9001 AND SessionId=3 AND TotalDurationMs IS NULL AND DurationStatus='unknown-values'")==1,
            "negative/missing duration sentinels cannot become a pretend complete physical total");
        Check(await Number("SELECT TotalDatabaseCalls FROM dbo.vw_SessionMetrics WHERE TraceId=9001 AND SessionId=1")==101,
            "materialized session DB count uses execution grain, not inclusive 37:1 counters");
        Check(await Number("SELECT COUNT(*) FROM dbo.vw_SessionMetrics WHERE TraceId=9001 AND SessionId=2 AND TotalDurationMs IS NULL AND DurationStatus='unknown-values'")==1
            && await Number("SELECT COUNT(*) FROM dbo.vw_TopMethodsBySession WHERE TraceId=9001 AND SessionId=2 AND TotalInclusiveMs IS NULL")==1,
            "unfinished zero-duration call cannot certify a known session or method duration");
        await Exec("""
            INSERT dbo.Messages VALUES(888,'synthetic message');
            UPDATE dbo.TraceLines SET MessageHash=888 WHERE UserSessionProcessThreadId=9105 AND Sequence=1;
            INSERT dbo.TopMethods(Id,BeginUspId,EndUspId,Name,Count,InclusiveTotal,ExclusiveTotal,RpcTotal,DatabaseCallTotal,Type)
                VALUES(123,9105,9105,'synthetic',1,80000000,30000000,0,2,'InclusiveXpp');
            """);
        foreach(var procedure in new[]{"sp_SearchTracesByKeyword","sp_SearchSqlStatements","sp_SearchMethods","sp_SearchMessages"})
        {
            using var cmd=new SqlCommand($"EXEC dbo.{procedure} @TraceId=9002,@Keyword=N'synthetic'",connection);
            using var reader=await cmd.ExecuteReaderAsync();
            var count=0;
            while(await reader.ReadAsync())
            {
                count++;
                Check(reader.GetString(reader.GetOrdinal("StoredDurationUnit"))=="unknown",
                    procedure+" explicitly exposes unknown historical provenance");
                for(var i=0;i<reader.FieldCount;i++)
                    if(reader.GetName(i).EndsWith("Ms",StringComparison.Ordinal))
                        Check(reader.IsDBNull(i),procedure+" cannot emit pretend millisecond timing");
            }
            Check(count>0,procedure+" exercised real synthetic matching rows");
        }
        Check(await Number("SELECT COUNT(*) FROM dbo.vw_TopMethodsWithUnits WHERE Id=123 AND InclusiveTotal IS NULL AND StoredInclusiveTotal=80000000")==1,
            "legacy native TopMethods retains original values without inferring units");
        await Exec("UPDATE dbo.Traces SET TraceParserVersion='ps-import-v2' WHERE TraceId=9002;");
        Check(await Number("SELECT InclusiveTotal FROM dbo.vw_TopMethodsWithUnits WHERE Id=123")==80000000
            && await Number("SELECT COUNT(*) FROM dbo.vw_TopMethodsWithUnits WHERE Id=123 AND StoredDurationUnit='nanoseconds'")==1,
            "proven direct PowerShell same-trace TopMethods exposes correct nanoseconds");
        await Exec("UPDATE dbo.Traces SET TraceParserVersion='native-unclassified' WHERE TraceId=9002;");
        Console.WriteLine($"PASS {checks} analytical checks; 37:1 inclusive inflation reproduced; " +
            (etlPath is null ? "ETL unit checks SKIPPED." : "v1/v2 exact fingerprints and corrected 80ms verified."));
        return checks;
    }
}
