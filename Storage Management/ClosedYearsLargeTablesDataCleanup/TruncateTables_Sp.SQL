IF OBJECT_ID('dbo.TruncateTables', 'P') IS NOT NULL
    DROP PROCEDURE dbo.TruncateTables;
GO
CREATE PROCEDURE dbo.TruncateTables
    @TableGroups NVARCHAR(MAX),
    @TableNames NVARCHAR(MAX),
    @SimulationMode BIT = 1
AS
BEGIN
    DECLARE @TableName NVARCHAR(255)
    DECLARE @SQL NVARCHAR(MAX)
    DECLARE @ErrorMessage NVARCHAR(4000)
    DECLARE @CDCState BIT

    -- Cursor to loop through the table names
    DECLARE TableCursor CURSOR FOR
    SELECT SQLNAME
    FROM SQLDICTIONARY a
    JOIN TABLEMETADATATABLE b ON a.TABLEID = b.TABLEID
    WHERE a.fieldid = 0 AND a.array = 0 
      AND (b.TABLEGROUP IN (SELECT value FROM STRING_SPLIT(@TableGroups, ',')) 
           OR a.NAME IN (SELECT value FROM STRING_SPLIT(@TableNames, ',')))

    OPEN TableCursor
    FETCH NEXT FROM TableCursor INTO @TableName
    WHILE @@FETCH_STATUS = 0
    BEGIN
        IF @SimulationMode = 1
        BEGIN
            PRINT 'Table to be truncated: ' + @TableName
        END
        ELSE
        BEGIN
            BEGIN TRY
                BEGIN TRANSACTION
                -- Check if CDC is enabled for the table
                SELECT @CDCState = is_tracked_by_cdc
                FROM sys.tables
                WHERE name = @TableName AND schema_id = SCHEMA_ID('dbo')
                -- Disable CDC if it is enabled
                IF @CDCState = 1
                BEGIN
                    SET @SQL = 'EXEC sys.sp_cdc_disable_table @source_schema = N''dbo'', @source_name = N''' + @TableName + ''', @capture_instance = N''dbo_' + @TableName + ''''
                    EXEC sp_executesql @SQL
                END
                -- Truncate the table
                SET @SQL = 'TRUNCATE TABLE ' + @TableName
                EXEC sp_executesql @SQL
                PRINT 'Successfully truncated table: ' + @TableName
                -- Re-enable CDC if it was previously enabled
                IF @CDCState = 1
                BEGIN
                    SET @SQL = 'EXEC sys.sp_cdc_enable_table @source_schema = N''dbo'', @source_name = N''' + @TableName + ''', @role_name = NULL'
                    EXEC sp_executesql @SQL
                END
                COMMIT TRANSACTION
            END TRY
            BEGIN CATCH
                ROLLBACK TRANSACTION
                SET @ErrorMessage = ERROR_MESSAGE()
                PRINT 'Error truncating table ' + @TableName + '. Error: ' + @ErrorMessage
            END CATCH
        END
        FETCH NEXT FROM TableCursor INTO @TableName
    END
    CLOSE TableCursor
    DEALLOCATE TableCursor
END