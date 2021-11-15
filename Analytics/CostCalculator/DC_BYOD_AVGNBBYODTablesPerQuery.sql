select avg(nbentities) nbentitiesperquery
from
(
	select qt.query_sql_text, count(stagingTables.EntityName) nbentities  
		FROM 
		sys.query_store_query_text AS qt
		JOIN sys.query_store_query AS q ON qt.query_text_id = q.query_text_id
		JOIN sys.query_store_plan AS p ON q.query_id = p.query_id
		JOIN sys.query_store_runtime_stats AS rs ON p.plan_id = rs.plan_id
		JOIN sys.query_store_runtime_stats_interval AS rsi ON rsi.runtime_stats_interval_id = rs.runtime_stats_interval_id
		join 
		(
			select 
				t.name as TableName,
				replace(t.name,'staging','') as EntityName
			from sys.tables t
			where 
				t.Name like '%staging'
		) stagingTables on qt.query_sql_text like '%'+stagingTables.TableName+'%'
		WHERE 
			rsi.start_time >= DATEADD(day, -10, GETUTCDATE()) and qt.query_sql_text like '%select %'
			--Adjust the #days as necessary e.g to reflect DATEADD(day, -#Days, GETUTCDATE())
		group by 
		qt.query_sql_text
) nbentitiesperquery