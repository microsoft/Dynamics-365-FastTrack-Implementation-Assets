
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
-- Create the stored procedure with specified parameters
CREATE OR ALTER PROCEDURE KeepOnlyRecordsSp
    @Table NVARCHAR(Max),
    @LE NVARCHAR(Max),
    @KeepFromDate DATE,
    @Simulation BIT,
	@Threshold INT = 2000000,
	@BatchSize INT = 5000000, 
	@Resume BIT = 0
AS
BEGIN

	DECLARE @SQL NVARCHAR(MAX)
    DECLARE @DateField NVARCHAR(255)
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

	    -- Check for CreatedDateTime and ModifiedDateTime fields
    IF EXISTS (SELECT * FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = @Table AND COLUMN_NAME = 'CREATEDDATETIME')
    BEGIN
        SET @DateField = 'CREATEDDATETIME'
    END
    ELSE IF EXISTS (SELECT * FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = @Table AND COLUMN_NAME = 'MODIFIEDDATETIME')
    BEGIN
        SET @DateField = 'MODIFIEDDATETIME'
    END
	ELSE IF EXISTS (SELECT * FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = @Table AND COLUMN_NAME = 'ACCOUNTINGDATE')
    BEGIN
        SET @DateField = 'ACCOUNTINGDATE'
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

	END

	BEGIN TRANSACTION

    -- Get column list excluding timestamp columns
    SELECT @ColumnList = STUFF((
        SELECT ', ' + column_name
        FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME = @Table AND DATA_TYPE NOT IN ('timestamp') AND TABLE_SCHEMA = 'DBO'
        FOR XML PATH(''), TYPE
    ).value('.', 'NVARCHAR(MAX)'), 1, 2, '')

    -- Check if CDC is enabled and disable it if necessary
    SELECT @CDCState = is_tracked_by_cdc
    FROM sys.tables
    WHERE name = @Table AND schema_id = SCHEMA_ID('dbo')

    IF @CDCState = 1
    BEGIN
        SET @SQL = 'EXEC sys.sp_cdc_disable_table @source_schema = N''dbo'', @source_name = N''' + @Table + ''', @capture_instance = N''dbo_' + @Table + ''''
                EXEC sp_executesql @SQL
    END

    -- Disable Change Data Capture or Change Tracking if enabled
    SET @SQL = 'IF EXISTS (SELECT * FROM sys.change_tracking_tables WHERE object_id = OBJECT_ID(''' + @Table + ''')) ALTER TABLE ' + @Table + ' DISABLE CHANGE_TRACKING'
    EXEC sp_executesql @SQL

    -- Set the run timestamp to current date and time
    SET @StartTime = GETDATE()

    -- Count records to be deleted in simulation mode
    SET @SQL = 'SELECT @DeletedRecords = COUNT(*) FROM ' + @Table + ' WHERE DataAreaID IN (SELECT value FROM STRING_SPLIT('''+@LE+''', '',''))'+' AND ' + @DateField + ' < ''' + CONVERT(NVARCHAR, @KeepFromDate, 120) + ''''
    EXEC sp_executesql @SQL, N'@DeletedRecords INT OUTPUT', @DeletedRecords OUTPUT

		    -- Count records to be deleted in simulation mode
    SET @SQL = 'SELECT @SavedRecords = COUNT(*) FROM ' + @Table + ' WHERE DataAreaID IN (SELECT value FROM STRING_SPLIT('''+@LE+''', '',''))'+' AND ' + @DateField + ' >= ''' + CONVERT(NVARCHAR, @KeepFromDate, 120) + ''''
    EXEC sp_executesql @SQL, N'@SavedRecords INT OUTPUT', @SavedRecords OUTPUT

	Print @SQL
	Print 'nbRecord to save : ' + CONVERT(NVARCHAR,@SavedRecords)
	IF (@SavedRecords > @Threshold)
		BEGIN
			set @BufferTABLEName = @Table+'cleanupbuffer'
			set @BufferTableDropPrefix = ''
		END
	ELSE
		BEGIN
			set @BufferTABLEName = '##TempTableCleanuDB'
			set @BufferTableDropPrefix = 'tempdb..'
		END
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
				-- Drop temporary table if it exists in tempdb
				IF OBJECT_ID(@BufferTableDropPrefix+@BufferTABLEName+Convert(NVARCHAR,@nbBatchExecution)) IS NOT NULL
				BEGIN
					SET @SQL = 'DROP TABLE '+@BufferTABLEName+Convert(NVARCHAR,@nbBatchExecution)
					EXEC sp_executesql @SQL
				END
				BEGIN TRANSACTION
				SET @SQL = 'SELECT ' + @ColumnList + ' INTO '+@BufferTABLEName+Convert(NVARCHAR,@nbBatchExecution)+' FROM ' + @Table + ' WHERE DataAreaID IN (SELECT value FROM STRING_SPLIT('''+@LE+''', '',''))'+' AND ' + @DateField + ' >= ''' + CONVERT(NVARCHAR, @KeepFromDate, 120) + ''''
	--			print @SQL
				SET @sql =@SQL + ' ORDER BY RecId OFFSET '+CONvert(NVARCHAR,@CurrentRow)+' ROWS FETCH NEXT '+CONvert(NVARCHAR,@BatchSize)+' ROWS ONLY;'
				EXEC sp_executesql @SQL 
				SET @CurrentRow = @CurrentRow + @BatchSize;
				SET @nbBatchExecution = @nbBatchExecution +1
				COMMIT TRANSACTION
				Update DBCleanupResultsLog
				set Step = @step, CurrentLoopIndex = @nbBatchExecution
				where TableName = @Table AND LegalEntity = @LE AND KeepFromDate = @KeepFromDate and StartTime = @RunTimestamp

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
										-- Drop temporary table if it exists in tempdb
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
					-- Drop temporary table if it exists in tempdb
					IF OBJECT_ID(@BufferTableDropPrefix+@BufferTABLEName+Convert(NVARCHAR,@nbBatchExecution)) IS NOT NULL
					BEGIN
						SET @SQL = 'DROP TABLE '+@BufferTABLEName+Convert(NVARCHAR,@nbBatchExecution)
						EXEC sp_executesql @SQL
					END
					BEGIN TRANSACTION
					SET @SQL = 'SELECT ' + @ColumnList + ' INTO '+@BufferTABLEName+Convert(NVARCHAR,@nbBatchExecution)+' FROM ' + @Table + ' WHERE DataAreaID IN (SELECT value FROM STRING_SPLIT('''+@LE+''', '',''))'+' AND ' + @DateField + ' >= ''' + CONVERT(NVARCHAR, @KeepFromDate, 120) + ''''
		--			print @SQL
					SET @sql =@SQL + ' ORDER BY RecId OFFSET '+CONvert(NVARCHAR,@CurrentRow)+' ROWS FETCH NEXT '+CONvert(NVARCHAR,@BatchSize)+' ROWS ONLY;'
					EXEC sp_executesql @SQL 
					SET @CurrentRow = @CurrentRow + @BatchSize;
					SET @nbBatchExecution = @nbBatchExecution +1
					COMMIT TRANSACTION
					Update DBCleanupResultsLog
					set Step = @step, CurrentLoopIndex = @nbBatchExecution
					where TableName = @Table AND LegalEntity = @LE AND KeepFromDate = @KeepFromDate and StartTime = @RunTimestamp

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
