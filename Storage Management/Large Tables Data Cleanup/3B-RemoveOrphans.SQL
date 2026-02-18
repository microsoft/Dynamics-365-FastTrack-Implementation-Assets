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
CREATE OR ALTER PROCEDURE [dbo].[RemoveOrphansOnTablesWithoutDateTime]
    @Table NVARCHAR(Max),
    @LE NVARCHAR(Max),
    @KeepFromDate DATE,
    @Simulation BIT = 1,
    @BatchSize INT = 5000000, 
    @Resume BIT = 0,
	@RowCount BIGINT = 0,
	@JoinCondition NVARCHAR(Max) -- INNER JOIN OTHER TABLE ON TABLE.FIELD = OTHERTABLE.RECID
AS
BEGIN

	DECLARE @NBRecordsEligible INT =0
	DECLARE @SQL NVARCHAR(MAX)
    DECLARE @CDCState BIT
    DECLARE @StartTime DATETIME
    DECLARE @EndTime DATETIME 
    DECLARE @Duration INT
    DECLARE @DeletedRecords INT =0
	DECLARE @SavedRecords INT =0
	DECLARE @SavedRecordsLoop INT =0
	DECLARE @TotalRecords INT 
    DECLARE @ColumnList NVARCHAR(MAX)
    DECLARE @RunTimestamp DATETIME
	DECLARE @BufferTABLEName NVARCHAR(MAX)
	DECLARE @BufferTableDropPrefix NVARCHAR(10) = ''
	DECLARE @Interimstart DATETIME
    DECLARE @Interimend DATETIME 
	DECLARE @nbBatchExecution INT = 1
	DECLARE @step INT = 0 
	DECLARE @minRecId BIGINT = 0
	DECLARE @maxRecId BIGINT = 0
	Declare @SourceTableName NVARCHAR(MAX)
	Declare @TargetTableName NVARCHAR(MAX)
	Declare @TableHasDataareaIdField BIT = 0 
	DECLARE @HasMoreRecords BIT =  1





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


	Print('checkpoint 2')

	IF @Resume = 1
	BEGIN
		SELECT TOP 1 @RunTimestamp = StartTime, @step = Step, @nbBatchExecution = CurrentLoopIndex
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
        SELECT ', ' + '#SourceTable.'+column_name
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


	BEGIN TRANSACTION
    -- Disable Change Data Capture or Change Tracking if enabled
    SET @SQL = 'IF EXISTS (SELECT * FROM sys.change_tracking_tables WHERE object_id = OBJECT_ID(''' + @Table + ''')) ALTER TABLE ' + @Table + ' DISABLE CHANGE_TRACKING'
    Print @SQL
	EXEC sp_executesql @SQL
	Print('CT disabled')
	COMMIT TRANSACTION

	-- Set the run timestamp to current date and time
    SET @StartTime = GETDATE()
	   
	Print @SQL
	set @BufferTABLEName = @Table+'cleanupbuffer'
	set @BufferTableDropPrefix = ''
	print 'BufferTable : '+@BufferTABLEName

	COMMIT TRANSACTION

	Print CONVERT(NVARCHAR(MAX),@@TRANCOUNT)

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
		WHILE @HasMoreRecords = 1
		BEGIN
				
			IF (@maxRecId = 0 and @nbBatchExecution > 1 )
			BEGIN
				set @nbBatchExecution =  @nbBatchExecution - 1
				if(OBJECT_ID(@BufferTableDropPrefix + @BufferTABLEName + CONVERT(NVARCHAR, @nbBatchExecution)) IS NOT NULL)
				BEGIN
					SET @SQL = 'SELECT @maxRecId = MIN(RecId) FROM ' + @BufferTABLEName + CONVERT(NVARCHAR, @nbBatchExecution)
					PRINT @SQL
					EXEC sp_executesql @SQL, N'@maxRecId BIGINT OUTPUT ', @maxRecId OUTPUT
					set @nbBatchExecution =  @nbBatchExecution + 1
				END
			END
			print 'after @maxRecId = 0 and @nbBatchExecution > 1 '
				
			
			IF (OBJECT_ID(@BufferTableDropPrefix + @BufferTABLEName + CONVERT(NVARCHAR, @nbBatchExecution)) IS NOT NULL)
			BEGIN
				SET @SQL = 'DROP TABLE ' + @BufferTABLEName + CONVERT(NVARCHAR, @nbBatchExecution)
				EXEC sp_executesql @SQL
			END
			print 'after drop '

									-- calculate batchsize
--			SET @SQL = 'SELECT @maxRecId = MIN(RecId) FROM ' + @BufferTABLEName + CONVERT(NVARCHAR, @nbBatchExecution)
--			PRINT @SQL
--			EXEC sp_executesql @SQL, N'@maxRecId BIGINT OUTPUT ', @maxRecId OUTPUT

			

			IF @maxRecId = 0
			BEGIN
				SET @SQL = 'SELECT @NBRecordsEligible = count(*) FROM ' + @Table +
							' ' + @JoinCondition + ' ' 
			END
			ELSE
			BEGIN
				SET @SQL = 'SELECT @NBRecordsEligible = count(*) FROM ' + @Table +
							' ' + @JoinCondition + ' ' +
							' WHERE '+@Table+'.RecId < ' + CONVERT(NVARCHAR, @maxRecId)
			END
			PRINT @SQL
			EXEC sp_executesql @SQL, N'@NBRecordsEligible BIGINT OUTPUT ', @nbRecordsEligible OUTPUT

			SELECT @NBRecordsEligible =
				CASE WHEN @NBRecordsEligible < @BatchSize
				THEN @NBRecordsEligible
				ELSE @BatchSize
			END;

			IF @maxRecId = 0
			BEGIN
				SET @SQL = 'SELECT TOP ' + CONVERT(NVARCHAR, @NBRecordsEligible) + ' ' + Replace(@ColumnList,'#SourceTable',@Table) +
							' INTO ' + @BufferTABLEName + CONVERT(NVARCHAR, @nbBatchExecution) +
							' FROM ' + @Table +
							' ' + @JoinCondition + ' ' +
							' ORDER BY RecId DESC'
			END
			ELSE
			BEGIN
				IF (@NBRecordsEligible = @BatchSize)
				BEGIN
					SET @SQL = 'SELECT TOP ' + CONVERT(NVARCHAR, @NBRecordsEligible) + ' ' + Replace(@ColumnList,'#SourceTable',@Table) +
								' INTO ' + @BufferTABLEName + CONVERT(NVARCHAR, @nbBatchExecution) +
								' FROM ' + @Table +
								' ' + @JoinCondition + ' ' +
								' WHERE '+@Table+'.RecId < ' + CONVERT(NVARCHAR, @maxRecId) +
								' ORDER BY '+@Table+'.RecId DESC'
				END
				ELSE 
				BEGIN
						SET @SQL = 'SELECT TOP ' + CONVERT(NVARCHAR, @NBRecordsEligible) + ' ' + Replace(@ColumnList,'#SourceTable',@Table) +
								' INTO ' + @BufferTABLEName + CONVERT(NVARCHAR, @nbBatchExecution) +
								' FROM ' + @Table +
								' ' + @JoinCondition + ' ' +
								' WHERE '+@Table+'.RecId < ' + CONVERT(NVARCHAR, @maxRecId) 					
				END
			END
			PRINT @SQL
			EXEC sp_executesql @SQL
 
			-- Update maxRecId
			SET @SQL = 'SELECT @maxRecId = MIN(RecId) FROM ' + @BufferTABLEName + CONVERT(NVARCHAR, @nbBatchExecution)
			PRINT @SQL
			EXEC sp_executesql @SQL, N'@maxRecId BIGINT OUTPUT ', @maxRecId OUTPUT
 
			PRINT CONVERT(NVARCHAR(max),@maxRecId)

			if (@maxRecId is Null or @maxRecId = 0 )
			begin
				SET @SQL = 'DROP TABLE ' + QUOTENAME(@BufferTABLEName + CONVERT(NVARCHAR, @nbBatchExecution));
				EXEC sp_executesql @SQL; 
				set @HasMoreRecords = 0;
				break;
			end

			SET @nbBatchExecution = @nbBatchExecution + 1
 
 
			UPDATE DBCleanupResultsLog
			SET Step = @step, CurrentLoopIndex = @nbBatchExecution
			WHERE TableName = @Table AND LegalEntity = @LE AND KeepFromDate = @KeepFromDate AND StartTime = @RunTimestamp

		END
		SET @Interimend = GETDATE()
		SET @Duration = DATEDIFF(MILLISECOND, @Interimstart, @Interimend)
		Print 'copy from main table duraion in ms ' + convert(NVARCHAR,@Duration)
	END

	set @HasMoreRecords = 1;

	-- Simulation mode: Estimate duration of select, truncate, and insert statements and count records
	IF @Simulation = 1
    BEGIN
		IF @step = 1 or @step = 2 
		BEGIN
	--##Step2 Begin
			SET @step =  2
			SET @Interimstart = GETDATE()
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
				SET @nbBatchExecution = 1
			END 

			SET @Interimstart = GETDATE()
			WHILE @HasMoreRecords = 1
			BEGIN
										
					IF OBJECT_ID(@BufferTableDropPrefix+@BufferTABLEName+Convert(NVARCHAR,@nbBatchExecution)+'simulation') IS NOT NULL
					BEGIN
						SET @SQL = 'DROP TABLE '+@BufferTABLEName+Convert(NVARCHAR,@nbBatchExecution)+'simulation'
						EXEC sp_executesql @SQL
					END

					IF OBJECT_ID(@BufferTableDropPrefix+@BufferTABLEName+Convert(NVARCHAR,@nbBatchExecution)) IS NULL
					BEGIN
						SET @HasMoreRecords = 0;
						Break;
					END

					BEGIN TRANSACTION
					SET @SQL = 'SELECT * INTO '+  @BufferTABLEName+Convert(NVARCHAR,@nbBatchExecution)+'simulation' +' FROM '+@BufferTABLEName+Convert(NVARCHAR,@nbBatchExecution)
					print @SQL
					EXEC sp_executesql @SQL 
					COMMIT TRANSACTION

					SET @SQL = 'SELECT @maxRecId = MIN(RecId) FROM ' + @BufferTABLEName + CONVERT(NVARCHAR, @nbBatchExecution)
					PRINT @SQL
					EXEC sp_executesql @SQL, N'@maxRecId BIGINT OUTPUT ', @maxRecId OUTPUT
					
					-- Count records to be deleted in simulation mode
					SET @SQL = 'SELECT @SavedRecordsLoop = COUNT(*) FROM ' + @BufferTABLEName+Convert(NVARCHAR,@nbBatchExecution)+'simulation' 
					Print @SQL
					EXEC sp_executesql @SQL, N'@SavedRecordsLoop INT OUTPUT', @SavedRecordsLoop OUTPUT
					set @SavedRecords = @SavedRecords + @SavedRecordsLoop
					
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
				SET @nbBatchExecution = 1
			END 
			SET @Interimstart = GETDATE()
			WHILE @HasMoreRecords = 1
			BEGIN
					
					IF OBJECT_ID(@BufferTableDropPrefix+@BufferTABLEName+Convert(NVARCHAR,@nbBatchExecution)) IS NULL
					BEGIN
						SET @HasMoreRecords = 0
						Break;
					END

					BEGIN TRANSACTION
					SET @SQL = 'INSERT INTO ' + @Table + ' (' + Replace(@ColumnList,'#SourceTable.','') + ') SELECT ' + Replace(@ColumnList,'#SourceTable.','') + ' FROM '+@BufferTABLEName+Convert(NVARCHAR,@nbBatchExecution)
					print @SQL
					EXEC sp_executesql @SQL 
					COMMIT TRANSACTION

					SET @SQL = 'SELECT @maxRecId = MIN(RecId) FROM ' + @BufferTABLEName + CONVERT(NVARCHAR, @nbBatchExecution)
					PRINT @SQL
					EXEC sp_executesql @SQL, N'@maxRecId BIGINT OUTPUT ', @maxRecId OUTPUT

					-- Drop temporary table if it exists in tempdb
					IF OBJECT_ID(@BufferTableDropPrefix+@BufferTABLEName+Convert(NVARCHAR,@nbBatchExecution)) IS NOT NULL
					BEGIN
						SET @SQL = 'DROP TABLE '+@BufferTABLEName+Convert(NVARCHAR,@nbBatchExecution)
						EXEC sp_executesql @SQL
					END
					SET @nbBatchExecution = @nbBatchExecution +1

					Update DBCleanupResultsLog
					set Step = @step, CurrentLoopIndex = @nbBatchExecution
					where TableName = @Table AND LegalEntity = @LE AND KeepFromDate = @KeepFromDate and StartTime = @RunTimestamp


			END
			-- Count records to be deleted in simulation mode
			SET @SQL = 'SELECT @SavedRecords = COUNT(*) FROM ' + @Table
			Print @SQL
			EXEC sp_executesql @SQL, N'@SavedRecords INT OUTPUT', @SavedRecords OUTPUT

		END

		SET @Interimend = GETDATE()
		SET @Duration = DATEDIFF(MILLISECOND, @Interimstart, @Interimend)
		Print 'Copy Back data duration in ms ' + convert(NVARCHAR,@Duration)
		
    END

	print('Checkpoint 10')

    SET @EndTime = GETDATE()
        -- Calculate duration of operations in simulation mode
    SET @Duration = DATEDIFF(MILLISECOND, @StartTime, @EndTime)
	
	print ('Row counts' + convert(NVARCHAR,@RowCount))
	print ('saved records' + convert(NVARCHAR,@SavedRecords))
	set @DeletedRecords = @RowCount - @SavedRecords
	print ('deleted records' + convert(NVARCHAR,@DeletedRecords))



	Update DBCleanupResultsLog
		set Step = @step, CurrentLoopIndex = 0, NbRecordsDeleted = @DeletedRecords, NbRecordsSaved = @SavedRecords, EstimatedDuration = @Duration, EndTime = @EndTime
		where TableName = @Table AND LegalEntity = @LE AND KeepFromDate = @KeepFromDate and StartTime = @RunTimestamp

    -- Select results from log table for verification in simulation mode 
    SELECT * FROM DBCleanupResultsLog WHERE TableName=@Table AND LegalEntity=@LE AND KeepFromDate=CONVERT(NVARCHAR, @KeepFromDate, 120)

    -- Re-enable Change Data Capture or Change Tracking if previously enabled
    IF @CDCState = 1
    BEGIN
		SET @SQL = 'EXEC sys.sp_cdc_enable_table @source_schema = N''dbo'', @source_name = N''' + @Table + ''', @role_name = NULL'
        Print @SQL
		EXEC sp_executesql @SQL
    END
	BEGIN TRANSACTION
		SET @SQL = 'IF EXISTS (SELECT * FROM sys.change_tracking_tables WHERE object_id = OBJECT_ID(''' + @Table + ''')) ALTER TABLE ' + @Table + ' ENABLE CHANGE_TRACKING'
		Print @SQL
		EXEC sp_executesql @SQL
	COMMIT TRANSACTION
	
	Print 'Sp execution complete'
	IF @@TRANCOUNT > 0
		COMMIT TRANSACTION

END
