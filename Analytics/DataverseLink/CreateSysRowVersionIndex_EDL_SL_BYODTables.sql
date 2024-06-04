-- FnO Tables that needs to be added to Synapse link requires index created on SysRowVersion.
-- Bellow script identify and create required index for synapse link added tables potential tables that you may want to add (BYOD or Export to data lake table)
declare @tablelist nvarchar(max);
declare @additionaltables nvarchar(max) = 'srsanalysisenums';

select  @tablelist = string_agg(convert(nvarchar(max),TABLENAME), ',')
from (
	select distinct TABLENAME
	from (
			-- Tables with Export to data lake Enabled in the environment 
			select DATAFEEDNAME as TABLENAME from DATAFEEDSTABLESCACHE where Status = 2
			union
			--Tables with BYOD enabled in the environment 
			select TABLENAME from AIFSQLCHANGETRACKINGENABLEDTABLES
			union
			--Tables with Synapse link enabled in the environment
			select PHYSICALTABLENAME as TABLENAME from AIFSQLROWVERSIONCHANGETRACKINGENABLEDTABLES
			
			union 
			select value as TableName from string_split(@additionaltables, ',') 
	) x
) y

print('TableList:' +@tablelist)

DECLARE @SchemaName NVARCHAR(MAX) = 'dbo';
DECLARE @TableId INT;
DECLARE @TableName NVARCHAR(250);
DECLARE @SQLStmt NVARCHAR(MAX);
DECLARE @SlNo INT = 0;



DECLARE Table_cursor CURSOR LOCAL FOR
SELECT T.ID, T.Name
 FROM TABLEIDTABLE T
 WHERE T.Name in ( select value from string_split(@tablelist, ','))

OPEN Table_cursor;
FETCH NEXT FROM Table_cursor INTO @TableId, @TableName;
WHILE @@FETCH_STATUS = 0
BEGIN
	BEGIN TRY
		BEGIN TRAN
			BEGIN
				-- Script timeout in milliseconds
				SET LOCK_TIMEOUT 1000;
				SET @SlNo = @SlNo + 1;

				-- Add SYSROWVERSION index
				IF NOT EXISTS (SELECT TOP 1 1
					FROM sys.indexes i
					INNER JOIN sys.index_columns ic ON ic.index_id = i.index_id AND ic.object_id = i.object_id
					INNER JOIN sys.columns c ON c.object_id = ic.object_id AND c.column_id = ic.column_id
					INNER JOIN sys.tables t ON t.object_id = c.object_id
					INNER JOIN sys.schemas s ON s.schema_id = t.schema_id
					WHERE s.name = @SchemaName AND ic.index_column_id = 1 AND ic.is_included_column = 0 AND t.name = @TableName AND c.name = 'SYSROWVERSION'
					)
				BEGIN
					SET @SQLStmt = '
					CREATE NONCLUSTERED INDEX AIF_I_' + CAST(@TableId as nvarchar) + 'SQLROWVERSIONIDX
					ON ' + @SchemaName + '.' + @TableName + ' ([SYSROWVERSION] ASC)
					WITH (ONLINE = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = ON)
					ON [PRIMARY]
					';
					EXEC sp_executesql @SQLStmt;
					print @SQLStmt;
				END

				-- Add RECID index
				IF NOT EXISTS (SELECT TOP 1 1
					FROM sys.indexes i
					INNER JOIN sys.index_columns ic ON ic.index_id = i.index_id AND ic.object_id = i.object_id
					INNER JOIN sys.columns c ON c.object_id = ic.object_id AND c.column_id = ic.column_id
					INNER JOIN sys.tables t ON t.object_id = c.object_id
					INNER JOIN sys.schemas s ON s.schema_id = t.schema_id
					WHERE s.name = @SchemaName AND ic.index_column_id = 1 AND ic.is_included_column = 0 AND t.name = @TableName AND c.name = 'RECID'
					)
				BEGIN
					SET @SQLStmt = '
					CREATE NONCLUSTERED INDEX AIF_I_' + CAST(@TableId as nvarchar) + 'RECIDDATASYNCIDX
					ON ' + @SchemaName + '.' + @TableName + ' ([RECID] ASC)
					WITH (ONLINE = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = ON)
					ON [PRIMARY]
					';
					EXEC sp_executesql @SQLStmt;
					print @SQLStmt;
				END

				SET LOCK_TIMEOUT 0;
			END
		COMMIT TRAN
		print cast(@SlNo as nvarchar) + '. ' + @SchemaName + '.' + @TableName + '(' + cast(@TableId as nvarchar) + ') => succeeded'
	END TRY
	BEGIN CATCH
		print cast(@SlNo as nvarchar) + '. ' + @SchemaName + '.' + @TableName + '(' + cast(@TableId as nvarchar) + ') => SQL error[' + cast(ERROR_NUMBER() as nvarchar) + '] : ' + ERROR_MESSAGE()
		ROLLBACK TRAN
	END CATCH
	FETCH NEXT FROM Table_cursor INTO @TableId, @TableName;
END

CLOSE Table_cursor
DEALLOCATE Table_cursor

--check the messages for "SQL error".