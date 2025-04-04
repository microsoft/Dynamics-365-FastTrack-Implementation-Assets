/*
Description:
This script is designed to cleanup records from specified tables in a database. It uses a cursor to loop through the table names ordered by size (Data + Index) and calls a stored procedure to archive records based on the provided parameters.

Parameters:
- @Tables: List of tables to be archived (comma separated)
- @MaxArchivingDate: Maximum archiving date
- @Simulation: Set to 1 for simulation mode, 0 for actual deletion
- @LE: List of legal entities

The script performs the following steps:
1. Prints the legal entities and date range.
2. Inserts table names, row counts, and total space into a temporary table.
3. Loops through the table names using a cursor and calls the stored procedure to cleanup records.
4. Drops the stored procedure at the end.
*/

DECLARE @SkipTables NVARCHAR(MAX) = 'MyTable1,MyTable2,Myatble3' -- Replace with your list of tables (comma separated)
DECLARE @MaxArchivingDate DATE = '2023-07-01' -- Replace with your max archiving date
DECLARE @Simulation BIT = 1 -- Set to 1 for simulation mode, 0 for actual deletion
DECLARE @LE NVARCHAR(Max) = 'MS,445I,BRMF,CNMF,DAT,DEMF,FRRT,FRSI,GBPM,GBSI,GLCO,GLMF,GLRT,GLSI,INMF,ITCO,JPMF,MXMF,MYMF,RUMF,RURT,SAMF,THMF,THPM,us01,USMF,USP2,USPI,USPM,USRT,USSI'
DECLARE @TOPXTables int = 10
DECLARE @Threshold INT = 500000
DECLARE @BatchSize INT = 500000
DECLARE @Resume BIT = 0

DECLARE @TableName NVARCHAR(255)
DECLARE @TotalSpace BigINt
DECLARE @StartDate DATE
DECLARE @EndDate DATE

BEGIN

    -- Create DBCleanupResultsLog table if it doesn't exist
    IF NOT EXISTS (SELECT * FROM sysobjects WHERE name='DBCleanupResultsLog' AND xtype='U')
    BEGIN
        CREATE TABLE DBCleanupResultsLog(
            TableName NVARCHAR(1000),
            LegalEntity NVARCHAR(1000),
            KeepFromDate NVARCHAR(120),
            NbRecordsDeleted INT,
			NbRecordsSaved INT,
            EstimatedDuration INT,
            StartTime DATETIME,
			EndTime DATETIME,
			Step INT,
			CurrentLoopIndex INT
        )
		CREATE INDEX idx_DBCleanupResultsLog_EndTime_StartTime_TableName_LegalEntity_KeepFromDate
		ON DBCleanupResultsLog (EndTime, StartTime, TableName, LegalEntity, KeepFromDate);
			   
    END

    PRINT 'LE :' + @LE + ' StartDate :' + CONVERT(NVARCHAR, @StartDate, 120) + ' EndDate :' + CONVERT(NVARCHAR, @EndDate, 120)
    
	    -- Drop temporary table if it exists in tempdb
    IF OBJECT_ID('FTDBCLEANUPLISTTABLES') IS NOT NULL
    BEGIN
        Declare @SQL NVARCHAR(MAX) = 'DROP TABLE FTDBCLEANUPLISTTABLES'
        EXEC sp_executesql @SQL
    END


    -- Cursor to loop through the table names ordered by size (Data + Index	)
	SELECT * INTO FTDBCLEANUPLISTTABLES FROM 
        (
		SELECT 
            t.name AS TableName,
            SUM(p.rows) AS RowCounts,
            SUM(a.total_pages) * 8 AS TotalSpace,
			sdf.TABLEID as TableId
        FROM
            sys.tables t
        INNER JOIN
            sys.indexes i ON t.object_id = i.object_id
        INNER JOIN
            sys.partitions p ON i.object_id = p.object_id AND i.index_id = p.index_id
        INNER JOIN
            sys.allocation_units a ON p.partition_id = a.container_id
		inner join (select SQLName,TABLEID from SQLDICTIONARY sd where sd.FIELDID = 0 and sd.ARRAY = 0) sdf on t.name = sdf.SQLNAME
		inner join TABLEMETADATATABLE TMT ON TMT.TABLEID = sdf.TABLEID
		where SDF.SQLNAME not in (SELECT value FROM STRING_SPLIT(@SkipTables, ',')) and (TMT.TABLEGROUP IN (4, 5, 6, 9, 10, 11) or SDF.SQLNAME in ('WHSASNITEM', 'WHSASNITEMRECEIPT', 'WHSUOMSTRUCTURE'))
        GROUP BY 
			t.name, sdf.TABLEID
			) orderedTables

    DECLARE TableCursor CURSOR FOR
    SELECT Top (@TOPXTables) TableName, TotalSpace FROM FTDBCLEANUPLISTTABLES
    ORDER BY TotalSpace DESC

    OPEN TableCursor
    FETCH NEXT FROM TableCursor INTO @TableName, @TotalSpace
    WHILE @@FETCH_STATUS = 0
    BEGIN
        -- Call stored procedure to archive records for the current table
		Print 'Table : '+@TableName+ ' totalspace : '+CONVERT(NVARCHAR,@TotalSpace)
		BEGIN TRY
			EXEC KeepOnlyRecordsSp @TableName, @LE, @MaxArchivingDate, @Simulation, @Threshold, @BatchSize, @Resume
		END TRY
		BEGIN CATCH
			PRINT ('Error while processing Table '+@TableName+'')
		END CATCH
		FETCH NEXT FROM TableCursor INTO @TableName, @TotalSpace
    END
    
    CLOSE TableCursor
    DEALLOCATE TableCursor

END

-- Drop the stored procedure at the end
--DROP table dbo.DBCleanupResultsLog
--DROP PROCEDURE dbo.KeepOnlyRecordsSp;
DROP TABLE dbo.FTDBCLEANUPLISTTABLES;
