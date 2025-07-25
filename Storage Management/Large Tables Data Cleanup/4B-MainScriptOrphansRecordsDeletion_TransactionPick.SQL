DECLARE @OrphansJoinConditions NVARCHAR(MAX) = '
[
  {
    "TableName": "GENERALJOURNALACCOUNTENTRY",
	"JoinedTableName" : "GENERALJOURNALENTRY",
    "JoinCondition": "INNER JOIN GENERALJOURNALENTRY ON GENERALJOURNALACCOUNTENTRY.GENERALJOURNALENTRY = GENERALJOURNALENTRY.RECID"
  },
  {
    "TableName": "GENERALJOURNALACCOUNTENTRY_W",
	"JoinedTableName" : "GENERALJOURNALENTRY",
    "JoinCondition": "INNER JOIN GENERALJOURNALENTRY ON GENERALJOURNALACCOUNTENTRY_W.GENERALJOURNALENTRY = GENERALJOURNALENTRY.RECID"
  },
  {
    "TableName": "GENERALJOURNALENTRY_W",
	"JoinedTableName" : "GENERALJOURNALENTRY",
    "JoinCondition": "INNER JOIN GENERALJOURNALENTRY ON GENERALJOURNALENTRY_W.GENERALJOURNALENTRY = GENERALJOURNALENTRY.RECID"
  },
  {
    "TableName": "INVENTTRANSORIGIN",
	"JoinedTableName" : "INVENTTRANS",
    "JoinCondition": "INNER JOIN INVENTTRANS ON INVENTTRANSORIGIN.RECID = INVENTTRANS.INVENTTRANSORIGIN"
  }
]';
DECLARE @SQL NVARCHAR(MAX) = ''
DECLARE @LE NVARCHAR(Max)
DECLARE @KeepFromdate DATE
DECLARE @BatchSize INT = 500000
DECLARE @Resume BIT = 1
DECLARE @RowCounts BIGINT
DECLARE @Simulation BIT = 1 -- Set to 1 for simulation mode, 0 for actual deletion

-- Parse JSON and loop with cursor
CREATE TABLE #JoinParts (
    TableName NVARCHAR(100),
	JoinedTableName NVARCHAR(100),
    JoinCondition NVARCHAR(MAX)
);

INSERT INTO #JoinParts (TableName, JoinedTableName, JoinCondition)
SELECT TableName, JoinedTableName, JoinCondition
FROM OPENJSON(@OrphansJoinConditions)
WITH (
    TableName NVARCHAR(100),
	JoinedTableName NVARCHAR(100),
    JoinCondition NVARCHAR(MAX)
);

DECLARE join_cursor CURSOR FOR
SELECT TableName, JoinedTableName, JoinCondition FROM #JoinParts;

DECLARE @TableName NVARCHAR(100);
DECLARE @JoinedTableName NVARCHAR(100);
DECLARE @JoinCondition NVARCHAR(MAX);

OPEN join_cursor;
FETCH NEXT FROM join_cursor INTO @TableName, @JoinedTableName, @JoinCondition;

WHILE @@FETCH_STATUS = 0
BEGIN
    PRINT 'TABLENAME = ' + @TableName;
	PRINT 'JOINEDTABLENAME = ' + @JoinedTableName;
	PRINT 'JOINCONDITION = ' + @JoinCondition;
    PRINT '-----------------------------';


	select top 1 @LE = LegalEntity, @KeepFromdate = KeepFromDate from DBCLeanupresultslog where TableName = @JoinedTableName and EndTime is not null and NbRecordsDeleted >= 0 order by StartTime desc;

	PRINT 'LE = ' + @LE;
	PRINT 'KEEPFROMDATE = ' + CONVERT(NVARCHAR(MAX),@KeepFromDate);

	if (@KeepFromdate is not null)
	BEGIN
		
		SET @SQL = 'Select @RowCounts = count(*) from '+@TableName
		PRINT @SQL
		EXEC sp_executesql @SQL, N'@RowCounts BIGINT OUTPUT', @RowCounts OUTPUT

		PRINT 'Row Count = '+CONVERT(NVARCHAR(MAX),@RowCounts)

		EXEC [RemoveOrphansOnTablesWithoutDateTime]     
		@TableName,
		@LE,
		@KeepFromDate,
		@Simulation,
		@BatchSize, 
		@Resume,
		@RowCounts,
		@JoinCondition
		PRINT '[RemoveOrphansOnTablesWithoutDateTime] sp execution complete for table '+@TableName
 	END
	ELSE
	BEGIN
		SET @SQL = 'Select @RowCounts = count(*) from '+@TableName
		PRINT @SQL
		EXEC sp_executesql @SQL, N'@RowCounts BIGINT OUTPUT', @RowCounts OUTPUT

		PRINT 'Row Count = '+CONVERT(NVARCHAR(MAX),@RowCounts)

		EXEC [RemoveOrphansOnTablesWithoutDateTime]     
		@TableName,
		'',
		'',
		@Simulation,
		@BatchSize, 
		@Resume,
		@RowCounts,
		@JoinCondition
		PRINT '[RemoveOrphansOnTablesWithoutDateTime] sp execution complete for table '+@TableName
	END

    FETCH NEXT FROM join_cursor INTO @TableName, @JoinedTableName, @JoinCondition;
END

CLOSE join_cursor;
DEALLOCATE join_cursor;
DROP TABLE #JoinParts;
