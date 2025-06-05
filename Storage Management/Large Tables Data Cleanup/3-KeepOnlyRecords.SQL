/****** Object:  StoredProcedure [dbo].[KeepOnlyRecordsSp]    Script Date: 6/4/2025 1:42:24 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


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
- @Threshold: Threshold value to determine buffer table usage (default is 2000000)
- @BatchSize: Size of each batch for processing records (default is 5000000)
- @Resume: Set to 1 to resume from previous run, 0 for fresh run (default is 0)

The script performs the following steps:
1. Drops the stored procedure if it already exists.
2. Creates the stored procedure with the specified parameters.
3. Performs the archiving operations based on the provided parameters.
*/
-- Create the stored procedure with specified parameters
CREATE OR ALTER PROCEDURE [dbo].[KeepOnlyRecordsSp]
    @Table NVARCHAR(Max),
    @LE NVARCHAR(Max),
    @KeepFromDate DATE,
    @Simulation BIT = 1,
    @Threshold INT = 2000000,
    @BatchSize INT = 5000000, 
    @Resume BIT = 0
AS
BEGIN

	DECLARE @SQL NVARCHAR(MAX)
    DECLARE @DateField NVARCHAR(255) = ''
    DECLARE @CDCState BIT
    DECLARE @StartTime DATETIME
    DECLARE @EndTime DATETIME 
    DECLARE @Duration INT
    DECLARE @DeletedRecords INT
	DECLARE @SavedRecords INT
    DECLARE @ColumnList NVARCHAR(MAX)
    DECLARE @RunTimestamp DATETIME
	DECLARE @CurrentRow INT = 0;
	DECLARE @BufferTABLEName NVARCHAR(MAX)
	DECLARE @BufferTableDropPrefix NVARCHAR(10) = ''
	DECLARE @Interimstart DATETIME
    	DECLARE @Interimend DATETIME 
	DECLARE @nbBatchExecution INT = 1
	DECLARE @step INT = 0 
	DECLARE @minRecId BIGINT = 0
	DECLARE @maxRecId BIGINT = 0
	Declare @partitionId bigint = 0


		-- Check if the table has an index with RecId as the first and only column
	IF NOT EXISTS (
		SELECT 1
		FROM sys.indexes i
		JOIN sys.index_columns ic ON i.object_id = ic.object_id AND i.index_id = ic.index_id
		JOIN sys.columns c ON ic.object_id = c.object_id AND ic.column_id = c.column_id
		WHERE i.object_id = OBJECT_ID(@Table)
		  AND c.name = 'RecId'
		  AND ic.key_ordinal = 1
		  AND NOT EXISTS (
			  SELECT 1
			  FROM sys.index_columns ic2
			  WHERE ic2.object_id = i.object_id
				AND ic2.index_id = i.index_id
				AND ic2.key_ordinal > 1
		  )
	)
	BEGIN
		DECLARE @IndexName NVARCHAR(128) = @Table + '_RecId_IDX'
		SET @SQL = 
			'CREATE NONCLUSTERED INDEX [' + @IndexName + '] ON [' + @Table + '] ([RecId])'
		EXEC sp_executesql @SQL
		PRINT 'Index created: ' + @IndexName
	END
	ELSE
	BEGIN
		PRINT 'Index with RecId as the only key column already exists on ' + @Table
	END
	
	Print('checkpoint 1')

	select top 1 @partitionId = PARTITION from USERINFO

	    -- Check for CreatedDateTime and ModifiedDateTime fields
    SELECT @DateField = CleanupColumn FROM FTDateTimeColumnMappingPerTable WHERE TABLE_NAME = @Table
	IF @DateField = ''
	BEGIN
        PRINT 'Warning: Table ' + @Table + ' does not have a date time'
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

	Print('checkpoint 2')

	IF @Resume = 1
	BEGIN
		SELECT TOP 1 @RunTimestamp = StartTime, @STep = Step, @nbBatchExecution = CurrentLoopIndex
			FROM DBCleanupResultsLog
			WHERE EndTime IS NULL
			AND TableName = @Table
			AND LegalEntity = @LE
			AND KeepFromDate = @KeepFromDate
			ORDER BY StartTime DESC

			IF @RunTimestamp IS NULL
			BEGIN
				SET @RunTimestamp = GETDATE()
				SET @Step = 0
				SET @nbBatchExecution = 1
				INSERT INTO DBCleanupResultsLog (TableName, LegalEntity, KeepFromDate, StartTime,Step, CurrentLoopIndex)
				VALUES (@Table, @LE, CONVERT(NVARCHAR, @KeepFromDate, 120), @RunTimestamp, @step, @nbBatchExecution)
			END
		Print('checkpoint 3')

	END
	ELSE 
	BEGIN
		if exists(SELECT TOP 1 @RunTimestamp 
			FROM DBCleanupResultsLog
			WHERE EndTime IS NULL
			AND TableName = @Table
			AND LegalEntity = @LE
			AND KeepFromDate = @KeepFromDate)
		begin
			RETURN 
		end

		SET @RunTimestamp = GETDATE()
			-- Insert a marker line to be able to resume
		INSERT INTO DBCleanupResultsLog (TableName, LegalEntity, KeepFromDate, StartTime,Step, CurrentLoopIndex)
		VALUES (@Table, @LE, CONVERT(NVARCHAR, @KeepFromDate, 120), @RunTimestamp, @step, @nbBatchExecution)
		Print('checkpoint 4')

	END

	Print('checkpoint 5')
	
	BEGIN TRANSACTION

    -- Get column list excluding timestamp columns
    SELECT @ColumnList = STUFF((
        SELECT ', ' + column_name
        FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME = @Table AND DATA_TYPE NOT IN ('timestamp') AND TABLE_SCHEMA = 'DBO'
        FOR XML PATH(''), TYPE
    ).value('.', 'NVARCHAR(MAX)'), 1, 2, '')
	
	Print('checkpoint 6')

    -- Check if CDC is enabled and disable it if necessary
    SELECT @CDCState = is_tracked_by_cdc
    FROM sys.tables
    WHERE name = @Table AND schema_id = SCHEMA_ID('dbo')

    IF @CDCState = 1
    BEGIN
        SET @SQL = 'EXEC sys.sp_cdc_disable_table @source_schema = N''dbo'', @source_name = N''' + @Table + ''', @capture_instance = N''dbo_' + @Table + ''''
                EXEC sp_executesql @SQL
    END

	Print('checkpoint 7')

    -- Disable Change Data Capture or Change Tracking if enabled
    SET @SQL = 'IF EXISTS (SELECT * FROM sys.change_tracking_tables WHERE object_id = OBJECT_ID(''' + @Table + ''')) ALTER TABLE ' + @Table + ' DISABLE CHANGE_TRACKING'
    EXEC sp_executesql @SQL

    -- Set the run timestamp to current date and time
    SET @StartTime = GETDATE()

	SET @SQL ='SELECT @minRecId = min(RecId) FROM '+@Table+' WHERE Partition = '+ CONVERT(NVARCHAR, @partitionId) + ' AND DataAreaID IN (SELECT value FROM STRING_SPLIT('''+@LE+''', '',''))'+' AND ' + @DateField + ' >= ''' + CONVERT(NVARCHAR, @KeepFromDate, 120) + ''''
	Print @SQL
	EXEC sp_executesql @SQL, N'@minRecId BIGINT OUTPUT', @minRecId OUTPUT

	Print('checkpoint 8')

    -- Count records to be deleted in simulation mode
    SET @SQL = 'SELECT @DeletedRecords = COUNT(*) FROM ' + @Table + ' WHERE Partition = '+ CONVERT(NVARCHAR, @partitionId) + ' AND  DataAreaID IN (SELECT value FROM STRING_SPLIT('''+@LE+''', '',''))'+' AND ' + @DateField + ' < ''' + CONVERT(NVARCHAR, @KeepFromDate, 120) + ''''
    Print @SQL
	EXEC sp_executesql @SQL, N'@DeletedRecords INT OUTPUT', @DeletedRecords OUTPUT

	Print('checkpoint 9')

		    -- Count records to be deleted in simulation mode
    SET @SQL = 'SELECT @SavedRecords = COUNT(*) FROM ' + @Table + ' WHERE Partition = '+ CONVERT(NVARCHAR, @partitionId) + ' AND DataAreaID IN (SELECT value FROM STRING_SPLIT('''+@LE+''', '',''))'+' AND ' + @DateField + ' >= ''' + CONVERT(NVARCHAR, @KeepFromDate, 120) + ''''
    Print @SQL
	EXEC sp_executesql @SQL, N'@SavedRecords INT OUTPUT', @SavedRecords OUTPUT
	
	Print('checkpoint 10')


	Print @SQL
	Print 'nbRecord to save : ' + CONVERT(NVARCHAR,@SavedRecords)
-- too risky to use unpersisted tables when transient errors or SQL azure governance stops the process, impossible to resume other than with PITR
--	IF (@SavedRecords > @Threshold)
--		BEGIN
			set @BufferTABLEName = @Table+'cleanupbuffer'
			set @BufferTableDropPrefix = ''
--		END
--	ELSE
--		BEGIN
--			set @BufferTABLEName = '##TempTableCleanuDB
--			set @BufferTableDropPrefix = 'tempdb..'
--		END
	print 'BufferTable : '+@BufferTABLEName

	COMMIT TRANSACTION

	-- Simulation mode: Estimate duration of select, truncate, and insert statements and count records
	IF @Simulation = 1
    BEGIN
--##STEP1 Begin
        IF @step <= 1
		BEGIN
			SET @Interimstart = GETDATE()
			IF @step = 0
			BEGIN
				-- Estimate duration of select statement in simulation mode
				SET @step =  1
				SET @nbBatchExecution = 1
			END
			ELSE
			BEGIN 
				SET @CurrentRow = (@nbBatchExecution-1)*@BatchSize
			END
			WHILE @CurrentRow < @SavedRecords
			BEGIN
				
				IF OBJECT_ID(@BufferTableDropPrefix + @BufferTABLEName + CONVERT(NVARCHAR, @nbBatchExecution)) IS NOT NULL
				BEGIN
					SET @SQL = 'DROP TABLE ' + @BufferTABLEName + CONVERT(NVARCHAR, @nbBatchExecution)
					EXEC sp_executesql @SQL
				END
 
				BEGIN TRANSACTION
 
				IF @maxRecId = 0
				BEGIN
					SET @SQL = 'SELECT TOP ' + CONVERT(NVARCHAR, @BatchSize) + ' ' + @ColumnList +
							   ' INTO ' + @BufferTABLEName + CONVERT(NVARCHAR, @nbBatchExecution) +
							   ' FROM ' + @Table +
							   ' WHERE RecId >= ' + CONVERT(NVARCHAR, @minRecId) +
							   ' ORDER BY RecId DESC'
				END
				ELSE
				BEGIN
					SET @SQL = 'SELECT TOP ' + CONVERT(NVARCHAR, @BatchSize) + ' ' + @ColumnList +
							   ' INTO ' + @BufferTABLEName + CONVERT(NVARCHAR, @nbBatchExecution) +
							   ' FROM ' + @Table +
							   ' WHERE RecId >= ' + CONVERT(NVARCHAR, @minRecId) +
							   ' AND RecId < ' + CONVERT(NVARCHAR, @maxRecId) +
							   ' ORDER BY RecId DESC'
				END
				PRINT @SQL
				EXEC sp_executesql @SQL
 
				-- Create index on DataAreaID
				SET @SQL = 'CREATE NONCLUSTERED INDEX IX_' + @BufferTABLEName + CONVERT(NVARCHAR, @nbBatchExecution) +
						   '_DataAreaID ON ' + @BufferTABLEName + CONVERT(NVARCHAR, @nbBatchExecution) + ' (DataAreaID)'
				PRINT @SQL
				EXEC sp_executesql @SQL
 
				BEGIN TRY
					-- Delete rows where DataAreaID is not in the list
					SET @SQL = 'DELETE FROM ' + @BufferTABLEName + CONVERT(NVARCHAR, @nbBatchExecution) +
							   ' WHERE DataAreaID NOT IN (SELECT value FROM STRING_SPLIT(''' + @LE + ''', '',''))'
					PRINT @SQL
					EXEC sp_executesql @SQL
				END TRY
				BEGIN CATCH
					Print 'missing delete permissions'
				END CATCH
 
				-- Update maxRecId
				SET @SQL = 'SELECT @maxRecId = MIN(RecId) FROM ' + @BufferTABLEName + CONVERT(NVARCHAR, @nbBatchExecution)
				PRINT @SQL
				EXEC sp_executesql @SQL, N'@maxRecId BIGINT OUTPUT', @maxRecId OUTPUT
 
				SET @CurrentRow = @CurrentRow + @BatchSize
				SET @nbBatchExecution = @nbBatchExecution + 1
 
				COMMIT TRANSACTION
 
				UPDATE DBCleanupResultsLog
				SET Step = @step, CurrentLoopIndex = @nbBatchExecution
				WHERE TableName = @Table AND LegalEntity = @LE AND KeepFromDate = @KeepFromDate AND StartTime = @RunTimestamp

			END
			SET @Interimend = GETDATE()
			SET @Duration = DATEDIFF(MILLISECOND, @Interimstart, @Interimend)
			Print 'copy from main table duraion in ms ' + convert(NVARCHAR,@Duration)
		END
		IF @step = 1 or @step = 2 
		BEGIN
	--##Step2 Begin
			SET @step =  2
			SET @Interimstart = GETDATE()
			-- Estimate duration of truncate statement in simulation mode
/* simulation of truncate is useless and the rolback is what is driving crazy IO 
			BEGIN TRANSACTION
			SET @SQL = 'TRUNCATE TABLE ' + @Table
			EXEC sp_executesql @SQL
			ROLLBACK TRANSACTION
*/
			SET @Interimend = GETDATE()
			SET @Duration = DATEDIFF(MILLISECOND, @Interimstart, @Interimend)
		
			Update DBCleanupResultsLog
			set Step = @step, CurrentLoopIndex = 0
			where TableName = @Table AND LegalEntity = @LE AND KeepFromDate = @KeepFromDate and StartTime = @RunTimestamp

			Print 'Trucate table duration in ms ' + convert(NVARCHAR,@Duration)
		END
		IF @step = 2 or @step = 3
		BEGIN
	--##Step3 begin		
			IF @step = 2
			BEGIN
				-- Estimate duration of insert statement in simulation mode
				SET @step =  3
				SET @CurrentRow = 0
				SET @nbBatchExecution = 1
			END 
			ELSE
			BEGIN 
				SET @CurrentRow = (@nbBatchExecution-1)*@BatchSize
			END
			SET @Interimstart = GETDATE()
			WHILE @CurrentRow < @SavedRecords
			BEGIN
										
					IF OBJECT_ID(@BufferTableDropPrefix+@BufferTABLEName+Convert(NVARCHAR,@nbBatchExecution)+'simulation') IS NOT NULL
					BEGIN
						SET @SQL = 'DROP TABLE '+@BufferTABLEName+Convert(NVARCHAR,@nbBatchExecution)+'simulation'
						EXEC sp_executesql @SQL
					END

					BEGIN TRANSACTION
					SET @SQL = 'SELECT * INTO '+  @BufferTABLEName+Convert(NVARCHAR,@nbBatchExecution)+'simulation' +' FROM '+@BufferTABLEName+Convert(NVARCHAR,@nbBatchExecution)
					print @SQL
					EXEC sp_executesql @SQL 
					COMMIT TRANSACTION

					-- Drop temporary table if it exists in tempdb
					IF OBJECT_ID(@BufferTableDropPrefix+@BufferTABLEName+Convert(NVARCHAR,@nbBatchExecution)) IS NOT NULL
					BEGIN
						SET @SQL = 'DROP TABLE '+@BufferTABLEName+Convert(NVARCHAR,@nbBatchExecution)
						EXEC sp_executesql @SQL
					END
					IF OBJECT_ID(@BufferTableDropPrefix+@BufferTABLEName+Convert(NVARCHAR,@nbBatchExecution)+'simulation') IS NOT NULL
					BEGIN
						SET @SQL = 'DROP TABLE '+@BufferTABLEName+Convert(NVARCHAR,@nbBatchExecution)+'simulation'
						EXEC sp_executesql @SQL
					END

					SET @CurrentRow = @CurrentRow + @BatchSize;
					SET @nbBatchExecution = @nbBatchExecution +1

					Update DBCleanupResultsLog
					set Step = @step, CurrentLoopIndex = @nbBatchExecution
					where TableName = @Table AND LegalEntity = @LE AND KeepFromDate = @KeepFromDate and StartTime = @RunTimestamp

			END
		END

		SET @Interimend = GETDATE()
		SET @Duration = DATEDIFF(MILLISECOND, @Interimstart, @Interimend)
		Print 'Copy Back data duraiton in ms ' + convert(NVARCHAR,@Duration)
		
    END
    ELSE
    BEGIN
--##STEP1 Begin
        IF @step <= 1
		BEGIN
			SET @Interimstart = GETDATE()
			IF @step = 0
			BEGIN
				-- Estimate duration of select statement in simulation mode
				SET @step =  1
				SET @nbBatchExecution = 1
			END
			ELSE
			BEGIN 
				SET @CurrentRow = (@nbBatchExecution-1)*@BatchSize
			END
			WHILE @CurrentRow < @SavedRecords
			BEGIN
				IF OBJECT_ID(@BufferTableDropPrefix + @BufferTABLEName + CONVERT(NVARCHAR, @nbBatchExecution)) IS NOT NULL
				BEGIN
					SET @SQL = 'DROP TABLE ' + @BufferTABLEName + CONVERT(NVARCHAR, @nbBatchExecution)
					EXEC sp_executesql @SQL
				END
 
				BEGIN TRANSACTION
 
				IF @maxRecId = 0
				BEGIN
					SET @SQL = 'SELECT TOP ' + CONVERT(NVARCHAR, @BatchSize) + ' ' + @ColumnList +
							   ' INTO ' + @BufferTABLEName + CONVERT(NVARCHAR, @nbBatchExecution) +
							   ' FROM ' + @Table +
							   ' WHERE RecId >= ' + CONVERT(NVARCHAR, @minRecId) +
							   ' ORDER BY RecId DESC'
				END
				ELSE
				BEGIN
					SET @SQL = 'SELECT TOP ' + CONVERT(NVARCHAR, @BatchSize) + ' ' + @ColumnList +
							   ' INTO ' + @BufferTABLEName + CONVERT(NVARCHAR, @nbBatchExecution) +
							   ' FROM ' + @Table +
							   ' WHERE RecId >= ' + CONVERT(NVARCHAR, @minRecId) +
							   ' AND RecId < ' + CONVERT(NVARCHAR, @maxRecId) +
							   ' ORDER BY RecId DESC'
				END
				PRINT @SQL
				EXEC sp_executesql @SQL
 
				-- Create index on DataAreaID
				SET @SQL = 'CREATE NONCLUSTERED INDEX IX_' + @BufferTABLEName + CONVERT(NVARCHAR, @nbBatchExecution) +
						   '_DataAreaID ON ' + @BufferTABLEName + CONVERT(NVARCHAR, @nbBatchExecution) + ' (DataAreaID)'
				PRINT @SQL
				EXEC sp_executesql @SQL
 
				BEGIN TRY
					-- Delete rows where DataAreaID is not in the list
					SET @SQL = 'DELETE FROM ' + @BufferTABLEName + CONVERT(NVARCHAR, @nbBatchExecution) +
							   ' WHERE DataAreaID NOT IN (SELECT value FROM STRING_SPLIT(''' + @LE + ''', '',''))'
					PRINT @SQL
					EXEC sp_executesql @SQL
				END TRY
				BEGIN CATCH
					Print 'missing delete permissions'
				END CATCH
 
				-- Update maxRecId
				SET @SQL = 'SELECT @maxRecId = MIN(RecId) FROM ' + @BufferTABLEName + CONVERT(NVARCHAR, @nbBatchExecution)
				PRINT @SQL
				EXEC sp_executesql @SQL, N'@maxRecId BIGINT OUTPUT', @maxRecId OUTPUT
 
				SET @CurrentRow = @CurrentRow + @BatchSize
				SET @nbBatchExecution = @nbBatchExecution + 1
 
				COMMIT TRANSACTION
 
				UPDATE DBCleanupResultsLog
				SET Step = @step, CurrentLoopIndex = @nbBatchExecution
				WHERE TableName = @Table AND LegalEntity = @LE AND KeepFromDate = @KeepFromDate AND StartTime = @RunTimestamp


			END
			SET @Interimend = GETDATE()
			SET @Duration = DATEDIFF(MILLISECOND, @Interimstart, @Interimend)
			Print 'copy from main table duraion in ms ' + convert(NVARCHAR,@Duration)
		END
		IF @step = 1 or @step = 2 
		BEGIN
	--##Step2 Begin
			SET @step =  2
			SET @Interimstart = GETDATE()
			-- Estimate duration of truncate statement in simulation mode
			BEGIN TRANSACTION
			SET @SQL = 'TRUNCATE TABLE ' + @Table
			EXEC sp_executesql @SQL
			COMMIT TRANSACTION
			SET @Interimend = GETDATE()
			SET @Duration = DATEDIFF(MILLISECOND, @Interimstart, @Interimend)
		
			Update DBCleanupResultsLog
			set Step = @step, CurrentLoopIndex = 0
			where TableName = @Table AND LegalEntity = @LE AND KeepFromDate = @KeepFromDate and StartTime = @RunTimestamp

			Print 'Trucate table duration in ms ' + convert(NVARCHAR,@Duration)
		END
		IF @step = 2 or @step = 3
		BEGIN
	--##Step3 begin		
			IF @step = 2
			BEGIN
				-- Estimate duration of insert statement in simulation mode
				SET @step =  3
				SET @CurrentRow = 0
				SET @nbBatchExecution = 1
			END 
			ELSE
			BEGIN 
				SET @CurrentRow = (@nbBatchExecution-1)*@BatchSize
			END
			SET @Interimstart = GETDATE()
			WHILE @CurrentRow < @SavedRecords
			BEGIN
					BEGIN TRANSACTION
					SET @SQL = 'INSERT INTO ' + @Table + ' (' + @ColumnList + ') SELECT ' + @ColumnList + ' FROM '+@BufferTABLEName+Convert(NVARCHAR,@nbBatchExecution)
					print @SQL
					EXEC sp_executesql @SQL 
					COMMIT TRANSACTION

				-- Drop temporary table if it exists in tempdb
					IF OBJECT_ID(@BufferTableDropPrefix+@BufferTABLEName+Convert(NVARCHAR,@nbBatchExecution)) IS NOT NULL
					BEGIN
						SET @SQL = 'DROP TABLE '+@BufferTABLEName+Convert(NVARCHAR,@nbBatchExecution)
						EXEC sp_executesql @SQL
					END
					SET @CurrentRow = @CurrentRow + @BatchSize;
					SET @nbBatchExecution = @nbBatchExecution +1

					Update DBCleanupResultsLog
					set Step = @step, CurrentLoopIndex = @nbBatchExecution
					where TableName = @Table AND LegalEntity = @LE AND KeepFromDate = @KeepFromDate and StartTime = @RunTimestamp


			END
		END

		SET @Interimend = GETDATE()
		SET @Duration = DATEDIFF(MILLISECOND, @Interimstart, @Interimend)
		Print 'Copy Back data duraiton in ms ' + convert(NVARCHAR,@Duration)
		
    END



    SET @EndTime = GETDATE()
        -- Calculate duration of operations in simulation mode
    SET @Duration = DATEDIFF(MILLISECOND, @StartTime, @EndTime)


	Update DBCleanupResultsLog
		set Step = @step, CurrentLoopIndex = 0, NbRecordsDeleted = @DeletedRecords, NbRecordsSaved = @SavedRecords, EstimatedDuration = @Duration, EndTime = @EndTime
		where TableName = @Table AND LegalEntity = @LE AND KeepFromDate = @KeepFromDate and StartTime = @RunTimestamp

    -- Select results from log table for verification in simulation mode 
    SELECT * FROM DBCleanupResultsLog WHERE TableName=@Table AND LegalEntity=@LE AND KeepFromDate=CONVERT(NVARCHAR, @KeepFromDate, 120)


    -- Re-enable Change Data Capture or Change Tracking if previously enabled
    IF @CDCState = 1
    BEGIN
		SET @SQL = 'EXEC sys.sp_cdc_enable_table @source_schema = N''dbo'', @source_name = N''' + @Table + ''', @role_name = NULL'
        EXEC sp_executesql @SQL
    END

    SET @SQL = 'IF EXISTS (SELECT * FROM sys.change_tracking_tables WHERE object_id = OBJECT_ID(''' + @Table + ''')) ALTER TABLE ' + @Table + ' ENABLE CHANGE_TRACKING'
    EXEC sp_executesql @SQL
END
GO


