-- Additive protocol v1. Run deliberately before deploying either application.
-- Never adopt, truncate, remap, reseed, rebuild or repair legacy objects/data.
-- Existing importers must be quiescent at cutover; old writers do not honor this protocol.
SET XACT_ABORT ON;
GO
IF OBJECT_ID('dbo.TPImportReceipts', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.TPImportReceipts (
        ImportId uniqueidentifier NOT NULL PRIMARY KEY,
        SourceKey binary(32) NOT NULL UNIQUE,
        AccountName nvarchar(128) COLLATE Latin1_General_100_BIN2 NOT NULL,
        ContainerName nvarchar(63) COLLATE Latin1_General_100_BIN2 NOT NULL,
        BlobName nvarchar(1024) COLLATE Latin1_General_100_BIN2 NOT NULL,
        SessionName nvarchar(500) NOT NULL,
        ETag nvarchar(128) COLLATE Latin1_General_100_BIN2 NULL,
        ContentHash binary(32) NULL,
        ParserVersion varchar(40) NOT NULL DEFAULT 'safe-import-v1',
        Phase varchar(24) NOT NULL DEFAULT 'Registered',
        RetryableFailure bit NOT NULL DEFAULT 0,
        -- Intentionally no FK: deleting a completed trace must retain its receipt.
        TraceId int NULL,
        ExpectedRows bigint NULL,
        ExpectedBinds bigint NULL,
        LastPromotedId bigint NOT NULL DEFAULT 0,
        LastBindSequence int NOT NULL DEFAULT 0,
        LastBindIndex int NOT NULL DEFAULT -1,
        CreatedUtc datetime2 NOT NULL DEFAULT SYSUTCDATETIME(),
        UpdatedUtc datetime2 NOT NULL DEFAULT SYSUTCDATETIME(),
        CONSTRAINT CK_TPImportPhase CHECK
          (Phase IN ('Registered','Parsing','Ready','Promoting','Binding','Finalizing','Complete','Deleted','RejectedOversize'))
    );
    CREATE UNIQUE INDEX UX_TPImportTrace ON dbo.TPImportReceipts(TraceId) WHERE TraceId IS NOT NULL;
END;
-- Add a rejection state to an already installed protocol without changing any rows.
IF EXISTS(SELECT 1 FROM sys.check_constraints WHERE parent_object_id=OBJECT_ID('dbo.TPImportReceipts')
    AND name='CK_TPImportPhase' AND definition NOT LIKE '%RejectedOversize%')
BEGIN
    BEGIN TRY
        BEGIN TRAN;
        ALTER TABLE dbo.TPImportReceipts DROP CONSTRAINT CK_TPImportPhase;
        ALTER TABLE dbo.TPImportReceipts WITH CHECK ADD CONSTRAINT CK_TPImportPhase CHECK
          (Phase IN ('Registered','Parsing','Ready','Promoting','Binding','Finalizing','Complete','Deleted','RejectedOversize'));
        COMMIT;
    END TRY
    BEGIN CATCH
        IF XACT_STATE()<>0 ROLLBACK;
        THROW;
    END CATCH;
END;
IF OBJECT_ID('dbo.TPImportLines', 'U') IS NULL
BEGIN
    SELECT TOP(0) * INTO dbo.TPImportLines FROM dbo.StageTraceLines;
    ALTER TABLE dbo.TPImportLines ADD ImportId uniqueidentifier NOT NULL, PayloadHash binary(32) NOT NULL;
    ALTER TABLE dbo.TPImportLines ADD CONSTRAINT PK_TPImportLines PRIMARY KEY CLUSTERED(ImportId,TraceLineId);
    CREATE UNIQUE INDEX UX_TPImportSequence ON dbo.TPImportLines(ImportId,Sequence);
    CREATE UNIQUE INDEX UX_TPImportLineId ON dbo.TPImportLines(TraceLineId);
END;
IF OBJECT_ID('dbo.TPImportBinds', 'U') IS NULL
    CREATE TABLE dbo.TPImportBinds (
        ImportId uniqueidentifier NOT NULL,
        Sequence int NOT NULL,
        ParameterIndex int NOT NULL,
        BindValue nvarchar(max) NULL,
        PayloadHash binary(32) NOT NULL,
        CONSTRAINT PK_TPImportBinds PRIMARY KEY(ImportId,Sequence,ParameterIndex)
    );
IF OBJECT_ID('dbo.TPImportThreads', 'U') IS NULL
    CREATE TABLE dbo.TPImportThreads (
        ImportId uniqueidentifier NOT NULL,
        TempThreadId int NOT NULL,
        ThreadId int NOT NULL,
        CONSTRAINT PK_TPImportThreads PRIMARY KEY(ImportId,TempThreadId)
    );
GO
-- Web gets EXECUTE on these two procedures only, never receipt-table access.
CREATE OR ALTER PROCEDURE dbo.tp_RegisterUpload
    @ImportId uniqueidentifier, @AccountName nvarchar(128), @ContainerName nvarchar(63),
    @BlobName nvarchar(1024), @SessionName nvarchar(500)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF @ImportId IS NULL OR LEN(@AccountName)=0 OR LEN(@ContainerName)=0 OR LEN(@SessionName)=0
       OR LEFT(@BlobName,46) COLLATE Latin1_General_100_BIN2 <>
          ('_imports/'+LOWER(CONVERT(varchar(36),@ImportId))+'/') COLLATE Latin1_General_100_BIN2
       OR LEN(@BlobName)<=50
       THROW 51100,'Invalid new-upload registration.',1;
    DECLARE @key binary(32)=HASHBYTES('SHA2_256',
        CONCAT(LEN(@AccountName),':',@AccountName,LEN(@ContainerName),':',@ContainerName,LEN(@BlobName),':',@BlobName));
    INSERT dbo.TPImportReceipts(ImportId,SourceKey,AccountName,ContainerName,BlobName,SessionName)
        VALUES(@ImportId,@key,@AccountName,@ContainerName,@BlobName,@SessionName);
END;
GO
CREATE OR ALTER PROCEDURE dbo.tp_GetImportStatus @ImportId uniqueidentifier=NULL, @TraceId int=NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT ImportId,TraceId,
       CASE WHEN Phase='Deleted' AND EXISTS(SELECT 1 FROM dbo.Traces t WHERE t.TraceId=r.TraceId)
          THEN 'Deleting' ELSE Phase END AS Phase,
       CAST(CASE WHEN RetryableFailure=1 OR
          (TraceId IS NOT NULL AND Phase NOT IN ('Complete','Deleted','RejectedOversize')
           AND APPLOCK_TEST('public',CONCAT('TraceParser:Trace:',TraceId),'Shared','Session')=1)
         THEN 1 ELSE 0 END AS bit) AS RetryableFailure,UpdatedUtc
    FROM dbo.TPImportReceipts r
    WHERE (@ImportId IS NOT NULL AND ImportId=@ImportId)
       OR (@ImportId IS NULL AND @TraceId IS NOT NULL AND TraceId=@TraceId);
END;
GO
-- Fixed metadata-only module; runtime callers need EXECUTE, not VIEW DEFINITION.
CREATE OR ALTER PROCEDURE dbo.tp_AssertDeletionProtocol
WITH EXECUTE AS OWNER
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @expected varbinary(32)=(SELECT CONVERT(varbinary(32),value) FROM sys.extended_properties
        WHERE class=1 AND major_id=OBJECT_ID('dbo.sp_DeleteTrace') AND name=N'TraceParserImporterDeletionHash');
    DECLARE @actual varbinary(32)=HASHBYTES('SHA2_256',OBJECT_DEFINITION(OBJECT_ID('dbo.sp_DeleteTrace')));
    IF @expected IS NULL OR DATALENGTH(@expected)<>32 OR @actual IS NULL OR @expected<>@actual
        THROW 51122,'Coordinated deletion is not installed or was changed; importer activation is blocked.',1;
END;
GO
-- Metadata is otherwise hidden from an EXECUTE-only caller. Never interpret hidden
-- sys.indexes rows as proof that the indexes are enabled.
CREATE OR ALTER PROCEDURE dbo.tp_AssertImporterStorage @FirstTraceLineId bigint=NULL
WITH EXECUTE AS OWNER
AS
BEGIN
    SET NOCOUNT ON;
    IF OBJECT_ID('dbo.TraceLines','U') IS NULL
       OR ISNULL(COLUMNPROPERTY(OBJECT_ID('dbo.TraceLines'),'TraceLineId','IsIdentity'),0)<>1
       OR EXISTS(SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID('dbo.TraceLines') AND is_disabled=1)
       THROW 51102,'TraceLines identity/index prerequisites are unavailable; no automatic repair.',1;
    IF @FirstTraceLineId IS NOT NULL AND @FirstTraceLineId<=
       ISNULL((SELECT CONVERT(bigint,last_value) FROM sys.identity_columns
         WHERE object_id=OBJECT_ID('dbo.TraceLines') AND name='TraceLineId'),0)
       THROW 51120,'ID allocator is behind the target identity high-water mark; no automatic reseeding.',1;
END;
GO
CREATE OR ALTER PROCEDURE dbo.tp_AssertImportOwner @ImportId uniqueidentifier
AS
BEGIN
    SET NOCOUNT ON;
    EXEC dbo.tp_AssertDeletionProtocol;
    IF APPLOCK_MODE('public','TraceParser:Importer:v1','Session') <> 'Exclusive'
       OR NOT EXISTS(SELECT 1 FROM dbo.TPImportReceipts WHERE ImportId=@ImportId)
       THROW 51101,'Importer ownership is absent; stop this attempt.',1;
    DECLARE @trace int=(SELECT TraceId FROM dbo.TPImportReceipts WHERE ImportId=@ImportId);
    IF @trace IS NULL OR APPLOCK_MODE('public',CONCAT('TraceParser:Trace:',@trace),'Session')<>'Exclusive'
       THROW 51101,'Trace ownership is absent; stop this attempt.',1;
    EXEC dbo.tp_AssertImporterStorage;
END;
GO
-- Additive allocator: shares the legacy lock/control, but never swallows rollback.
-- An absent, nonsingleton or stale control is held for review, never reseeded.
CREATE OR ALTER PROCEDURE dbo.tp_ReserveTraceLineIds @ImportId uniqueidentifier,@BatchSize int
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    EXEC dbo.tp_AssertImportOwner @ImportId;
    IF @BatchSize<1 OR @BatchSize>200000 THROW 51118,'Invalid staging allocation size.',1;
    BEGIN TRY
      BEGIN TRAN;
      DECLARE @rc int,@first bigint;
      EXEC @rc=sys.sp_getapplock @Resource='ReserveTraceLineIdControl',@LockMode='Exclusive',
          @LockOwner='Transaction',@LockTimeout=5000;
      IF @rc<0 THROW 51119,'ID allocator is busy.',1;
      IF (SELECT COUNT_BIG(*) FROM dbo.TraceLineIDControls WITH(UPDLOCK,HOLDLOCK))<>1
          THROW 51120,'ID allocator requires explicit review; no automatic initialization.',1;
      SELECT @first=NextTraceLineId FROM dbo.TraceLineIDControls;
      EXEC dbo.tp_AssertImporterStorage @FirstTraceLineId=@first;
      IF @first IS NULL OR @first<1 OR @first>9223372036854775807-@BatchSize
         OR @first<=ISNULL((SELECT MAX(TraceLineId) FROM dbo.TraceLines),0)
         OR @first<=ISNULL((SELECT MAX(TraceLineId) FROM dbo.StageTraceLines),0)
         OR @first<=ISNULL((SELECT MAX(TraceLineId) FROM dbo.TPImportLines),0)
          THROW 51120,'ID allocator is invalid/stale; no automatic reseeding.',1;
      UPDATE dbo.TraceLineIDControls SET NextTraceLineId=@first+@BatchSize;
      COMMIT;
      SELECT @first;
    END TRY
    BEGIN CATCH
      IF XACT_STATE()<>0 ROLLBACK;
      THROW;
    END CATCH;
END;
GO
CREATE OR ALTER PROCEDURE dbo.tp_BeginImport
    @AccountName nvarchar(128), @ContainerName nvarchar(63), @BlobName nvarchar(1024), @ETag nvarchar(128),
    @ContentLength bigint
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @rc int, @id uniqueidentifier, @trace int, @phase varchar(24), @oldTag nvarchar(128), @session nvarchar(500);
    EXEC @rc=sys.sp_getapplock @Resource='TraceParser:Importer:v1',@LockMode='Exclusive',
        @LockOwner='Session',@LockTimeout=0;
    IF @rc<0 THROW 51103,'Another importer owns the database; retry later.',1;
    DECLARE @key binary(32)=HASHBYTES('SHA2_256',
        CONCAT(LEN(@AccountName),':',@AccountName,LEN(@ContainerName),':',@ContainerName,LEN(@BlobName),':',@BlobName));
    SELECT @id=ImportId,@trace=TraceId,@phase=Phase,@oldTag=ETag,@session=SessionName
      FROM dbo.TPImportReceipts WHERE SourceKey=@key
      AND AccountName=@AccountName COLLATE Latin1_General_100_BIN2
      AND ContainerName=@ContainerName COLLATE Latin1_General_100_BIN2
      AND BlobName=@BlobName COLLATE Latin1_General_100_BIN2;
    -- An old/unregistered blob is held, not adopted and not replayed.
    IF @id IS NULL THROW 51104,'LegacyUntracked: explicit upload registration required; blob retained.',1;
    IF @ETag IS NULL OR LEN(@ETag)=0 OR @ContentLength IS NULL OR @ContentLength<0
       OR EXISTS(SELECT 1 FROM dbo.TPImportReceipts WHERE ImportId=@id AND ParserVersion<>'safe-import-v1')
       THROW 51107,'Missing/invalid source version or length, or incompatible import protocol.',1;
    IF @oldTag IS NOT NULL AND @oldTag<>@ETag COLLATE Latin1_General_100_BIN2
       THROW 51105,'Unregistered blob replacement held; create a fresh registered upload.',1;
    IF @phase IN ('Complete','Deleted')
    BEGIN
        SELECT ImportId,TraceId,Phase,LastPromotedId FROM dbo.TPImportReceipts WHERE ImportId=@id;
        RETURN;
    END;
    -- Mirrors the existing 1 GiB UI/server policy, not a new size allowance.
    -- Commit the rejected receipt before reporting failure; never create a root.
    IF @phase='RejectedOversize' THROW 51127,'ETL rejected: exceeds 1 GiB; blob and receipt retained.',1;
    IF @ContentLength>1073741824
    BEGIN
        UPDATE dbo.TPImportReceipts SET ETag=@ETag,Phase='RejectedOversize',RetryableFailure=0,
            UpdatedUtc=SYSUTCDATETIME() WHERE ImportId=@id;
        THROW 51127,'ETL rejected: exceeds 1 GiB; blob and receipt retained.',1;
    END;
    EXEC dbo.tp_AssertDeletionProtocol;
    EXEC dbo.tp_AssertImporterStorage;
    IF @trace IS NULL
    BEGIN
        BEGIN TRAN;
        INSERT dbo.Traces(TraceName,TraceFile,TimeStampBegin,TimeStampEnd,TraceParserVersion)
          VALUES(@session,SUBSTRING(@BlobName,47,1024),GETUTCDATE(),GETUTCDATE(),'safe-import-v1');
        SET @trace=CONVERT(int,SCOPE_IDENTITY());
        UPDATE dbo.TPImportReceipts SET TraceId=@trace,ETag=@ETag,Phase='Parsing',UpdatedUtc=SYSUTCDATETIME()
          WHERE ImportId=@id;
        COMMIT;
    END;
    DECLARE @lock nvarchar(255)=CONCAT('TraceParser:Trace:',@trace);
    EXEC @rc=sys.sp_getapplock @Resource=@lock,@LockMode='Exclusive',@LockOwner='Session',@LockTimeout=0;
    IF @rc<0 THROW 51106,'Trace is busy; retry later.',1;
    EXEC dbo.tp_AssertImportOwner @id;
    UPDATE dbo.TPImportReceipts SET RetryableFailure=0,UpdatedUtc=SYSUTCDATETIME() WHERE ImportId=@id;
    SELECT ImportId,TraceId,Phase,LastPromotedId FROM dbo.TPImportReceipts WHERE ImportId=@id;
END;
GO
CREATE OR ALTER PROCEDURE dbo.tp_SetImportContentHash @ImportId uniqueidentifier,@ContentHash binary(32)
AS
BEGIN
    SET NOCOUNT ON;
    EXEC dbo.tp_AssertImportOwner @ImportId;
    IF EXISTS(SELECT 1 FROM dbo.TPImportReceipts WHERE ImportId=@ImportId
        AND (ParserVersion<>'safe-import-v1' OR (ContentHash IS NOT NULL AND ContentHash<>@ContentHash)))
        THROW 51107,'Import content or parser protocol differs from the durable receipt.',1;
    UPDATE dbo.TPImportReceipts SET ContentHash=@ContentHash,UpdatedUtc=SYSUTCDATETIME() WHERE ImportId=@ImportId;
END;
GO
-- Caller creates #ImportRows/#ImportBinds and bulk-copies into those connection-local tables.
-- Every replay is verified; allocated gaps are allowed, existing staged IDs never change.
CREATE OR ALTER PROCEDURE dbo.tp_StageImportBatch @ImportId uniqueidentifier
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    EXEC dbo.tp_AssertImportOwner @ImportId;
    IF NOT EXISTS(SELECT 1 FROM dbo.TPImportReceipts WHERE ImportId=@ImportId AND Phase='Parsing')
       THROW 51108,'Staging is frozen after Ready.',1;
    IF EXISTS(SELECT 1 FROM #ImportRows WHERE ImportId<>@ImportId OR Sequence IS NULL OR Sequence<=0)
       OR EXISTS(SELECT 1 FROM #ImportBinds WHERE ImportId<>@ImportId OR Sequence<=0 OR ParameterIndex<0)
       THROW 51109,'Malformed staged batch.',1;
    IF EXISTS(SELECT 1 FROM #ImportRows GROUP BY Sequence HAVING COUNT(*)<>1)
       OR EXISTS(SELECT 1 FROM #ImportBinds GROUP BY Sequence,ParameterIndex HAVING COUNT(*)<>1)
       THROW 51109,'Duplicate identity within staged batch.',1;
    BEGIN TRAN;
    IF EXISTS(SELECT 1 FROM #ImportRows i JOIN dbo.TPImportLines s
        ON s.ImportId=@ImportId AND s.Sequence=i.Sequence WHERE s.PayloadHash<>i.PayloadHash)
       OR EXISTS(SELECT 1 FROM #ImportBinds i JOIN dbo.TPImportBinds s
        ON s.ImportId=@ImportId AND s.Sequence=i.Sequence AND s.ParameterIndex=i.ParameterIndex
        WHERE s.PayloadHash<>i.PayloadHash)
    BEGIN
        ROLLBACK;
        THROW 51110,'Replay differs from durable staged data; retained for review.',1;
    END;
    INSERT dbo.TPImportLines SELECT i.* FROM #ImportRows i
       WHERE NOT EXISTS(SELECT 1 FROM dbo.TPImportLines s WHERE s.ImportId=@ImportId AND s.Sequence=i.Sequence);
    INSERT dbo.TPImportBinds SELECT i.* FROM #ImportBinds i
       WHERE NOT EXISTS(SELECT 1 FROM dbo.TPImportBinds s WHERE s.ImportId=@ImportId AND s.Sequence=i.Sequence
                        AND s.ParameterIndex=i.ParameterIndex);
    COMMIT;
END;
GO
-- Executed within the caller's dimension transaction, on the same owned connection.
CREATE OR ALTER PROCEDURE dbo.tp_MapImportThread @ImportId uniqueidentifier,@TempThreadId int,@ThreadId int
AS
BEGIN
    SET NOCOUNT ON;
    EXEC dbo.tp_AssertImportOwner @ImportId;
    IF @@TRANCOUNT=0 OR @TempThreadId>=0 OR NOT EXISTS
      (SELECT 1 FROM dbo.TPImportReceipts r JOIN dbo.UserSessionProcessThreads t ON t.TraceId=r.TraceId
       WHERE r.ImportId=@ImportId AND r.Phase='Parsing' AND t.UserSessionProcessThreadId=@ThreadId)
       THROW 51121,'Thread mapping requires an owned parsing transaction and matching trace.',1;
    INSERT dbo.TPImportThreads(ImportId,TempThreadId,ThreadId) VALUES(@ImportId,@TempThreadId,@ThreadId);
END;
GO
-- Executed within the caller's dimension transaction, on the same owned connection.
CREATE OR ALTER PROCEDURE dbo.tp_MarkImportReady
    @ImportId uniqueidentifier,@ExpectedRows bigint,@ExpectedBinds bigint
AS
BEGIN
    SET NOCOUNT ON;
    EXEC dbo.tp_AssertImportOwner @ImportId;
    IF @@TRANCOUNT=0 THROW 51111,'Ready requires the dimension transaction.',1;
    IF NOT EXISTS(SELECT 1 FROM dbo.TPImportReceipts WHERE ImportId=@ImportId AND Phase='Parsing' AND ContentHash IS NOT NULL)
       OR (SELECT COUNT_BIG(*) FROM dbo.TPImportLines WHERE ImportId=@ImportId)<>@ExpectedRows
       OR (SELECT COUNT_BIG(*) FROM dbo.TPImportBinds WHERE ImportId=@ImportId)<>@ExpectedBinds
       OR EXISTS(SELECT 1 FROM dbo.TPImportLines s LEFT JOIN dbo.TPImportThreads m
         ON m.ImportId=s.ImportId AND m.TempThreadId=s.UserSessionProcessThreadId
         WHERE s.ImportId=@ImportId AND m.ThreadId IS NULL)
       OR EXISTS(SELECT 1 FROM dbo.TPImportBinds b LEFT JOIN dbo.TPImportLines s
         ON s.ImportId=b.ImportId AND s.Sequence=b.Sequence AND s.CallTypeId=64
         WHERE b.ImportId=@ImportId AND s.TraceLineId IS NULL)
       OR EXISTS(SELECT 1 FROM dbo.UserSessions s JOIN dbo.UserSessions other
         ON other.SessionId=s.SessionId AND other.TraceId<>s.TraceId
         WHERE s.TraceId=(SELECT TraceId FROM dbo.TPImportReceipts WHERE ImportId=@ImportId))
       THROW 51112,'Incomplete or inconsistent parse cannot become Ready.',1;
    UPDATE dbo.TPImportReceipts SET Phase='Ready',ExpectedRows=@ExpectedRows,ExpectedBinds=@ExpectedBinds,
       UpdatedUtc=SYSUTCDATETIME() WHERE ImportId=@ImportId;
END;
GO
-- Bind fan-out has its own atomic bounded cursor: one SQL statement can have many
-- parameters, so a line-count bound alone cannot bound a promotion transaction.
CREATE OR ALTER PROCEDURE dbo.tp_PromoteImportBinds @ImportId uniqueidentifier,@BatchSize int=1000
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    EXEC dbo.tp_AssertImportOwner @ImportId;
    IF @BatchSize<1 OR @BatchSize>4000 THROW 51113,'Promotion batch must be 1..4000 rows.',1;
    DECLARE @seq int,@idx int,@trace int;
    SELECT @seq=LastBindSequence,@idx=LastBindIndex,@trace=TraceId FROM dbo.TPImportReceipts
      WHERE ImportId=@ImportId AND Phase='Binding';
    IF @trace IS NULL THROW 51114,'Import is not ready for bind promotion.',1;
    DECLARE @batch TABLE(Sequence int,ParameterIndex int,TraceLineId bigint,BindValue nvarchar(max),
        PRIMARY KEY(Sequence,ParameterIndex));
    INSERT @batch
      SELECT TOP(@BatchSize) b.Sequence,b.ParameterIndex,s.TraceLineId,b.BindValue
      FROM dbo.TPImportBinds b JOIN dbo.TPImportLines s ON s.ImportId=b.ImportId AND s.Sequence=b.Sequence
      WHERE b.ImportId=@ImportId AND (b.Sequence>@seq OR (b.Sequence=@seq AND b.ParameterIndex>@idx))
      ORDER BY b.Sequence,b.ParameterIndex;
    DECLARE @rows int=@@ROWCOUNT;
    IF @rows=0
    BEGIN
        UPDATE dbo.TPImportReceipts SET Phase='Finalizing',UpdatedUtc=SYSUTCDATETIME() WHERE ImportId=@ImportId;
        SELECT 0; RETURN;
    END;
    SELECT TOP(1) @seq=Sequence,@idx=ParameterIndex FROM @batch ORDER BY Sequence DESC,ParameterIndex DESC;
    BEGIN TRY
      BEGIN TRAN;
      IF EXISTS(SELECT 1 FROM @batch b WHERE NOT EXISTS
        (SELECT 1 FROM dbo.TraceLines l WITH(HOLDLOCK) JOIN dbo.UserSessionProcessThreads t
          ON t.UserSessionProcessThreadId=l.UserSessionProcessThreadId
          WHERE l.TraceLineId=b.TraceLineId AND t.TraceId=@trace AND l.CallTypeId=64))
          THROW 51125,'A staged bind has no matching promoted SQL line; retained for review.',1;
      INSERT dbo.QueryBindParameters(TraceLineId,ParameterIndex,BindValue)
          SELECT TraceLineId,ParameterIndex,BindValue FROM @batch;
      UPDATE dbo.TPImportReceipts SET LastBindSequence=@seq,LastBindIndex=@idx,UpdatedUtc=SYSUTCDATETIME()
          WHERE ImportId=@ImportId;
      COMMIT;
      SELECT @rows;
    END TRY
    BEGIN CATCH
      IF XACT_STATE()<>0 ROLLBACK;
      THROW;
    END CATCH;
END;
GO
-- IDENTITY_INSERT is not covered by ownership chaining. Confine its required
-- ALTER permission to this fixed module's dedicated, non-login execution user.
-- The Function receives neither ALTER nor IMPERSONATE on this user.
IF ISNULL(HAS_PERMS_BY_NAME(DB_NAME(),'DATABASE','VIEW DEFINITION'),0)<>1
    THROW 51126,'Migration requires complete database definition visibility to validate the promotion executor.',1;
IF DATABASE_PRINCIPAL_ID(N'TPImportPromotionExecutor') IS NULL
    CREATE USER TPImportPromotionExecutor WITHOUT LOGIN;
DECLARE @executor int=DATABASE_PRINCIPAL_ID(N'TPImportPromotionExecutor');
-- Permissions ON this USER belong to other grantees, not to the executor.
IF EXISTS(SELECT 1 FROM sys.database_permissions WHERE class=4 AND major_id=@executor)
    THROW 51126,'Promotion executor has unexpected inbound principal permissions; review required before granting authority.',1;
IF NOT EXISTS(SELECT 1 FROM sys.database_principals
      WHERE principal_id=@executor AND type='S' AND authentication_type=0)
   OR EXISTS(SELECT 1 FROM sys.database_role_members WHERE member_principal_id=@executor)
   OR EXISTS(SELECT 1 FROM sys.schemas WHERE principal_id=@executor)
   OR EXISTS(SELECT 1 FROM sys.objects WHERE principal_id=@executor)
   OR EXISTS(SELECT 1 FROM sys.database_principals WHERE owning_principal_id=@executor)
   OR EXISTS(SELECT 1 FROM sys.sql_modules WHERE execute_as_principal_id=@executor
        AND object_id<>ISNULL(OBJECT_ID(N'dbo.tp_PromoteImportBatch'),-1))
   OR EXISTS(SELECT 1 FROM sys.database_permissions WHERE grantee_principal_id=@executor
        AND NOT (class=1 AND major_id=OBJECT_ID(N'dbo.TraceLines') AND minor_id=0
                 AND permission_name='ALTER' AND state='G')
        AND NOT (class=0 AND permission_name='CONNECT' AND state='G'))
    THROW 51126,'Promotion executor has unexpected identity, ownership or permissions; review required.',1;
GRANT ALTER ON OBJECT::dbo.TraceLines TO TPImportPromotionExecutor;
GO
CREATE OR ALTER PROCEDURE dbo.tp_PromoteImportBatch @ImportId uniqueidentifier,@BatchSize int=1000
WITH EXECUTE AS 'TPImportPromotionExecutor'
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    EXEC dbo.tp_AssertImportOwner @ImportId;
    IF @BatchSize<1 OR @BatchSize>4000 THROW 51113,'Promotion batch must be 1..4000 rows.',1;
    DECLARE @last bigint,@end bigint,@phase varchar(24);
    SELECT @last=LastPromotedId,@phase=Phase FROM dbo.TPImportReceipts WHERE ImportId=@ImportId;
    IF @phase NOT IN ('Ready','Promoting','Binding','Finalizing') THROW 51114,'Import is not Ready.',1;
    IF @phase='Finalizing' BEGIN SELECT 0; RETURN; END;
    IF @phase='Binding'
    BEGIN
        EXEC dbo.tp_PromoteImportBinds @ImportId,@BatchSize;
        RETURN;
    END;
    SELECT @end=MAX(TraceLineId) FROM
      (SELECT TOP(@BatchSize) TraceLineId FROM dbo.TPImportLines
       WHERE ImportId=@ImportId AND TraceLineId>@last ORDER BY TraceLineId) b;
    IF @end IS NULL
    BEGIN
       UPDATE dbo.TPImportReceipts SET Phase='Binding',UpdatedUtc=SYSUTCDATETIME() WHERE ImportId=@ImportId;
       EXEC dbo.tp_PromoteImportBinds @ImportId,@BatchSize;
       RETURN;
    END;
    BEGIN TRY
      BEGIN TRAN;
      SET IDENTITY_INSERT dbo.TraceLines ON;
      INSERT dbo.TraceLines
        (TraceLineId,UserSessionProcessThreadId,CallTypeId,Sequence,SequenceEnd,[TimeStamp],TimeStampEnd,
         InclusiveDurationNano,ExclusiveDurationNano,DatabaseDurationNano,ParentSequence,InclusiveRpc,
         DatabaseCalls,QueryStatementHash,QueryTableHash,PrepDurationNano,BindDurationNano,RowFetchDurationNano,
         RowFetchCount,MethodHash,MessageHash,CallstackHash,HasChildren,IsComplete,IsRecursive,
         TransactionParentSequence,FileName,RoleRoleId,RoleInstanceRoleInstanceId,EventLevel,EventId,
         AzureTenantAzureTenantId,EventType,PropertiesXml,LineNumber,EventName)
      SELECT s.TraceLineId,m.ThreadId,s.CallTypeId,s.Sequence,s.SequenceEnd,s.[TimeStamp],s.TimeStampEnd,
         s.InclusiveDurationNano,s.ExclusiveDurationNano,s.DatabaseDurationNano,s.ParentSequence,s.InclusiveRpc,
         s.DatabaseCalls,s.QueryStatementHash,s.QueryTableHash,s.PrepDurationNano,s.BindDurationNano,s.RowFetchDurationNano,
         s.RowFetchCount,s.MethodHash,s.MessageHash,s.CallstackHash,s.HasChildren,s.IsComplete,s.IsRecursive,
         s.TransactionParentSequence,s.FileName,s.RoleRoleId,s.RoleInstanceRoleInstanceId,s.EventLevel,s.EventId,
         s.AzureTenantAzureTenantId,s.EventType,s.PropertiesXml,s.LineNumber,s.EventName
      FROM dbo.TPImportLines s JOIN dbo.TPImportThreads m
        ON m.ImportId=s.ImportId AND m.TempThreadId=s.UserSessionProcessThreadId
      WHERE s.ImportId=@ImportId AND s.TraceLineId>@last AND s.TraceLineId<=@end;
      DECLARE @rows int=@@ROWCOUNT;
      SET IDENTITY_INSERT dbo.TraceLines OFF;
      UPDATE dbo.TPImportReceipts SET LastPromotedId=@end,Phase='Promoting',UpdatedUtc=SYSUTCDATETIME()
        WHERE ImportId=@ImportId;
      COMMIT;
      SELECT @rows;
    END TRY
    BEGIN CATCH
      IF XACT_STATE()<>0 ROLLBACK;
      SET IDENTITY_INSERT dbo.TraceLines OFF;
      THROW;
    END CATCH;
END;
GO
CREATE OR ALTER PROCEDURE dbo.tp_CompleteImport @ImportId uniqueidentifier
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    EXEC dbo.tp_AssertImportOwner @ImportId;
    DECLARE @trace int,@rows bigint,@binds bigint;
    SELECT @trace=TraceId,@rows=ExpectedRows,@binds=ExpectedBinds FROM dbo.TPImportReceipts
       WHERE ImportId=@ImportId AND Phase='Finalizing';
    IF @trace IS NULL THROW 51115,'Import is not ready to finalize.',1;
    BEGIN TRY
      BEGIN TRAN;
    IF (SELECT COUNT_BIG(*) FROM dbo.TraceLines l JOIN dbo.UserSessionProcessThreads t
        ON t.UserSessionProcessThreadId=l.UserSessionProcessThreadId WHERE t.TraceId=@trace)<>@rows
       OR (SELECT COUNT_BIG(*) FROM dbo.QueryBindParameters b JOIN dbo.TraceLines l ON l.TraceLineId=b.TraceLineId
        JOIN dbo.UserSessionProcessThreads t ON t.UserSessionProcessThreadId=l.UserSessionProcessThreadId
        WHERE t.TraceId=@trace)<>@binds
       OR EXISTS(SELECT 1 FROM dbo.UserSessions s WITH(UPDLOCK,HOLDLOCK)
         JOIN dbo.UserSessions other WITH(UPDLOCK,HOLDLOCK) ON other.SessionId=s.SessionId AND other.TraceId<>s.TraceId
         WHERE s.TraceId=@trace)
       THROW 51116,'Promoted counts or global session identities differ; retained for review.',1;
      EXEC dbo.sp_PopulateSessionAggregations @TraceId=@trace;
      UPDATE dbo.TPImportReceipts SET Phase='Complete',RetryableFailure=0,UpdatedUtc=SYSUTCDATETIME()
         WHERE ImportId=@ImportId;
      COMMIT;
    END TRY
    BEGIN CATCH
      IF XACT_STATE()<>0 ROLLBACK;
      THROW;
    END CATCH;
END;
GO
CREATE OR ALTER PROCEDURE dbo.tp_CleanupCompletedImport @ImportId uniqueidentifier,@BatchSize int=1000
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF @BatchSize<1 OR @BatchSize>4000 THROW 51113,'Cleanup batch must be 1..4000 rows.',1;
    IF NOT EXISTS(SELECT 1 FROM dbo.TPImportReceipts WHERE ImportId=@ImportId AND Phase IN ('Complete','Deleted'))
       THROW 51117,'Only confirmed completed-import staging may be cleaned.',1;
    DELETE TOP(@BatchSize) FROM dbo.TPImportBinds WHERE ImportId=@ImportId;
    DECLARE @n int=@@ROWCOUNT;
    DELETE TOP(@BatchSize) FROM dbo.TPImportLines WHERE ImportId=@ImportId;
    SET @n+=@@ROWCOUNT;
    DELETE TOP(@BatchSize) FROM dbo.TPImportThreads WHERE ImportId=@ImportId;
    SELECT @n+@@ROWCOUNT;
END;
GO
CREATE OR ALTER PROCEDURE dbo.tp_RecordImportFailure @ImportId uniqueidentifier
AS
BEGIN
    SET NOCOUNT ON;
    EXEC dbo.tp_AssertImportOwner @ImportId;
    UPDATE dbo.TPImportReceipts SET RetryableFailure=1,UpdatedUtc=SYSUTCDATETIME()
      WHERE ImportId=@ImportId AND Phase NOT IN ('Complete','Deleted','RejectedOversize');
END;
GO
-- The only principal created by this script is the dedicated WITHOUT LOGIN
-- promotion executor above; only that user receives ALTER on dbo.TraceLines.
-- No application grants are applied automatically. Deployment must explicitly grant:
-- web principal: EXECUTE dbo.tp_RegisterUpload, dbo.tp_GetImportStatus only.
-- Function principal: EXECUTE only the caller procedures listed in README, SELECT dbo.TPImportLines
-- and dbo.TPImportBinds (empty connection-local staging prototypes only), plus its existing
-- narrow dimension permissions. No new durable-table mutation grants are required.
-- Do NOT grant table writes to web, broaden DAB, or grant db_owner/db_datawriter.
-- Never grant the Function ALTER/CONTROL/ownership, or IMPERSONATE on the executor.
-- Rollback: disable new registrations and quiesce the Function through the approved
-- operational process. Retain every TPImport* object and receipt; old importer binaries
-- are NOT safe rollback targets for queued protocol uploads. Never drop receipts.
