-- Create a stored procedure to delete records
IF OBJECT_ID('dbo.DeleteRecords', 'P') IS NOT NULL
    DROP PROCEDURE dbo.DeleteRecords;
GO
CREATE PROCEDURE DeleteRecords
    @Table NVARCHAR(255),
    @LE NVARCHAR(10),
    @StartDate DATE,
    @EndDate DATE,
    @Simulation BIT
AS
BEGIN
    DECLARE @SQL NVARCHAR(MAX)
    DECLARE @DateField NVARCHAR(255)
    DECLARE @CDCState BIT
    DECLARE @StartTime DATETIME
    DECLARE @EndTime DATETIME 
    DECLARE @Duration INT
    DECLARE @DeletedRecords INT

    -- Check for CreatedDateTime and ModifiedDateTime fields
    IF EXISTS (SELECT * FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = @Table AND COLUMN_NAME = 'CreatedDateTime')
    BEGIN
        SET @DateField = 'CreatedDateTime'
    END
    ELSE IF EXISTS (SELECT * FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = @Table AND COLUMN_NAME = 'ModifiedDateTime')
    BEGIN
        SET @DateField = 'ModifiedDateTime'
    END
    ELSE
    BEGIN
        PRINT 'Warning: Table ' + @Table + ' does not have CreatedDateTime or ModifiedDateTime fields.'
        RETURN
    END

    IF EXISTS (SELECT * FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = @Table AND COLUMN_NAME = 'DataAreaId')
    BEGIN
        PRINT 'DataAreaId exists in ' + @Table
    END
    ELSE
    BEGIN
        PRINT 'Warning: Table ' + @Table + ' does not have DataAreaId'
        RETURN
    END

    -- Check if CDC is enabled and disable it if necessary
    SELECT @CDCState = is_tracked_by_cdc
    FROM sys.tables
    WHERE name = @Table AND schema_id = SCHEMA_ID('dbo')

    IF @CDCState = 1
    BEGIN
        SET @SQL = 'EXEC sys.sp_cdc_disable_table @source_schema = ''dbo'', @source_name = ''' + @Table + ''''
        EXEC sp_executesql @SQL
    END

    -- Disable Change Data Capture or Change Tracking if enabled
    SET @SQL = 'IF EXISTS (SELECT * FROM sys.change_tracking_tables WHERE object_id = OBJECT_ID(''' + @Table + ''')) ALTER TABLE ' + @Table + ' DISABLE CHANGE_TRACKING'
    EXEC sp_executesql @SQL

    -- Delete records if not in simulation mode
    IF @Simulation = 0
    BEGIN
        SET @SQL = 'SELECT @DeletedRecords = COUNT(*) FROM ' + @Table + ' WHERE DataAreaID = ''' + @LE + ''' AND ' + @DateField + ' BETWEEN ''' + CONVERT(NVARCHAR, @StartDate, 120) + ''' AND ''' + CONVERT(NVARCHAR, @EndDate, 120) + ''''
        EXEC sp_executesql @SQL, N'@DeletedRecords INT OUTPUT', @DeletedRecords OUTPUT
		SET @StartTime = GETDATE()
        SET @SQL = 'DELETE FROM ' + @Table + ' WHERE DataAreaID = ''' + @LE + ''' AND ' + @DateField + ' BETWEEN ''' + CONVERT(NVARCHAR, @StartDate, 120) + ''' AND ''' + CONVERT(NVARCHAR, @EndDate, 120) + ''''
        EXEC sp_executesql @SQL
        SET @EndTime = GETDATE()
        SET @Duration = DATEDIFF(SECOND, @StartTime, @EndTime)
        SELECT @Table AS 'Table', @LE AS 'Legal Entity', CONVERT(NVARCHAR, @StartDate, 120) AS 'Start Date', CONVERT(NVARCHAR, @EndDate, 120) AS 'End Date', @DeletedRecords AS 'Nb Records Deleted', @Duration AS 'Estimated Duration'
    END
    ELSE
    BEGIN
        -- Simulation mode: Estimate duration of delete statement and count records
        BEGIN TRANSACTION
        SET @SQL = 'SELECT @DeletedRecords = COUNT(*) FROM ' + @Table + ' WHERE DataAreaID = ''' + @LE + ''' AND ' + @DateField + ' BETWEEN ''' + CONVERT(NVARCHAR, @StartDate, 120) + ''' AND ''' + CONVERT(NVARCHAR, @EndDate, 120) + ''''
        EXEC sp_executesql @SQL, N'@DeletedRecords INT OUTPUT', @DeletedRecords OUTPUT
		SET @StartTime = GETDATE()
        SET @SQL = 'DELETE FROM ' + @Table + ' WHERE DataAreaID = ''' + @LE + ''' AND ' + @DateField + ' BETWEEN ''' + CONVERT(NVARCHAR, @StartDate, 120) + ''' AND ''' + CONVERT(NVARCHAR, @EndDate, 120) + ''''
        EXEC sp_executesql @SQL
        SET @EndTime = GETDATE()
        ROLLBACK TRANSACTION
        SET @Duration = DATEDIFF(SECOND, @StartTime, @EndTime)
        SELECT @Table AS 'Table', @LE AS 'Legal Entity', CONVERT(NVARCHAR, @StartDate, 120) AS 'Start Date', CONVERT(NVARCHAR, @EndDate, 120) AS 'End Date', @DeletedRecords AS 'Nb Records Deleted', @Duration AS 'Estimated Duration'
    END

    -- Re-enable Change Data Capture or Change Tracking if previously enabled
    IF @CDCState = 1
    BEGIN
        SET @SQL = 'EXEC sys.sp_cdc_enable_table @source_schema = ''dbo'', @source_name = ''' + @Table + ''''
        EXEC sp_executesql @SQL
    END

    SET @SQL = 'IF EXISTS (SELECT * FROM sys.change_tracking_tables WHERE object_id = OBJECT_ID(''' + @Table + ''')) ALTER TABLE ' + @Table + ' ENABLE CHANGE_TRACKING'
    EXEC sp_executesql @SQL
END