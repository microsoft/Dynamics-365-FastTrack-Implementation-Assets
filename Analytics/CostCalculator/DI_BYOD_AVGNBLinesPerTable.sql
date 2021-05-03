Select acgNbLines = AVG(records)
from
(
	SELECT
		BITables.TableName,
		8 * SUM(a.used_pages) * 1024 AS 'SIZEINB',
		max(p.rows) as Records
	FROM sys.indexes AS i
	JOIN sys.partitions AS p ON p.OBJECT_ID = i.OBJECT_ID AND p.index_id = i.index_id
	JOIN sys.allocation_units AS a ON a.container_id = p.partition_id
	JOIN 
	(select 
		t.name as TableName,
		replace(t.name,'staging','') as EntityName
	from sys.tables t
	where 
		t.Name like '%staging') as BITables on 
	  BITables.TableName = OBJECT_NAME(i.OBJECT_ID)
	where (i.type_desc = 'CLUSTERED' or i.type_desc ='HEAP') and OBJECT_SCHEMA_NAME(i.OBJECT_ID) = 'dbo' 
	GROUP BY BITables.TableName
) detailedtablesstats