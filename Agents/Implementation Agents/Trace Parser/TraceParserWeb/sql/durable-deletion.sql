-- Install after safe-importer.sql, then run sp_DeleteTrace.sql before granting access.
-- Empty queue; no historical trace is automatically scheduled. No GO.
SET NOCOUNT ON;
SET XACT_ABORT ON;
IF @@TRANCOUNT<>0 THROW 51200,'Install durable deletion outside a transaction.',1;
IF OBJECT_ID('dbo.TPImportReceipts','U') IS NULL OR OBJECT_ID('dbo.Traces','U') IS NULL
    THROW 51200,'Install the supported importer schema first.',1;
IF EXISTS(SELECT 1 FROM sys.triggers WHERE parent_id=OBJECT_ID('dbo.Traces') AND is_disabled=0)
    THROW 51200,'Review root triggers before installing durable deletion.',1;
BEGIN TRY
BEGIN TRAN;
DECLARE @new bit=CASE WHEN OBJECT_ID('dbo.TraceDeletionJobs') IS NULL THEN 1 ELSE 0 END;
-- An incarnation token distinguishes even an identically named, manually reused TraceId.
IF COL_LENGTH('dbo.Traces','DeletionIdentity') IS NULL
    ALTER TABLE dbo.Traces ADD DeletionIdentity uniqueidentifier NOT NULL
        CONSTRAINT DF_Traces_DeletionIdentity DEFAULT NEWID() WITH VALUES;
IF NOT EXISTS(SELECT 1 FROM sys.columns WHERE object_id=OBJECT_ID('dbo.Traces')
    AND name='DeletionIdentity' AND TYPE_NAME(user_type_id)='uniqueidentifier' AND is_nullable=0 AND is_computed=0
    AND OBJECT_DEFINITION(default_object_id)='(newid())')
    THROW 51200,'Unsupported trace incarnation column.',1;
IF OBJECT_ID('dbo.TraceDeletionJobs') IS NULL
BEGIN
    CREATE TABLE dbo.TraceDeletionJobs(
        JobId uniqueidentifier NOT NULL CONSTRAINT PK_TraceDeletionJobs PRIMARY KEY,
        RequestKey uniqueidentifier NOT NULL,
        TenantId uniqueidentifier NOT NULL,
        RequesterId uniqueidentifier NOT NULL,
        TraceId int NOT NULL,
        TraceIdentity uniqueidentifier NOT NULL,
        ImportId uniqueidentifier NULL,
        State varchar(20) NOT NULL,
        IsActive bit NOT NULL CONSTRAINT DF_DeletionActive DEFAULT 1,
        LeaseToken uniqueidentifier NULL,
        LeaseOwner uniqueidentifier NULL,
        LeaseExpiresUtc datetime2 NULL,
        Sequence bigint NOT NULL CONSTRAINT DF_DeletionSequence DEFAULT 0,
        CommittedRows bigint NOT NULL CONSTRAINT DF_DeletionRows DEFAULT 0,
        LastRows int NOT NULL CONSTRAINT DF_DeletionLastRows DEFAULT 0,
        LastPhase nvarchar(40) NOT NULL CONSTRAINT DF_DeletionPhase DEFAULT N'Queued',
        LastHasMore int NOT NULL CONSTRAINT DF_DeletionMore DEFAULT 1,
        Attempts int NOT NULL CONSTRAINT DF_DeletionAttempts DEFAULT 0,
        NextDueUtc datetime2 NOT NULL CONSTRAINT DF_DeletionDue DEFAULT SYSUTCDATETIME(),
        ErrorCode int NULL,
        ErrorMessage nvarchar(256) NULL,
        CreatedUtc datetime2 NOT NULL CONSTRAINT DF_DeletionCreated DEFAULT SYSUTCDATETIME(),
        UpdatedUtc datetime2 NOT NULL CONSTRAINT DF_DeletionUpdated DEFAULT SYSUTCDATETIME(),
        CONSTRAINT CK_DeletionState CHECK(State IN ('Queued','Running','RetryScheduled','CancelRequested',
            'Cancelled','Blocked','Failed','Completed')),
        CONSTRAINT CK_DeletionCounters CHECK(Sequence>=0 AND CommittedRows>=0 AND LastRows>=0 AND Attempts>=0),
        CONSTRAINT CK_DeletionLease CHECK(
            (LeaseToken IS NULL AND LeaseOwner IS NULL AND LeaseExpiresUtc IS NULL)
            OR (LeaseToken IS NOT NULL AND LeaseOwner IS NOT NULL AND LeaseExpiresUtc IS NOT NULL)),
        CONSTRAINT CK_DeletionActive CHECK((State='Completed' AND IsActive=0) OR (State<>'Completed' AND IsActive=1))
    );
    CREATE UNIQUE INDEX UX_DeletionRequest ON dbo.TraceDeletionJobs(TenantId,RequesterId,RequestKey);
    CREATE UNIQUE INDEX UX_DeletionTrace ON dbo.TraceDeletionJobs(TraceId) WHERE IsActive=1;
    -- A constant filtered key enforces ONE leased job across processes and Function instances.
    ALTER TABLE dbo.TraceDeletionJobs ADD WorkSlot AS (CONVERT(int,1)) PERSISTED;
    CREATE UNIQUE INDEX UX_DeletionSlot ON dbo.TraceDeletionJobs(WorkSlot) WHERE LeaseToken IS NOT NULL;
    CREATE INDEX IX_DeletionDue ON dbo.TraceDeletionJobs(State,NextDueUtc,CreatedUtc);
    CREATE INDEX IX_DeletionRequester ON dbo.TraceDeletionJobs(TenantId,RequesterId,CreatedUtc DESC);
    CREATE TABLE dbo.TraceDeletionRequests(
        TenantId uniqueidentifier NOT NULL,
        RequesterId uniqueidentifier NOT NULL,
        RequestKey uniqueidentifier NOT NULL,
        JobId uniqueidentifier NOT NULL REFERENCES dbo.TraceDeletionJobs(JobId),
        CONSTRAINT PK_TraceDeletionRequests PRIMARY KEY(TenantId,RequesterId,RequestKey)
    );
END;
-- Fail closed on unsupported objects; installation never drops/recreates job state.
IF (SELECT COUNT(*) FROM sys.columns WHERE object_id=OBJECT_ID('dbo.TraceDeletionJobs'))<>24
    OR (SELECT COUNT(*) FROM sys.columns WHERE object_id=OBJECT_ID('dbo.TraceDeletionRequests'))<>4
    OR EXISTS(SELECT 1 FROM sys.triggers WHERE parent_id=OBJECT_ID('dbo.TraceDeletionJobs') AND is_disabled=0)
    OR EXISTS(SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID('dbo.TraceDeletionJobs') AND is_disabled=1)
    OR EXISTS(SELECT 1 FROM sys.check_constraints WHERE parent_object_id=OBJECT_ID('dbo.TraceDeletionJobs')
        AND (is_disabled=1 OR is_not_trusted=1))
    THROW 51200,'Unsupported durable deletion schema. No jobs changed.',1;

EXEC(N'CREATE OR ALTER PROCEDURE dbo.dj_AssertProtocol @Install bit=0
WITH EXECUTE AS OWNER
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @shape nvarchar(max)=
        (SELECT OBJECT_NAME(c.object_id) AS tableName,c.name,c.user_type_id,c.max_length,c.is_nullable,c.is_computed,
            cc.definition AS computedDefinition,dc.definition AS defaultDefinition
         FROM sys.columns c LEFT JOIN sys.computed_columns cc ON c.object_id=cc.object_id AND c.column_id=cc.column_id
         LEFT JOIN sys.default_constraints dc ON c.default_object_id=dc.object_id
         WHERE c.object_id IN(OBJECT_ID(''dbo.TraceDeletionJobs''),OBJECT_ID(''dbo.TraceDeletionRequests''))
            OR (c.object_id=OBJECT_ID(''dbo.Traces'') AND c.name=''DeletionIdentity'')
         ORDER BY c.object_id,c.column_id FOR JSON PATH);
    SET @shape+=
        (SELECT OBJECT_NAME(i.object_id) AS tableName,i.name,i.type,i.is_unique,i.is_disabled,i.has_filter,i.filter_definition,
            ic.key_ordinal,ic.is_included_column,c.name AS columnName
         FROM sys.indexes i JOIN sys.index_columns ic ON i.object_id=ic.object_id AND i.index_id=ic.index_id
         JOIN sys.columns c ON c.object_id=ic.object_id AND c.column_id=ic.column_id
         WHERE i.object_id IN(OBJECT_ID(''dbo.TraceDeletionJobs''),OBJECT_ID(''dbo.TraceDeletionRequests''))
         ORDER BY i.object_id,i.index_id,ic.index_column_id FOR JSON PATH);
    SET @shape+=
        (SELECT name,definition,is_disabled,is_not_trusted FROM sys.check_constraints
         WHERE parent_object_id=OBJECT_ID(''dbo.TraceDeletionJobs'') ORDER BY name FOR JSON PATH);
    SET @shape+=
        (SELECT name,is_disabled,is_not_trusted,delete_referential_action,update_referential_action,
            OBJECT_NAME(referenced_object_id) AS referencedTable
         FROM sys.foreign_keys WHERE parent_object_id=OBJECT_ID(''dbo.TraceDeletionRequests'')
         ORDER BY name FOR JSON PATH);
    DECLARE @hash varbinary(32)=HASHBYTES(''SHA2_256'',@shape),@expected varbinary(32);
    SELECT @expected=CONVERT(varbinary(32),value) FROM sys.extended_properties
        WHERE major_id=OBJECT_ID(''dbo.TraceDeletionJobs'') AND name=''TraceParserDeletionSchemaHash'';
    IF @Install=1 AND @expected IS NULL
        EXEC sys.sp_addextendedproperty @name=N''TraceParserDeletionSchemaHash'',@value=@hash,
            @level0type=N''SCHEMA'',@level0name=N''dbo'',@level1type=N''TABLE'',@level1name=N''TraceDeletionJobs'';
    ELSE IF @expected IS NULL OR @hash IS NULL OR @hash<>@expected
        THROW 51200,''Durable deletion schema changed. Owner review required.'',1;
    IF EXISTS(SELECT 1 FROM sys.triggers WHERE parent_id IN(OBJECT_ID(''dbo.TraceDeletionJobs''),OBJECT_ID(''dbo.Traces''),
            OBJECT_ID(''dbo.TraceDeletionRequests''))
            AND is_disabled=0)
        OR EXISTS(SELECT 1 FROM sys.objects WHERE object_id IN(OBJECT_ID(''dbo.TraceDeletionJobs''),OBJECT_ID(''dbo.Traces''),
            OBJECT_ID(''dbo.TPImportReceipts''),OBJECT_ID(''dbo.TraceDeletionRequests''))
            AND COALESCE(principal_id,(SELECT principal_id FROM sys.schemas WHERE name=''dbo''))
                <>(SELECT principal_id FROM sys.schemas WHERE name=''dbo''))
        THROW 51200,''Unsupported deletion ownership or triggers.'',1;
    IF NOT EXISTS(SELECT 1 FROM sys.columns WHERE object_id=OBJECT_ID(''dbo.Traces'') AND name=''DeletionIdentity''
        AND TYPE_NAME(user_type_id)=''uniqueidentifier'' AND is_nullable=0 AND is_computed=0 AND default_object_id<>0)
        THROW 51200,''Unsupported trace incarnation column.'',1;
    IF @Install=0 AND NOT EXISTS(SELECT 1 FROM sys.extended_properties WHERE major_id=OBJECT_ID(''dbo.sp_DeleteTrace'')
        AND name=''TraceParserDurableDeletionHash''
        AND CONVERT(varbinary(32),value)=HASHBYTES(''SHA2_256'',OBJECT_DEFINITION(OBJECT_ID(''dbo.sp_DeleteTrace''))))
        THROW 51202,''Durable deletion contract is not installed or changed. Owner review required.'',1;
END');
-- Only installation may initialize the fingerprint, and only for a table created above.
IF @new=0 AND NOT EXISTS(SELECT 1 FROM sys.extended_properties WHERE major_id=OBJECT_ID('dbo.TraceDeletionJobs')
    AND name='TraceParserDeletionSchemaHash')
    THROW 51200,'Existing job table has no supported schema contract.',1;
EXEC dbo.dj_AssertProtocol @Install=1;

EXEC(N'CREATE OR ALTER PROCEDURE dbo.dj_Read
    @TenantId uniqueidentifier,@RequesterId uniqueidentifier,@JobId uniqueidentifier=NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT JobId,TraceId,State,Sequence,CommittedRows,LastPhase,ErrorCode,ErrorMessage,
        CreatedUtc,UpdatedUtc,NextDueUtc
    FROM dbo.TraceDeletionJobs
    WHERE TenantId=@TenantId AND RequesterId=@RequesterId AND (@JobId IS NULL OR JobId=@JobId)
    ORDER BY CreatedUtc DESC,JobId;
END');

EXEC(N'CREATE OR ALTER PROCEDURE dbo.dj_Enqueue
    @TenantId uniqueidentifier,@RequesterId uniqueidentifier,@RequestKey uniqueidentifier,@TraceId int
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    IF @@TRANCOUNT<>0 THROW 51201,''Call enqueue outside a transaction.'',1;
    IF @TraceId IS NULL OR @TraceId<=0 OR @TenantId IS NULL OR @RequesterId IS NULL OR @RequestKey IS NULL
        OR @TenantId=CONVERT(uniqueidentifier,0x0) OR @RequesterId=CONVERT(uniqueidentifier,0x0)
        OR @RequestKey=CONVERT(uniqueidentifier,0x0) THROW 51201,''Invalid request identity.'',1;
    EXEC dbo.dj_AssertProtocol;
    DECLARE @job uniqueidentifier,@identity uniqueidentifier,@import uniqueidentifier,@phase varchar(24),@r int;
    BEGIN TRY
        BEGIN TRAN;
        -- Serialize request keys separately, before the trace lock. Never take these locks in a worker.
        DECLARE @requestLock nvarchar(255)=CONCAT(''TraceParser:DeleteRequest:'',@TenantId,'':'',@RequesterId,'':'',@RequestKey);
        EXEC @r=sys.sp_getapplock @Resource=@requestLock,@LockMode=''Exclusive'',@LockOwner=''Transaction'',@LockTimeout=0;
        IF @r<0 THROW 51130,''Request is busy. Retry with the same request key.'',1;
        SELECT @job=JobId FROM dbo.TraceDeletionRequests WHERE TenantId=@TenantId AND RequesterId=@RequesterId AND RequestKey=@RequestKey;
        IF @job IS NOT NULL
        BEGIN
            IF EXISTS(SELECT 1 FROM dbo.TraceDeletionJobs WHERE JobId=@job AND TraceId<>@TraceId)
                THROW 51201,''Request key belongs to a different trace.'',1;
            COMMIT; EXEC dbo.dj_Read @TenantId,@RequesterId,@job; RETURN;
        END;
        DECLARE @lock nvarchar(255)=CONCAT(''TraceParser:Trace:'',@TraceId);
        EXEC @r=sys.sp_getapplock @Resource=@lock,@LockMode=''Exclusive'',@LockOwner=''Transaction'',@LockTimeout=0;
        IF @r<0 THROW 51130,''Trace is busy. Retry later.'',1;
        SELECT @job=JobId FROM dbo.TraceDeletionJobs WHERE TraceId=@TraceId AND IsActive=1;
        IF @job IS NOT NULL
        BEGIN
            IF NOT EXISTS(SELECT 1 FROM dbo.TraceDeletionJobs WHERE JobId=@job AND TenantId=@TenantId AND RequesterId=@RequesterId)
                THROW 51203,''Trace has an existing deletion request. Contact the requester.'',1;
            INSERT dbo.TraceDeletionRequests VALUES(@TenantId,@RequesterId,@RequestKey,@job);
            COMMIT; EXEC dbo.dj_Read @TenantId,@RequesterId,@job; RETURN;
        END;
        SELECT @identity=DeletionIdentity FROM dbo.Traces WITH(UPDLOCK,HOLDLOCK) WHERE TraceId=@TraceId;
        IF @identity IS NULL THROW 51204,''Trace is absent. No deletion job was created.'',1;
        SELECT @import=ImportId,@phase=Phase FROM dbo.TPImportReceipts WITH(READCOMMITTEDLOCK) WHERE TraceId=@TraceId;
        IF @phase NOT IN(''Complete'',''Deleted'') THROW 51131,''Import is active or retryable. Deletion is blocked.'',1;
        SET @job=NEWID();
        INSERT dbo.TraceDeletionJobs(JobId,RequestKey,TenantId,RequesterId,TraceId,TraceIdentity,ImportId,State)
            VALUES(@job,@RequestKey,@TenantId,@RequesterId,@TraceId,@identity,@import,''Queued'');
        INSERT dbo.TraceDeletionRequests VALUES(@TenantId,@RequesterId,@RequestKey,@job);
        COMMIT;
        EXEC dbo.dj_Read @TenantId,@RequesterId,@job;
    END TRY
    BEGIN CATCH
        IF XACT_STATE()<>0 ROLLBACK;
        THROW;
    END CATCH;
END');

EXEC(N'CREATE OR ALTER PROCEDURE dbo.dj_Control
    @TenantId uniqueidentifier,@RequesterId uniqueidentifier,@JobId uniqueidentifier,@Action varchar(10)
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    IF @@TRANCOUNT<>0 THROW 51201,''Call control outside a transaction.'',1;
    IF @Action NOT IN(''Cancel'',''Resume'') OR @Action IS NULL THROW 51201,''Invalid action.'',1;
    -- Only job locks: never subsequently acquire trace/data/receipt locks.
    BEGIN TRAN;
    IF NOT EXISTS(SELECT 1 FROM dbo.TraceDeletionJobs WITH(UPDLOCK,HOLDLOCK)
        WHERE JobId=@JobId AND TenantId=@TenantId AND RequesterId=@RequesterId)
    BEGIN ROLLBACK; THROW 51203,''Deletion job is unavailable.'',1; END;
    IF @Action=''Cancel''
        UPDATE dbo.TraceDeletionJobs SET State=CASE WHEN LeaseToken IS NULL THEN ''Cancelled'' ELSE ''CancelRequested'' END,
            UpdatedUtc=SYSUTCDATETIME()
        WHERE JobId=@JobId AND State IN(''Queued'',''Running'',''RetryScheduled'',''CancelRequested'');
    ELSE
        UPDATE dbo.TraceDeletionJobs SET State=''Queued'',Attempts=0,NextDueUtc=SYSUTCDATETIME(),
            ErrorCode=NULL,ErrorMessage=NULL,UpdatedUtc=SYSUTCDATETIME()
        WHERE JobId=@JobId AND LeaseToken IS NULL AND State IN(''Cancelled'',''Blocked'',''Failed'');
    COMMIT;
    EXEC dbo.dj_Read @TenantId,@RequesterId,@JobId;
END');

EXEC(N'CREATE OR ALTER PROCEDURE dbo.dj_Claim @Owner uniqueidentifier
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    IF @@TRANCOUNT<>0 OR @Owner IS NULL THROW 51201,''Invalid claim.'',1;
    DECLARE @r int,@job uniqueidentifier,@now datetime2=SYSUTCDATETIME();
    DECLARE @claimed TABLE(JobId uniqueidentifier,TraceId int,LeaseToken uniqueidentifier,Sequence bigint);
    BEGIN TRY
        BEGIN TRAN;
        EXEC @r=sys.sp_getapplock @Resource=''TraceParser:DeletionSlot'',@LockMode=''Exclusive'',
            @LockOwner=''Transaction'',@LockTimeout=0;
        IF @r<0 BEGIN ROLLBACK; RETURN; END;
        -- UPDLOCK waits for an old batch to commit before reclaiming, even after expiry.
        IF EXISTS(SELECT 1 FROM dbo.TraceDeletionJobs WITH(UPDLOCK,HOLDLOCK)
            WHERE LeaseToken IS NOT NULL AND LeaseExpiresUtc>@now)
        BEGIN COMMIT; RETURN; END;
        UPDATE dbo.TraceDeletionJobs SET LeaseToken=NULL,LeaseOwner=NULL,LeaseExpiresUtc=NULL,
            State=CASE WHEN State=''CancelRequested'' THEN ''Cancelled''
                WHEN Attempts>=8 THEN ''Failed'' ELSE ''RetryScheduled'' END,
            Attempts=Attempts+1,ErrorCode=51210,
            ErrorMessage=N''Worker lease expired. Progress retained; bounded retry or explicit owner-reviewed resume required.'',
            NextDueUtc=DATEADD(second,CONVERT(int,POWER(2.0,CASE WHEN Attempts>6 THEN 6 ELSE Attempts END))*5
                +ABS(CONVERT(bigint,CHECKSUM(NEWID())))%5,@now),UpdatedUtc=@now
        WHERE LeaseToken IS NOT NULL AND LeaseExpiresUtc<=@now;
        SELECT TOP(1) @job=JobId FROM dbo.TraceDeletionJobs WITH(UPDLOCK,HOLDLOCK)
            WHERE State IN(''Queued'',''RetryScheduled'') AND NextDueUtc<=@now
            ORDER BY NextDueUtc,CreatedUtc,JobId;
        UPDATE dbo.TraceDeletionJobs SET State=''Running'',LeaseOwner=@Owner,LeaseToken=NEWID(),
            LeaseExpiresUtc=DATEADD(second,90,SYSUTCDATETIME()),UpdatedUtc=SYSUTCDATETIME()
            OUTPUT inserted.JobId,inserted.TraceId,inserted.LeaseToken,inserted.Sequence INTO @claimed
            WHERE JobId=@job;
        COMMIT;
        SELECT JobId,TraceId,LeaseToken,Sequence FROM @claimed;
    END TRY
    BEGIN CATCH IF XACT_STATE()<>0 ROLLBACK; THROW; END CATCH;
END');

EXEC(N'CREATE OR ALTER PROCEDURE dbo.dj_Renew
    @JobId uniqueidentifier,@Token uniqueidentifier
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE dbo.TraceDeletionJobs SET LeaseExpiresUtc=DATEADD(second,90,SYSUTCDATETIME())
    WHERE JobId=@JobId AND LeaseToken=@Token AND LeaseExpiresUtc>SYSUTCDATETIME()
        AND State IN(''Running'',''CancelRequested'');
    IF @@ROWCOUNT<>1 THROW 51205,''Deletion lease is no longer owned.'',1;
END');

EXEC(N'CREATE OR ALTER PROCEDURE dbo.dj_Inspect @JobId uniqueidentifier,@Token uniqueidentifier
AS
BEGIN
    SET NOCOUNT ON;
    SELECT Sequence,State FROM dbo.TraceDeletionJobs WHERE JobId=@JobId AND LeaseToken=@Token;
END');

EXEC(N'CREATE OR ALTER PROCEDURE dbo.dj_Release
    @JobId uniqueidentifier,@Token uniqueidentifier,@ErrorCode int=NULL
AS
BEGIN
    SET NOCOUNT ON;
    -- Codes, not exception text, cross the persistence boundary. Stale owners cannot release successors.
    UPDATE dbo.TraceDeletionJobs SET
        State=CASE WHEN State=''CancelRequested'' THEN ''Cancelled''
            WHEN @ErrorCode=51131 THEN ''Blocked''
            WHEN @ErrorCode IS NULL THEN ''Queued''
            WHEN @ErrorCode IN(-2,1205,1222,51130,40197,40501,40613,10928,10929,10053,10054,10060)
                AND Attempts<8 THEN ''RetryScheduled'' ELSE ''Failed'' END,
        Attempts=CASE WHEN @ErrorCode IS NULL THEN 0 ELSE Attempts+1 END,
        NextDueUtc=DATEADD(second,CASE WHEN @ErrorCode IS NULL THEN 5
            ELSE CONVERT(int,POWER(2.0,CASE WHEN Attempts>6 THEN 6 ELSE Attempts END))*5
                +ABS(CONVERT(bigint,CHECKSUM(NEWID())))%5 END,SYSUTCDATETIME()),
        ErrorCode=@ErrorCode,
        ErrorMessage=CASE WHEN @ErrorCode IS NULL THEN NULL
            WHEN @ErrorCode=51131 THEN N''Import is active/retryable. Resolve it, then explicitly resume.''
            WHEN @ErrorCode IN(-2,1205,1222,51130,40197,40501,40613,10928,10929,10053,10054,10060)
                THEN N''Transient SQL failure. Bounded retry; inspect committed progress before resuming.''
            ELSE N''Deletion stopped. Deployment owner must review permissions, schema and trace identity before resume.'' END,
        LeaseOwner=NULL,LeaseToken=NULL,LeaseExpiresUtc=NULL,UpdatedUtc=SYSUTCDATETIME()
    WHERE JobId=@JobId AND LeaseToken=@Token AND LeaseExpiresUtc>SYSUTCDATETIME()
        AND State IN(''Running'',''CancelRequested'');
END');

EXEC(N'CREATE OR ALTER PROCEDURE dbo.dj_Step
    @JobId uniqueidentifier,@Token uniqueidentifier,@ExpectedSequence bigint,@BatchSize int=2000
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @trace int;
    SELECT @trace=TraceId FROM dbo.TraceDeletionJobs WHERE JobId=@JobId AND LeaseToken=@Token;
    IF @trace IS NULL THROW 51205,''Deletion lease is no longer owned.'',1;
    EXEC dbo.dj_AssertProtocol;
    EXEC dbo.sp_DeleteTrace @TraceId=@trace,@BatchSize=@BatchSize,
        @JobId=@JobId,@LeaseToken=@Token,@ExpectedSequence=@ExpectedSequence;
    SELECT Sequence,State FROM dbo.TraceDeletionJobs WHERE JobId=@JobId;
END');
COMMIT;
END TRY
BEGIN CATCH
    IF XACT_STATE()<>0 ROLLBACK;
    THROW;
END CATCH;
