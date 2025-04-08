/*
Description:
This script is designed to cleanup records from specified tables in a database. It uses a cursor to loop through the table names ordered by size (Data + Index) and calls a stored procedure to archive records based on the provided parameters.

Parameters:
- @Tables: List of tables to be archived (comma separated)
- @MaxArchivingDate: Maximum archiving date
- @Simulation: Set to 1 for simulation mode, 0 for actual deletion
- @LE: List of legal entities
- @Threshold: Threshold value to determine buffer table usage (default is 500000)
- @BatchSize: Size of each batch for processing records (default is 500000)
- @Resume: Set to 1 to resume from previous run, 0 for fresh run (default is 1)

The script performs the following steps:
1. Prints the legal entities and date range.
2. Inserts table names, row counts, and total space into a temporary table.
3. Loops through the table names using a cursor and calls the stored procedure to cleanup records.
4. Drops the temporary table at the end.
*/

DECLARE @SkipTables NVARCHAR(MAX) = 'MyTable1,MyTable2,Myatble3' -- Replace with your list of tables (comma separated)
DECLARE @MaxArchivingDate DATE = '2023-07-01' -- Replace with your max archiving date
DECLARE @Simulation BIT = 1 -- Set to 1 for simulation mode, 0 for actual deletion
DECLARE @LE NVARCHAR(Max) = 'MS,445I,BRMF,CNMF,DAT,DEMF,FRRT,FRSI,GBPM,GBSI,GLCO,GLMF,GLRT,GLSI,INMF,ITCO,JPMF,MXMF,MYMF,RUMF,RURT,SAMF,THMF,THPM,us01,USMF,USP2,USPI,USPM,USRT,USSI'
DECLARE @TOPXTables INT = 10
DECLARE @Threshold INT = 500000
DECLARE @BatchSize INT = 500000
DECLARE @Resume BIT = 1

DECLARE @TableName NVARCHAR(255)
DECLARE @TotalSpace BIGINT
DECLARE @StartDate DATE
DECLARE @EndDate DATE
DECLARE @semaacquired INT
DECLARE @tempTableListTableName NVARCHAR(255) = 'FTDBCLEANUPLISTTABLES' + CONVERT(NVARCHAR, @@SPID)
DECLARE @SQL NVARCHAR(MAX) = ''

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

    -- Insert table names, row counts, and total space into a temporary table ordered by size (Data + Index)
    SET @SQL = 'SELECT * INTO ' + @tempTableListTableName + ' FROM 
        (
        SELECT 
            t.name AS TableName,
            SUM(p.rows) AS RowCounts,
            SUM(a.total_pages) * 8 AS TotalSpace,
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
        WHERE SDF.SQLNAME NOT IN (SELECT value FROM STRING_SPLIT(''' + @SkipTables + ''', '','')) AND (TMT.TABLEGROUP IN (4, 5, 6, 9, 10, 11) OR SDF.SQLNAME IN (''WHSASNITEM'', ''WHSASNITEMRECEIPT'', ''WHSUOMSTRUCTURE''))
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

        DECLARE Cursor' + CONVERT(NVARCHAR, @@SPID) + ' CURSOR FOR SELECT TOP (' + CONVERT(NVARCHAR, @TOPXTables) + ') TableName, TotalSpace FROM ' + @tempTableListTableName + ' ORDER BY TotalSpace DESC
        OPEN Cursor' + CONVERT(NVARCHAR, @@SPID) + '
        FETCH NEXT FROM Cursor' + CONVERT(NVARCHAR, @@SPID) + ' INTO @TableName, @TotalSpace';

    EXEC sp_executesql @SQL, N'@TableName NVARCHAR(255) OUTPUT, @TotalSpace BIGINT OUTPUT', @TableName OUTPUT, @TotalSpace OUTPUT

    WHILE @@FETCH_STATUS = 0
    BEGIN
        -- Call stored procedure to archive records for the current table
        PRINT 'Table : ' + @TableName + ' totalspace : ' + CONVERT(NVARCHAR, @TotalSpace)
        BEGIN TRY
            
            -- Acquire a semaphore
            EXEC @semaacquired = sp_getapplock @Resource = @TableName, @LockMode = 'Exclusive', @LockOwner = 'Session', @LockTimeout = 10000

            IF @semaacquired >= 0
            BEGIN
                -- The semaphore was acquired successfully
                PRINT 'Semaphore acquired'

                EXEC KeepOnlyRecordsSp @TableName, @LE, @MaxArchivingDate, @Simulation, @Threshold, @BatchSize, @Resume

                -- Release the semaphore
                EXEC sp_releaseapplock @Resource = @TableName, @LockOwner = 'Session'
                PRINT 'Semaphore released'
            END
            ELSE
            BEGIN
                -- Failed to acquire the semaphore
                PRINT 'Failed to acquire semaphore'
            END

        END TRY
        BEGIN CATCH
            PRINT ('Error while processing Table ' + @TableName)
            
            IF @semaacquired >= 0
            BEGIN
                EXEC sp_releaseapplock @Resource = @TableName, @LockOwner = 'Session'
            END
            COMMIT TRANSACTION
        END CATCH
        
        SET @SQL = 'FETCH NEXT FROM Cursor' + CONVERT(NVARCHAR, @@SPID) + ' INTO @TableName, @TotalSpace'
        EXEC sp_executesql @SQL, N'@TableName NVARCHAR(255) OUTPUT, @TotalSpace BIGINT OUTPUT', @TableName OUTPUT, @TotalSpace OUTPUT
        
    END

    SET @SQL = 'CLOSE Cursor' + CONVERT(NVARCHAR, @@SPID) + '
                DEALLOCATE Cursor' + CONVERT(NVARCHAR, @@SPID)
    EXEC sp_executesql @SQL

END

-- Drop the temporary table at the end
IF OBJECT_ID(@tempTableListTableName) IS NOT NULL
BEGIN
    SET @SQL = 'DROP TABLE ' + @tempTableListTableName
    EXEC sp_executesql @SQL
END
