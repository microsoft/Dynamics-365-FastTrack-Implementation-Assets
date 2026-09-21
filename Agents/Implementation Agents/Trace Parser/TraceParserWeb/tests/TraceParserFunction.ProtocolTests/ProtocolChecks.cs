using System.Data;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using System.Text.Json;
using Microsoft.Data.SqlClient;
using Microsoft.Extensions.Logging.Abstractions;
using TraceParserFunction;

// This executable intentionally accepts no connection string or database argument.
var runLarge=false;
var lockOrderOnly=false;
string? etlFixture=null;
for(var arg=0;arg<args.Length;arg++)
{
    if(args[arg]=="--large" && !runLarge) runLarge=true;
    else if(args[arg]=="--lock-order" && !lockOrderOnly) lockOrderOnly=true;
    else if(args[arg]=="--etl-fixture" && etlFixture is null && arg+1<args.Length)
        etlFixture=Path.GetFullPath(args[++arg]);
    else throw new ArgumentException("Only --large, --lock-order and --etl-fixture <approved synthetic ETL> are supported; connection overrides are prohibited.");
}
if(etlFixture is not null && (!File.Exists(etlFixture) ||
    Path.GetFileName(etlFixture) is not ("synthetic-small.etl" or "synthetic-large.etl" or "synthetic-near-limit.etl")))
    throw new ArgumentException("Use an approved synthetic-small.etl, synthetic-large.etl or synthetic-near-limit.etl fixture; no customer ETL.");
const string instance = @"(localdb)\TPImporterTests_c100bb02";
var database = "TPImporterProtocol_" + Guid.NewGuid().ToString("N");
var masterString = new SqlConnectionStringBuilder
{
    DataSource = instance, InitialCatalog = "master", IntegratedSecurity = true,
    Encrypt = false, Pooling = false, ConnectRetryCount = 0, ConnectTimeout = 15
}.ConnectionString;
var databaseString = new SqlConnectionStringBuilder(masterString) { InitialCatalog = database }.ConnectionString;
if (!Regex.IsMatch(database, "^TPImporterProtocol_[0-9a-f]{32}$") || instance != @"(localdb)\TPImporterTests_c100bb02")
    throw new InvalidOperationException("Unsafe fixture target.");
var checks = 0;
var created = false;
var wholeTest=System.Diagnostics.Stopwatch.StartNew();
await using var master = new SqlConnection(masterString);
await master.OpenAsync();
try
{
    await Exec(master, $"CREATE DATABASE [{database}]");
    created = true;
    Console.WriteLine($"CREATED {database}");
    await using (var setup = await Open())
    {
        foreach (var path in new[] { "Fixture.sql", "safe-importer.sql" })
        {
            if(path=="safe-importer.sql") await ExecutorInboundChecks(setup);
            foreach (var batch in Regex.Split(await File.ReadAllTextAsync(Path.Combine(AppContext.BaseDirectory, path)),
                         @"^\s*GO\s*$", RegexOptions.Multiline | RegexOptions.IgnoreCase))
                if (!string.IsNullOrWhiteSpace(batch)) await Exec(setup, batch);
        }
        var beforeGuard=await Register();
        await using(var activation=await Open())
        {
            await Reject(51122,()=>Importer().BeginImportAsync(activation,"account","etl-uploads",Name(beforeGuard),"\"v1\"",default));
            Check(await Scalar(activation,"SELECT COUNT(*) FROM dbo.Traces")==0,"activation before coordinated deletion creates no trace");
        }
        await Exec(setup,await File.ReadAllTextAsync(Path.Combine(AppContext.BaseDirectory,"sp_DeleteTrace.sql")));
    }
    if(!lockOrderOnly) await RunChecks();
    foreach(var snapshot in new[]{false,true})
    {
        await Exec(master,$"ALTER DATABASE [{database}] SET READ_COMMITTED_SNAPSHOT {(snapshot?"ON":"OFF")};");
        await LockOrderChecks(snapshot);
    }
    Console.WriteLine($"PASS {checks} protocol checks. Fixture={database}");
}
finally
{
    if (created)
    {
        // The name is generated here and never supplied externally. No other fixture is touched.
        await Exec(master, $"ALTER DATABASE [{database}] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [{database}];");
        Console.WriteLine($"CLEANED {database}");
    }
    Console.WriteLine(JsonSerializer.Serialize(new { Kind="WholeProtocolTestWallTime",ElapsedSeconds=wholeTest.Elapsed.TotalSeconds }));
}

async Task ExecutorInboundChecks(SqlConnection setup)
{
    await Exec(setup,"CREATE USER TPImportPromotionExecutor WITHOUT LOGIN; CREATE USER ProtocolInboundProbe WITHOUT LOGIN;");
    var migration=await File.ReadAllTextAsync(Path.Combine(AppContext.BaseDirectory,"safe-importer.sql"));
    foreach(var (permission,state) in new[]{("IMPERSONATE","G"),("CONTROL","G"),("ALTER","G"),
        ("IMPERSONATE","W"),("VIEW DEFINITION","G"),("IMPERSONATE","D")})
    {
        var verb=state=="D"?"DENY":"GRANT";
        var option=state=="W"?" WITH GRANT OPTION":"";
        await Exec(setup,$"{verb} {permission} ON USER::TPImportPromotionExecutor TO ProtocolInboundProbe{option};");
        var refused=false;
        try
        {
            foreach(var batch in Regex.Split(migration,@"^\s*GO\s*$",RegexOptions.Multiline|RegexOptions.IgnoreCase))
                if(!string.IsNullOrWhiteSpace(batch)) await Exec(setup,batch);
        }
        catch(SqlException ex) when(ex.Number==51126) { refused=true; }
        if(!refused)
        {
            // Reproduction of the reviewed bug. This branch must become unreachable.
            await using var probe=await Open();
            await Exec(probe,"EXECUTE AS USER='ProtocolInboundProbe'; EXECUTE AS USER='TPImportPromotionExecutor'; ALTER TABLE dbo.TraceLines ADD InboundBypassMarker int NULL;");
            throw new Exception("Confirmed inbound authority bypass: migration accepted the grant and the runtime probe altered TraceLines outside the guarded module.");
        }
        Check(refused,$"migration rejects inbound {permission} state {state} on executor");
        Check(await Scalar(setup,"SELECT COUNT(*) FROM sys.database_permissions WHERE grantee_principal_id=DATABASE_PRINCIPAL_ID('TPImportPromotionExecutor') AND class=1 AND major_id=OBJECT_ID('dbo.TraceLines') AND permission_name='ALTER'")==0,
            "rejected pre-existing principal acquires no target ALTER");
        Check(await Scalar(setup,$"SELECT COUNT(*) FROM sys.database_permissions WHERE class=4 AND major_id=DATABASE_PRINCIPAL_ID('TPImportPromotionExecutor') AND grantee_principal_id=DATABASE_PRINCIPAL_ID('ProtocolInboundProbe') AND permission_name='{permission}' AND state='{state}'")==1,
            "migration does not silently revoke inbound permission");
        // Only the fixture resets the grant it just introduced; production never revokes.
        await Exec(setup,$"REVOKE {permission} ON USER::TPImportPromotionExecutor FROM ProtocolInboundProbe CASCADE;");
    }
}

async Task LockOrderChecks(bool snapshot)
{
    await using(var setup=await Open())
        await Exec(setup,"""
            IF USER_ID('LockOrderWeb') IS NULL CREATE USER LockOrderWeb WITHOUT LOGIN;
            IF USER_ID('LockOrderFunction') IS NULL CREATE USER LockOrderFunction WITHOUT LOGIN;
            GRANT EXECUTE ON dbo.sp_DeleteTrace TO LockOrderWeb;
            GRANT EXECUTE ON dbo.tp_PromoteImportBatch TO LockOrderFunction;
            GRANT EXECUTE ON dbo.tp_CompleteImport TO LockOrderFunction;
            """);
    foreach(var legacy in new[]{true,false})
    foreach(var operation in new[]{"Lines","Binds","Complete"})
    {
        var completedId=await Register();
        int completedTrace;
        await using(var seed=await Open())
        {
            var importer=Importer();
            completedTrace=(await importer.BeginImportAsync(seed,"account","etl-uploads",Name(completedId),"\"locks\"",default)).TraceId;
            await importer.SetContentHashAsync(seed,Hash("lock-order-completed"));
            importer.FlushStageBatch(seed,[Row(1,64),Row(2,8)],[]);
            importer.FinishDimensions(seed,completedTrace,Dimensions(completedTrace),new(){Staged=2});
            await importer.PromoteStageToTraceLines(seed);
            await importer.CompleteImportAsync(seed);
            await importer.CleanupCompletedAsync(seed);
            // Only this disposable fixture simulates a legacy root without a receipt.
            if(legacy) await Exec(seed,"DELETE dbo.TPImportReceipts WHERE ImportId=@id",completedId);
        }
        var id=await Register();
        await using var promoter=await Open();
        var active=Importer();
        var trace=(await active.BeginImportAsync(promoter,"account","etl-uploads",Name(id),"\"locks\"",default)).TraceId;
        await active.SetContentHashAsync(promoter,Hash("lock-order-active"));
        active.FlushStageBatch(promoter,[Row(1,64),Row(2,8)],[new(){TempSeq=1,ParamIdx=0,BindVal="active"}]);
        active.FinishDimensions(promoter,trace,Dimensions(trace),new(){Staged=2});
        if(operation=="Binds")
            await Exec(promoter,"EXEC dbo.tp_PromoteImportBatch @ImportId=@id,@BatchSize=2",id);
        else if(operation=="Complete")
            await active.PromoteStageToTraceLines(promoter);
        await using var observer=await Open();
        await using var deleter=await Open();
        var promoterSpid=await Scalar(promoter,"SELECT @@SPID");
        var deleterSpid=await Scalar(deleter,"SELECT @@SPID");
        await Exec(deleter,"SET DEADLOCK_PRIORITY LOW; SET TRANSACTION ISOLATION LEVEL READ COMMITTED; EXECUTE AS USER='LockOrderWeb';");
        await Reject(51130,()=>Exec(deleter,$"EXEC dbo.sp_DeleteTrace @TraceId={trace},@BatchSize=1"));
        // Test-only outer transaction represents observed lock escalation without
        // adding TABLOCKX or artificial barriers to either production procedure.
        await Exec(promoter,"BEGIN TRAN; SELECT COUNT_BIG(*) FROM dbo.TraceLines WITH(TABLOCKX,HOLDLOCK); EXECUTE AS USER='LockOrderFunction';");
        Task? deletion=null;
        try
        {
            deletion=DeleteBatch();
            var deadline=System.Diagnostics.Stopwatch.StartNew();
            while(await Scalar(observer,$"""
                SELECT COUNT(*) FROM sys.dm_tran_locks
                WHERE request_session_id={deleterSpid} AND resource_type='OBJECT'
                  AND resource_associated_entity_id=OBJECT_ID('dbo.TraceLines')
                  AND request_status='WAIT'
                """)==0)
            {
                if(deletion.IsCompleted) await deletion;
                if(deadline.Elapsed>TimeSpan.FromSeconds(15)) throw new Exception("Deletion did not reach the observable TraceLines lock barrier.");
                await Task.Delay(25);
            }
            Check(await Scalar(observer,$"""
                SELECT COUNT(*) FROM sys.dm_tran_locks
                WHERE request_session_id={promoterSpid} AND resource_type='OBJECT'
                  AND resource_associated_entity_id=OBJECT_ID('dbo.TraceLines')
                  AND request_mode='X' AND request_status='GRANT'
                """)>0,"observed promoter TraceLines X / deletion WAIT barrier");
            await Exec(promoter,operation=="Complete"
                ? "EXEC dbo.tp_CompleteImport @ImportId=@id"
                : "EXEC dbo.tp_PromoteImportBatch @ImportId=@id,@BatchSize=1",id);
            await Exec(promoter,"COMMIT;");
            await deletion;
            Check(await Scalar(observer,$"SELECT COUNT(*) FROM dbo.TPImportReceipts WHERE ImportId='{id}' AND LastPromotedId>0")==1,
                "concurrent mutation preserves its checkpoint");
            if(!legacy)
                Check(await Scalar(observer,$"SELECT COUNT(*) FROM dbo.TPImportReceipts WHERE ImportId='{completedId}' AND Phase='Deleted'")==1,
                    "first concurrent deletion commits its tombstone");
            // Continue through binding and completion while the unrelated deletion
            // is resumable. Each actual procedure still runs as an EXECUTE-only caller.
            if(operation!="Complete")
            {
                for(var remaining=0;remaining<3;remaining++)
                {
                    await Exec(promoter,"EXEC dbo.tp_PromoteImportBatch @ImportId=@id,@BatchSize=1",id);
                    await DeleteBatch();
                }
                await Exec(promoter,"EXEC dbo.tp_CompleteImport @ImportId=@id",id);
            }
            var batches=0;
            while(await Scalar(observer,$"SELECT COUNT(*) FROM dbo.Traces WHERE TraceId={completedTrace}")!=0)
            {
                if(++batches>30) throw new Exception("Concurrent deletion did not converge.");
                await DeleteBatch();
            }
            Check(await Scalar(observer,$"SELECT COUNT(*) FROM dbo.TraceLines l JOIN dbo.UserSessionProcessThreads t ON t.UserSessionProcessThreadId=l.UserSessionProcessThreadId WHERE t.TraceId={trace}")==2,
                "unrelated promoted lines preserved");
            Check(await Scalar(observer,$"SELECT COUNT(*) FROM dbo.TPImportReceipts WHERE ImportId='{id}' AND Phase='Complete' AND LastBindSequence=1 AND LastBindIndex=0")==1,
                "unrelated binding cursor and completion preserved");
            Console.WriteLine($"LOCK ORDER PASS RCSI={snapshot} legacy={legacy} operation={operation}");
        }
        finally
        {
            // Release only the test-owned pressure transaction, even on a failed barrier.
            await Exec(promoter,"IF @@TRANCOUNT>0 ROLLBACK;");
            if(deletion is not null) await deletion;
        }

        async Task DeleteBatch()
        {
            using var command=deleter.CreateCommand();
            command.CommandTimeout=45;
            command.CommandText=$"EXEC dbo.sp_DeleteTrace @TraceId={completedTrace},@BatchSize=1";
            using var reader=await command.ExecuteReaderAsync();
            if(!await reader.ReadAsync()) throw new Exception("Missing deletion acknowledgement.");
            Check(reader.GetInt32(2) is >=0 and <=1,"concurrent deletion keeps its row bound");
        }
    }
}

async Task RunChecks()
{
    await using (var legacy = await Open())
    {
        await Reject(51104, () => Importer().BeginImportAsync(legacy, "account", "etl-uploads", "old/file.etl", "\"v1\"", default));
        Check(await Scalar(legacy, "SELECT COUNT(*) FROM dbo.Traces") == 0, "legacy delivery creates no trace");
    }
    await Register();
    await Register();
    await using (var pending = await Open())
        Check(await Scalar(pending,"SELECT COUNT(*) FROM dbo.TPImportReceipts WHERE TraceId IS NULL")>=2,
            "filtered unique trace index permits multiple pending registrations");
    var id = await Register();
    var name = Name(id);
    int trace;
    long retainedId;
    await using (var first = await Open())
    {
        var importer = Importer();
        var receipt = await importer.BeginImportAsync(first, "account", "etl-uploads", name, "\"v1\"", default);
        trace = receipt.TraceId;
        Check(await Scalar(first,"SELECT COUNT(*) FROM dbo.Traces WHERE TraceFile=N'sample.etl'")==1,
            "public trace contains display filename, not private registered source path");
        await importer.SetContentHashAsync(first, Hash("fixture"));
        // Binds for a held SELECT are flushed before the statement itself.
        importer.FlushStageBatch(first, [], [new() { TempSeq = 2, ThreadId = -1, ParamIdx = 0, BindVal = "synthetic" }]);
        importer.FlushStageBatch(first, [Row(2, 64), Row(1, 8)], []);
        retainedId = await Scalar(first, "SELECT TraceLineId FROM dbo.TPImportLines WHERE Sequence=2");
        Check(await Scalar(first, "SELECT COUNT(*) FROM dbo.TPImportBinds") == 1, "held SELECT bind is durable");
        await using var concurrent = await Open();
        await Reject(51103, () => Importer().BeginImportAsync(concurrent, "account", "etl-uploads", name, "\"v1\"", default, waitForOwnership:false));
        await importer.RecordFailureAsync(first);
    }
    // New process/parser-like object, same receipt and same immutable source.
    await using (var retry = await Open())
    {
        var importer = Importer();
        var receipt = await importer.BeginImportAsync(retry, "account", "etl-uploads", name, "\"v1\"", default);
        Check(receipt.TraceId == trace && receipt.Phase == "Parsing", "retry reuses trace");
        await importer.SetContentHashAsync(retry, Hash("fixture"));
        importer.FlushStageBatch(retry, [Row(2, 64), Row(1, 8)], [new() { TempSeq = 2, ParamIdx = 0, BindVal = "synthetic" }]);
        Check(await Scalar(retry, "SELECT TraceLineId FROM dbo.TPImportLines WHERE Sequence=2") == retainedId, "replay retains allocated IDs");
        Check(await Scalar(retry, "SELECT COUNT(*) FROM dbo.TPImportLines") == 2, "replay creates no duplicate rows");
        var changed = Row(2, 64); changed.FileName = "changed";
        await Reject(51110, () => { importer.FlushStageBatch(retry, [changed], []); return Task.CompletedTask; });
        await Reject(51107, () => importer.SetContentHashAsync(retry, Hash("different")));
        Check(await Scalar(retry, "SELECT COUNT(*) FROM dbo.TPImportLines") == 2, "failed replay retains staging");
        var dims = Dimensions(trace);
        importer.FinishDimensions(retry, trace, dims, new() { Staged = 2 });
        Check(await Scalar(retry, "SELECT COUNT(*) FROM dbo.TPImportThreads") == 1, "durable thread mapping");
        Check(await Scalar(retry, "SELECT COUNT(*) FROM dbo.UserSessions") == 1, "one composite-key session");
        await Reject(51108, () => { importer.FlushStageBatch(retry, [Row(3, 8)], []); return Task.CompletedTask; });
        // Fault after line mutation: the line batch and its checkpoint roll back together.
        await Exec(retry, "CREATE TRIGGER dbo.FailBind ON dbo.TraceLines AFTER INSERT AS THROW 51200,'synthetic line failure',1;");
        await Reject(51200, () => importer.PromoteStageToTraceLines(retry));
        Check(await Scalar(retry, "SELECT COUNT(*) FROM dbo.TraceLines") == 0, "failed promotion rolls back lines");
        Check(await Scalar(retry, $"SELECT LastPromotedId FROM dbo.TPImportReceipts WHERE ImportId='{id}'") == 0, "failed promotion rolls back checkpoint");
        await Exec(retry, "DROP TRIGGER dbo.FailBind");
        // Commit one row, discard the returned acknowledgement, then lose the connection.
        await Exec(retry, "EXEC dbo.tp_PromoteImportBatch @ImportId=@id,@BatchSize=1", id);
    }
    await using (var resumed = await Open())
    {
        var importer = Importer();
        var receipt = await importer.BeginImportAsync(resumed, "account", "etl-uploads", name, "\"v1\"", default);
        Check(receipt.Phase == "Promoting", "lost acknowledgement resumes after Ready");
        await importer.PromoteStageToTraceLines(resumed);
        Check(await Scalar(resumed, "SELECT COUNT(*) FROM dbo.TraceLines") == 2, "promotion resumes without duplicates");
        Check(await Scalar(resumed, "SELECT COUNT(*) FROM dbo.QueryBindParameters") == 1, "bind promoted exactly once");
        Check(await Scalar(resumed, "SELECT COUNT(*) FROM dbo.QueryBindParameters WHERE TraceLineId=" + retainedId) == 1,
            "bind resolves held statement ID rather than flush order");
        Check(await Scalar(resumed, "SELECT COUNT(*) FROM sys.indexes WHERE object_id=OBJECT_ID('dbo.TraceLines') AND is_disabled=1") == 0,
            "all indexes stay enabled");
        await Exec(resumed, "CREATE TRIGGER dbo.FailAggregate ON dbo.TopMethodsBySession AFTER INSERT AS THROW 51201,'synthetic aggregate failure',1;");
        await Reject(51201, () => importer.CompleteImportAsync(resumed));
        Check(await Scalar(resumed, "SELECT COUNT(*) FROM dbo.SessionMetrics") == 0, "aggregate failure rolls back first physical table");
        Check(await Scalar(resumed, "SELECT COUNT(*) FROM dbo.TPImportReceipts WHERE Phase='Complete'") == 0, "failure cannot publish completion");
        await Exec(resumed, "DROP TRIGGER dbo.FailAggregate");
        await importer.CompleteImportAsync(resumed);
        Check(await Scalar(resumed, "SELECT TotalTraceLines FROM dbo.SessionMetrics") == 2, "physical aggregate count");
        Check(await Scalar(resumed, "SELECT COUNT(*) FROM dbo.TopMethodsBySession") == 1, "physical method aggregate");
        await Exec(resumed,"CREATE TRIGGER dbo.FailCleanup ON dbo.TPImportLines AFTER DELETE AS THROW 51205,'synthetic cleanup failure',1;");
        await Reject(51205,()=>importer.CleanupCompletedAsync(resumed));
        await importer.RecordFailureAsync(resumed);
        Check(await Scalar(resumed,$"SELECT COUNT(*) FROM dbo.TPImportReceipts WHERE ImportId='{id}' AND Phase='Complete' AND RetryableFailure=0")==1,
            "cleanup failure cannot revert durable completion");
        Check((await importer.BeginImportAsync(resumed,"account","etl-uploads",name,"\"v1\"",default)).IsTerminal,
            "retry after failed cleanup remains terminal, never reimports");
        await Exec(resumed,"DROP TRIGGER dbo.FailCleanup");
        await importer.CleanupCompletedAsync(resumed);
        Check(await Scalar(resumed, "SELECT COUNT(*) FROM dbo.TPImportLines") == 0, "completed stage cleanup");
        Check(await Scalar(resumed, "SELECT COUNT(*) FROM dbo.TPImportBinds") == 0, "completed bind cleanup");
        await Exec(resumed, "INSERT dbo.StageTraceLines SELECT TOP(1) * FROM dbo.TraceLines ORDER BY TraceLineId;");
    }
    await using (var duplicate = await Open())
    {
        var receipt = await Importer().BeginImportAsync(duplicate, "account", "etl-uploads", name, "\"v1\"", default);
        Check(receipt.IsTerminal && receipt.TraceId == trace, "completed duplicate is a no-op");
        Check(await Scalar(duplicate, "SELECT COUNT(*) FROM dbo.Traces") == 1, "duplicate creates no second trace");
        // Receipt semantics alone here; actual deletion coordination tests require the handed-off deletion candidate.
        await Exec(duplicate, "UPDATE dbo.TPImportReceipts SET Phase='Deleted' WHERE ImportId=@id", id);
    }
    await using (var deleted = await Open())
    {
        Check((await Importer().BeginImportAsync(deleted, "account", "etl-uploads", name, "\"v1\"", default)).Phase == "Deleted",
            "deleted receipt prevents reimport");
        await Reject(51105, () => Importer().BeginImportAsync(deleted, "account", "etl-uploads", name, "\"v2\"", default));
        using var status = deleted.CreateCommand();
        status.CommandText="EXEC dbo.tp_GetImportStatus @ImportId=@id";
        status.Parameters.Add("@id",SqlDbType.UniqueIdentifier).Value=id;
        using var reader=await status.ExecuteReaderAsync();
        await reader.ReadAsync();
        Check(reader.GetString(2)=="Deleting","tombstone with surviving root is visibly incomplete deletion");
    }
    var fresh = await Register();
    await using (var next = await Open())
    {
        var importer = Importer();
        var receipt = await importer.BeginImportAsync(next, "account", "etl-uploads", Name(fresh), "\"v2\"", default);
        Check(receipt.TraceId != trace, "fresh logical re-upload is a distinct registered version");
        await importer.SetContentHashAsync(next, Hash("fixture2"));
        importer.FlushStageBatch(next, [Row(1, 8)], []);
        importer.FinishDimensions(next, receipt.TraceId, Dimensions(receipt.TraceId), new() { Staged = 1 });
        Check(await Scalar(next, "SELECT COUNT(DISTINCT SessionId) FROM dbo.UserSessions") == 2, "sessions remain globally distinct");
        Check(await Scalar(next, "SELECT MIN(TraceLineId) FROM dbo.TPImportLines") > retainedId, "global IDs never reused");
    }
    await using (var caseCheck = await Open())
        await Reject(51104, () => Importer().BeginImportAsync(caseCheck, "account", "etl-uploads", Name(fresh).Replace("sample","SAMPLE"), "\"v2\"", default));
    // Verify strict reservation does not initialize or reseed an invalid legacy control.
    var stale = await Register();
    await using (var invalid = await Open())
    {
        var importer = Importer();
        await importer.BeginImportAsync(invalid, "account", "etl-uploads", Name(stale), "\"v1\"", default);
        await Exec(invalid, "UPDATE dbo.TraceLineIDControls SET NextTraceLineId=1");
        await Reject(51120, () => { importer.FlushStageBatch(invalid, [Row(1, 8)], []); return Task.CompletedTask; });
        Check(await Scalar(invalid, "SELECT NextTraceLineId FROM dbo.TraceLineIDControls") == 1, "stale allocator not repaired");
        // Restore only this synthetic fixture's own control for the remaining tests.
        await Exec(invalid, "UPDATE dbo.TraceLineIDControls SET NextTraceLineId=100000");
    }
    await FailureChecks();
    await RestrictedLifecycleChecks();
    await InputSizeChecks();
    await WriterChecks();
    await OwnershipWaitChecks();
    await BindFanoutChecks();
    await CoordinationChecks();
    if (runLarge) await LargeChecks();
    if (etlFixture is not null) await RealEtlChecks(etlFixture);
    await using var legacyStage = await Open();
    Check(await Scalar(legacyStage,"SELECT COUNT(*) FROM dbo.StageTraceLines")==1,"legacy staging is retained unchanged");
}

async Task InputSizeChecks()
{
    const long limit=TraceParser.Shared.ImportFilePolicy.MaxFileSizeBytes;
    await using var observer=await Open();
    await Exec(observer,"ALTER TABLE dbo.TPImportReceipts DROP CONSTRAINT CK_TPImportPhase; ALTER TABLE dbo.TPImportReceipts WITH CHECK ADD CONSTRAINT CK_TPImportPhase CHECK (Phase IN ('Registered','Parsing','Ready','Promoting','Binding','Finalizing','Complete','Deleted'));");
    foreach(var batch in Regex.Split(await File.ReadAllTextAsync(Path.Combine(AppContext.BaseDirectory,"safe-importer.sql")),
        @"^\s*GO\s*$",RegexOptions.Multiline|RegexOptions.IgnoreCase))
        if(!string.IsNullOrWhiteSpace(batch)) await Exec(observer,batch);
    Check(await Scalar(observer,"SELECT COUNT(*) FROM sys.check_constraints WHERE parent_object_id=OBJECT_ID('dbo.TPImportReceipts') AND name='CK_TPImportPhase' AND definition LIKE '%RejectedOversize%' AND is_not_trusted=0")==1,
        "existing phase constraint upgrades atomically without changing receipt data");
    foreach(var length in new[]{limit-1,limit,limit+1,long.MaxValue})
    {
        var id=await Register();
        var blob=new BoundaryBlobClient();
        var properties=Azure.Storage.Blobs.Models.BlobsModelFactory.BlobProperties(
            contentLength:length,eTag:new Azure.ETag("\"size-v1\""));
        var path=Path.Combine(Environment.CurrentDirectory,$"never-downloaded-{id:N}.etl");
        await using(var conn=await Open())
        {
            await Exec(conn,"EXECUTE AS USER='ProtocolLifecycle'");
            var importer=Importer();
            var parser=new EtlParser(importer,NullLogger<EtlParser>.Instance);
            var function=new ParseEtlFunction(parser,importer,NullLogger<ParseEtlFunction>.Instance);
            if(length<=limit)
            {
                try
                {
                    await function.ProcessRegisteredBlobAsync(blob,Name(id),properties,conn,path,default);
                    throw new Exception("Allowed input did not reach the download boundary.");
                }
                catch(BoundaryDownloadReachedException)
                {
                    Check(blob.DownloadCalls==1 && blob.DownloadWasPinned,"at/below 1 GiB admission reaches only the ETag-pinned download");
                }
            }
            else
            {
                await function.ProcessRegisteredBlobAsync(blob,Name(id),properties,conn,path,default);
                Check(blob.DownloadCalls==0 && !File.Exists(path),"oversize cannot reach download, scratch file or real parser");
                Check(await Scalar(observer,$"SELECT COUNT(*) FROM dbo.TPImportReceipts WHERE ImportId='{id}' AND Phase='RejectedOversize' AND TraceId IS NULL AND ETag='\"size-v1\"' AND RetryableFailure=0")==1,
                    "oversize is durably rejected without a trace or success-shaped completion");
                await using var web=await Open();
                await Exec(web,"EXECUTE AS USER='ProtocolWeb';");
                using var status=web.CreateCommand();
                status.CommandText=$"EXEC dbo.tp_GetImportStatus @ImportId='{id}';";
                using var statusReader=await status.ExecuteReaderAsync();
                Check(await statusReader.ReadAsync() && statusReader.IsDBNull(1) && statusReader.GetString(2)=="RejectedOversize" && !statusReader.GetBoolean(3),
                    "procedure-only web status exposes terminal rejection, not retry or completion");
            }
        }
        if(length>limit)
        {
            await using var duplicate=await Open();
            await Exec(duplicate,"EXECUTE AS USER='ProtocolLifecycle'");
            var importer=Importer();
            var function=new ParseEtlFunction(new EtlParser(importer,NullLogger<EtlParser>.Instance),
                importer,NullLogger<ParseEtlFunction>.Instance);
            await function.ProcessRegisteredBlobAsync(blob,Name(id),properties,duplicate,path,default);
            Check(blob.DownloadCalls==0,"rejected delivery retry acknowledges rejection without expensive work");
            // Caller cannot lower its claimed length to revive a rejected immutable identity.
            await Reject(51127,()=>importer.BeginImportAsync(duplicate,"account","etl-uploads",Name(id),"\"size-v1\"",default,contentLength:limit));
            Check(await Scalar(observer,$"SELECT COUNT(*) FROM dbo.TPImportLines WHERE ImportId='{id}'")==0,
                "oversize rejection creates no staging and performs no cleanup/adoption");
        }
    }
    // A new logical upload is a new registration, not an automatic reset of rejection.
    var fresh=await Register();
    await using var valid=await Open();
    await Exec(valid,"EXECUTE AS USER='ProtocolLifecycle'");
    Check((await Importer().BeginImportAsync(valid,"account","etl-uploads",Name(fresh),"\"fresh\"",default,contentLength:limit)).Phase=="Parsing",
        "fresh at-limit registration is admitted independently of rejected receipts");
}

async Task OwnershipWaitChecks()
{
    var id=await Register();
    await using var owner=await Open();
    var original=await Importer().BeginImportAsync(owner,"account","etl-uploads",Name(id),"\"wait\"",default);
    await using var waiter=await Open();
    using(var cancelled=new CancellationTokenSource(TimeSpan.FromMilliseconds(150)))
    {
        try
        {
            await Importer().BeginImportAsync(waiter,"account","etl-uploads",Name(id),"\"wait\"",cancelled.Token);
            throw new Exception("Cancelled ownership wait unexpectedly succeeded.");
        }
        catch(OperationCanceledException) when(cancelled.IsCancellationRequested)
        {
            Check(true,"contended ownership wait observes invocation cancellation");
        }
    }
    using var budget=new CancellationTokenSource(TimeSpan.FromSeconds(15));
    var waiting=Importer().BeginImportAsync(waiter,"account","etl-uploads",Name(id),"\"wait\"",budget.Token);
    await Task.Delay(150);
    Check(!waiting.IsCompleted,"contention waits instead of consuming delivery retries");
    await owner.DisposeAsync();
    Check((await waiting).TraceId==original.TraceId,"ownership wait resumes same receipt after prior connection closes");
    Check(await Scalar(waiter,$"SELECT COUNT(*) FROM dbo.Traces WHERE TraceId={original.TraceId}")==1,
        "ownership contention never creates a duplicate trace");
}

async Task RestrictedLifecycleChecks()
{
    await using var observer=await Open();
    await Exec(observer,"CREATE USER ProtocolLifecycle WITHOUT LOGIN;");
    foreach(var procedure in new[]{"tp_BeginImport","tp_SetImportContentHash","tp_ReserveTraceLineIds",
        "tp_StageImportBatch","tp_MapImportThread","tp_MarkImportReady","tp_PromoteImportBatch",
        "tp_CompleteImport","tp_CleanupCompletedImport","tp_RecordImportFailure","tp_AssertImportOwner"})
        await Exec(observer,$"GRANT EXECUTE ON dbo.{procedure} TO ProtocolLifecycle;");
    foreach(var table in new[]{"TPImportLines","TPImportBinds"})
        await Exec(observer,$"GRANT SELECT ON dbo.{table} TO ProtocolLifecycle;");
    foreach(var table in new[]{"MethodNames","QueryStatements","QueryTables","Messages","Users","Customers",
        "UserSessions","UserSessionProcessThreads"})
        await Exec(observer,$"GRANT SELECT,INSERT ON dbo.{table} TO ProtocolLifecycle;");
    await Exec(observer,"GRANT SELECT ON dbo.Traces(TraceId) TO ProtocolLifecycle; GRANT UPDATE ON dbo.Traces(TimeStampBegin,TimeStampEnd) TO ProtocolLifecycle;");
    await ApplyMigration();
    Check(await Scalar(observer,"SELECT COUNT(*) FROM sys.sql_modules WHERE object_id=OBJECT_ID('dbo.tp_PromoteImportBatch') AND execute_as_principal_id=DATABASE_PRINCIPAL_ID('TPImportPromotionExecutor')")==1,
        "idempotent migration preserves dedicated promotion execution context");
    Check(await Scalar(observer,"SELECT COUNT(*) FROM sys.database_permissions WHERE grantee_principal_id=DATABASE_PRINCIPAL_ID('TPImportPromotionExecutor') AND class=1 AND major_id=OBJECT_ID('dbo.TraceLines') AND permission_name='ALTER' AND state='G'")==1,
        "nonlogin executor holds only the required target ALTER grant");
    await Exec(observer,"ALTER ROLE db_datareader ADD MEMBER TPImportPromotionExecutor;");
    try { await Reject(51126,ApplyMigration); }
    finally { await Exec(observer,"ALTER ROLE db_datareader DROP MEMBER TPImportPromotionExecutor;"); }
    await Exec(observer,"GRANT SELECT ON dbo.Traces TO TPImportPromotionExecutor;");
    try { await Reject(51126,ApplyMigration); }
    finally { await Exec(observer,"REVOKE SELECT ON dbo.Traces FROM TPImportPromotionExecutor;"); }
    await ApplyMigration();
    await Exec(observer,"EXEC dbo.tp_AssertDeletionProtocol;");
    Check(true,"principal guards and idempotent migration retain deletion activation fingerprint");
    var id=await Register();
    var stagedId=0L;
    int trace;
    await using(var first=await Open())
    {
        await Exec(first,"EXECUTE AS USER='ProtocolLifecycle'");
        var importer=Importer();
        trace=(await importer.BeginImportAsync(first,"account","etl-uploads",Name(id),"\"restricted\"",default)).TraceId;
        await importer.SetContentHashAsync(first,Hash("restricted-lifecycle"));
        importer.FlushStageBatch(first,[Row(2,8)],[new(){TempSeq=1,ParamIdx=0,BindVal="synthetic"}]);
        importer.FlushStageBatch(first,[Row(1,64)],[]);
        stagedId=await Scalar(observer,$"SELECT TraceLineId FROM dbo.TPImportLines WHERE ImportId='{id}' AND Sequence=1");
        await importer.RecordFailureAsync(first);
    }
    await using(var retry=await Open())
    {
        await Exec(retry,"EXECUTE AS USER='ProtocolLifecycle'");
        await Reject(51101,()=>Exec(retry,$"EXEC dbo.tp_PromoteImportBatch @ImportId='{id}'"));
        Check(await Scalar(retry,"SELECT CASE WHEN USER_NAME()='ProtocolLifecycle' THEN 1 ELSE 0 END")==1,
            "failed module ownership check restores caller context");
        var principalBatch=Regex.Split(await File.ReadAllTextAsync(Path.Combine(AppContext.BaseDirectory,"safe-importer.sql")),
            @"^\s*GO\s*$",RegexOptions.Multiline|RegexOptions.IgnoreCase).Single(batch=>batch.Contains("DECLARE @executor int="));
        await Reject(51126,()=>Exec(retry,principalBatch));
        foreach(var deniedSql in new[]{
            "SET IDENTITY_INSERT dbo.TraceLines ON;",
            "ALTER TABLE dbo.TraceLines ADD ForbiddenColumn int NULL;",
            "CREATE TABLE dbo.ForbiddenTable(Id int);",
            "ALTER PROCEDURE dbo.tp_PromoteImportBatch AS SELECT 42;",
            "EXECUTE AS USER='TPImportPromotionExecutor';",
            "UPDATE dbo.TraceLines SET Sequence=Sequence;",
            "UPDATE dbo.TPImportReceipts SET Phase='Complete';"})
        {
            try { await Exec(retry,deniedSql); throw new Exception("Restricted caller unexpectedly gained direct authority: "+deniedSql); }
            catch(SqlException ex) when(ex.Number is 1088 or 4902 or 262 or 3701 or 15151 or 15517 or 229)
            {
                Check(true,$"restricted direct authority denied ({ex.Number}): {deniedSql}");
            }
        }
        var importer=Importer();
        Check((await importer.BeginImportAsync(retry,"account","etl-uploads",Name(id),"\"restricted\"",default)).TraceId==trace,
            "restricted pre-Ready replay retains its trace");
        await importer.SetContentHashAsync(retry,Hash("restricted-lifecycle"));
        importer.FlushStageBatch(retry,[Row(1,64),Row(2,8)],[new(){TempSeq=1,ParamIdx=0,BindVal="synthetic"}]);
        Check(await Scalar(observer,$"SELECT TraceLineId FROM dbo.TPImportLines WHERE ImportId='{id}' AND Sequence=1")==stagedId,
            "restricted stage replay retains line allocation");
        var dims=Dimensions(trace);
        dims.EnsureQueryStatement("select synthetic_restricted");
        dims.EnsureQueryTable("synthetic_restricted");
        dims.EnsureMessage("synthetic restricted message");
        var begin=DateTime.UtcNow.ToFileTimeUtc();
        importer.FinishDimensions(retry,trace,dims,new(){Staged=2,MinFileTimeUtc=begin,MaxFileTimeUtc=begin+1000});
        Check(await Scalar(observer,$"SELECT COUNT(*) FROM dbo.TPImportReceipts WHERE ImportId='{id}' AND Phase='Ready'")==1,
            "restricted dimensions publish Ready atomically");
        await Exec(observer,"CREATE TRIGGER dbo.FailRestrictedPromotion ON dbo.TraceLines AFTER INSERT AS BEGIN THROW 51208,'Synthetic restricted promotion failure',1; END;");
        try { await Reject(51208,()=>importer.PromoteStageToTraceLines(retry)); }
        finally { await Exec(observer,"DROP TRIGGER dbo.FailRestrictedPromotion;"); }
        Check(await Scalar(retry,"SELECT CASE WHEN USER_NAME()='ProtocolLifecycle' THEN 1 ELSE 0 END")==1
            && await Scalar(retry,"SELECT COALESCE(HAS_PERMS_BY_NAME('dbo.TraceLines','OBJECT','ALTER'),0)")==0,
            "post-mutation failure restores caller without target ALTER authority");
        Check(await Scalar(retry,$"SELECT CASE WHEN APPLOCK_MODE('public','TraceParser:Importer:v1','Session')='Exclusive' AND APPLOCK_MODE('public','TraceParser:Trace:{trace}','Session')='Exclusive' THEN 1 ELSE 0 END")==1,
            "module failure preserves caller's session-owned public application locks");
        Check(await Scalar(observer,$"SELECT COUNT(*) FROM dbo.TPImportReceipts WHERE ImportId='{id}' AND LastPromotedId=0 AND Phase='Ready'")==1,
            "restricted failed promotion retains durable Ready checkpoint");
        await importer.PromoteStageToTraceLines(retry);
        Check(await Scalar(observer,$"SELECT COUNT(*) FROM dbo.QueryBindParameters WHERE TraceLineId={stagedId}")==1,
            "restricted promotion materializes binds exactly once");
        await importer.CompleteImportAsync(retry);
        Check(await Scalar(observer,$"SELECT COUNT(*) FROM dbo.TPImportReceipts WHERE ImportId='{id}' AND Phase='Complete'")==1
            && await Scalar(observer,$"SELECT COUNT(*) FROM dbo.SessionMetrics WHERE TraceId={trace}")==1
            && await Scalar(observer,$"SELECT COUNT(*) FROM dbo.TopMethodsBySession WHERE TraceId={trace}")==1,
            "restricted aggregate and completion contract succeeds");
        await importer.CleanupCompletedAsync(retry);
        Check(await Scalar(observer,$"SELECT COUNT(*) FROM dbo.TPImportLines WHERE ImportId='{id}'")==0
            && await Scalar(observer,$"SELECT COUNT(*) FROM dbo.TPImportBinds WHERE ImportId='{id}'")==0
            && await Scalar(observer,$"SELECT COUNT(*) FROM dbo.TPImportThreads WHERE ImportId='{id}'")==0,
            "restricted completion cleans only its staging");
        Check(await Scalar(retry,"SELECT CASE WHEN USER_NAME()='ProtocolLifecycle' THEN 1 ELSE 0 END")==1,
            "promotion restores original restricted execution context");
        Check(await Scalar(retry,"SELECT COALESCE(HAS_PERMS_BY_NAME('dbo.TraceLines','OBJECT','ALTER'),0)")==0,
            "promotion does not leak target ALTER authority to caller");
    }
    await using(var replay=await Open())
    {
        await Exec(replay,"EXECUTE AS USER='ProtocolLifecycle'");
        var importer=Importer();
        Check((await importer.BeginImportAsync(replay,"account","etl-uploads",Name(id),"\"restricted\"",default)).IsTerminal,
            "restricted completed replay remains terminal");
        await importer.CleanupCompletedAsync(replay);
    }

    async Task ApplyMigration()
    {
        foreach(var batch in Regex.Split(await File.ReadAllTextAsync(Path.Combine(AppContext.BaseDirectory,"safe-importer.sql")),
                    @"^\s*GO\s*$",RegexOptions.Multiline|RegexOptions.IgnoreCase))
            if(!string.IsNullOrWhiteSpace(batch)) await Exec(observer,batch);
    }
}

async Task BindFanoutChecks()
{
    var id=await Register();
    int trace;
    await using(var conn=await Open())
    {
        var importer=Importer();
        trace=(await importer.BeginImportAsync(conn,"account","etl-uploads",Name(id),"\"fanout\"",default)).TraceId;
        await importer.SetContentHashAsync(conn,Hash("fanout"));
        importer.FlushStageBatch(conn,[Row(1,64)],
            Enumerable.Range(0,2505).Select(i=>new BindParamRow{TempSeq=1,ParamIdx=i,BindVal="synthetic"}).ToList());
        importer.FinishDimensions(conn,trace,Dimensions(trace),new(){Staged=1});
        Check(await Scalar(conn,$"EXEC dbo.tp_PromoteImportBatch @ImportId='{id}',@BatchSize=1000")==1,
            "line phase has a bounded independent checkpoint");
        Check(await Scalar(conn,$"SELECT COUNT(*) FROM dbo.QueryBindParameters b JOIN dbo.TraceLines l ON l.TraceLineId=b.TraceLineId JOIN dbo.UserSessionProcessThreads t ON t.UserSessionProcessThreadId=l.UserSessionProcessThreadId WHERE t.TraceId={trace}")==0,
            "large bind fanout is deferred while import remains nonterminal");
        await Exec(conn,"CREATE TRIGGER dbo.FailFanout ON dbo.QueryBindParameters AFTER INSERT AS THROW 51207,'synthetic bind transaction failure',1;");
        await Reject(51207,()=>Exec(conn,$"EXEC dbo.tp_PromoteImportBatch @ImportId='{id}',@BatchSize=1000"));
        Check(await Scalar(conn,$"SELECT LastBindIndex FROM dbo.TPImportReceipts WHERE ImportId='{id}'")==-1,
            "failed bind transaction cannot advance its cursor");
        await Exec(conn,"DROP TRIGGER dbo.FailFanout");
        // Discard acknowledgement for the first committed bind batch, then lose the session.
        await Exec(conn,$"EXEC dbo.tp_PromoteImportBatch @ImportId='{id}',@BatchSize=1000");
    }
    await using(var retry=await Open())
    {
        var importer=Importer();
        Check((await importer.BeginImportAsync(retry,"account","etl-uploads",Name(id),"\"fanout\"",default)).Phase=="Binding",
            "lost bind acknowledgement resumes the durable binding phase");
        var counts=new List<long>();
        while(true)
        {
            var count=await Scalar(retry,$"EXEC dbo.tp_PromoteImportBatch @ImportId='{id}',@BatchSize=1000");
            counts.Add(count);
            if(count==0)break;
            if(counts.Count>5)throw new Exception("Bind cursor did not converge");
        }
        Check(counts.SequenceEqual(new long[]{1000,505,0}),"bind fanout obeys row bound and resumes without duplication");
        Check(await Scalar(retry,$"SELECT COUNT(*) FROM dbo.QueryBindParameters b JOIN dbo.TraceLines l ON l.TraceLineId=b.TraceLineId JOIN dbo.UserSessionProcessThreads t ON t.UserSessionProcessThreadId=l.UserSessionProcessThreadId WHERE t.TraceId={trace}")==2505,
            "all bind values retain reference integrity after bind retry");
        await importer.CompleteImportAsync(retry);
        await importer.CleanupCompletedAsync(retry);
    }
}

async Task WriterChecks()
{
    var id=await Register();
    await using(var conn=await Open())
    {
        var importer=Importer();
        await importer.BeginImportAsync(conn,"account","etl-uploads",Name(id),"\"writer\"",default);
        await importer.SetContentHashAsync(conn,Hash("writer"));
        await Exec(conn,"CREATE TRIGGER dbo.PauseStage ON dbo.TPImportLines AFTER INSERT AS WAITFOR DELAY '00:00:30';");
        var spid=await Scalar(conn,"SELECT @@SPID");
        var writer=new StageBatchWriter(importer,conn);
        try
        {
            writer.Write([Row(1,8)],[]);
            await using var monitor=await Open();
            var waiting=false;
            for(var attempt=0;attempt<200;attempt++)
            {
                if(await Scalar(monitor,$"SELECT COUNT(*) FROM sys.dm_exec_requests WHERE session_id={spid} AND wait_type='WAITFOR'")>0)
                {waiting=true;break;}
                await Task.Delay(25);
            }
            Check(waiting,"real parser consumer reached post-mutation SQL wait");
            // This is the parser's actual production writer disposal path on producer failure.
            throw new InvalidDataException("Synthetic producer event failure");
        }
        catch(InvalidDataException)
        {
            var stop=System.Diagnostics.Stopwatch.StartNew();
            writer.Dispose();
            Check(writer.ConsumerCompleted && stop.Elapsed<TimeSpan.FromSeconds(10),
                "producer failure cancels and joins SQL consumer before ownership release");
            Check(importer.ImportCancellation==CancellationToken.None,"writer restores invocation cancellation scope");
        }
        finally{writer.Dispose();}
        await conn.CloseAsync();
    }
    await using(var inspect=await Open())
    {
        Check(await Scalar(inspect,$"SELECT COUNT(*) FROM dbo.TPImportLines WHERE ImportId='{id}'")==0,
            "cancelled consumer mutation rolls back before connection ownership release");
        await Exec(inspect,"DROP TRIGGER dbo.PauseStage");
    }
    var consumerId=await Register();
    await using(var conn=await Open())
    {
        var importer=Importer();
        await importer.BeginImportAsync(conn,"account","etl-uploads",Name(consumerId),"\"writer\"",default);
        await Exec(conn,"CREATE TRIGGER dbo.FailWriter ON dbo.TPImportLines AFTER INSERT AS THROW 51206,'synthetic consumer failure',1;");
        var writer=new StageBatchWriter(importer,conn);
        var failed=false;
        try{writer.Write([Row(1,8)],[]);writer.Complete();}
        catch(InvalidOperationException ex) when(ex.InnerException is SqlException sql && sql.Number==51206){failed=true;}
        finally{writer.Dispose();}
        Check(failed && writer.ConsumerCompleted,"SQL consumer failure reaches producer with original cause and joined worker");
        Check(await Scalar(conn,$"SELECT COUNT(*) FROM dbo.TPImportLines WHERE ImportId='{consumerId}'")==0,"consumer failure cannot publish partial batch");
        await Exec(conn,"DROP TRIGGER dbo.FailWriter");
    }
}

async Task CoordinationChecks()
{
    var id=await Register();
    int trace;
    await using(var active=await Open())
    {
        var importer=Importer();
        trace=(await importer.BeginImportAsync(active,"account","etl-uploads",Name(id),"\"v1\"",default)).TraceId;
        await importer.SetContentHashAsync(active,Hash("coordination"));
        importer.FlushStageBatch(active,[Row(1,64),Row(2,8)],
            [new(){TempSeq=1,ParamIdx=0,BindVal="one"},new(){TempSeq=1,ParamIdx=1,BindVal="two"}]);
        await using var deleter=await Open();
        await Reject(51130,()=>Exec(deleter,$"EXEC dbo.sp_DeleteTrace @TraceId={trace},@BatchSize=1"));
        Check(await Scalar(deleter,$"SELECT COUNT(*) FROM dbo.Traces WHERE TraceId={trace}")==1,"active importer protects root");
        await importer.RecordFailureAsync(active);
    }
    await using(var betweenRetries=await Open())
    {
        await Reject(51131,()=>Exec(betweenRetries,$"EXEC dbo.sp_DeleteTrace @TraceId={trace},@BatchSize=1"));
        Check(await Scalar(betweenRetries,$"SELECT COUNT(*) FROM dbo.TPImportLines WHERE ImportId='{id}'")==2,
            "retryable import deletion rejection preserves staged rows");
    }
    await using(var resume=await Open())
    {
        var importer=Importer();
        await importer.BeginImportAsync(resume,"account","etl-uploads",Name(id),"\"v1\"",default);
        // Reparse before Ready: same source and bind count, no new trace or IDs.
        importer.FlushStageBatch(resume,[Row(1,64),Row(2,8)],
            [new(){TempSeq=1,ParamIdx=0,BindVal="one"},new(){TempSeq=1,ParamIdx=1,BindVal="two"}]);
        importer.FinishDimensions(resume,trace,Dimensions(trace),new(){Staged=2});
        await importer.PromoteStageToTraceLines(resume);
        var legacyTrace=await Scalar(resume,"""
            INSERT dbo.Traces(TraceName,TraceFile,TimeStampBegin,TimeStampEnd,TraceParserVersion)
            OUTPUT INSERTED.TraceId VALUES(N'synthetic legacy collision',N'fixture.etl',GETUTCDATE(),GETUTCDATE(),N'legacy');
            """);
        await Exec(resume,$"""
            INSERT dbo.UserSessions(SessionId,TraceId,UserId,SessionName,CustomerCustomerId)
            SELECT SessionId,{legacyTrace},UserId,N'synthetic collision',CustomerCustomerId
            FROM dbo.UserSessions WHERE TraceId={trace};
            """);
        await Reject(51116,()=>importer.CompleteImportAsync(resume));
        Check(await Scalar(resume,$"SELECT COUNT(*) FROM dbo.UserSessions WHERE TraceId={legacyTrace}")==1,
            "global session collision is refused without changing legacy data");
        // Remove only the deliberately injected synthetic collision owned by this test.
        await Exec(resume,$"DELETE dbo.UserSessions WHERE TraceId={legacyTrace}; DELETE dbo.Traces WHERE TraceId={legacyTrace};");
        await importer.CompleteImportAsync(resume);
        // Deliberately retain completed stage as if cleanup were interrupted.
    }
    await using(var deletion=await Open())
    {
        await Exec(deletion,"GRANT EXECUTE ON dbo.sp_DeleteTrace TO ProtocolWeb; GRANT SELECT ON dbo.Traces TO ProtocolWeb;");
        await Exec(deletion,"EXECUTE AS USER='ProtocolWeb'");
        try
        {
            await Exec(deletion,$"EXEC dbo.sp_DeleteTrace @TraceId={trace},@BatchSize=1");
            Check(await Scalar(deletion,$"SELECT COUNT(*) FROM dbo.Traces WHERE TraceId={trace}")==1,
                "first deletion batch is not root-absence proof");
            using var status=deletion.CreateCommand();
            status.CommandText="EXEC dbo.tp_GetImportStatus @ImportId=@id";
            status.Parameters.Add("@id",SqlDbType.UniqueIdentifier).Value=id;
            using var reader=await status.ExecuteReaderAsync();
            await reader.ReadAsync();
            Check(reader.GetString(2)=="Deleting","restricted web sees resumable partial deletion");
        }
        finally{await Exec(deletion,"REVERT");}
        Check(await Scalar(deletion,$"SELECT COUNT(*) FROM dbo.TPImportReceipts WHERE ImportId='{id}' AND Phase='Deleted'")==1,
            "first committed deletion atomically retains terminal receipt");
    }
    await using(var duplicate=await Open())
    {
        var importer=Importer();
        Check((await importer.BeginImportAsync(duplicate,"account","etl-uploads",Name(id),"\"v1\"",default)).IsTerminal,
            "duplicate delivery during partial deletion never resumes import");
        await importer.CleanupCompletedAsync(duplicate);
    }
    await using(var deletion=await Open())
    {
        await Exec(deletion,"EXECUTE AS USER='ProtocolWeb'");
        try
        {
            var batches=0;
            while(await Scalar(deletion,$"SELECT COUNT(*) FROM dbo.Traces WHERE TraceId={trace}")!=0)
            {
                if(++batches>30)throw new Exception("Deletion did not converge.");
                await Exec(deletion,$"EXEC dbo.sp_DeleteTrace @TraceId={trace},@BatchSize=1");
            }
            Check(batches>1,"partial deletion remains resumable across fresh calls");
        }
        finally{await Exec(deletion,"REVERT");}
        Check(await Scalar(deletion,$"SELECT COUNT(*) FROM dbo.TPImportReceipts WHERE ImportId='{id}' AND Phase='Deleted'")==1,
            "root deletion retains tombstone");
        Check(await Scalar(deletion,$"SELECT COUNT(*) FROM dbo.UserSessions WHERE TraceId={trace}")==0,
            "coordinated deletion drains actual composite-key sessions");
        // Restoring any older procedure while retaining extended properties cannot silently enable imports.
        await Exec(deletion,"ALTER PROCEDURE dbo.sp_DeleteTrace @TraceId int AS SELECT 0 AS HasMore;");
        var blocked=await Register();
        await using(var invalid=await Open())
            await Reject(51122,()=>Importer().BeginImportAsync(invalid,"account","etl-uploads",Name(blocked),"\"v1\"",default));
        await Exec(deletion,await File.ReadAllTextAsync(Path.Combine(AppContext.BaseDirectory,"sp_DeleteTrace.sql")));
        Check(true,"restored coordinated migration reestablishes activation fingerprint");
    }
}

async Task FailureChecks()
{
    var id = await Register();
    await using (var conn = await Open())
    {
        var importer = Importer();
        var receipt = await importer.BeginImportAsync(conn, "account", "etl-uploads", Name(id), "\"v1\"", default);
        await importer.SetContentHashAsync(conn, Hash("failures"));
        await Exec(conn, "CREATE TRIGGER dbo.FailStage ON dbo.TPImportLines AFTER INSERT AS THROW 51202,'synthetic stage failure',1;");
        await Reject(51202, () => { importer.FlushStageBatch(conn, [Row(1,8)], []); return Task.CompletedTask; });
        Check(await Scalar(conn, $"SELECT COUNT(*) FROM dbo.TPImportLines WHERE ImportId='{id}'") == 0, "staging failure commits no partial batch");
        await Exec(conn, "DROP TRIGGER dbo.FailStage");
        importer.FlushStageBatch(conn, [Row(1,8)], []);
        await Exec(conn, "CREATE TRIGGER dbo.FailThread ON dbo.TPImportThreads AFTER INSERT AS THROW 51203,'synthetic mapping failure',1;");
        await Reject(51203, () => { importer.FinishDimensions(conn, receipt.TraceId, Dimensions(receipt.TraceId), new() { Staged=1 }); return Task.CompletedTask; });
        Check(await Scalar(conn, $"SELECT COUNT(*) FROM dbo.UserSessions WHERE TraceId={receipt.TraceId}") == 0, "dimension failure rolls back sessions and threads");
        Check(await Scalar(conn, $"SELECT COUNT(*) FROM dbo.TPImportLines WHERE ImportId='{id}'") == 1, "dimension failure retains staged rows");
        await Exec(conn, "DROP TRIGGER dbo.FailThread");
        await Reject(51117, () => Exec(conn, "EXEC dbo.tp_CleanupCompletedImport @id", id));
        importer.FinishDimensions(conn, receipt.TraceId, Dimensions(receipt.TraceId), new() { Staged=1 });
        await Exec(conn, "CREATE TRIGGER dbo.FailCheckpoint ON dbo.TPImportReceipts AFTER UPDATE AS IF EXISTS(SELECT 1 FROM inserted WHERE Phase='Promoting') THROW 51204,'synthetic checkpoint failure',1;");
        await Reject(51204, () => importer.PromoteStageToTraceLines(conn));
        Check(await Scalar(conn, $"SELECT LastPromotedId FROM dbo.TPImportReceipts WHERE ImportId='{id}'") == 0,
            "checkpoint failure rolls back target rows");
        await Exec(conn, "DROP TRIGGER dbo.FailCheckpoint");
        // Losing ownership on the same session must fail closed.
        await Exec(conn, "EXEC sys.sp_releaseapplock @Resource='TraceParser:Importer:v1',@LockOwner='Session'");
        await Reject(51101, () => importer.PromoteStageToTraceLines(conn));
    }
    // An inactive nonterminal import is explicitly retryable even after a hard process loss.
    await using (var status = await Open())
    {
        using var query = status.CreateCommand();
        query.CommandText = "EXEC dbo.tp_GetImportStatus @ImportId=@id";
        query.Parameters.Add("@id",SqlDbType.UniqueIdentifier).Value=id;
        using var reader = await query.ExecuteReaderAsync();
        await reader.ReadAsync();
        Check(reader.GetBoolean(3), "connection loss exposes interrupted status");
    }
    var disabled = await Register();
    await using (var conn = await Open())
    {
        await Exec(conn, "ALTER INDEX IX_USP_QUERY ON dbo.TraceLines DISABLE");
        await Reject(51102, () => Importer().BeginImportAsync(conn,"account","etl-uploads",Name(disabled),"\"v1\"",default));
        Check(await Scalar(conn,$"SELECT COUNT(*) FROM dbo.TPImportReceipts WHERE ImportId='{disabled}' AND TraceId IS NULL") == 1,
            "disabled-index activation creates no trace");
        Check(await Scalar(conn,"SELECT is_disabled FROM sys.indexes WHERE name='IX_USP_QUERY' AND object_id=OBJECT_ID('dbo.TraceLines')") == 1,
            "importer never repairs disabled indexes");
        await Exec(conn, "ALTER INDEX IX_USP_QUERY ON dbo.TraceLines REBUILD"); // Synthetic fixture only.
    }
    var cancelled = await Register();
    await using (var conn = await Open())
    {
        using var cts = new CancellationTokenSource();
        var importer=Importer();
        await importer.BeginImportAsync(conn,"account","etl-uploads",Name(cancelled),"\"v1\"",cts.Token);
        cts.Cancel();
        try { importer.FlushStageBatch(conn,[Row(1,8)],[]); throw new Exception("Cancellation ignored"); }
        catch(OperationCanceledException) { Check(true,"cancelled staging performs no write"); }
    }
    var badFile = Path.Combine(Environment.CurrentDirectory, $"synthetic-invalid-{Guid.NewGuid():N}.etl");
    try
    {
        await File.WriteAllBytesAsync(badFile,[0,1,2,3]);
        var invalidEtl = await Register();
        await using var conn=await Open();
        var importer=Importer();
        var receipt=await importer.BeginImportAsync(conn,"account","etl-uploads",Name(invalidEtl),"\"v1\"",default);
        var parser=new EtlParser(importer,NullLogger<EtlParser>.Instance);
        var failed=false;
        try{parser.Parse(badFile,receipt.TraceId,conn);}
        catch(Exception){failed=true;}
        Check(failed,"malformed short ETL rejected before native reader construction");
        Check(await Scalar(conn,$"SELECT COUNT(*) FROM dbo.TPImportLines WHERE ImportId='{invalidEtl}'")==0,
            "malformed input leaves no consumer SQL writes");
    }
    finally{if(File.Exists(badFile))File.Delete(badFile);}
    await using (var permissions = await Open())
    {
        await Exec(permissions,"CREATE USER ProtocolWeb WITHOUT LOGIN; GRANT EXECUTE ON dbo.tp_RegisterUpload TO ProtocolWeb; GRANT EXECUTE ON dbo.tp_GetImportStatus TO ProtocolWeb;");
        await Exec(permissions,"EXECUTE AS USER='ProtocolWeb'; EXEC dbo.tp_GetImportStatus; REVERT;");
        Check(true,"web status works through procedure-only grants");
        await Reject(229, () => Exec(permissions,"EXECUTE AS USER='ProtocolWeb'; SELECT * FROM dbo.TPImportReceipts;"));
        await Exec(permissions,"REVERT;");
        await Reject(229, () => Exec(permissions,"EXECUTE AS USER='ProtocolWeb'; UPDATE dbo.TPImportReceipts SET Phase='Complete';"));
        await Exec(permissions,"REVERT;");
    }
    await using(var setup=await Open())
        await Exec(setup,"CREATE USER ProtocolFunction WITHOUT LOGIN; GRANT EXECUTE ON dbo.tp_BeginImport TO ProtocolFunction; GRANT EXECUTE ON dbo.tp_ReserveTraceLineIds TO ProtocolFunction;");
    var restricted=await Register();
    await using(var conn=await Open())
    {
        await Exec(conn,"EXECUTE AS USER='ProtocolFunction'");
        var importer=Importer();
        await importer.BeginImportAsync(conn,"account","etl-uploads",Name(restricted),"\"v1\"",default);
        Check(await Scalar(conn,"SELECT COUNT(*) FROM sys.indexes WHERE object_id=OBJECT_ID('dbo.TraceLines')")==0,
            "restricted function caller cannot directly inspect target index metadata");
        Check(await Scalar(conn,$"EXEC dbo.tp_ReserveTraceLineIds @ImportId='{restricted}',@BatchSize=1")>0,
            "owned allocator works through narrow EXECUTE permissions");
    }
    var restrictedDisabled=await Register();
    await using(var setup=await Open())
    {
        await Exec(setup,"ALTER INDEX IX_USP_QUERY ON dbo.TraceLines DISABLE");
        try
        {
            await using var conn=await Open();
            await Exec(conn,"EXECUTE AS USER='ProtocolFunction'");
            await Reject(51102,()=>Importer().BeginImportAsync(conn,"account","etl-uploads",Name(restrictedDisabled),"\"v1\"",default));
            Check(await Scalar(setup,$"SELECT COUNT(*) FROM dbo.TPImportReceipts WHERE ImportId='{restrictedDisabled}' AND TraceId IS NULL")==1,
                "hidden metadata cannot bypass disabled-index activation guard");
        }
        finally{await Exec(setup,"ALTER INDEX IX_USP_QUERY ON dbo.TraceLines REBUILD");}
    }
}

async Task RealEtlChecks(string path)
{
    using var catalog=JsonDocument.Parse(await File.ReadAllTextAsync(Path.Combine(Path.GetDirectoryName(path)!,"fixture-catalog.json")));
    var fixture=catalog.RootElement.GetProperty("fixtures").EnumerateArray()
        .Single(entry=>entry.GetProperty("file").GetString()==Path.GetFileName(path));
    var expected=fixture.TryGetProperty("expectedCounts",out var observed)?observed:
        fixture.GetProperty("expectedParserCountsNotObservedForThisFile");
    var expectedRows=expected.GetProperty("Staged").GetInt32();
    var expectedBinds=expected.GetProperty("BindParamRows").GetInt32();
    var firstBatch=fixture.TryGetProperty("batchSizes",out var batches)?batches[0].GetInt32():Math.Min(200000,expectedRows);
    Check(new FileInfo(path).Length==fixture.GetProperty("bytes").GetInt64(),"real ETL matches approved catalog size");
    var timer=System.Diagnostics.Stopwatch.StartNew();
    byte[] contentHash;
    await using(var file=File.OpenRead(path)) contentHash=await SHA256.HashDataAsync(file);
    if(fixture.TryGetProperty("sha256",out var expectedHash))
        Check(Convert.ToHexString(contentHash)==expectedHash.GetString(),"near-limit ETL SHA256 matches approved catalog");
    using var budget=new CancellationTokenSource(TimeSpan.FromMinutes(15));
    await using var resources=await EtlResourceGuard.StartAsync(databaseString,budget);
    await using var observer=await Open();
    var preexistingLines=await Scalar(observer,"SELECT COUNT_BIG(*) FROM dbo.TraceLines");
    Check(preexistingLines>0,"real ETL imports into an unrelated prepopulated indexed target");
    var id=await Register();
    int trace;
    long retainedBinds;
    double interruptedParseSeconds,replayParseSeconds,promotionCompletionSeconds;
    var peakObservedManaged=GC.GetTotalMemory(false);
    await using(var first=await Open())
    {
        await Exec(first,"EXECUTE AS USER='ProtocolLifecycle'");
        var importer=Importer();
        trace=(await importer.BeginImportAsync(first,"account","etl-uploads",Name(id),"\"real-etl\"",budget.Token,contentLength:new FileInfo(path).Length)).TraceId;
        await importer.SetContentHashAsync(first,contentHash);
        // A large ETL fails in its second real parser batch; the small ETL fails
        // in Ready's dimensions after its only parser batch was durably staged.
        var trigger=expectedRows>firstBatch
            ? $"CREATE TRIGGER dbo.FailRealEtl ON dbo.TPImportLines AFTER INSERT AS BEGIN IF (SELECT COUNT_BIG(*) FROM dbo.TPImportLines WHERE ImportId='{id}')>{firstBatch} THROW 51209,'Synthetic interruption after committed parser batch',1; END;"
            : "CREATE TRIGGER dbo.FailRealEtl ON dbo.TPImportThreads AFTER INSERT AS BEGIN THROW 51209,'Synthetic interruption before Ready',1; END;";
        await Exec(observer,trigger);
        var parseTimer=System.Diagnostics.Stopwatch.StartNew();
        try
        {
            new EtlParser(importer,NullLogger<EtlParser>.Instance).Parse(path,trace,first);
            throw new Exception("Real ETL interruption did not fire.");
        }
        catch(Exception ex) when(HasSqlError(ex,51209))
        {
            Check(true,"real parser/channel reports injected SQL failure");
            await importer.RecordFailureAsync(first);
        }
        finally { await Exec(observer,"DROP TRIGGER dbo.FailRealEtl;"); }
        interruptedParseSeconds=parseTimer.Elapsed.TotalSeconds;
        peakObservedManaged=Math.Max(peakObservedManaged,GC.GetTotalMemory(false));
        Check(await Scalar(observer,$"SELECT COUNT_BIG(*) FROM dbo.TPImportLines WHERE ImportId='{id}'")==firstBatch,
            "first real parser batch survives interrupted pre-Ready attempt");
        retainedBinds=await Scalar(observer,$"SELECT COUNT_BIG(*) FROM dbo.TPImportBinds WHERE ImportId='{id}'");
        Check(retainedBinds>0 && retainedBinds<=expectedBinds,"committed real parser binds survive pre-Ready interruption");
        Check(await Scalar(observer,$"SELECT COUNT(*) FROM dbo.TPImportReceipts WHERE ImportId='{id}' AND Phase='Parsing' AND RetryableFailure=1")==1,
            "real interrupted parse is explicitly retryable, never Ready");
        Check(await Scalar(observer,$"SELECT COUNT(*) FROM dbo.UserSessions WHERE TraceId={trace}")==0,
            "interrupted real parse publishes no partial session dimensions");
        await Exec(observer,$"SELECT Sequence,TraceLineId,PayloadHash INTO #EtlRetained FROM dbo.TPImportLines WHERE ImportId='{id}';");
        await Exec(observer,$"SELECT Sequence,ParameterIndex,PayloadHash INTO #EtlRetainedBinds FROM dbo.TPImportBinds WHERE ImportId='{id}';");
    }
    var unrelatedBefore=await UnrelatedSnapshot(trace);
    await using(var retry=await Open())
    {
        await Exec(retry,"EXECUTE AS USER='ProtocolLifecycle'");
        var importer=Importer();
        Check((await importer.BeginImportAsync(retry,"account","etl-uploads",Name(id),"\"real-etl\"",budget.Token,contentLength:new FileInfo(path).Length)).TraceId==trace,
            "fresh importer resumes real ETL on same trace");
        await importer.SetContentHashAsync(retry,contentHash);
        var parseTimer=System.Diagnostics.Stopwatch.StartNew();
        var stats=new EtlParser(importer,NullLogger<EtlParser>.Instance).Parse(path,trace,retry);
        replayParseSeconds=parseTimer.Elapsed.TotalSeconds;
        peakObservedManaged=Math.Max(peakObservedManaged,GC.GetTotalMemory(false));
        Check(stats.Staged==expectedRows && stats.Enter==expected.GetProperty("Enter").GetInt32()
            && stats.Exit==expected.GetProperty("Exit").GetInt32() && stats.Stmt==expected.GetProperty("Stmt").GetInt32()
            && stats.Bind==expected.GetProperty("Bind").GetInt32() && stats.Fetch==expected.GetProperty("Fetch").GetInt32()
            && stats.Msg==expected.GetProperty("Msg").GetInt32() && stats.Mismatch==expected.GetProperty("Mismatch").GetInt32(),
            "real parser event counters match fixture catalog");
        Check(await Scalar(observer,$"SELECT COUNT(*) FROM dbo.TPImportReceipts WHERE ImportId='{id}' AND Phase='Ready' AND ExpectedRows={expectedRows} AND ExpectedBinds={expectedBinds}")==1,
            "real parser and SQL consumer durably publish exact Ready totals");
        Check(await Scalar(observer,$"SELECT COUNT_BIG(*) FROM dbo.TPImportLines WHERE ImportId='{id}'")==expectedRows
            && await Scalar(observer,$"SELECT COUNT(DISTINCT Sequence) FROM dbo.TPImportLines WHERE ImportId='{id}'")==expectedRows,
            "real replay loses and duplicates no lines");
        Check(await Scalar(observer,$"SELECT COUNT(*) FROM #EtlRetained old JOIN dbo.TPImportLines s ON s.ImportId='{id}' AND s.Sequence=old.Sequence AND s.TraceLineId=old.TraceLineId AND s.PayloadHash=old.PayloadHash")==firstBatch,
            "fresh parser replay preserves all retained IDs and payload fingerprints");
        Check(await Scalar(observer,$"SELECT COUNT(*) FROM #EtlRetainedBinds old JOIN dbo.TPImportBinds b ON b.ImportId='{id}' AND b.Sequence=old.Sequence AND b.ParameterIndex=old.ParameterIndex AND b.PayloadHash=old.PayloadHash")==retainedBinds,
            "fresh parser replay preserves retained bind payloads without duplication");
        if(expectedRows>firstBatch)
            Check(await Scalar(observer,$"SELECT COUNT(*) FROM dbo.TPImportLines s WHERE s.ImportId='{id}' AND s.CallTypeId=64 AND s.Sequence<(SELECT MAX(Sequence) FROM #EtlRetained) AND NOT EXISTS(SELECT 1 FROM #EtlRetained old WHERE old.Sequence=s.Sequence)")>0,
                "held SELECT crossing the real parser batch is not skipped by a sequence high-water mark");
        Check(await Scalar(observer,$"SELECT COUNT(*) FROM dbo.UserSessions WHERE TraceId={trace}")==expected.GetProperty("Sessions").GetInt32()
            && await Scalar(observer,$"SELECT COUNT(*) FROM dbo.UserSessionProcessThreads WHERE TraceId={trace}")==expected.GetProperty("Threads").GetInt32()
            && await Scalar(observer,$"SELECT COUNT(*) FROM dbo.TPImportThreads m JOIN dbo.UserSessionProcessThreads t ON t.UserSessionProcessThreadId=m.ThreadId JOIN dbo.UserSessions s ON s.SessionId=t.SessionId AND s.TraceId=t.TraceId WHERE m.ImportId='{id}' AND t.TraceId={trace} AND m.TempThreadId=-1")==1,
            "real X++ and SQL events share the correct composite session/thread mapping");
        Check(await Scalar(observer,$"SELECT COUNT(*) FROM dbo.TPImportBinds b JOIN dbo.TPImportLines s ON s.ImportId=b.ImportId AND s.Sequence=b.Sequence WHERE b.ImportId='{id}' AND s.CallTypeId=64 AND b.Sequence%10=5 AND b.ParameterIndex=0 AND b.BindValue=N'SYNTHETIC-42'")==expectedBinds,
            "real held SELECT parameters bind by statement sequence, not flush order");
        Check(await Scalar(observer,$"SELECT COUNT(*) FROM (SELECT Sequence,LAG(Sequence) OVER(ORDER BY TraceLineId) previous FROM dbo.TPImportLines WHERE ImportId='{id}') q WHERE previous>Sequence")>0,
            "real SQL staging preserves out-of-order parser emission");
        Check(await Scalar(observer,$"SELECT COUNT(*) FROM dbo.TPImportLines WHERE ImportId='{id}' AND CallTypeId=64 AND Sequence%10=5 AND InclusiveDurationNano=120000 AND RowFetchDurationNano=30000")==expectedBinds,
            "real parser duration fields retain existing tick semantics unchanged");
        // Report failure to the client AFTER the procedure committed, then close
        // the session. This models lost commit acknowledgement without a network.
        await Reject(51210,()=>Exec(retry,$"EXEC dbo.tp_PromoteImportBatch @ImportId='{id}',@BatchSize=3; THROW 51210,'Synthetic failure after promotion commit',1;"));
        await importer.RecordFailureAsync(retry);
        Check(await Scalar(observer,$"SELECT COUNT(*) FROM dbo.TPImportReceipts WHERE ImportId='{id}' AND Phase='Promoting' AND LastPromotedId>0")==1,
            "real ETL first promotion checkpoint commits before lost acknowledgement");
    }
    await using(var resumed=await Open())
    {
        await Exec(resumed,"EXECUTE AS USER='ProtocolLifecycle'");
        var importer=Importer();
        var receipt=await importer.BeginImportAsync(resumed,"account","etl-uploads",Name(id),"\"real-etl\"",budget.Token,contentLength:new FileInfo(path).Length);
        Check(receipt.TraceId==trace && receipt.Phase=="Promoting","real ETL durable promotion resumes without reparse");
        var finishTimer=System.Diagnostics.Stopwatch.StartNew();
        await importer.PromoteStageToTraceLines(resumed);
        Check(await Scalar(observer,$"SELECT COUNT(*) FROM dbo.TPImportReceipts WHERE ImportId='{id}' AND Phase='Finalizing'")==1,
            "real ETL rows and bindings finish before aggregation");
        await importer.CompleteImportAsync(resumed);
        Check(await Scalar(observer,$"SELECT COUNT(*) FROM dbo.TPImportReceipts WHERE ImportId='{id}' AND Phase='Complete' AND RetryableFailure=0")==1
            && await Scalar(observer,$"SELECT TotalTraceLines FROM dbo.SessionMetrics WHERE TraceId={trace}")==expectedRows
            && await Scalar(observer,$"SELECT SUM(CallCount) FROM dbo.TopMethodsBySession WHERE TraceId={trace}")==expected.GetProperty("Enter").GetInt32(),
            "real ETL physical aggregates and Complete commit with exact counts");
        Check(await Scalar(observer,$"SELECT COUNT(*) FROM dbo.TraceLines l JOIN dbo.UserSessionProcessThreads t ON t.UserSessionProcessThreadId=l.UserSessionProcessThreadId WHERE t.TraceId={trace}")==expectedRows
            && await Scalar(observer,$"SELECT COUNT(*) FROM dbo.QueryBindParameters b JOIN dbo.TraceLines l ON l.TraceLineId=b.TraceLineId JOIN dbo.UserSessionProcessThreads t ON t.UserSessionProcessThreadId=l.UserSessionProcessThreadId WHERE t.TraceId={trace} AND l.Sequence%10=5 AND l.CallTypeId=64 AND b.ParameterIndex=0 AND b.BindValue=N'SYNTHETIC-42'")==expectedBinds,
            "real promotion recovery has exact line/bind cardinality and association");
        Check(await Scalar(observer,$"SELECT COUNT(*) FROM #EtlRetained old JOIN dbo.TraceLines l ON l.TraceLineId=old.TraceLineId AND l.Sequence=old.Sequence JOIN dbo.UserSessionProcessThreads t ON t.UserSessionProcessThreadId=l.UserSessionProcessThreadId WHERE t.TraceId={trace}")==firstBatch,
            "real committed target retains IDs from interrupted parse");
        await importer.CleanupCompletedAsync(resumed);
        promotionCompletionSeconds=finishTimer.Elapsed.TotalSeconds;
        peakObservedManaged=Math.Max(peakObservedManaged,GC.GetTotalMemory(false));
        Check(await Scalar(observer,$"SELECT (SELECT COUNT(*) FROM dbo.TPImportLines WHERE ImportId='{id}')+(SELECT COUNT(*) FROM dbo.TPImportBinds WHERE ImportId='{id}')+(SELECT COUNT(*) FROM dbo.TPImportThreads WHERE ImportId='{id}')")==0,
            "real completed import cleans its new staging, binds and mapping");
    }
    await using(var duplicate=await Open())
    {
        await Exec(duplicate,"EXECUTE AS USER='ProtocolLifecycle'");
        var importer=Importer();
        Check((await importer.BeginImportAsync(duplicate,"account","etl-uploads",Name(id),"\"real-etl\"",budget.Token,contentLength:new FileInfo(path).Length)).IsTerminal,
            "real completed ETL delivery remains terminal");
        await importer.CleanupCompletedAsync(duplicate);
    }
    Check(unrelatedBefore==await UnrelatedSnapshot(trace),"real ETL retry preserves unrelated prepopulated trace data");
    Check(await Scalar(observer,"SELECT COUNT(*) FROM sys.indexes WHERE object_id=OBJECT_ID('dbo.TraceLines') AND is_disabled=1")==0,
        "real ETL full lifecycle leaves every target index enabled");
    await Exec(observer,"DROP TABLE #EtlRetained; DROP TABLE #EtlRetainedBinds;");
    Console.WriteLine(JsonSerializer.Serialize(new {
        Kind="RealSyntheticEtlSqlPipeline", Fixture=Path.GetFileName(path), Bytes=new FileInfo(path).Length,
        Sha256=Convert.ToHexString(contentHash), ExpectedRows=expectedRows, ExpectedBinds=expectedBinds,
        RetainedRowsAfterInterruption=firstBatch, RetainedBindsAfterInterruption=retainedBinds, PreexistingTraceLines=preexistingLines,
        InterruptedParseSeconds=interruptedParseSeconds, ReplayParseSeconds=replayParseSeconds,
        PromotionAggregationCleanupSeconds=promotionCompletionSeconds, TotalElapsedSeconds=timer.Elapsed.TotalSeconds,
        PeakObservedManagedBytes=peakObservedManaged, RestrictedPrincipal="ProtocolLifecycle",
        Scope="Unchanged production EtlParser, real StageBatchWriter/channel, SqlImporter, actual SQL protocol, restricted grants; pre-Ready failure/fresh replay and post-Ready lost acknowledgement; ticks preserved",
        Limit="LocalDB and these synthetic provider events only; no Azure/blob transfer/host invocation, no maximum-file or malformed-provider certification; no private header data emitted"
    }));

    async Task<string> UnrelatedSnapshot(int excludedTrace)
    {
        var values=new List<string>();
        foreach(var select in new[]{
            $"SELECT * FROM dbo.Traces WHERE TraceId<>{excludedTrace}",
            $"SELECT * FROM dbo.UserSessions WHERE TraceId<>{excludedTrace}",
            $"SELECT * FROM dbo.UserSessionProcessThreads WHERE TraceId<>{excludedTrace}",
            $"SELECT l.* FROM dbo.TraceLines l JOIN dbo.UserSessionProcessThreads t ON t.UserSessionProcessThreadId=l.UserSessionProcessThreadId WHERE t.TraceId<>{excludedTrace}",
            $"SELECT b.* FROM dbo.QueryBindParameters b JOIN dbo.TraceLines l ON l.TraceLineId=b.TraceLineId JOIN dbo.UserSessionProcessThreads t ON t.UserSessionProcessThreadId=l.UserSessionProcessThreadId WHERE t.TraceId<>{excludedTrace}",
            $"SELECT * FROM dbo.SessionMetrics WHERE TraceId<>{excludedTrace}",
            $"SELECT * FROM dbo.TopMethodsBySession WHERE TraceId<>{excludedTrace}"})
        {
            using var command=observer.CreateCommand();
            command.CommandText=$"SELECT CONCAT(COUNT_BIG(*),':',ISNULL(CHECKSUM_AGG(BINARY_CHECKSUM(*)),0)) FROM ({select}) protectedRows;";
            values.Add((string)(await command.ExecuteScalarAsync(budget.Token))!);
        }
        return string.Join("|",values);
    }
}

static bool HasSqlError(Exception error,int number) =>
    error is SqlException sql && sql.Errors.Cast<SqlError>().Any(e=>e.Number==number)
    || error.InnerException is not null && HasSqlError(error.InnerException,number);

async Task LargeChecks()
{
    const int rows = 250_000;
    var clock=System.Diagnostics.Stopwatch.StartNew();
    long maxMemory=0;
    for(var pass=0;pass<2;pass++)
    {
        var id=await Register();
        await using var conn=await Open();
        var importer=Importer();
        var receipt=await importer.BeginImportAsync(conn,"account","etl-uploads",Name(id),"\"large\"",default);
        await importer.SetContentHashAsync(conn,Hash("large"+pass));
        for(var start=1;start<=rows;start+=10000)
        {
            importer.FlushStageBatch(conn,Enumerable.Range(start,Math.Min(10000,rows-start+1)).Select(i=>Row(i,8)).ToList(),[]);
            maxMemory=Math.Max(maxMemory,GC.GetTotalMemory(false));
        }
        importer.FinishDimensions(conn,receipt.TraceId,Dimensions(receipt.TraceId),new(){Staged=rows});
        await using var readerConn=await Open();
        var committed=0;
        while(true)
        {
            using var batch=conn.CreateCommand();
            batch.CommandText="EXEC dbo.tp_PromoteImportBatch @ImportId=@id,@BatchSize=1000";
            batch.Parameters.Add("@id",SqlDbType.UniqueIdentifier).Value=id;
            var n=Convert.ToInt32(await batch.ExecuteScalarAsync());
            if(n==0)break;
            Check(n<=1000,"bounded large promotion");
            committed+=n;
            // Independent SQL session must make read progress between committed batches.
            Check(await Scalar(readerConn,$"SELECT COUNT_BIG(*) FROM dbo.TraceLines l JOIN dbo.UserSessionProcessThreads t ON t.UserSessionProcessThreadId=l.UserSessionProcessThreadId WHERE t.TraceId={receipt.TraceId}")==committed,
                "independent reader sees committed progress");
        }
        await importer.CompleteImportAsync(conn);
        await importer.CleanupCompletedAsync(conn);
        Check(committed==rows,"large import exact count");
        Check(await Scalar(conn,"SELECT COUNT(*) FROM sys.indexes WHERE object_id=OBJECT_ID('dbo.TraceLines') AND is_disabled=1")==0,
            "large import keeps indexes enabled");
    }
    Console.WriteLine($"SYNTHETIC LARGE: 2x{rows} rows; second pass has prepopulated target; elapsed={clock.Elapsed}; peakObservedManagedBytes={maxMemory}. NOT an ETL-parser or Azure performance certification.");
}

SqlImporter Importer() => new(NullLogger<SqlImporter>.Instance);
byte[] Hash(string text) => SHA256.HashData(Encoding.UTF8.GetBytes(text));
string Name(Guid id) => $"_imports/{id:D}/sample.etl";
StageRow Row(int seq, int type) => new()
{
    ThreadId = -1, Seq = seq, SeqEnd = seq, CallTypeId = type, TS = 1, TSEnd = 2, IsComplete = true,
    MethodHash = type == 8 ? SqlImporter.ComputeHash("test.method") : null, IncNano = 1000000, ExcNano = 1000000
};
InMemoryDimensions Dimensions(int trace)
{
    var dims = new InMemoryDimensions();
    var user = dims.GetUserId("synthetic-user");
    var cust = dims.GetCustomerId("synthetic-customer");
    var sess = dims.GetUserSessionId(trace, "session", user, cust);
    dims.GetThreadId("00000000-0000-0000-0000-000000000001", "", sess, trace);
    dims.EnsureMethodName("test.method", dims.GetMethodHash("test.method"));
    return dims;
}
async Task<Guid> Register()
{
    var id = Guid.NewGuid();
    await using var conn = await Open();
    using var cmd = conn.CreateCommand();
    cmd.CommandText = "EXEC dbo.tp_RegisterUpload @id,N'account',N'etl-uploads',@name,N'synthetic-session'";
    cmd.Parameters.Add("@id", SqlDbType.UniqueIdentifier).Value = id;
    cmd.Parameters.Add("@name", SqlDbType.NVarChar, 1024).Value = Name(id);
    await cmd.ExecuteNonQueryAsync();
    return id;
}
async Task<SqlConnection> Open()
{
    var conn = new SqlConnection(databaseString);
    await conn.OpenAsync();
    return conn;
}
async Task Exec(SqlConnection conn, string sql, Guid? id = null)
{
    using var cmd = conn.CreateCommand(); cmd.CommandText = sql; cmd.CommandTimeout = 120;
    if (id.HasValue) cmd.Parameters.Add("@id", SqlDbType.UniqueIdentifier).Value = id.Value;
    await cmd.ExecuteNonQueryAsync();
}
async Task<long> Scalar(SqlConnection conn, string sql)
{
    using var cmd = conn.CreateCommand(); cmd.CommandText = sql;
    return Convert.ToInt64(await cmd.ExecuteScalarAsync());
}
void Check(bool result, string label)
{
    if (!result) throw new InvalidOperationException("FAIL " + label);
    checks++;
    if (label is not "bounded large promotion" and not "independent reader sees committed progress")
        Console.WriteLine("PASS " + label);
}
async Task Reject(int number, Func<Task> action)
{
    try { await action(); }
    catch (SqlException ex) when (ex.Number == number) { checks++; Console.WriteLine("PASS reject " + number); return; }
    throw new InvalidOperationException("Expected SQL rejection " + number);
}
