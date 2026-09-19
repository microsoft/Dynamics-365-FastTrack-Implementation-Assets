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
    ('TopMethods', 'BeginUspId', 'int'),
    ('StageTraceLines', 'UserSessionProcessThreadId', 'int'),
    ('SessionMetrics', 'TraceId', 'int'), ('TopMethodsBySession', 'TraceId', 'int');

IF EXISTS (
    SELECT 1 FROM @required r
    LEFT JOIN sys.tables t ON t.name = r.TableName AND t.schema_id = SCHEMA_ID('dbo')
    LEFT JOIN sys.columns c ON c.object_id = t.object_id AND c.name = r.ColumnName
    WHERE t.object_id IS NULL OR c.column_id IS NULL OR TYPE_NAME(c.user_type_id) <> r.TypeName
        OR c.is_computed = 1 OR t.temporal_type <> 0 OR t.is_memory_optimized = 1
        OR COALESCE(t.principal_id, @owner) <> @owner)
    THROW 51001, 'Unsupported deletion schema: required dbo physical tables/columns/types/ownership differ. No procedure changed.', 1;

IF EXISTS (
    SELECT 1 FROM sys.triggers tr JOIN sys.tables t ON t.object_id = tr.parent_id
    WHERE t.schema_id = SCHEMA_ID('dbo') AND t.name IN (SELECT TableName FROM @required)
        AND tr.is_disabled = 0)
    THROW 51002, 'Review enabled triggers before installing bounded deletion. No procedure changed.', 1;

-- Reject unknown inbound edges (including disabled FKs), cascading actions and
-- composite keys. They could violate ordering, trace isolation or row bounds.
DECLARE @edges TABLE (Child sysname, ChildColumn sysname, Parent sysname, ParentColumn sysname);
INSERT @edges VALUES
    ('QueryBindParameters', 'TraceLineId', 'TraceLines', 'TraceLineId'),
    ('XppParameters', 'TraceLineId', 'TraceLines', 'TraceLineId'),
    ('TraceLines', 'UserSessionProcessThreadId', 'UserSessionProcessThreads', 'UserSessionProcessThreadId'),
    ('StageTraceLines', 'UserSessionProcessThreadId', 'UserSessionProcessThreads', 'UserSessionProcessThreadId'),
    ('TopMethods', 'BeginUspId', 'UserSessionProcessThreads', 'UserSessionProcessThreadId'),
    ('UserSessionProcessThreads', 'SessionId', 'UserSessions', 'SessionId'),
    ('UserSessionProcessThreads', 'TraceId', 'Traces', 'TraceId'),
    ('UserSessions', 'TraceId', 'Traces', 'TraceId'),
    ('SessionMetrics', 'TraceId', 'Traces', 'TraceId'),
    ('TopMethodsBySession', 'TraceId', 'Traces', 'TraceId'),
    ('SessionMetrics', 'SessionId', 'UserSessions', 'SessionId'),
    ('TopMethodsBySession', 'SessionId', 'UserSessions', 'SessionId');
IF EXISTS (
    SELECT 1
    FROM sys.foreign_keys fk
    JOIN sys.tables p ON p.object_id = fk.referenced_object_id
    JOIN sys.tables c ON c.object_id = fk.parent_object_id
    JOIN sys.foreign_key_columns fc ON fc.constraint_object_id = fk.object_id
    WHERE p.schema_id = SCHEMA_ID('dbo') AND p.name IN (SELECT TableName FROM @required)
      AND (fk.delete_referential_action <> 0 OR fc.constraint_column_id <> 1
        OR c.schema_id <> SCHEMA_ID('dbo')
        OR NOT EXISTS (SELECT 1 FROM @edges e WHERE e.Child = c.name AND e.Parent = p.name
            AND e.ChildColumn = COL_NAME(c.object_id, fc.parent_column_id)
            AND e.ParentColumn = COL_NAME(p.object_id, fc.referenced_column_id))))
    THROW 51003, 'Unsupported deletion foreign key graph. No procedure changed.', 1;

IF EXISTS (SELECT 1 FROM sys.objects WHERE object_id = OBJECT_ID('dbo.sp_DeleteTrace')
    AND (type <> 'P' OR COALESCE(principal_id, @owner) <> @owner))
    THROW 51004, 'Unsupported deletion procedure ownership or object type.', 1;

IF EXISTS (
    SELECT 1 FROM (VALUES ('Traces', 'TraceId'), ('TraceLines', 'TraceLineId'),
        ('UserSessionProcessThreads', 'UserSessionProcessThreadId'), ('UserSessions', 'SessionId')) r(TableName, ColumnName)
    WHERE NOT EXISTS (
        SELECT 1 FROM sys.indexes i
        JOIN sys.index_columns ic ON ic.object_id = i.object_id AND ic.index_id = i.index_id AND ic.key_ordinal = 1
        WHERE i.object_id = OBJECT_ID('dbo.' + r.TableName) AND i.is_unique = 1
            AND i.has_filter = 0 AND i.is_disabled = 0
            AND COL_NAME(i.object_id, ic.column_id) = r.ColumnName
            AND NOT EXISTS (SELECT 1 FROM sys.index_columns extra WHERE extra.object_id = i.object_id
                AND extra.index_id = i.index_id AND extra.key_ordinal > 1)))
    THROW 51005, 'Required unique deletion keys are unavailable. No procedure changed.', 1;

EXEC(N'CREATE OR ALTER PROCEDURE dbo.sp_DeleteTrace
    @TraceId INT,
    @BatchSize INT = 2000
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
        -- Serialize same-trace callers for this one batch, never the whole deletion.
        IF NOT EXISTS (SELECT 1 FROM dbo.Traces WITH (UPDLOCK, HOLDLOCK) WHERE TraceId = @TraceId)
        BEGIN
            COMMIT TRANSACTION;
            SELECT @HasMore AS HasMore, @Phase AS Phase, @RowsDeleted AS RowsDeleted;
            RETURN;
        END;
        SET @HasMore = 1;

        DECLARE @batch TABLE (Id BIGINT PRIMARY KEY);
        INSERT @batch (Id)
        SELECT TOP (@BatchSize) tl.TraceLineId
        FROM dbo.TraceLines tl
        JOIN dbo.UserSessionProcessThreads u ON u.UserSessionProcessThreadId = tl.UserSessionProcessThreadId
        WHERE u.TraceId = @TraceId;

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

        SET @Phase = N''TopMethods'';
        DELETE TOP (@BatchSize) tm FROM dbo.TopMethods tm
        JOIN dbo.UserSessionProcessThreads u ON tm.BeginUspId = u.UserSessionProcessThreadId
        WHERE u.TraceId = @TraceId;
        SET @RowsDeleted = @@ROWCOUNT;
        IF @RowsDeleted > 0 GOTO Finished;

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

        SET @Phase = N''Traces'';
        DELETE FROM dbo.Traces WHERE TraceId = @TraceId;
        SET @RowsDeleted = @@ROWCOUNT;
        SET @HasMore = 0;

Finished:
        COMMIT TRANSACTION;
        SELECT @HasMore AS HasMore, @Phase AS Phase, @RowsDeleted AS RowsDeleted;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;');
