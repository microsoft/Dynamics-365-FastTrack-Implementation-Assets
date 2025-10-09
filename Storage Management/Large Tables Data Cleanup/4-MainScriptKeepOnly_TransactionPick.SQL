/*
Description:
This script is designed to cleanup records from specified tables in a database. It uses a cursor to loop through the table names ordered by size (Data + Index) and calls a stored procedure to archive records based on the provided parameters.
 
Parameters:
- @Tables: List of tables to be archived (comma separated)
- @MaxArchivingDate: Maximum archiving date
- @Simulation: Set to 1 for simulation mode, 0 for actual deletion
- @LE: List of legal entities
- @MaxThruputInMB: Size of each batch for processing records (default is 100 GB)
- @Resume: Set to 1 to resume from previous run, 0 for fresh run (default is 1)
 
The script performs the following steps:
1. Prints the legal entities and date range.
2. Inserts table names, row counts, and total space into a temporary table.
3. Loops through the table names using a cursor and calls the stored procedure to cleanup records.
4. Drops the temporary table at the end.
*/ 
/*
*/

-- Tables to exclude anyway BATCHHISTORY, BATCHJOB, BATCH, BATCHJOBHISTORY,Sysdatabaselog
DECLARE @SkipTables NVARCHAR(MAX) = 'BATCHHISTORY,BATCH,SYSDATABASELOG,BATCHJOB,BATCHJOBHISTORY' -- Replace with your list of tables (comma separated)
DECLARE @SELECTEDTABLES NVARCHAR(MAX) = '' -- Replace with your list of tables you want to run the script for (comma separated)
DECLARE @MaxArchivingDate DATE = '2025-03-01' -- Replace with your max archiving date
DECLARE @Simulation BIT = 0 -- Set to 1 for simulation mode, 0 for actual deletion
DECLARE @LE NVARCHAR(Max) = '2002,1003,1005,3003,3023,3104,3105,3106,3107,3109,3200,8900,1002,1004,2001,2003,2004,2005,2006,2011,3002,3004,3021,3101,3110,3111,3112,3400,3902,4004,6001,6002,6004,6006,6008,8000,8001,8010,9003,1001,7000,6003,7100,8020,9006,9008,9036,9068,1901,1904,1905,2010,2901,2904,2905,3001,3020,3100,3102,3103,3300,3301,3302,3304,3305,3306,3307,3308,3309,3310,3316,3901,4904,6005,6007,6905,8901,9001,9004,9005,9007,9009,9010,9011,9012,9013,9014,9015,9016,9017,9018,9019,9020,9021,9022,9023,9024,9026,9027,9028,9031,9032,9033,9034,9035,9037,9038,9039,9040,9044,9048,9050,9051,9064,9075,9912,9914,9918,9919,9923,9939,3904,3905,4001,5001,3113,3115,3114,3116,5600,1000,2000'
DECLARE @TOPXTables INT = 50
DECLARE @MaxThruputInMB BIGINT = 512 --Lower if you get an sql throttling errors
DECLARE @Resume BIT = 1
DECLARE @IncludeTablesWithoutDataarea BIT = 1
 
DECLARE @BatchSize BIGINT 
DECLARE @TableName NVARCHAR(255)
DECLARE @TotalSpace BIGINT
DECLARE @RowCounts BIGINT
DECLARE @RowSize BIGINT
DECLARE @StartDate DATE
DECLARE @EndDate DATE
DECLARE @semaacquired INT
DECLARE @tempTableListTableName NVARCHAR(255) = 'FTDBCLEANUPLISTTABLES' + CONVERT(NVARCHAR, @@SPID)
DECLARE @SQL NVARCHAR(MAX) = ''
DECLARE @StartTime DATETIME2, @EndTime DATETIME2, @DurationSeconds INT;
 
BEGIN 
    -- Create the log table if it doesn't exist
    BEGIN TRANSACTION
    EXEC CreateDBCleanup
    COMMIT TRANSACTION
 
    PRINT 'LE :' + @LE + ' StartDate :' + CONVERT(NVARCHAR, @StartDate, 120) + ' EndDate :' + CONVERT(NVARCHAR, @EndDate, 120)
    -- Drop temporary table if it exists in tempdb
    IF OBJECT_ID(@tempTableListTableName) IS NOT NULL
    BEGIN
        SET @SQL = 'DROP TABLE ' + @tempTableListTableName
        EXEC sp_executesql @SQL
    END
 
	DECLARE @MaxThruputinB BIGINT = (@MaxThruputInMB*1024*1024)
    -- Insert table names, row counts, and total space into a temporary table ordered by size (Data + Index)
    SET @SQL = 'SELECT *, TotalSpace/(RowCounts+1) as RowSize, ('+ convert(NVARCHAR,@MaxThruputinB) +'/ ((TotalSpace/(RowCounts+1))+1024)) as BatchSize INTO ' + @tempTableListTableName + ' FROM 
        (
        SELECT 
            t.name AS TableName,
            SUM(p.rows) / count(a.container_id)  AS RowCounts,
            SUM(a.total_pages)*8*1024 AS TotalSpace,
            sdf.TABLEID AS TableId
        FROM
            sys.tables t
        INNER JOIN
            sys.indexes i ON t.object_id = i.object_id
        INNER JOIN
            sys.partitions p ON i.object_id = p.object_id AND i.index_id = p.index_id
        INNER JOIN
            sys.allocation_units a ON p.partition_id = a.container_id
        INNER JOIN (SELECT SQLName, TABLEID FROM SQLDICTIONARY sd WHERE sd.FIELDID = 0 AND sd.ARRAY = 0) sdf ON t.name = sdf.SQLNAME
        INNER JOIN TABLEMETADATATABLE TMT ON TMT.TABLEID = sdf.TABLEID
        WHERE '
		IF @SELECTEDTABLES != ''
		BEGIN
		SET @SQL = @SQL + 'SDF.SQLNAME IN (SELECT value FROM STRING_SPLIT(''' + @SELECTEDTABLES + ''', '','')) AND '
		END 
		SET @SQL = @SQL + ' SDF.SQLNAME NOT IN (SELECT value FROM STRING_SPLIT(''' + @SkipTables + ''', '','')) AND (TMT.TABLEGROUP IN (4, 5, 6, 9, 10, 11) OR SDF.SQLNAME IN (''WHSASNITEM'', ''WHSASNITEMRECEIPT'', ''WHSUOMSTRUCTURE''))
        GROUP BY 
            t.name, sdf.TABLEID
        ) orderedTables';
 
    PRINT @SQL
    EXEC sp_executesql @SQL
 
    -- Declare and open cursor to loop through the table names ordered by size (Data + Index)
    SET @SQL = '    
        IF CURSOR_STATUS(''global'', ''Cursor' + CONVERT(NVARCHAR, @@SPID) + ''') >=0
        BEGIN
            CLOSE Cursor' + CONVERT(NVARCHAR, @@SPID) + '
            DEALLOCATE Cursor' + CONVERT(NVARCHAR, @@SPID) + '
        END
 
        DECLARE Cursor' + CONVERT(NVARCHAR, @@SPID) + ' CURSOR FOR SELECT TOP (' + CONVERT(NVARCHAR, @TOPXTables) + ') TableName, TotalSpace, RowCounts, RowSize, BatchSize FROM ' + @tempTableListTableName + ' ORDER BY TotalSpace DESC
        OPEN Cursor' + CONVERT(NVARCHAR, @@SPID) + '
        FETCH NEXT FROM Cursor' + CONVERT(NVARCHAR, @@SPID) + ' INTO @TableName, @TotalSpace, @RowCounts, @RowSize, @BatchSize ';
 
    EXEC sp_executesql @SQL, N'@TableName NVARCHAR(255) OUTPUT, @TotalSpace BIGINT OUTPUT, @RowCounts BIGINT OUTPUT, @RowSize BIGINT OUTPUT, @BatchSize BIGINT OUTPUT', @TableName OUTPUT, @TotalSpace OUTPUT, @RowCounts OUTPUT,@RowSize OUTPUT, @BatchSize OUTPUT

    WHILE @@FETCH_STATUS = 0
    BEGIN
        -- Call stored procedure to archive records for the current table
        PRINT 'Table : ' + @TableName + ' totalspace : ' + CONVERT(NVARCHAR, @TotalSpace) + ' Rowcounts : ' + CONVERT(NVARCHAR, @RowCounts) + ' Rowsize : ' + CONVERT(NVARCHAR, @RowSize) + ' BatchSize : ' + CONVERT(NVARCHAR, @BatchSize)
        BEGIN TRY

			-- Check for CreatedDateTime and ModifiedDateTime fields
			DECLARE @DateField NVARCHAR(255) = ''
			SELECT @DateField = CleanupColumn FROM FTDateTimeColumnMappingPerTable WHERE TABLE_NAME = @TableName
			IF @DateField != ''
			BEGIN
				SET @SQL = '';
				-- Disable all non clustered indexes and triggers
				SELECT @SQL += 'ALTER INDEX [' + i.name + '] ON [' + s.name + '].[' + t.name + '] DISABLE;'
				FROM sys.indexes i
				JOIN sys.tables t ON i.object_id = t.object_id
				JOIN sys.schemas s ON t.schema_id = s.schema_id
				WHERE i.type = 2
					AND i.is_unique = 0
					AND i.is_disabled = 0
					AND i.is_primary_key = 0
					AND i.is_unique_constraint =0
					AND t.name = @TableName;

				print @SQL
				EXEC sp_executesql @SQL;
	
				-- Disable all triggers
				SET @SQL = '';

				SELECT @SQL += 'DISABLE TRIGGER [' + tr.name + '] ON [' + s.name + '].[' + t.name + '];'
				FROM sys.triggers tr
				JOIN sys.tables t ON tr.parent_id = t.object_id
				JOIN sys.schemas s ON t.schema_id = s.schema_id
				WHERE
					tr.is_disabled  = 0 AND
					t.name = @TableName;
				print @SQL
				EXEC sp_executesql @SQL;

				-- Acquire a semaphore
				EXEC @semaacquired = sp_getapplock @Resource = @TableName, @LockMode = 'Exclusive', @LockOwner = 'Session', @LockTimeout = 10000
          
			
				IF @semaacquired >= 0
				BEGIN
					-- The semaphore was acquired successfully
					PRINT 'Semaphore acquired'

				
					EXEC KeepOnlyRecordsSp @TableName, @LE, @MaxArchivingDate, @Simulation, @BatchSize, @Resume, @RowCounts, @IncludeTablesWithoutDataarea
					PRINT 'Keeponlyrecords sp execution complete for table '+@TableName
					-- Release the semaphore
					EXEC sp_releaseapplock @Resource = @TableName, @LockOwner = 'Session'
					PRINT 'Semaphore released'
				END
				ELSE
				BEGIN
					-- Failed to acquire the semaphore
					PRINT 'Failed to acquire semaphore'
				END
				IF @@TRANCOUNT > 0
					COMMIT TRANSACTION
			
			END
			SET @SQL = 'FETCH NEXT FROM Cursor' + CONVERT(NVARCHAR, @@SPID) + ' INTO @TableName, @TotalSpace, @RowCounts, @RowSize, @BatchSize'
			EXEC sp_executesql @SQL, N'@TableName NVARCHAR(255) OUTPUT, @TotalSpace BIGINT OUTPUT, @RowCounts BIGINT OUTPUT, @RowSize BIGINT OUTPUT, @BatchSize BIGINT OUTPUT', @TableName OUTPUT, @TotalSpace OUTPUT, @RowCounts OUTPUT,@RowSize OUTPUT, @BatchSize OUTPUT
        END TRY
        BEGIN CATCH
            PRINT ('Error while processing Table ' + @TableName)
            IF @semaacquired >= 0
            BEGIN
                EXEC sp_releaseapplock @Resource = @TableName, @LockOwner = 'Session'
            END
			IF @@TRANCOUNT > 0
				COMMIT TRANSACTION
			SET @SQL = 'FETCH NEXT FROM Cursor' + CONVERT(NVARCHAR, @@SPID) + ' INTO @TableName, @TotalSpace, @RowCounts, @RowSize, @BatchSize'
			EXEC sp_executesql @SQL, N'@TableName NVARCHAR(255) OUTPUT, @TotalSpace BIGINT OUTPUT, @RowCounts BIGINT OUTPUT, @RowSize BIGINT OUTPUT, @BatchSize BIGINT OUTPUT', @TableName OUTPUT, @TotalSpace OUTPUT, @RowCounts OUTPUT,@RowSize OUTPUT, @BatchSize OUTPUT

        END CATCH
    END
 
    SET @SQL = 'CLOSE Cursor' + CONVERT(NVARCHAR, @@SPID) + '
                DEALLOCATE Cursor' + CONVERT(NVARCHAR, @@SPID)
    EXEC sp_executesql @SQL
 
END

-- Drop the temporary table at the end
IF OBJECT_ID(@tempTableListTableName) IS NOT NULL
BEGIN
    
    SET @SQL = '    
        IF CURSOR_STATUS(''global'', ''Cursor' + CONVERT(NVARCHAR, @@SPID) + ''') >=0
        BEGIN
            CLOSE Cursor' + CONVERT(NVARCHAR, @@SPID) + '
            DEALLOCATE Cursor' + CONVERT(NVARCHAR, @@SPID) + '
        END
 
        DECLARE Cursor' + CONVERT(NVARCHAR, @@SPID) + ' CURSOR FOR SELECT TOP (' + CONVERT(NVARCHAR, @TOPXTables) + ') TableName, TotalSpace, RowCounts, RowSize, BatchSize FROM ' + @tempTableListTableName + ' ORDER BY TotalSpace DESC
        OPEN Cursor' + CONVERT(NVARCHAR, @@SPID) + '
        FETCH NEXT FROM Cursor' + CONVERT(NVARCHAR, @@SPID) + ' INTO @TableName, @TotalSpace, @RowCounts, @RowSize, @BatchSize ';
 
    EXEC sp_executesql @SQL, N'@TableName NVARCHAR(255) OUTPUT, @TotalSpace BIGINT OUTPUT, @RowCounts BIGINT OUTPUT, @RowSize BIGINT OUTPUT, @BatchSize BIGINT OUTPUT', @TableName OUTPUT, @TotalSpace OUTPUT, @RowCounts OUTPUT,@RowSize OUTPUT, @BatchSize OUTPUT

	WHILE @@FETCH_STATUS = 0
	BEGIN
		
		-- Check for CreatedDateTime and ModifiedDateTime fields
		DECLARE @DateFieldRebuild NVARCHAR(255) = ''
		SELECT @DateFieldRebuild = CleanupColumn FROM FTDateTimeColumnMappingPerTable WHERE TABLE_NAME = @TableName
		IF @DateFieldRebuild != ''
		BEGIN
			Print 'rebuild index table '+ @TableName

			-- Capture start time
			SET @StartTime = SYSDATETIME();

			SET @SQL = '';
			-- Rebuild all non-clustered indexes
			SELECT @SQL += 'ALTER INDEX [' + i.name + '] ON [' + s.name + '].[' + t.name + '] REBUILD WITH (MAXDOP = 16);'
			FROM sys.indexes i
			JOIN sys.tables t ON i.object_id = t.object_id
			JOIN sys.schemas s ON t.schema_id = s.schema_id
			WHERE i.type = 2
				AND i.is_unique = 0
				AND i.is_disabled = 1
				AND i.is_primary_key = 0
				AND i.is_unique_constraint =0
				AND t.name = @TableName
				AND i.name LIKE 'I_%';

			PRINT 'Rebuilding indexes for table: ' + @TableName;
			PRINT @SQL;
			EXEC sp_executesql @SQL;

			-- Enable all triggers
			SET @SQL = '';
			SELECT @SQL += 'ENABLE TRIGGER [' + tr.name + '] ON [' + s.name + '].[' + t.name + '];'
			FROM sys.triggers tr
			JOIN sys.tables t ON tr.parent_id = t.object_id
			JOIN sys.schemas s ON t.schema_id = s.schema_id
			WHERE
				tr.is_disabled  = 1 AND
				t.name = @TableName;


			PRINT @SQL;
			EXEC sp_executesql @SQL;

			-- Capture end time and calculate duration
			SET @EndTime = SYSDATETIME();
			SET @DurationSeconds = DATEDIFF(SECOND, @StartTime, @EndTime);

			PRINT 'Duration for table ' + @TableName + ': ' + CAST(@DurationSeconds AS VARCHAR(10)) + ' seconds';
		END
		-- Fetch next
		SET @SQL = 'FETCH NEXT FROM Cursor' + CONVERT(NVARCHAR, @@SPID) + ' INTO @TableName, @TotalSpace, @RowCounts, @RowSize, @BatchSize';
		EXEC sp_executesql @SQL,
			N'@TableName NVARCHAR(255) OUTPUT, @TotalSpace BIGINT OUTPUT, @RowCounts BIGINT OUTPUT, @RowSize BIGINT OUTPUT, @BatchSize BIGINT OUTPUT',
			@TableName OUTPUT, @TotalSpace OUTPUT, @RowCounts OUTPUT, @RowSize OUTPUT, @BatchSize OUTPUT;

    END
 
    SET @SQL = 'CLOSE Cursor' + CONVERT(NVARCHAR, @@SPID) + '
                DEALLOCATE Cursor' + CONVERT(NVARCHAR, @@SPID)
    EXEC sp_executesql @SQL

	
	SET @SQL = 'DROP TABLE ' + @tempTableListTableName
    EXEC sp_executesql @SQL
END

