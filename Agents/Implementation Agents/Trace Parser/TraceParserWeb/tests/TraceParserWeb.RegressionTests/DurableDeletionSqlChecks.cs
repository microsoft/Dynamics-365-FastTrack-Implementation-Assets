using System.Data;
using System.Text.RegularExpressions;
using Microsoft.Data.SqlClient;
using TraceParser.Deletion;

internal static class DurableDeletionSqlChecks
{
    const string Server = @"(localdb)\TPImporterTests_c100bb02";
    static int checks;
    static readonly Guid Tenant = Guid.NewGuid(), Requester = Guid.NewGuid();
    static readonly string Root = Path.GetFullPath(Path.Combine(AppContext.BaseDirectory, "..", "..", "..", "..", ".."));

    public static async Task RunAsync()
    {
        foreach (var rcsi in new[] { false, true })
        {
            var db = "TPDurableDelete_c100bb02_" + Guid.NewGuid().ToString("N");
            await using var master = await Open("master");
            await Exec(master, $"CREATE DATABASE [{db}]");
            try
            {
                if (rcsi) await Exec(master, $"ALTER DATABASE [{db}] SET READ_COMMITTED_SNAPSHOT ON");
                await using var owner = await Open(db);
                var fixture = await File.ReadAllTextAsync(Path.Combine(Root, "tests", "TraceParserFunction.ProtocolTests", "Fixture.sql"));
                foreach (var batch in Regex.Split(fixture, @"^\s*GO\s*$", RegexOptions.Multiline | RegexOptions.IgnoreCase))
                    if (!string.IsNullOrWhiteSpace(batch)) await Exec(owner, batch);
                var importer = await File.ReadAllTextAsync(Path.Combine(Root, "sql", "safe-importer.sql"));
                foreach (var batch in Regex.Split(importer, @"^\s*GO\s*$", RegexOptions.Multiline | RegexOptions.IgnoreCase))
                    if (!string.IsNullOrWhiteSpace(batch)) await Exec(owner, batch);
                var migration = await File.ReadAllTextAsync(Path.Combine(Root, "sql", "durable-deletion.sql"));
                var deletion = await File.ReadAllTextAsync(Path.Combine(Root, "sql", "sp_DeleteTrace.sql"));
                await Exec(owner, migration);
                Check(await Number(owner, "SELECT COUNT(*) FROM dbo.TraceDeletionJobs") == 0, "Migration adopted traces");
                await Exec(owner, deletion);
                await Exec(owner, """
                    CREATE USER JobWeb WITHOUT LOGIN;
                    CREATE USER JobWorker WITHOUT LOGIN;
                    CREATE USER OldDeletion WITHOUT LOGIN;
                    GRANT EXECUTE ON dbo.sp_DeleteTrace TO OldDeletion;
                    GRANT SELECT ON dbo.Traces TO OldDeletion;
                    """);
                var permissions = (await File.ReadAllTextAsync(Path.Combine(Root, "sql", "durable-deletion-permissions.sql")))
                    .Replace("TraceParserDeletionWeb", "JobWeb").Replace("TraceParserDeletionWorker", "JobWorker");
                await Exec(owner, permissions);
                await using var web = await Open(db, "JobWeb");
                await using var worker = await Open(db, "JobWorker");
                await using var second = await Open(db, "JobWorker");
                await using var legacy = await Open(db, "OldDeletion");
                await Error(() => Exec(web, "DELETE dbo.TraceDeletionJobs"), 229);
                await Error(() => Exec(worker, "SELECT * FROM dbo.Traces"), 229);
                await Error(() => Exec(web, $"EXEC dbo.dj_Claim '{Guid.NewGuid()}'"), 229);
                await Error(() => Exec(worker, $"EXEC dbo.dj_Enqueue '{Tenant}','{Requester}','{Guid.NewGuid()}',1"), 229);
                await Error(() => Exec(web, "EXEC dbo.dj_AssertProtocol @Install=1"), 229);
                await Error(() => Exec(worker, "EXEC dbo.sp_DeleteTrace 1"), 229);
                await Error(() => Exec(worker, "EXEC dbo.dj_AssertProtocol @Install=1"), 229);
                await Exec(owner, "EXEC dbo.tp_AssertDeletionProtocol"); checks++;

                var trace = await Seed(owner, "durable fixture");
                var key = Guid.NewGuid();
                var alias = Guid.NewGuid();
                var job = await Enqueue(web, trace, key);
                Check(job == await Enqueue(web, trace, key), "Request replay created another job");
                Check(job == await Enqueue(web, trace, alias), "Double click created another job");
                await Error(() => Enqueue(web, trace, Guid.NewGuid(), Guid.NewGuid()), 51203);
                Check((await Rows(web, $"EXEC dbo.dj_Read '{Guid.NewGuid()}','{Requester}','{job}'")).Count == 0, "Cross-tenant status leak");
                Check((await Rows(web, $"EXEC dbo.dj_Read '{Tenant}','{Guid.NewGuid()}','{job}'")).Count == 0, "Cross-user status leak");
                await Error(() => Exec(web, $"EXEC dbo.dj_Control '{Tenant}','{Guid.NewGuid()}','{job}','Cancel'"), 51203);
                await Error(() => Exec(legacy, $"EXEC dbo.sp_DeleteTrace {trace}"), 51206);
                await Exec(owner, migration);
                await Exec(owner, deletion);
                Check(await Number(owner, "SELECT COUNT(*) FROM dbo.TraceDeletionJobs") == 1, "Reinstall changed jobs");
                await Exec(owner, "EXEC dbo.tp_AssertDeletionProtocol"); checks++;
                var competing = await Task.WhenAll(Claim(worker), Claim(second));
                Check(competing.Count(c => c.HasValue) == 1, "Simultaneous scaled claims both acquired work");
                var lease = competing.Single(c => c.HasValue);
                Check(lease is not null && lease.Value.Job == job, "Claim failed");
                Check(await Claim(second) is null, "Scaled worker acquired second global slot");
                var l = lease!.Value;
                await Error(() => Step(second, l with { Token = Guid.NewGuid() }), 51205);
                await Error(() => Step(worker, l with { Seq = 2 }), 51207);
                await Error(() => Exec(owner, $"EXEC dbo.sp_DeleteTrace @TraceId={trace+1},@JobId='{job}',@LeaseToken='{l.Token}',@ExpectedSequence=0"), 51205);
                await Error(() => Exec(worker, $"EXEC dbo.dj_Step '{Guid.NewGuid()}','{l.Token}',0"), 51205);

                // Statement failure after data writes rolls the data and progress back together.
                await Exec(owner, """
                    CREATE TRIGGER dbo.SyntheticDeleteFailure ON dbo.TraceLines AFTER DELETE AS
                    THROW 51300,'Synthetic rollback before commit',1;
                    """);
                await Error(() => Step(worker, l), 51300);
                Check(await Number(owner, $"SELECT Sequence FROM dbo.TraceDeletionJobs WHERE JobId='{job}'") == 0, "Rolled-back batch advanced sequence");
                Check(await Number(owner, "SELECT COUNT(*) FROM dbo.TraceLines") == 5, "Rolled-back batch lost data");
                await Exec(owner, "DROP TRIGGER dbo.SyntheticDeleteFailure");
                await Step(worker, l); // Deliberately discard acknowledgement.
                Check(await Number(owner, $"SELECT Sequence FROM dbo.TraceDeletionJobs WHERE JobId='{job}'") == 1, "Lost ack did not persist");
                Check(await Number(owner, $"SELECT CommittedRows FROM dbo.TraceDeletionJobs WHERE JobId='{job}'") == 2, "Wrong committed counter");
                await Step(worker, l); // Same sequence must not delete an extra batch.
                Check(await Number(owner, "SELECT COUNT(*) FROM dbo.TraceLines") == 3, "Expected-sequence replay deleted again");
                checks++;

                // Old owner holds the job row while data is blocked. Expiry must not permit takeover.
                await Exec(owner, $"UPDATE dbo.TraceDeletionJobs SET LeaseExpiresUtc=DATEADD(second,2,SYSUTCDATETIME()) WHERE JobId='{job}'");
                await using (var blocker = await Open(db))
                {
                    await Exec(blocker, $"BEGIN TRAN; SELECT TraceId FROM dbo.Traces WITH(XLOCK,HOLDLOCK) WHERE TraceId={trace}");
                    var pending = Step(worker, l with { Seq = 1 });
                    await WaitForBlocked(owner, "sp_DeleteTrace");
                    // SQL time is intentionally tested here; lifecycle/backoff tests below edit only owned fixtures.
                    await Task.Delay(2200);
                    var reclaim = Claim(second);
                    await Task.Delay(150);
                    Check(!reclaim.IsCompleted, "Expired takeover passed uncommitted ownership lock");
                    await Exec(blocker, "ROLLBACK");
                    await pending;
                    await reclaim;
                }
                Check(await Number(owner, $"SELECT Sequence FROM dbo.TraceDeletionJobs WHERE JobId='{job}'") == 2, "Blocked owner lost committed progress");
                await Exec(owner, $"UPDATE dbo.TraceDeletionJobs SET NextDueUtc=DATEADD(second,-1,SYSUTCDATETIME()) WHERE JobId='{job}'");
                l = (await Claim(second))!.Value;
                await Error(() => Step(worker, lease.Value with { Seq = 2 }), 51205);
                await Exec(worker, $"EXEC dbo.dj_Release '{job}','{lease.Value.Token}',51013");
                Check(await Number(owner, $"SELECT COUNT(*) FROM dbo.TraceDeletionJobs WHERE JobId='{job}' AND LeaseToken='{l.Token}'") == 1,
                    "Stale release cleared successor");
                await Exec(web, $"EXEC dbo.dj_Control '{Tenant}','{Requester}','{job}','Cancel'");
                await Step(second, l);
                Check(await State(owner, job) == "Cancelled", "Cancel-before-batch not honored");
                Check(await Number(owner, "SELECT COUNT(*) FROM dbo.TraceLines") == 1, "Cancellation deleted another batch");
                await Exec(web, $"EXEC dbo.dj_Control '{Tenant}','{Requester}','{job}','Resume'");
                var resumed = (await Claim(worker))!.Value;
                Check(resumed.Token != l.Token && resumed.Seq == 2, "Resume reused lease or reset progress");

                // Cancellation waits behind an already committing batch, then stops the next one.
                await using (var blocker = await Open(db))
                {
                    await Exec(blocker, $"BEGIN TRAN; SELECT TraceId FROM dbo.Traces WITH(XLOCK,HOLDLOCK) WHERE TraceId={trace}");
                    var pending = Step(worker, resumed);
                    await WaitForBlocked(owner, "sp_DeleteTrace");
                    var cancel = Exec(web, $"EXEC dbo.dj_Control '{Tenant}','{Requester}','{job}','Cancel'");
                    await Task.Delay(100);
                    Check(!cancel.IsCompleted, "Cancel did not serialize with committing batch");
                    await Exec(blocker, "ROLLBACK");
                    await pending;
                    await cancel;
                }
                await Step(worker, resumed with { Seq = 3 });
                Check(await State(owner, job) == "Cancelled", "Concurrent cancellation was overwritten");
                Check(await Number(owner, $"SELECT CommittedRows FROM dbo.TraceDeletionJobs WHERE JobId='{job}'") == 5, "Cancel lost committed rows");
                await Exec(web, $"EXEC dbo.dj_Control '{Tenant}','{Requester}','{job}','Resume'");
                resumed = (await Claim(second))!.Value;
                for (var n = 0; n < 20 && await State(owner, job) != "Completed"; n++)
                {
                    await Step(second, resumed);
                    resumed = resumed with { Seq = resumed.Seq + 1 };
                }
                Check(await State(owner, job) == "Completed", "Full SQL lifecycle did not complete");
                Check(await Number(owner, $"SELECT COUNT(*) FROM dbo.Traces WHERE TraceId={trace}") == 0, "Completion left root");
                Check((await Rows(web, $"EXEC dbo.dj_Read '{Tenant}','{Requester}','{job}'")).Count == 1, "Completed rootless job not recoverable");
                Check(await Enqueue(web, trace, key) == job, "Completed request replay recreated job");
                Check(await Enqueue(web, trace, alias) == job, "Duplicate request alias lost its completed job");
                await Error(() => Enqueue(web, trace, Guid.NewGuid()), 51204);

                await EligibilityAndFailures(owner, web, worker, legacy);
                // Exercise the actual production SQL client and worker, not only raw procedure calls.
                // SQL authorization itself is covered above with the two restricted principals.
                var client = new SqlDeletionJobStore(owner.ConnectionString);
                foreach (var existing in await client.ReadAsync(Tenant, Requester, null, default))
                    if (existing.CanCancel) await client.ControlAsync(Tenant, Requester, existing.JobId, "Cancel", default);
                var endToEndTrace = await Seed(owner, "production client end to end");
                var endToEnd = await client.EnqueueAsync(Tenant, Requester, Guid.NewGuid(), endToEndTrace, default);
                await new DeletionWorker(client, TimeProvider.System).RunSliceAsync(default);
                endToEnd = (await client.ReadAsync(Tenant, Requester, endToEnd.JobId, default)).Single();
                Check(endToEnd.State == "Completed" && endToEnd.CommittedRows == 8 && endToEnd.Sequence == 4,
                    "Production SQL client/worker did not complete full cycle");
                Console.WriteLine($"Durable deletion SQL RCSI={rcsi}: {checks} cumulative checks passed.");
            }
            finally
            {
                SqlConnection.ClearAllPools();
                await Exec(master, $"ALTER DATABASE [{db}] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [{db}]");
            }
        }
        Console.WriteLine($"{checks} durable deletion real-SQL checks passed; owned databases removed.");
    }

    static async Task EligibilityAndFailures(SqlConnection owner, SqlConnection web, SqlConnection worker, SqlConnection legacy)
    {
        var trace = await Seed(owner, "eligibility");
        var import = Guid.NewGuid();
        await Exec(owner, $"""
            INSERT dbo.TPImportReceipts(ImportId,SourceKey,AccountName,ContainerName,BlobName,SessionName,TraceId,Phase)
            VALUES('{import}',HASHBYTES('SHA2_256','{import}'),'synthetic','synthetic','synthetic','synthetic',{trace},'Parsing');
            """);
        await Error(() => Enqueue(web, trace, Guid.NewGuid()), 51131);
        await Exec(owner, $"UPDATE dbo.TPImportReceipts SET Phase='Complete' WHERE ImportId='{import}'");
        var job = await Enqueue(web, trace, Guid.NewGuid());
        var lease = (await Claim(worker))!.Value;
        await Exec(owner, $"UPDATE dbo.TPImportReceipts SET Phase='Promoting' WHERE ImportId='{import}'");
        await Error(() => Step(worker, lease), 51131);
        await Exec(worker, $"EXEC dbo.dj_Release '{job}','{lease.Token}',51131");
        Check(await State(owner, job) == "Blocked", "Changed import eligibility not stopped");
        await Exec(owner, $"UPDATE dbo.TPImportReceipts SET Phase='Complete' WHERE ImportId='{import}'");
        Check(await Claim(worker) is null, "Blocked job auto-resumed");
        await Exec(web, $"EXEC dbo.dj_Control '{Tenant}','{Requester}','{job}','Resume'");
        lease = (await Claim(worker))!.Value;
        await Exec(owner, """
            CREATE TRIGGER dbo.SyntheticTombstoneFailure ON dbo.TPImportReceipts AFTER UPDATE AS
            IF EXISTS(SELECT 1 FROM inserted WHERE Phase='Deleted')
                THROW 51301,'Synthetic failure after data writes and tombstone',1;
            """);
        var beforeRows = await Number(owner, "SELECT COUNT(*) FROM dbo.TraceLines");
        await Error(() => Step(worker, lease), 51301);
        Check(await Number(owner, "SELECT COUNT(*) FROM dbo.TraceLines") == beforeRows
            && await Number(owner, $"SELECT Sequence FROM dbo.TraceDeletionJobs WHERE JobId='{job}'") == 0
            && (string)(await Scalar(owner, $"SELECT Phase FROM dbo.TPImportReceipts WHERE ImportId='{import}'"))! == "Complete",
            "Failed tombstone left data, receipt or progress partially committed");
        await Exec(owner, "DROP TRIGGER dbo.SyntheticTombstoneFailure");
        await Step(worker, lease);
        Check((string)(await Scalar(owner, $"SELECT Phase FROM dbo.TPImportReceipts WHERE ImportId='{import}'"))! == "Deleted",
            "Receipt tombstone did not commit with first batch");
        await Exec(worker, $"EXEC dbo.dj_Release '{job}','{lease.Token}',1205");
        Check(await State(owner, job) == "RetryScheduled", "Transient retry not classified");
        Check(await Claim(worker) is null, "Backoff ignored next due time");
        await Exec(owner, $"UPDATE dbo.TraceDeletionJobs SET NextDueUtc=DATEADD(second,-1,SYSUTCDATETIME()),Attempts=8 WHERE JobId='{job}'");
        lease = (await Claim(worker))!.Value;
        await Exec(worker, $"EXEC dbo.dj_Release '{job}','{lease.Token}',1205");
        Check(await State(owner, job) == "Failed", "Retry limit not bounded");
        await Exec(web, $"EXEC dbo.dj_Control '{Tenant}','{Requester}','{job}','Resume'");
        lease = (await Claim(worker))!.Value;
        await Exec(owner, $"UPDATE dbo.Traces SET DeletionIdentity=NEWID() WHERE TraceId={trace}");
        await Error(() => Step(worker, lease), 51208);
        await Exec(worker, $"EXEC dbo.dj_Release '{job}','{lease.Token}',51208");
        Check(await State(owner, job) == "Failed", "Identity mismatch not permanent");

        var other = await Seed(owner, "independent legacy");
        await Exec(legacy, $"EXEC dbo.sp_DeleteTrace {other},2");
        checks++;
        var otherJob = await Enqueue(web, other, Guid.NewGuid());
        lease = (await Claim(worker))!.Value;
        Check(lease.Job == otherJob, "Failed job starved eligible job");
        Check(await Number(owner, $"SELECT CommittedRows FROM dbo.TraceDeletionJobs WHERE JobId='{otherJob}'") == 0, "Prior partial history included");
        await Exec(owner, "ALTER INDEX UX_DeletionTrace ON dbo.TraceDeletionJobs DISABLE");
        await Error(() => Step(worker, lease), 51200);
        Check(await State(owner, otherJob) == "Running", "Schema error fabricated completion");
        await Error(() => Exec(owner, awaitMigration()), 51200);
        await Exec(owner, "ALTER INDEX UX_DeletionTrace ON dbo.TraceDeletionJobs REBUILD");
        await Exec(owner, "EXEC sys.sp_updateextendedproperty @name=N'TraceParserDurableDeletionHash',@value=0x00,@level0type=N'SCHEMA',@level0name=N'dbo',@level1type=N'PROCEDURE',@level1name=N'sp_DeleteTrace'");
        await Error(() => Step(worker, lease), 51202);
        await Exec(owner, await File.ReadAllTextAsync(Path.Combine(Root, "sql", "sp_DeleteTrace.sql")));
        await Exec(owner, "REVOKE EXECUTE ON dbo.dj_Step FROM JobWorker");
        await Error(() => Step(worker, lease), 229);
        await Exec(worker, $"EXEC dbo.dj_Release '{otherJob}','{lease.Token}',229");
        Check(await State(owner, otherJob) == "Failed", "Permission denial was retryable/completed");
        await Exec(owner, "GRANT EXECUTE ON dbo.dj_Step TO JobWorker");
        await Exec(web, $"EXEC dbo.dj_Control '{Tenant}','{Requester}','{otherJob}','Resume'");
        lease = (await Claim(worker))!.Value;
        await Exec(owner, $"""
            INSERT dbo.TopMethods(Id,BeginUspId,EndUspId)
            SELECT 1,a.UserSessionProcessThreadId,b.UserSessionProcessThreadId
            FROM dbo.UserSessionProcessThreads a CROSS JOIN dbo.UserSessionProcessThreads b
            WHERE a.TraceId={other} AND b.TraceId={trace};
            """);
        await Error(() => Step(worker, lease), 51013);
        await Exec(owner, "DELETE dbo.TopMethods WHERE Id=1");
        await Exec(worker, $"EXEC dbo.dj_Release '{otherJob}','{lease.Token}',51130");
        Check(await State(owner, otherJob) == "RetryScheduled", "Busy trace did not yield its slot");
        var absent = await Seed(owner, "root absence");
        var absentJob = await Enqueue(web, absent, Guid.NewGuid());
        lease = (await Claim(worker))!.Value;
        Check(lease.Job == absentJob, "Busy/backoff job starved a due job");
        // Simulate independently verified historical cleanup; only this owned synthetic fixture.
        await Exec(owner, $"""
            DELETE tl FROM dbo.TraceLines tl JOIN dbo.UserSessionProcessThreads u
                ON tl.UserSessionProcessThreadId=u.UserSessionProcessThreadId WHERE u.TraceId={absent};
            DELETE dbo.UserSessionProcessThreads WHERE TraceId={absent};
            DELETE dbo.UserSessions WHERE TraceId={absent};
            DELETE dbo.Traces WHERE TraceId={absent};
            """);
        await Step(worker, lease);
        Check(await State(owner, absentJob) == "Completed", "Actual root absence did not complete idempotently");
        Check(await Number(owner, $"SELECT CommittedRows FROM dbo.TraceDeletionJobs WHERE JobId='{absentJob}'") == 0,
            "Root absence invented committed rows");

        var cancelled = await Seed(owner, "queued cancellation");
        var cancelledJob = await Enqueue(web, cancelled, Guid.NewGuid());
        await Exec(web, $"EXEC dbo.dj_Control '{Tenant}','{Requester}','{cancelledJob}','Cancel'");
        Check(await State(owner, cancelledJob) == "Cancelled", "Queued cancellation failed");
        await Exec(web, $"EXEC dbo.dj_Control '{Tenant}','{Requester}','{cancelledJob}','Resume'");
        lease = (await Claim(worker))!.Value;
        await Exec(web, $"EXEC dbo.dj_Control '{Tenant}','{Requester}','{cancelledJob}','Cancel'");
        await Exec(owner, $"UPDATE dbo.TraceDeletionJobs SET LeaseExpiresUtc=DATEADD(second,-1,SYSUTCDATETIME()) WHERE JobId='{cancelledJob}'");
        await Claim(worker);
        Check(await State(owner, cancelledJob) == "Cancelled", "Expired cancelled lease resumed deletion");
        Check(await Number(owner, $"SELECT COUNT(*) FROM dbo.Traces WHERE TraceId={cancelled}") == 1, "Cancellation lost root");
        await Exec(web, $"EXEC dbo.dj_Control '{Tenant}','{Requester}','{cancelledJob}','Resume'");
        lease = (await Claim(worker))!.Value;
        Check(lease.Job == cancelledJob, "Explicit resume did not reclaim held job");
        await Exec(owner, $"UPDATE dbo.TraceDeletionJobs SET Attempts=8,LeaseExpiresUtc=DATEADD(second,-1,SYSUTCDATETIME()) WHERE JobId='{cancelledJob}'");
        await Claim(worker);
        Check(await State(owner, cancelledJob) == "Failed", "Repeated expired claims retried forever");

        string awaitMigration() => File.ReadAllText(Path.Combine(Root, "sql", "durable-deletion.sql"));
    }

    static async Task<int> Seed(SqlConnection c, string name)
    {
        return Convert.ToInt32(await Scalar(c, $"""
            INSERT dbo.Traces(TraceName,TraceFile,TimeStampBegin,TimeStampEnd,TraceParserVersion)
                VALUES(N'{name}','synthetic.etl','2020-01-01','2020-01-01','legacy');
            DECLARE @trace int=SCOPE_IDENTITY(),@thread int,@user int,@customer int;
            INSERT dbo.Users(UserName) VALUES(CONVERT(nvarchar(36),NEWID())); SET @user=SCOPE_IDENTITY();
            INSERT dbo.Customers(CustomerName) VALUES(CONVERT(nvarchar(36),NEWID())); SET @customer=SCOPE_IDENTITY();
            INSERT dbo.UserSessions(SessionId,TraceId,SessionName,UserId,CustomerCustomerId)
                VALUES(@trace,@trace,'synthetic',@user,@customer);
            INSERT dbo.UserSessionProcessThreads(SessionId,TraceId,RequestId,ActivityId,RelatedActivityId)
                VALUES(@trace,@trace,NEWID(),NEWID(),NEWID());
            SET @thread=SCOPE_IDENTITY();
            INSERT dbo.TraceLines(UserSessionProcessThreadId,CallTypeId,Sequence,SequenceEnd,[TimeStamp],
                TimeStampEnd,InclusiveDurationNano,ExclusiveDurationNano,DatabaseDurationNano,
                InclusiveRpc,DatabaseCalls,PrepDurationNano,BindDurationNano,RowFetchDurationNano,
                RowFetchCount,HasChildren,FileName,EventId,EventType,LineNumber)
            SELECT @thread,1,n,n,0,0,0,0,0,0,0,0,0,0,0,0,'synthetic.etl',1,1,1
                FROM(VALUES(1),(2),(3),(4),(5))n(n);
            SELECT @trace;
            """))!;
    }

    static Task<SqlConnection> Open(string db, string? user = null) => OpenCore(db, user);
    static async Task<SqlConnection> OpenCore(string db, string? user)
    {
        if (db != "master" && !Regex.IsMatch(db, "^TPDurableDelete_c100bb02_[a-f0-9]{32}$"))
            throw new InvalidOperationException("Not an owned local fixture database.");
        var c = new SqlConnection(new SqlConnectionStringBuilder { DataSource = Server, InitialCatalog = db,
            IntegratedSecurity = true, Encrypt = false, Pooling = false, ConnectTimeout = 15 }.ConnectionString);
        await c.OpenAsync();
        if (!c.DataSource.Contains("TPImporterTests_c100bb02", StringComparison.OrdinalIgnoreCase)) throw new Exception("Unsafe server");
        if (user is not null) await Exec(c, $"EXECUTE AS USER='{user}'");
        return c;
    }
    static async Task Exec(SqlConnection c, string sql)
    { using var command = new SqlCommand(sql, c) { CommandTimeout = 30 }; await command.ExecuteNonQueryAsync(); }
    static async Task<object?> Scalar(SqlConnection c, string sql)
    { using var command = new SqlCommand(sql, c) { CommandTimeout = 30 }; return await command.ExecuteScalarAsync(); }
    static async Task<long> Number(SqlConnection c, string sql) => Convert.ToInt64(await Scalar(c, sql));
    static async Task<List<object[]>> Rows(SqlConnection c, string sql)
    {
        using var command = new SqlCommand(sql, c) { CommandTimeout = 30 };
        using var r = await command.ExecuteReaderAsync();
        var rows = new List<object[]>();
        while (await r.ReadAsync()) { var values = new object[r.FieldCount]; r.GetValues(values); rows.Add(values); }
        return rows;
    }
    static async Task<Guid> Enqueue(SqlConnection c, int trace, Guid key, Guid? requester = null) =>
        (Guid)(await Rows(c, $"EXEC dbo.dj_Enqueue '{Tenant}','{requester ?? Requester}','{key}',{trace}"))[0][0];
    readonly record struct Lease(Guid Job, Guid Token, long Seq);
    static async Task<Lease?> Claim(SqlConnection c)
    {
        var rows = await Rows(c, $"EXEC dbo.dj_Claim '{Guid.NewGuid()}'");
        return rows.Count == 0 ? null : new((Guid)rows[0][0], (Guid)rows[0][2], (long)rows[0][3]);
    }
    static Task Step(SqlConnection c, Lease l) => Exec(c, $"EXEC dbo.dj_Step '{l.Job}','{l.Token}',{l.Seq},2");
    static async Task<string> State(SqlConnection c, Guid id) => (string)(await Scalar(c, $"SELECT State FROM dbo.TraceDeletionJobs WHERE JobId='{id}'"))!;
    static async Task Error(Func<Task> action, int number)
    {
        try { await action(); throw new Exception($"Expected SQL {number}"); }
        catch (SqlException e) when (e.Number == number) { checks++; }
    }
    static void Check(bool value, string message) { if (!value) throw new Exception(message); checks++; }
    static async Task WaitForBlocked(SqlConnection c, string text)
    {
        for (var n = 0; n < 100; n++)
        {
            if (await Number(c, "SELECT COUNT(*) FROM sys.dm_exec_requests WHERE database_id=DB_ID() AND blocking_session_id<>0") > 0) return;
            await Task.Delay(20);
        }
        throw new Exception("Synthetic batch did not block: " + text);
    }
}
