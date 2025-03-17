IF OBJECT_ID('dbo.KeepOnlyRecordsSp', 'P') IS NOT NULL
    DROP PROCEDURE dbo.KeepOnlyRecordsSp;
GO
CREATE PROCEDURE KeepOnlyRecordsSp
    @Table NVARCHAR(MAX),
    @LE NVARCHAR(MAX),
    @KeepFromDate DATE,
    @Simulation BIT
AS
BEGIN
    DECLARE @SQL NVARCHAR(MAX)
    DECLARE @DateField NVARCHAR(255)
    DECLARE @CDCState BIT
    DECLARE @StartTime DATETIME
    DECLARE @EndTime DATETIME 
    DECLARE @Duration INT
    DECLARE @SelectedRecords INT
    DECLARE @ColumnList NVARCHAR(MAX)

    -- Check for CreatedDateTime and ModifiedDateTime fields
    IF EXISTS (SELECT * FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = @Table AND COLUMN_NAME = 'CREATEDDATETIME')
    BEGIN
        SET @DateField = 'CREATEDDATETIME'
    END
    ELSE IF EXISTS (SELECT * FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = @Table AND COLUMN_NAME = 'MODIFIEDDATETIME')
    BEGIN
        SET @DateField = 'MODIFIEDDATETIME'
    END
    ELSE
    BEGIN
        PRINT 'Warning: Table ' + @Table + ' does not have CreatedDateTime or ModifiedDateTime fields.'
        RETURN
    END

    IF EXISTS (SELECT * FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = @Table AND (COLUMN_NAME = 'DataAreaId'))
    BEGIN
        PRINT 'DataAreaId exists in ' + @Table
    END
    ELSE
    BEGIN
        PRINT 'Warning: Table ' + @Table + ' does not have DataAreaId'
        RETURN
    END

    -- Get column list excluding timestamp columns
-- Get column list excluding timestamp columns
    SELECT @ColumnList = STUFF((
        SELECT ', ' + column_name
        FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME = @Table AND DATA_TYPE NOT IN ('timestamp')
        FOR XML PATH(''), TYPE
    ).value('.', 'NVARCHAR(MAX)'), 1, 2, '')

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

	IF OBJECT_ID('tempdb..##TempTable') IS NOT NULL
	BEGIN
		SET @SQL = 'DROP TABLE ##TempTable'
		EXEC sp_executesql @SQL
	END

    -- Simulation mode: Estimate duration of select, truncate, and insert statements and count records
    IF @Simulation = 1
    BEGIN
        BEGIN TRANSACTION
        SET @SQL = 'SELECT @SelectedRecords = COUNT(*) FROM ' + @Table + ' WHERE DataAreaID IN (SELECT value FROM STRING_SPLIT('''+@LE+''', '',''))'+' AND ' + @DateField + ' > ''' + CONVERT(NVARCHAR, @KeepFromDate, 120) + ''''
        EXEC sp_executesql @SQL, N'@SelectedRecords INT OUTPUT', @SelectedRecords OUTPUT
        SET @StartTime = GETDATE()
        SET @SQL = 'SELECT ' + @ColumnList + ' INTO ##TempTable FROM ' + @Table + ' WHERE DataAreaID IN (SELECT value FROM STRING_SPLIT('''+@LE+''', '',''))'+' AND ' + @DateField + ' > ''' + CONVERT(NVARCHAR, @KeepFromDate, 120) + ''''
        EXEC sp_executesql @SQL
        SET @SQL = 'TRUNCATE TABLE ' + @Table
        EXEC sp_executesql @SQL
        SET @SQL = 'INSERT INTO ' + @Table + ' (' + @ColumnList + ') SELECT ' + @ColumnList + ' FROM ##TempTable'
        EXEC sp_executesql @SQL
        SET @EndTime = GETDATE()
        ROLLBACK TRANSACTION
        SET @Duration = DATEDIFF(SECOND, @StartTime, @EndTime)
        SELECT @Table AS 'Table', @LE AS 'Legal Entity', CONVERT(NVARCHAR, @KeepFromDate, 120) AS 'Keep From Date', @SelectedRecords AS 'Nb Records Selected', @Duration AS 'Estimated Duration'
    END
    ELSE
    BEGIN
        -- Insert records into temp table
        SET @SQL = 'SELECT ' + @ColumnList + ' INTO ##TempTable FROM ' + @Table + ' WHERE DataAreaID IN (SELECT value FROM STRING_SPLIT('''+@LE+''', '',''))'+' AND ' + @DateField + ' > ''' + CONVERT(NVARCHAR, @KeepFromDate, 120) + ''''
        EXEC sp_executesql @SQL

        -- Truncate the original table
        SET @SQL = 'TRUNCATE TABLE ' + @Table
        EXEC sp_executesql @SQL

        -- Insert records back from temp table into original table
        SET @SQL = 'INSERT INTO ' + @Table + ' (' + @ColumnList + ') SELECT ' + @ColumnList + ' FROM ##TempTable'
        EXEC sp_executesql @SQL
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
GO
