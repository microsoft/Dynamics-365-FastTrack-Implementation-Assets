
# Load the JSON configuration file
$config = Get-Content -Path ".\config.json" | ConvertFrom-Json

$entityList = $config.entityList 
$sandboxServerName = $config.sandboxServerName
$sandboxDatabaseName = $config.sandboxDatabaseName
$sandboxuid = $config.sandboxuid
$sandboxPwd = $config.sandboxPwd

# Specify the path to the JSON file
$AXDBDependenciesJson = '.\dependencies.json'

# connection string 
$sourceConnectionString = "Server=$($sandboxServerName);Database=$($sandboxDatabaseName);uid=$($sandboxuid);Pwd=$($sandboxPwd)"
                

# sql query
$query = "drop table if exists #myEntitiestree;
Declare @entities nvarchar(max)= '$entityList';
With allviews (nodeId, parentNodeId, nodeIdType, rootNode, depth) AS (
-- 1 Anchor member - represents the list of root nodes considered with a depth of 0	
	select nv.name as nodeId,
       CAST(null as NVARCHAR(MAX)) as parentNodeId,
       CAST('VIEW' as nvarchar(60)) COLLATE DATABASE_DEFAULT as nodeIdType,
	   nv.name as rootNode,
	   0 as depth
	from sys.views nv
	where schema_name(nv.schema_id) = 'dbo' 
	AND nv.name in (select value from string_split(@entities, ','))
	union all
-- 2 recursive member - represents the iteration path to navigate from a node to its parent
--increases depth by 1 at each iteration and keeps a trace of the initial root node from the anchor member 
	select o.name as nodeId,
       CAST(p.name as NVARCHAR(Max)) as parentNodeId,
       o.type_desc COLLATE DATABASE_DEFAULT as nodeIdType,
	   allviews.rootNode as rootnode,
	   allviews.depth + 1 as depth
	from sys.sql_expression_dependencies d
	join sys.objects o
			on o.object_id = d.referenced_id
	join sys.objects p
			on p.object_id = d.referencing_id
	join allviews on allviews.nodeId = p.name
	where 
	d.referenced_id is not null and 
-- 3 ending condition
	p.type_desc = 'VIEW' and
	schema_name(p.schema_id) = 'dbo' and schema_name(o.schema_id) = 'dbo'
)
--4 inserts the results in a temporary table for ease of use
Select * into #myEntitiestree from allviews ;

select nodeId as entityName, 
nodeIdType as objectType,  
max(depth) as depth,
(select top 1 m.definition from sys.sql_modules m
join	sys.objects o on m.object_id = o.object_id  
		and o.schema_id = schema_id('dbo')
		and o.name COLLATE DATABASE_DEFAULT = x.nodeId COLLATE DATABASE_DEFAULT 
		and o.type_desc COLLATE DATABASE_DEFAULT =  nodeIdType COLLATE DATABASE_DEFAULT) as definitions,
	--	string_agg(convert(nvarchar(max), case when [Key] is not null then COLUMN_NAME else null end), '','') WITHIN GROUP (ORDER BY [Key] ASC)  as KeyColumn,
	
(select 	
	STRING_AGG(convert(nvarchar(max), '[' + C.COLUMN_NAME + '] ' + case DATA_TYPE when 'nvarchar' then 'nvarchar(100)' when 'timestamp' then 'varbinary(100)'  else DATA_TYPE end ), ',') as C1
	from INFORMATION_SCHEMA.COLUMNS C
	left join   INFORMATION_SCHEMA.KEY_COLUMN_USAGE K
	on C.TABLE_SCHEMA = K.TABLE_SCHEMA and C.Table_Name = K.Table_Name and C.COLUMN_NAME = K.COLUMN_NAME
	where  C.TABLE_SCHEMA = 'dbo' and C.TABLE_NAME = x.nodeId
			) as columnList
from #myEntitiestree x
group by nodeId, nodeIdType 
order by depth desc
FOR JSON PATH, ROOT ('AXDBDependencies')
"

# Create a SqlConnection object
$connection = New-Object System.Data.SqlClient.SqlConnection
$connection.ConnectionString = $sourceConnectionString

# Create a SqlCommand object and set its properties
$command = $connection.CreateCommand()
$command.CommandText = $query
$command.CommandType = [System.Data.CommandType]::Text
$command.CommandTimeout = 3600


Write-Host "Connecting to database" 

# Open the SQL connection
$connection.Open()


Write-Host "Executing query" 

# Execute the SQL command
$dataReader = $command.ExecuteReader()

$json = ""
while ($dataReader.Read())
{
    $json += $dataReader.GetValue(0)
}


Write-Host "Writing file"

# Save the JSON to a file
$json | Out-File $AXDBDependenciesJson

Write-Host "AXDB dependency file generated" -ForegroundColor Green

# Close the SQL connection
$connection.Close()