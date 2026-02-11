--Drop Table IF EXISTS #myEntitiestree;

/****************************************************Part 1 recursion*************************************/
-----------------------------------------------BEGIN Recursive section ---------------------------------------
With allviews (nodeId, parentNodeId, nodeIdType, rootNode, depth) AS (
-- 1 Anchor member - represents the list of root nodes considered with a depth of 0	
	select nv.name as nodeId,
       CAST(null as NVARCHAR(MAX)) as parentNodeId,
       CAST('VIEW' as nvarchar(60)) COLLATE DATABASE_DEFAULT as nodeIdType,
	   nv.name as rootNode,
	   0 as depth
	from sys.views nv
	join 
	(/**************put he view catalog query here ****************/
		select 
			distinct EntityTable, TARGETENTITY
			from 
			DMFDEFINITIONGROUPEXECUTION DDGEH
			inner join
			DMFDEFINITIONGROUPENTITY DDGE on DDGEH.DEFINITIONGROUP = DDGE.DEFINITIONGROUP
			inner join 
			DMFDATASOURCE DDS on 
			DDS.PARTITION = DDGE.PARTITION and 
			DDGE.DEFAULTREFRESHTYPE = 0 and
			DDS.SOURCENAME = DDGE.SOURCE 
			inner join 
			DMFENTITY DE on DE.ENTITYNAME = DDGE.ENTITY
			where DDS.TYPE = 4 --AX DB Type
	) 
	catalog
	on catalog.TARGETENTITY = nv.name
	where schema_name(nv.schema_id) = 'dbo' 	
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
------------------------------------------------End recursive section -------------------------------

select avg(nbtables)
from
(
	Select count(nodeId) nbtables, rootNode from #myEntitiestree where #myEntitiestree.nodeIdType = 'USER_TABLE' group by rootNode
) countnbtables