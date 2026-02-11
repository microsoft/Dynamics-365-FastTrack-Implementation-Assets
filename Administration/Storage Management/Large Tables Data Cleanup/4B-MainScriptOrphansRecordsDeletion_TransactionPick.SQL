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
DECLARE @BatchSize INT = 200000
DECLARE @Resume BIT = 1
DECLARE @RowCounts BIGINT
DECLARE @Simulation BIT = 0 -- Set to 1 for simulation mode, 0 for actual deletion

IF OBJECT_ID('tempdb..#JoinParts') IS NOT NULL
    DROP TABLE #JoinParts;

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

DECLARE @StartTime DATETIME2, @EndTime DATETIME2, @DurationSeconds INT;

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

	-- Check for CreatedDateTime and ModifiedDateTime fields
	IF @Simulation = 0
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
	        AND i.is_unique_constraint = 0
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
	END
	
	PRINT 'Duration for table ' + @TableName + ': ' + CAST(@DurationSeconds AS VARCHAR(10)) + ' seconds';

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


DECLARE join_cursor_2 CURSOR FOR
SELECT TableName, JoinedTableName, JoinCondition FROM #JoinParts;

OPEN join_cursor_2;
FETCH NEXT FROM join_cursor_2 INTO @TableName, @JoinedTableName, @JoinCondition;

WHILE @@FETCH_STATUS = 0
BEGIN
	Print 'rebuild index table '+ @TableName

	-- Capture start time
	SET @StartTime = SYSDATETIME();
		
	IF @Simulation = 0
	BEGIN
	
		PRINT 'Rebuilding indexes for table: ' + @TableName;
		
		-- Call stored procedure to rebuild disabled nonclustered indexes for the current table
		EXEC dbo.RebuildDisabledNonclusteredIndexes
		     @TargetDOP             = 1,        -- MAXDOP = 1 as requested
		     @UseOnline             = 1,        -- Azure SQL supports ONLINE
		     @UseLowPriorityWait    = 1,        -- WAIT_AT_LOW_PRIORITY nested in ONLINE
		     @PauseBetweenItemsMs   = 2000,
		     @PauseBetweenBatchesMs = 3000,
		     @ItemsPerBatch         = 5,
		     @FilterTablesCsv       = @TableName,  -- single table, no schema, no spaces
		     @SkipIndexesCsv        = NULL;        -- or provide a CSV to skip specific indexes
		
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
	END
	-- Capture end time and calculate duration
	SET @EndTime = SYSDATETIME();
	SET @DurationSeconds = DATEDIFF(SECOND, @StartTime, @EndTime);

	PRINT 'Duration for table ' + @TableName + ': ' + CAST(@DurationSeconds AS VARCHAR(10)) + ' seconds';

    FETCH NEXT FROM join_cursor_2 INTO @TableName, @JoinedTableName, @JoinCondition;
END

CLOSE join_cursor_2;
DEALLOCATE join_cursor_2;
DROP TABLE #JoinParts;


