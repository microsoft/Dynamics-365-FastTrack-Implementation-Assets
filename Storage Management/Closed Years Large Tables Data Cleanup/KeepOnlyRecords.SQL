/*
Description:
This script is designed to archive records from specified tables in a database. It creates a stored procedure that takes table name, legal entity, date, and simulation mode as parameters. The stored procedure performs the following steps:

1. Checks for the existence of necessary fields in the table.
2. Disables Change Data Capture or Change Tracking if enabled.
3. In simulation mode, estimates the duration of select, truncate, and insert statements and counts records.
4. In actual mode, performs the select, truncate, and insert operations.
5. Inserts results into a log table.
6. Re-enables Change Data Capture or Change Tracking if previously enabled.

Parameters:
- @Table: Name of the table to be archived
- @LE: List of legal entities
- @KeepFromDate: Date to keep records from
- @Simulation: Set to 1 for simulation mode, 0 for actual deletion

The script performs the following steps:
1. Drops the stored procedure if it already exists.
2. Creates the stored procedure with the specified parameters.
3. Performs the archiving operations based on the provided parameters.
*/

-- Drop the stored procedure if it already exists
IF OBJECT_ID('dbo.KeepOnlyRecordsSp', 'P') IS NOT NULL
    DROP PROCEDURE dbo.KeepOnlyRecordsSp;
GO

-- Create the stored procedure with specified parameters
CREATE PROCEDURE KeepOnlyRecordsSp
    @Table NVARCHAR(Max),
    @LE NVARCHAR(Max),
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
    DECLARE @DeletedRecords INT
    DECLARE @ColumnList NVARCHAR(MAX)
    DECLARE @RunTimestamp DATETIME

    -- Create DBCleanupResultsLog table if it doesn't exist
    IF NOT EXISTS (SELECT * FROM sysobjects WHERE name='DBCleanupResultsLog' AND xtype='U')
    BEGIN
        CREATE TABLE DBCleanupResultsLog(
            TableName NVARCHAR(MAX),
            LegalEntity NVARCHAR(MAX),
            KeepFromDate NVARCHAR(120),
            NbRecordsDeleted INT,
            EstimatedDuration INT,
            RunTimestamp DATETIME
        )
    END

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

    -- Check for DataAreaId field in the table
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

    -- Drop temporary table if it exists in tempdb
    IF OBJECT_ID('tempdb..##TempTable') IS NOT NULL
    BEGIN
        SET @SQL = 'DROP TABLE ##TempTable'
        EXEC sp_executesql @SQL
    END

    -- Set the run timestamp to current date and time
    SET @RunTimestamp = GETDATE()

    -- Simulation mode: Estimate duration of select, truncate, and insert statements and count records
    IF @Simulation = 1
    BEGIN
        BEGIN TRANSACTION
        
        -- Count records to be deleted in simulation mode
        SET @SQL = 'SELECT @DeletedRecords = COUNT(*) FROM ' + @Table + ' WHERE DataAreaID IN (SELECT value FROM STRING_SPLIT('''+@LE+''', '',''))'+' AND ' + @DateField + ' < ''' + CONVERT(NVARCHAR, @KeepFromDate, 120) + ''''
        EXEC sp_executesql @SQL, N'@DeletedRecords INT OUTPUT', @DeletedRecords OUTPUT
        
        -- Estimate duration of select statement in simulation mode
        SET @StartTime = GETDATE()
        SET @SQL = 'SELECT ' + @ColumnList + ' INTO ##TempTable FROM ' + @Table + ' WHERE DataAreaID IN (SELECT value FROM STRING_SPLIT('''+@LE+''', '',''))'+' AND ' + @DateField + ' > ''' + CONVERT(NVARCHAR, @KeepFromDate, 120) + ''''
        EXEC sp_executesql @SQL
        
        -- Estimate duration of truncate statement in simulation mode
        SET @SQL = 'TRUNCATE TABLE ' + @Table
        EXEC sp_executesql @SQL
        
        -- Estimate duration of insert statement in simulation mode
        SET @SQL = 'INSERT INTO ' + @Table + ' (' + @ColumnList + ') SELECT ' + @ColumnList + ' FROM ##TempTable'
        EXEC sp_executesql @SQL
        
        SET @EndTime = GETDATE()
        
        ROLLBACK TRANSACTION
        
        -- Calculate duration of operations in simulation mode
        SET @Duration = DATEDIFF(SECOND, @StartTime, @EndTime)
        
        -- Insert results into persisted table DBCleanupResultsLog 
        INSERT INTO DBCleanupResultsLog (TableName, LegalEntity, KeepFromDate, NbRecordsDeleted, EstimatedDuration, RunTimestamp)
        VALUES (@Table, @LE, CONVERT(NVARCHAR, @KeepFromDate, 120), @DeletedRecords, @Duration, @RunTimestamp)
        
        -- Select results from log table for verification in simulation mode 
        SELECT * FROM DBCleanupResultsLog WHERE TableName=@Table AND LegalEntity=@LE AND KeepFromDate=CONVERT(NVARCHAR, @KeepFromDate, 120)
        
    END
    ELSE
    BEGIN
        SET @SQL = 'SELECT @DeletedRecords = COUNT(*) FROM ' + @Table + ' WHERE DataAreaID IN (SELECT value FROM STRING_SPLIT('''+@LE+''', '',''))'+' AND ' + @DateField + ' < ''' + CONVERT(NVARCHAR, @KeepFromDate, 120) + ''''
        EXEC sp_executesql @SQL, N'@DeletedRecords INT OUTPUT', @DeletedRecords OUTPUT
        SET @StartTime = GETDATE()
        SET @SQL = 'SELECT ' + @ColumnList + ' INTO ##TempTable FROM ' + @Table + ' WHERE DataAreaID IN (SELECT value FROM STRING_SPLIT('''+@LE+''', '',''))'+' AND ' + @DateField + ' > ''' + CONVERT(NVARCHAR, @KeepFromDate, 120) + ''''
        EXEC sp_executesql @SQL
        SET @SQL = 'TRUNCATE TABLE ' + @Table
        EXEC sp_executesql @SQL
        SET @SQL = 'INSERT INTO ' + @Table + ' (' + @ColumnList + ') SELECT ' + @ColumnList + ' FROM ##TempTable'
        EXEC sp_executesql @SQL
        SET @EndTime = GETDATE()
        SET @Duration = DATEDIFF(SECOND, @StartTime, @EndTime)
        
        -- Insert results into persisted table DBCleanupResultsLog 
        INSERT INTO DBCleanupResultsLog (TableName, LegalEntity, KeepFromDate, NbRecordsDeleted, EstimatedDuration, RunTimestamp)
        VALUES (@Table, @LE, CONVERT(NVARCHAR, @KeepFromDate, 120), @DeletedRecords, @Duration, @RunTimestamp)
        
        SELECT * FROM DBCleanupResultsLog WHERE TableName=@Table AND LegalEntity=@LE AND KeepFromDate=CONVERT(NVARCHAR, @KeepFromDate, 120)
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
