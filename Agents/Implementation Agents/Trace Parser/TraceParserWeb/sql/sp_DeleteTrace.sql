-- Standalone, single-batch migration for fresh AND existing databases.
-- Run as the deployment owner after reviewing the schema prerequisites in README.
-- No GO: a failed prerequisite must prevent CREATE OR ALTER in every client.
SET NOCOUNT ON;
SET XACT_ABORT ON;

IF @@TRANCOUNT <> 0
    THROW 51000, 'Install deletion outside an existing transaction.', 1;

DECLARE @required TABLE (TableName sysname, ColumnName sysname, TypeName sysname);
DECLARE @owner INT = (SELECT principal_id FROM sys.schemas WHERE name = 'dbo');
INSERT @required VALUES
    ('Traces', 'TraceId', 'int'),
    ('UserSessions', 'SessionId', 'int'), ('UserSessions', 'TraceId', 'int'),
    ('UserSessionProcessThreads', 'UserSessionProcessThreadId', 'int'),
    ('UserSessionProcessThreads', 'SessionId', 'int'), ('UserSessionProcessThreads', 'TraceId', 'int'),
    ('TraceLines', 'TraceLineId', 'bigint'), ('TraceLines', 'UserSessionProcessThreadId', 'int'),
    ('QueryBindParameters', 'TraceLineId', 'bigint'),
    ('XppParameters', 'TraceLineId', 'bigint'),
    ('TopMethods', 'Id', 'int'), ('TopMethods', 'BeginUspId', 'int'), ('TopMethods', 'EndUspId', 'int'),
    ('StageTraceLines', 'UserSessionProcessThreadId', 'int'),
    ('SessionMetrics', 'TraceId', 'int'), ('TopMethodsBySession', 'TraceId', 'int'),
    ('MethodAotLayers', 'TraceId', 'int'), ('TraceInformations', 'TraceId', 'int');

IF EXISTS (
    SELECT 1 FROM @required r
    LEFT JOIN sys.tables t ON t.name = r.TableName AND t.schema_id = SCHEMA_ID('dbo')
    LEFT JOIN sys.columns c ON c.object_id = t.object_id AND c.name = r.ColumnName
    WHERE t.object_id IS NULL OR c.column_id IS NULL OR TYPE_NAME(c.user_type_id) <> r.TypeName
        OR c.is_computed = 1 OR t.temporal_type <> 0 OR t.is_memory_optimized = 1
        OR t.is_filetable = 1 OR t.is_remote_data_archive_enabled = 1
        OR t.is_node = 1 OR t.is_edge = 1 OR t.ledger_type <> 0
        OR COALESCE(t.principal_id, @owner) <> @owner)
    THROW 51001, 'Unsupported deletion schema: required dbo physical tables/columns/types/ownership differ. No procedure changed.', 1;

IF EXISTS (
    SELECT 1 FROM sys.triggers tr JOIN sys.tables t ON t.object_id = tr.parent_id
    WHERE t.schema_id = SCHEMA_ID('dbo') AND t.name IN (SELECT TableName FROM @required)
        AND tr.is_disabled = 0)
    THROW 51002, 'Review enabled triggers before installing bounded deletion. No procedure changed.', 1;

-- Match each entire FK, not individual columns from different allowed edges.
-- The only supported composite is threads -> sessions (SessionId, TraceId).
DECLARE @edges TABLE (EdgeId int, Ordinal int, Child sysname, ChildColumn sysname, Parent sysname, ParentColumn sysname);
INSERT @edges VALUES
    (1, 1, 'QueryBindParameters', 'TraceLineId', 'TraceLines', 'TraceLineId'),
    (2, 1, 'XppParameters', 'TraceLineId', 'TraceLines', 'TraceLineId'),
    (3, 1, 'TraceLines', 'UserSessionProcessThreadId', 'UserSessionProcessThreads', 'UserSessionProcessThreadId'),
    (4, 1, 'StageTraceLines', 'UserSessionProcessThreadId', 'UserSessionProcessThreads', 'UserSessionProcessThreadId'),
    (5, 1, 'TopMethods', 'BeginUspId', 'UserSessionProcessThreads', 'UserSessionProcessThreadId'),
    (6, 1, 'TopMethods', 'EndUspId', 'UserSessionProcessThreads', 'UserSessionProcessThreadId'),
    (7, 1, 'UserSessionProcessThreads', 'SessionId', 'UserSessions', 'SessionId'),
    (7, 2, 'UserSessionProcessThreads', 'TraceId', 'UserSessions', 'TraceId'),
    (8, 1, 'UserSessionProcessThreads', 'TraceId', 'Traces', 'TraceId'),
    (9, 1, 'UserSessions', 'TraceId', 'Traces', 'TraceId'),
    (10, 1, 'SessionMetrics', 'TraceId', 'Traces', 'TraceId'),
    (11, 1, 'TopMethodsBySession', 'TraceId', 'Traces', 'TraceId'),
    (12, 1, 'MethodAotLayers', 'TraceId', 'Traces', 'TraceId'),
    (13, 1, 'TraceInformations', 'TraceId', 'Traces', 'TraceId');
IF EXISTS (
    SELECT 1
    FROM sys.foreign_keys fk
    JOIN sys.tables p ON p.object_id = fk.referenced_object_id
    JOIN sys.tables c ON c.object_id = fk.parent_object_id
    WHERE p.schema_id = SCHEMA_ID('dbo') AND p.name IN (SELECT TableName FROM @required)
      AND (fk.delete_referential_action <> 0 OR c.schema_id <> SCHEMA_ID('dbo')
        OR NOT EXISTS (
            SELECT 1 FROM @edges e WHERE e.Ordinal = 1 AND e.Child = c.name AND e.Parent = p.name
                AND (SELECT COUNT(*) FROM sys.foreign_key_columns fc WHERE fc.constraint_object_id = fk.object_id)
                    = (SELECT COUNT(*) FROM @edges expected WHERE expected.EdgeId = e.EdgeId)
                AND NOT EXISTS (
                    SELECT 1 FROM sys.foreign_key_columns fc
                    WHERE fc.constraint_object_id = fk.object_id
                        AND NOT EXISTS (SELECT 1 FROM @edges expected WHERE expected.EdgeId = e.EdgeId
                            AND expected.Ordinal = fc.constraint_column_id
                            AND expected.ChildColumn = COL_NAME(c.object_id, fc.parent_column_id)
                            AND expected.ParentColumn = COL_NAME(p.object_id, fc.referenced_column_id))))))
    THROW 51003, 'Unsupported deletion foreign key graph. No procedure changed.', 1;

IF EXISTS (SELECT 1 FROM sys.objects WHERE object_id = OBJECT_ID('dbo.sp_DeleteTrace')
    AND (type <> 'P' OR COALESCE(principal_id, @owner) <> @owner))
    THROW 51004, 'Unsupported deletion procedure ownership or object type.', 1;

DECLARE @keys TABLE (TableName sysname, ColumnName sysname, Ordinal int);
INSERT @keys VALUES ('Traces', 'TraceId', 1), ('TraceLines', 'TraceLineId', 1),
    ('UserSessionProcessThreads', 'UserSessionProcessThreadId', 1),
    ('UserSessions', 'SessionId', 1), ('UserSessions', 'TraceId', 2), ('TopMethods', 'Id', 1);
IF EXISTS (
    SELECT 1 FROM @keys r WHERE r.Ordinal = 1 AND
    NOT EXISTS (
        SELECT 1 FROM sys.indexes i
        WHERE i.object_id = OBJECT_ID('dbo.' + r.TableName) AND i.is_unique = 1
            AND i.has_filter = 0 AND i.is_disabled = 0
            AND (SELECT COUNT(*) FROM sys.index_columns ic WHERE ic.object_id = i.object_id
                AND ic.index_id = i.index_id AND ic.key_ordinal > 0)
                = (SELECT COUNT(*) FROM @keys expected WHERE expected.TableName = r.TableName)
            AND NOT EXISTS (
                SELECT 1 FROM @keys expected WHERE expected.TableName = r.TableName
                    AND NOT EXISTS (
                        SELECT 1 FROM sys.index_columns ic WHERE ic.object_id = i.object_id AND ic.index_id = i.index_id
                            AND ic.key_ordinal = expected.Ordinal
                            AND COL_NAME(i.object_id, ic.column_id) = expected.ColumnName))))
    THROW 51005, 'Required unique deletion keys are unavailable. No procedure changed.', 1;

-- Batch selection must seek target threads, then their lines, rather than scan
-- unrelated traces. Do not depend on index names or repair indexes in this migration.
IF EXISTS (
    SELECT 1 FROM (VALUES
        ('UserSessionProcessThreads', 'TraceId'),
        ('TraceLines', 'UserSessionProcessThreadId')) r(TableName, ColumnName)
    WHERE NOT EXISTS (
        SELECT 1 FROM sys.indexes i
        JOIN sys.index_columns ic ON ic.object_id = i.object_id AND ic.index_id = i.index_id
        WHERE i.object_id = OBJECT_ID('dbo.' + r.TableName)
            AND i.type IN (1, 2) AND i.is_disabled = 0 AND i.is_hypothetical = 0
            AND i.has_filter = 0 AND ic.key_ordinal = 1
            AND COL_NAME(i.object_id, ic.column_id) = r.ColumnName))
    THROW 51007, 'Required thread-leading deletion seek indexes are unavailable. No procedure changed.', 1;

-- Install-time selection preserves standalone legacy deletion without hiding receipt
-- tables behind caller-sensitive OBJECT_ID checks in the restricted runtime module.
DECLARE @coordinated bit = CASE WHEN OBJECT_ID('dbo.TPImportReceipts', 'U') IS NULL THEN 0 ELSE 1 END;
IF @coordinated = 1 AND (
    ISNULL(COL_LENGTH('dbo.TPImportReceipts', 'TraceId'),-1) <> 4
    OR ISNULL(COL_LENGTH('dbo.TPImportReceipts', 'Phase'),-1) <> 24
    OR COL_LENGTH('dbo.TPImportReceipts', 'UpdatedUtc') IS NULL
    OR COALESCE((SELECT principal_id FROM sys.objects WHERE object_id=OBJECT_ID('dbo.TPImportReceipts')), @owner) <> @owner)
    THROW 51006, 'Unsupported import receipt schema/ownership. No procedure changed.', 1;
DECLARE @receiptGuard nvarchar(max) = CASE WHEN @coordinated=1 THEN N'
        -- The trace application lock protects eligibility, including absent receipts.
        -- Do not retain receipt range/key locks while waiting for trace data:
        -- promotion, binding and completion all write data before their receipt.
        DECLARE @receiptId uniqueidentifier, @receiptPhase varchar(24);
        SELECT @receiptId=ImportId,@receiptPhase=Phase
            FROM dbo.TPImportReceipts WITH (READCOMMITTEDLOCK) WHERE TraceId=@TraceId;
        IF @receiptPhase NOT IN (''Complete'',''Deleted'')
            THROW 51131, ''Import is active or awaiting retry. Deletion is blocked until durable completion.'', 1;
' ELSE N'' END;
DECLARE @receiptFinish nvarchar(max) = CASE WHEN @coordinated=1 THEN N'
        -- Tombstone commits with the first successful deletion batch, never before it.
        -- Seek the captured receipt only after data writes. Legacy/Deleted traces
        -- need no receipt write or missing-key range lock.
        IF @receiptPhase=''Complete''
        UPDATE dbo.TPImportReceipts SET Phase=''Deleted'',UpdatedUtc=SYSUTCDATETIME()
            WHERE ImportId=@receiptId AND Phase=''Complete'';
' ELSE N'' END;

DECLARE @durable bit=CASE WHEN OBJECT_ID('dbo.TraceDeletionJobs','U') IS NULL THEN 0 ELSE 1 END;
IF @durable=1 AND (@coordinated=0 OR COL_LENGTH('dbo.Traces','DeletionIdentity') IS NULL)
    THROW 51200,'Install the supported durable deletion schema first.',1;
DECLARE @jobGuard nvarchar(max)=CASE WHEN @durable=1 THEN N'
        IF @JobId IS NULL
        BEGIN
            IF EXISTS(SELECT 1 FROM dbo.TraceDeletionJobs WHERE TraceId=@TraceId AND IsActive=1)
                THROW 51206,''Use the existing durable job; direct deletion is blocked.'',1;
        END
        ELSE
        BEGIN
            DECLARE @sequence bigint,@state varchar(20),@identity uniqueidentifier,@jobImport uniqueidentifier;
            -- Ownership is retained until commit. Expired takeover cannot pass this row lock.
            SELECT @sequence=Sequence,@state=State,@identity=TraceIdentity,@jobImport=ImportId
            FROM dbo.TraceDeletionJobs WITH(UPDLOCK,HOLDLOCK)
            WHERE JobId=@JobId AND TraceId=@TraceId AND LeaseToken=@LeaseToken
                AND LeaseExpiresUtc>SYSUTCDATETIME() AND State IN(''Running'',''CancelRequested'');
            IF @sequence IS NULL THROW 51205,''Deletion lease/binding is no longer owned.'',1;
            IF @ExpectedSequence IS NULL OR @ExpectedSequence>@sequence OR @ExpectedSequence<@sequence-1
                THROW 51207,''Unexpected deletion sequence; reconcile persisted progress.'',1;
            IF @ExpectedSequence=@sequence-1
            BEGIN
                SELECT @HasMore=LastHasMore,@Phase=LastPhase,@RowsDeleted=LastRows
                    FROM dbo.TraceDeletionJobs WHERE JobId=@JobId;
                COMMIT;
                SELECT @HasMore AS HasMore,@Phase AS Phase,@RowsDeleted AS RowsDeleted;
                RETURN;
            END;
            IF @state=''CancelRequested''
            BEGIN
                UPDATE dbo.TraceDeletionJobs SET State=''Cancelled'',LeaseToken=NULL,LeaseOwner=NULL,
                    LeaseExpiresUtc=NULL,UpdatedUtc=SYSUTCDATETIME() WHERE JobId=@JobId;
                COMMIT;
                SELECT 1 AS HasMore,N''Cancelled'' AS Phase,0 AS RowsDeleted;
                RETURN;
            END;
            IF EXISTS(SELECT 1 FROM dbo.Traces WHERE TraceId=@TraceId AND DeletionIdentity<>@identity)
                OR ISNULL(@jobImport,CONVERT(uniqueidentifier,0x0))<>ISNULL(@receiptId,CONVERT(uniqueidentifier,0x0))
                THROW 51208,''Trace/import identity changed. Owner review required.'',1;
        END;
' ELSE N'
        IF @JobId IS NOT NULL OR @LeaseToken IS NOT NULL OR @ExpectedSequence IS NOT NULL
            THROW 51202,''Durable deletion is not installed.'',1;
' END;
DECLARE @jobFinish nvarchar(max)=CASE WHEN @durable=1 THEN N'
        IF @JobId IS NOT NULL
        BEGIN
            -- Actual successful root query, under module ownership, is the sole completion authority.
            DECLARE @complete bit=CASE WHEN EXISTS(SELECT 1 FROM dbo.Traces WHERE TraceId=@TraceId) THEN 0 ELSE 1 END;
            UPDATE dbo.TraceDeletionJobs SET Sequence=Sequence+1,CommittedRows=CommittedRows+@RowsDeleted,
                LastRows=@RowsDeleted,LastPhase=@Phase,LastHasMore=CASE WHEN @complete=1 THEN 0 ELSE 1 END,
                State=CASE WHEN @complete=1 THEN ''Completed'' ELSE ''Running'' END,
                IsActive=CASE WHEN @complete=1 THEN 0 ELSE 1 END,
                LeaseToken=CASE WHEN @complete=1 THEN NULL ELSE LeaseToken END,
                LeaseOwner=CASE WHEN @complete=1 THEN NULL ELSE LeaseOwner END,
                LeaseExpiresUtc=CASE WHEN @complete=1 THEN NULL ELSE LeaseExpiresUtc END,
                Attempts=0,ErrorCode=NULL,ErrorMessage=NULL,UpdatedUtc=SYSUTCDATETIME()
            WHERE JobId=@JobId;
        END;
' ELSE N'' END;

BEGIN TRY
BEGIN TRANSACTION;
EXEC(N'CREATE OR ALTER PROCEDURE dbo.sp_DeleteTrace
    @TraceId INT,
    @BatchSize INT = 2000,
    @JobId uniqueidentifier = NULL,
    @LeaseToken uniqueidentifier = NULL,
    @ExpectedSequence bigint = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF @TraceId IS NULL OR @TraceId <= 0
        THROW 51010, ''TraceId must be positive.'', 1;
    IF @BatchSize IS NULL OR @BatchSize < 1 OR @BatchSize > 10000
        THROW 51011, ''BatchSize must be between 1 and 10000.'', 1;
    IF @@TRANCOUNT <> 0
        THROW 51012, ''Call deletion outside an existing transaction.'', 1;

    DECLARE @RowsDeleted INT = 0, @Phase nvarchar(40) = N''Complete'', @HasMore INT = 0;
    BEGIN TRY
        BEGIN TRANSACTION;
        -- Importer: global importer session lock -> trace session lock -> data locks.
        -- Deleter: trace transaction lock -> eligibility read -> data -> receipt. Never acquire
        -- the global importer lock here, so unrelated completed traces remain deletable.
        DECLARE @lockResult int, @traceLock nvarchar(255)=CONCAT(''TraceParser:Trace:'',@TraceId);
        EXEC @lockResult=sys.sp_getapplock @Resource=@traceLock,@LockMode=''Exclusive'',
            @LockOwner=''Transaction'',@LockTimeout=0;
        IF @lockResult<0
            THROW 51130, ''Trace is busy with an import or another deletion batch. Retry later.'', 1;
' + @receiptGuard + @jobGuard + N'
        -- Serialize same-trace callers for this one batch, never the whole deletion.
        IF NOT EXISTS (SELECT 1 FROM dbo.Traces WITH (UPDLOCK, HOLDLOCK) WHERE TraceId = @TraceId)
            GOTO Finished;
        SET @HasMore = 1;

        -- A method can reference this trace at either endpoint. Never infer ownership
        -- from BeginUspId alone: a cross-trace/missing endpoint requires owner review.
        DECLARE @methods TABLE (Id int PRIMARY KEY, BeginTraceId int NULL, EndTraceId int NULL);
        INSERT @methods (Id, BeginTraceId, EndTraceId)
        SELECT TOP (@BatchSize) tm.Id, b.TraceId, e.TraceId
        FROM dbo.TopMethods tm
        LEFT JOIN dbo.UserSessionProcessThreads b ON b.UserSessionProcessThreadId = tm.BeginUspId
        LEFT JOIN dbo.UserSessionProcessThreads e ON e.UserSessionProcessThreadId = tm.EndUspId
        WHERE b.TraceId = @TraceId OR e.TraceId = @TraceId;
        IF EXISTS (SELECT 1 FROM @methods WHERE BeginTraceId IS NULL OR EndTraceId IS NULL
            OR BeginTraceId <> @TraceId OR EndTraceId <> @TraceId)
            THROW 51013, ''TopMethods has cross-trace or missing thread endpoints. No rows from this batch were deleted. Earlier batches may be committed; owner review is required.'', 1;
        IF EXISTS (SELECT 1 FROM @methods)
        BEGIN
            SET @Phase = N''TopMethods'';
            DELETE tm FROM dbo.TopMethods tm JOIN @methods m ON m.Id = tm.Id;
            SET @RowsDeleted = @@ROWCOUNT;
            GOTO Finished;
        END;

        DECLARE @batch TABLE (Id BIGINT PRIMARY KEY);
        -- Keep work proportional to the target threads and the batch, even
        -- after partial deletion or when unrelated traces dominate the table.
        INSERT @batch (Id)
        SELECT TOP (@BatchSize) tl.TraceLineId
        FROM dbo.UserSessionProcessThreads u WITH (FORCESEEK)
        INNER LOOP JOIN dbo.TraceLines tl WITH (FORCESEEK)
            ON tl.UserSessionProcessThreadId = u.UserSessionProcessThreadId
        WHERE u.TraceId = @TraceId
        OPTION (FORCE ORDER);

        IF EXISTS (SELECT 1 FROM @batch)
        BEGIN
            -- Fan-out is independently bounded: a single line can have many parameters.
            SET @Phase = N''QueryBindParameters'';
            DELETE TOP (@BatchSize) q FROM dbo.QueryBindParameters q JOIN @batch b ON b.Id = q.TraceLineId;
            SET @RowsDeleted = @@ROWCOUNT;
            IF @RowsDeleted > 0 GOTO Finished;

            SET @Phase = N''XppParameters'';
            DELETE TOP (@BatchSize) x FROM dbo.XppParameters x JOIN @batch b ON b.Id = x.TraceLineId;
            SET @RowsDeleted = @@ROWCOUNT;
            IF @RowsDeleted > 0 GOTO Finished;

            SET @Phase = N''TraceLines'';
            DELETE tl FROM dbo.TraceLines tl JOIN @batch b ON b.Id = tl.TraceLineId;
            SET @RowsDeleted = @@ROWCOUNT;
            GOTO Finished;
        END;

        SET @Phase = N''StageTraceLines'';
        DELETE TOP (@BatchSize) stl FROM dbo.StageTraceLines stl
        JOIN dbo.UserSessionProcessThreads u ON stl.UserSessionProcessThreadId = u.UserSessionProcessThreadId
        WHERE u.TraceId = @TraceId;
        SET @RowsDeleted = @@ROWCOUNT;
        IF @RowsDeleted > 0 GOTO Finished;

        SET @Phase = N''SessionMetrics'';
        DELETE TOP (@BatchSize) FROM dbo.SessionMetrics WHERE TraceId = @TraceId;
        SET @RowsDeleted = @@ROWCOUNT;
        IF @RowsDeleted > 0 GOTO Finished;

        SET @Phase = N''TopMethodsBySession'';
        DELETE TOP (@BatchSize) FROM dbo.TopMethodsBySession WHERE TraceId = @TraceId;
        SET @RowsDeleted = @@ROWCOUNT;
        IF @RowsDeleted > 0 GOTO Finished;

        SET @Phase = N''UserSessionProcessThreads'';
        DELETE TOP (@BatchSize) FROM dbo.UserSessionProcessThreads WHERE TraceId = @TraceId;
        SET @RowsDeleted = @@ROWCOUNT;
        IF @RowsDeleted > 0 GOTO Finished;

        SET @Phase = N''UserSessions'';
        DELETE TOP (@BatchSize) FROM dbo.UserSessions WHERE TraceId = @TraceId;
        SET @RowsDeleted = @@ROWCOUNT;
        IF @RowsDeleted > 0 GOTO Finished;

        SET @Phase = N''MethodAotLayers'';
        DELETE TOP (@BatchSize) FROM dbo.MethodAotLayers WHERE TraceId = @TraceId;
        SET @RowsDeleted = @@ROWCOUNT;
        IF @RowsDeleted > 0 GOTO Finished;

        SET @Phase = N''TraceInformations'';
        DELETE TOP (@BatchSize) FROM dbo.TraceInformations WHERE TraceId = @TraceId;
        SET @RowsDeleted = @@ROWCOUNT;
        IF @RowsDeleted > 0 GOTO Finished;

        SET @Phase = N''Traces'';
        DELETE FROM dbo.Traces WHERE TraceId = @TraceId;
        SET @RowsDeleted = @@ROWCOUNT;
        SET @HasMore = 0;

Finished:
' + @receiptFinish + @jobFinish + N'
        COMMIT TRANSACTION;
        SELECT @HasMore AS HasMore, @Phase AS Phase, @RowsDeleted AS RowsDeleted;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;');

-- A definition fingerprint makes activation fail closed if an older/noncoordinated
-- procedure is restored. CREATE OR ALTER alone preserves extended properties.
DECLARE @definitionHash varbinary(32) = CASE WHEN @coordinated=1
    THEN HASHBYTES('SHA2_256',OBJECT_DEFINITION(OBJECT_ID('dbo.sp_DeleteTrace'))) ELSE 0x END;
IF EXISTS (SELECT 1 FROM sys.extended_properties WHERE class=1
    AND major_id=OBJECT_ID('dbo.sp_DeleteTrace') AND name=N'TraceParserImporterDeletionHash')
    EXEC sys.sp_updateextendedproperty @name=N'TraceParserImporterDeletionHash',@value=@definitionHash,
        @level0type=N'SCHEMA',@level0name=N'dbo',@level1type=N'PROCEDURE',@level1name=N'sp_DeleteTrace';
ELSE
    EXEC sys.sp_addextendedproperty @name=N'TraceParserImporterDeletionHash',@value=@definitionHash,
        @level0type=N'SCHEMA',@level0name=N'dbo',@level1type=N'PROCEDURE',@level1name=N'sp_DeleteTrace';
IF @durable=1
BEGIN
    IF EXISTS(SELECT 1 FROM sys.extended_properties WHERE major_id=OBJECT_ID('dbo.sp_DeleteTrace')
        AND name=N'TraceParserDurableDeletionHash')
        EXEC sys.sp_updateextendedproperty @name=N'TraceParserDurableDeletionHash',@value=@definitionHash,
            @level0type=N'SCHEMA',@level0name=N'dbo',@level1type=N'PROCEDURE',@level1name=N'sp_DeleteTrace';
    ELSE
        EXEC sys.sp_addextendedproperty @name=N'TraceParserDurableDeletionHash',@value=@definitionHash,
            @level0type=N'SCHEMA',@level0name=N'dbo',@level1type=N'PROCEDURE',@level1name=N'sp_DeleteTrace';
END;
COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
