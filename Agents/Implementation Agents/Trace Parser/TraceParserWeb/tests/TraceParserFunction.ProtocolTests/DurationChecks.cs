using System.Security.Cryptography;
using System.Text;
using Microsoft.Data.SqlClient;
using Microsoft.Extensions.Logging.Abstractions;
using TraceParserFunction;

static class DurationChecks
{
    public static async Task<int> UpgradeAnalysisAsync(SqlConnection db,string directory,string artifact)
    {
        var checks=0;
        void Check(bool ok,string message)
        {
            if(!ok) throw new Exception(message);
            checks++; Console.WriteLine("PASS "+message);
        }
        await Exec(db,"ALTER TABLE dbo.Traces ADD AxVersion nvarchar(50) NULL;");
        var names=new[]{"sp_PopulateSessionAggregations","vw_NPlusOnePatterns","vw_SessionMetrics",
            "vw_SessionSummary","vw_SlowSqlStatements","vw_TopMethodsBySession","vw_TraceLineDetails",
            "sp_SearchTracesByKeyword","sp_SearchSqlStatements","sp_SearchMethods","sp_SearchMessages"};
        foreach(var name in names)
        {
            // Read only the explicitly supplied sanitized module capture files. The
            // generated upgrade verifies every exact production module hash itself.
            var text=await File.ReadAllTextAsync(Path.Combine(directory,"deployed.dbo."+name+".sql"));
            await Exec(db,$"DROP {(name.StartsWith("vw_")?"VIEW":"PROCEDURE")} IF EXISTS dbo.{name};");
            await Exec(db,text);
        }
        var upgrade=await File.ReadAllTextAsync(artifact);
        await Exec(db,"""
            INSERT dbo.Traces(TraceName,TraceFile,TimeStampBegin,TimeStampEnd,TraceParserVersion)
                VALUES('synthetic retained aggregate','fixture',GETUTCDATE(),GETUTCDATE(),'safe-import-v1');
            DECLARE @trace int=SCOPE_IDENTITY();
            CREATE TABLE #AggregateRoot(TraceId int);
            INSERT #AggregateRoot VALUES(@trace);
            INSERT dbo.SessionMetrics(TraceId,SessionId,TotalTraceLines,RootCalls,TotalDurationMs,
                TotalDatabaseMs,TotalDatabaseCalls,TotalRpcCalls,TotalRowsFetched)
                VALUES(@trace,1,8,1,0.8,0.12,3737,0,0);
            INSERT dbo.TopMethodsBySession(SessionId,TraceId,MethodName,CallCount,TotalInclusiveMs,
                TotalExclusiveMs,AvgInclusiveMs,TotalDbCalls,TotalDbMs)
                VALUES(1,@trace,'retained historical',1,0.8,0.5,0.8,101,0.12);
            EXEC dbo.dj_Enqueue '00000000-0000-0000-0000-000000000010',
                '00000000-0000-0000-0000-000000000011','00000000-0000-0000-0000-000000000012',@trace;
            ALTER TABLE dbo.QueryBindParameters NOCHECK CONSTRAINT ALL;
            ALTER TABLE dbo.XppParameters NOCHECK CONSTRAINT ALL;
            """);
        var before=await Snapshot(db);
        var lateFailure=System.Text.RegularExpressions.Regex.Replace(upgrade,
            @"EXEC dbo.dj_AssertProtocol;\r?\nCOMMIT;",
            "EXEC dbo.dj_AssertProtocol;\nTHROW 51299,'Synthetic late migration failure',1;\nCOMMIT;");
        Check(lateFailure!=upgrade,"failure injection is after all analytical schema/module edits");
        await Reject(51299,()=>Exec(db,lateFailure));
        Check(await Number(db,"SELECT COUNT(*) FROM sys.views WHERE name='vw_TraceDurationUnits'")==0
            && before==await Snapshot(db),"late analysis migration failure atomically rolls back schema/modules and preserves all historical data/jobs");
        await Exec(db,upgrade);
        Check(before==await Snapshot(db),"actual captured materialized baseline upgrade preserves rows, receipt hashes, aggregate numbers, deletion jobs and disabled FKs");
        Console.WriteLine(System.Text.Json.JsonSerializer.Serialize(new{Kind="AnalysisUpgradeHistoricalHash",
            Before=before,After=await Snapshot(db),RetainedQueuedJobs=1,HistoricalBackfill=false}));
        Check(await Number(db,"SELECT TotalInclusiveMs FROM dbo.vw_TopMethodsBySession WHERE MethodName='retained historical'")==80,
            "actual upgraded physical v1 method reader returns 80ms from untouched 0.8");
        Check(await Number(db,"SELECT COUNT(*) FROM dbo.vw_SessionMetrics WHERE TraceId=(SELECT TraceId FROM #AggregateRoot) AND TotalDurationMs IS NULL AND TotalDatabaseCalls IS NULL AND TotalTraceLines=8")==1,
            "actual upgraded legacy physical session reader withholds unreliable totals without raw full scans");
        await Reject(51128,()=>Exec(db,upgrade));
        Check(before==await Snapshot(db),"analysis upgrade replay refuses re-adoption and never rewrites historical rows");
        await Exec(db,"""
            DELETE r FROM dbo.TraceDeletionRequests r JOIN dbo.TraceDeletionJobs j ON j.JobId=r.JobId
                WHERE j.TraceId=(SELECT TraceId FROM #AggregateRoot);
            DELETE dbo.TraceDeletionJobs WHERE TraceId=(SELECT TraceId FROM #AggregateRoot);
            DELETE dbo.SessionMetrics WHERE TraceId=(SELECT TraceId FROM #AggregateRoot);
            DELETE dbo.TopMethodsBySession WHERE TraceId=(SELECT TraceId FROM #AggregateRoot);
            DELETE dbo.Traces WHERE TraceId=(SELECT TraceId FROM #AggregateRoot);
            DROP TABLE #AggregateRoot;
            ALTER TABLE dbo.QueryBindParameters WITH CHECK CHECK CONSTRAINT ALL;
            ALTER TABLE dbo.XppParameters WITH CHECK CHECK CONSTRAINT ALL;
            """);
        return checks;
    }

    public static async Task<int> UpgradeAsync(SqlConnection db)
    {
        var checks=0;
        void Check(bool ok,string message)
        {
            if(!ok) throw new Exception(message);
            checks++; Console.WriteLine("PASS "+message);
        }
        var upgrade=await File.ReadAllTextAsync(Path.Combine(AppContext.BaseDirectory,"duration-import-v2.sql"));
        await Exec(db,"""
            CREATE TABLE #DurationRoots(TraceId int,ImportId uniqueidentifier);
            DECLARE @phase varchar(24),@id uniqueidentifier,@trace int;
            DECLARE phases CURSOR LOCAL FAST_FORWARD FOR SELECT p FROM
                (VALUES('Parsing'),('Ready'),('Promoting'),('Complete')) v(p);
            OPEN phases; FETCH NEXT FROM phases INTO @phase;
            WHILE @@FETCH_STATUS=0
            BEGIN
                SET @id=NEWID();
                INSERT dbo.Traces(TraceName,TraceFile,TimeStampBegin,TimeStampEnd,TraceParserVersion)
                    VALUES('synthetic migration preservation','fixture.etl',GETUTCDATE(),GETUTCDATE(),'safe-import-v1');
                SET @trace=SCOPE_IDENTITY();
                INSERT #DurationRoots VALUES(@trace,@id);
                INSERT dbo.TPImportReceipts(ImportId,SourceKey,AccountName,ContainerName,BlobName,SessionName,
                    ParserVersion,TraceId,Phase,ContentHash,ExpectedRows,ExpectedBinds,LastPromotedId)
                VALUES(@id,HASHBYTES('SHA2_256',CONVERT(varchar(36),@id)),'fixture','etl-uploads',
                    CONCAT('_imports/',LOWER(CONVERT(varchar(36),@id)),'/fixture.etl'),'fixture',
                    'safe-import-v1',@trace,@phase,HASHBYTES('SHA2_256','retained-content'),8,2,CASE WHEN @phase='Promoting' THEN 2 ELSE 0 END);
                INSERT dbo.TPImportBinds VALUES(@id,5,0,'retained bind',HASHBYTES('SHA2_256','retained-payload'));
                INSERT dbo.TPImportLines(TraceLineId,UserSessionProcessThreadId,CallTypeId,Sequence,SequenceEnd,
                    TimeStamp,TimeStampEnd,InclusiveDurationNano,ExclusiveDurationNano,DatabaseDurationNano,
                    InclusiveRpc,DatabaseCalls,PrepDurationNano,BindDurationNano,RowFetchDurationNano,
                    RowFetchCount,HasChildren,FileName,EventId,EventType,LineNumber,ImportId,PayloadHash)
                VALUES(900000+@trace,-1,8,1,8,134342968939507772,134342968940307772,
                    800000,500000,120000,0,2,10000,60000,30000,1,1,'retained fixture',24501,1,0,@id,
                    HASHBYTES('SHA2_256','retained-line-payload'));
                FETCH NEXT FROM phases INTO @phase;
            END;
            CLOSE phases; DEALLOCATE phases;
            -- Historical disabled/untrusted parameter constraints are a supported baseline.
            ALTER TABLE dbo.QueryBindParameters NOCHECK CONSTRAINT ALL;
            ALTER TABLE dbo.XppParameters NOCHECK CONSTRAINT ALL;
            """);
        var before=await Snapshot(db);
        string original;
        using(var command=new SqlCommand("SELECT OBJECT_DEFINITION(OBJECT_ID('dbo.tp_RegisterUpload'))",db))
            original=(string)(await command.ExecuteScalarAsync())!;
        await Exec(db,"ALTER PROCEDURE dbo.tp_RegisterUpload AS SELECT 1;");
        await Reject(51128,()=>Exec(db,upgrade));
        Check(before==await Snapshot(db),"importer semantic drift blocks upgrade before any historical mutation");
        await Exec(db,"DROP PROCEDURE dbo.tp_RegisterUpload;");
        await Exec(db,original);
        await Exec(db,upgrade);
        Check(before==await Snapshot(db),"upgrade preserves all original receipt/content/payload hashes, root identities, jobs and disabled FKs byte-for-byte");
        Console.WriteLine(System.Text.Json.JsonSerializer.Serialize(new{Kind="ImporterUpgradeHistoricalHash",
            Before=before,After=await Snapshot(db),Phases=new[]{"Parsing","Ready","Promoting","Complete"}}));
        Check(await Number(db,"SELECT COUNT(*) FROM sys.procedures WHERE name LIKE 'tp[_]%'")==16,
            "coordinated upgrade retains exact 16-module importer contract");
        await Reject(51128,()=>Exec(db,upgrade));
        Check(before==await Snapshot(db),"repeated upgrade fails closed without mutating historical records");
        await Exec(db,"EXEC dbo.tp_AssertDeletionProtocol; EXEC dbo.dj_AssertProtocol;");
        Check(true,"durable/legacy deletion fingerprints and schema remain valid");
        await Exec(db,"""
            DELETE l FROM dbo.TPImportLines l JOIN #DurationRoots r ON r.ImportId=l.ImportId;
            DELETE b FROM dbo.TPImportBinds b JOIN #DurationRoots r ON r.ImportId=b.ImportId;
            DELETE b FROM dbo.TPImportReceipts b JOIN #DurationRoots r ON r.ImportId=b.ImportId;
            DELETE t FROM dbo.Traces t JOIN #DurationRoots r ON r.TraceId=t.TraceId;
            DROP TABLE #DurationRoots;
            ALTER TABLE dbo.QueryBindParameters WITH CHECK CHECK CONSTRAINT ALL;
            ALTER TABLE dbo.XppParameters WITH CHECK CHECK CONSTRAINT ALL;
            """);
        return checks;
    }

    public static async Task<int> ContractsAsync(SqlConnection db)
    {
        var checks=0;
        void Check(bool ok,string message)
        {
            if(!ok) throw new Exception(message);
            checks++; Console.WriteLine("PASS "+message);
        }
        foreach(var phase in new[]{"Registered","Parsing","Ready","Promoting","Complete"})
        {
            var id=Guid.NewGuid();
            var blob=$"_imports/{id:D}/synthetic.etl";
            await Exec(db,$"EXEC dbo.tp_RegisterUpload '{id}','account','etl-uploads','{blob}','fixture','safe-import-v2';");
            // Old worker sends no WorkerVersion. Even terminal/Ready receipts cannot
            // bypass capability negotiation (the root stays absent for Registered).
            if(phase!="Registered")
                await Exec(db,$"UPDATE dbo.TPImportReceipts SET Phase='{phase}' WHERE ImportId='{id}';");
            await Reject(51107,()=>Exec(db,$"EXEC dbo.tp_BeginImport 'account','etl-uploads','{blob}','\"fixture\"',0;"));
            Check(await Number(db,$"SELECT COUNT(*) FROM dbo.TPImportReceipts WHERE ImportId='{id}' AND TraceId IS NULL AND ParserVersion='safe-import-v2'")==1,
                $"old worker refuses v2 {phase} before mutation");
            await Exec(db,$"DELETE dbo.TPImportReceipts WHERE ImportId='{id}';");
        }
        foreach(var version in new[]{"safe-import-v3","","SAFE-IMPORT-V2","safe-import-v2 "})
        {
            var id=Guid.NewGuid();
            // Case matching is deliberately checked too: recorded provenance is exact.
            await Reject(51107,()=>Exec(db,$"EXEC dbo.tp_RegisterUpload '{id}','account','etl-uploads','_imports/{id:D}/synthetic.etl','fixture','{version}';"));
            Check(true,"unrecognized registration version fails closed: "+version);
        }
        var invalidId=Guid.NewGuid();
        var invalidBlob=$"_imports/{invalidId:D}/synthetic.etl";
        await Exec(db,$"EXEC dbo.tp_RegisterUpload '{invalidId}','account','etl-uploads','{invalidBlob}','fixture';");
        await Reject(51107,()=>Exec(db,$"EXEC dbo.tp_BeginImport 'account','etl-uploads','{invalidBlob}','\"fixture\"',0,@WorkerVersion='future-worker';"));
        await Exec(db,$"UPDATE dbo.TPImportReceipts SET ParserVersion='unclassified' WHERE ImportId='{invalidId}';");
        var importer=new SqlImporter(NullLogger<SqlImporter>.Instance);
        await Reject(51107,()=>importer.BeginImportAsync(db,"account","etl-uploads",invalidBlob,"\"fixture\"",default));
        Check(await Number(db,$"SELECT COUNT(*) FROM dbo.TPImportReceipts WHERE ImportId='{invalidId}' AND TraceId IS NULL AND ParserVersion='unclassified'")==1,
            "unsupported worker/receipt versions stay unclaimed and are never downgraded");
        await Exec(db,$"DELETE dbo.TPImportReceipts WHERE ImportId='{invalidId}';");
        var sentinel=new StageRow { IncNano=-1,ExcNano=-2,DbNano=123,PrepNano=10000,
            BindNano=20000,FetchNano=30000,TS=134342968939507772,TSEnd=134342968940307772,DbCalls=5,Rpc=9 };
        var encoded=DurationContract.Encode(sentinel,"safe-import-v2");
        Check(encoded.IncNano==-1 && encoded.ExcNano==-2 && encoded.DbNano==12300
            && encoded.PrepNano==1000000 && encoded.BindNano==2000000 && encoded.FetchNano==3000000
            && encoded.TS==sentinel.TS && encoded.TSEnd==sentinel.TSEnd && encoded.DbCalls==5 && encoded.Rpc==9
            && sentinel.DbNano==123,"six duration fields convert on a copy; timestamps/counts/negative sentinels stay unchanged");
        Check(ReferenceEquals(sentinel,DurationContract.Encode(sentinel,"safe-import-v1")),
            "v1 output uses original row without any conversion");
        try { DurationContract.Encode(sentinel,"unknown"); throw new Exception("Unknown version accepted"); }
        catch(InvalidOperationException) { Check(true,"C# encoder refuses unsupported version"); }
        try { DurationContract.Encode(new(){IncNano=long.MaxValue},"safe-import-v2"); throw new Exception("Overflow accepted"); }
        catch(OverflowException) { Check(true,"duration multiplication overflows closed before staging"); }
        return checks;
    }

    static async Task<string> Snapshot(SqlConnection db)
    {
        var text=new StringBuilder();
        foreach(var sql in new[]{
            "SELECT * FROM dbo.TPImportReceipts ORDER BY ImportId FOR JSON PATH,INCLUDE_NULL_VALUES",
            "SELECT * FROM dbo.TPImportBinds ORDER BY ImportId,Sequence,ParameterIndex FOR JSON PATH,INCLUDE_NULL_VALUES",
            "SELECT * FROM dbo.TPImportLines ORDER BY ImportId,Sequence FOR JSON PATH,INCLUDE_NULL_VALUES",
            "SELECT * FROM dbo.Traces ORDER BY TraceId FOR JSON PATH,INCLUDE_NULL_VALUES",
            "SELECT * FROM dbo.TraceDeletionJobs ORDER BY JobId FOR JSON PATH,INCLUDE_NULL_VALUES",
            "SELECT * FROM dbo.TraceDeletionRequests ORDER BY JobId,RequestKey FOR JSON PATH,INCLUDE_NULL_VALUES",
            "SELECT TraceId,SessionId,SessionName,UserName,TraceName,TotalTraceLines,RootCalls,TotalDurationMs,TotalDatabaseMs,TotalDatabaseCalls,TotalRpcCalls,TotalRowsFetched,ComputedAtUtc FROM dbo.SessionMetrics ORDER BY TraceId,SessionId FOR JSON PATH,INCLUDE_NULL_VALUES",
            "SELECT Id,SessionId,TraceId,MethodName,CallCount,TotalInclusiveMs,TotalExclusiveMs,AvgInclusiveMs,TotalDbCalls,TotalDbMs,ComputedAtUtc FROM dbo.TopMethodsBySession ORDER BY Id FOR JSON PATH,INCLUDE_NULL_VALUES",
            "SELECT name,is_disabled,is_not_trusted FROM sys.foreign_keys ORDER BY name FOR JSON PATH"})
        {
            using var cmd=new SqlCommand(sql,db);
            using var reader=await cmd.ExecuteReaderAsync();
            while(await reader.ReadAsync()) text.Append(reader.GetString(0));
        }
        return Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(text.ToString())));
    }
    internal static async Task Exec(SqlConnection db,string sql)
    {
        using var cmd=new SqlCommand(sql,db){CommandTimeout=30};
        await cmd.ExecuteNonQueryAsync();
    }
    internal static async Task<decimal> Number(SqlConnection db,string sql)
    {
        using var cmd=new SqlCommand(sql,db);
        return Convert.ToDecimal(await cmd.ExecuteScalarAsync());
    }
    internal static async Task Reject(int number,Func<Task> action)
    {
        try { await action(); }
        catch(SqlException ex) when(ex.Number==number) { return; }
        throw new Exception($"Expected SQL rejection {number}");
    }
}
