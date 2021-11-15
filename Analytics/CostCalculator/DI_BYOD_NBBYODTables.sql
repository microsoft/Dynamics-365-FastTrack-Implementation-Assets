select count(*)
from
(
select 
	t.name as TableName,
	replace(t.name,'staging','') as EntityName
from sys.tables t
where 
	t.Name like '%staging'
) BYODTableList
