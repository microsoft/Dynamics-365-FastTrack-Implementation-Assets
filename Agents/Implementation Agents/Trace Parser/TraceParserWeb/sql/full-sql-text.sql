-- Optional upgrade: store full SQL statement text (issue #571).
-- Widens dbo.QueryStatements.Statement to nvarchar(max). The web importer detects the wider
-- column and stops truncating new statements at 4,000 characters. Rows imported earlier keep
-- their truncated text; re-import those traces to get the full text. Safe to run again. No GO.
SET NOCOUNT ON;
SET XACT_ABORT ON;
IF @@TRANCOUNT<>0 THROW 51300,'Run the full SQL text upgrade outside a transaction.',1;
IF OBJECT_ID('dbo.QueryStatements','U') IS NULL
    THROW 51300,'Install the Trace Parser schema first.',1;
IF COL_LENGTH('dbo.QueryStatements','Statement') IS NULL
    THROW 51300,'dbo.QueryStatements.Statement was not found.',1;
IF COL_LENGTH('dbo.QueryStatements','Statement')=-1
BEGIN
    PRINT 'dbo.QueryStatements.Statement already stores full text.';
    RETURN;
END;
DECLARE @col int=(SELECT column_id FROM sys.columns
    WHERE object_id=OBJECT_ID('dbo.QueryStatements') AND name='Statement');
IF NOT EXISTS(SELECT 1 FROM sys.columns WHERE object_id=OBJECT_ID('dbo.QueryStatements')
    AND column_id=@col AND TYPE_NAME(user_type_id)='nvarchar' AND is_computed=0)
    THROW 51300,'Unsupported dbo.QueryStatements.Statement column type.',1;
IF EXISTS(SELECT 1 FROM sys.index_columns WHERE object_id=OBJECT_ID('dbo.QueryStatements') AND column_id=@col)
    THROW 51300,'An index uses dbo.QueryStatements.Statement. Review it before widening the column.',1;
IF EXISTS(SELECT 1 FROM sys.stats_columns sc JOIN sys.stats s ON s.object_id=sc.object_id AND s.stats_id=sc.stats_id
    WHERE sc.object_id=OBJECT_ID('dbo.QueryStatements') AND sc.column_id=@col AND s.auto_created=0 AND s.user_created=1)
    THROW 51300,'User statistics use dbo.QueryStatements.Statement. Review them before widening the column.',1;
IF EXISTS(SELECT 1 FROM sys.sql_expression_dependencies d JOIN sys.sql_modules m ON m.object_id=d.referencing_id
    WHERE d.referenced_id=OBJECT_ID('dbo.QueryStatements') AND m.is_schema_bound=1)
    THROW 51300,'A schema-bound object references dbo.QueryStatements. Review it before widening the column.',1;
DECLARE @null nvarchar(8)=CASE WHEN (SELECT is_nullable FROM sys.columns
    WHERE object_id=OBJECT_ID('dbo.QueryStatements') AND column_id=@col)=1 THEN N'NULL' ELSE N'NOT NULL' END;
DECLARE @sql nvarchar(max);
BEGIN TRY
BEGIN TRAN;
    -- Auto-created statistics would block ALTER COLUMN; SQL Server recreates them on demand.
    SELECT @sql=STRING_AGG(CONVERT(nvarchar(max),N'DROP STATISTICS dbo.QueryStatements.'+QUOTENAME(s.name)),N';')
    FROM sys.stats s JOIN sys.stats_columns sc ON sc.object_id=s.object_id AND sc.stats_id=s.stats_id
    WHERE s.object_id=OBJECT_ID('dbo.QueryStatements') AND sc.column_id=@col AND s.auto_created=1;
    IF @sql IS NOT NULL EXEC sys.sp_executesql @sql;
    SET @sql=N'ALTER TABLE dbo.QueryStatements ALTER COLUMN Statement nvarchar(max) '+@null+N';';
    EXEC sys.sp_executesql @sql;
    IF COL_LENGTH('dbo.QueryStatements','Statement')<>-1
        THROW 51300,'dbo.QueryStatements.Statement was not widened.',1;
COMMIT;
PRINT 'dbo.QueryStatements.Statement now stores full text.';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT>0 ROLLBACK;
    THROW;
END CATCH;
