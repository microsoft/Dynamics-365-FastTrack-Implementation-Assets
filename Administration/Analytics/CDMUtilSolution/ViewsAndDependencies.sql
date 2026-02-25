--Tips : in SSMS, Tools -> Options -> Query Results -> SQL Server -> Results to grid -> check the boc "Retail CR/LF on copy or save"

-- ***************************************************Part 1 recursion************************************* 
-----------------------------------------------BEGIN Recursive section ---------------------------------------
With allviews (nodeId, parentNodeId, nodeIdType, rootNode, depth) AS (
-- 1 Anchor member - represents the list of root nodes considered with a depth of 0	
	select nv.name as nodeId,
       CAST(null as NVARCHAR(MAX)) as parentNodeId,
       CAST('VIEW' as nvarchar(60)) COLLATE DATABASE_DEFAULT as nodeIdType,
	   nv.name as rootNode,
	   0 as depth
	from sys.views nv
	--join [DATAFEEDSMODELENTITYCATALOG] catalog
	--on catalog.entityObjectName = nv.name
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

-- ***************************************************Part 2 data tree analysis************************************* 

-- Full entities view list
Select * from #myEntitiestree where #myEntitiestree.nodeIdType = 'VIEW'
order by rootNode, depth desc



-- list all the required tables in the lake to generate all the data entities 
--(this may prevent you from generating all the 11000 tables for next time, 
--combined to the list of tables with data you should be able to have the 
--largest possible coverage with the minum required tables)
Select distinct nodeId from #myEntitiestree where #myEntitiestree.nodeIdType = 'USER_TABLE'


--All view definitions related to entities (assumes that all tables are in the lake)
select schema_name(v.schema_id) as schema_name,
       v.name as view_name,
       v.create_date as created,
       v.modify_date as last_modified,
	   orderedViews.depth as depth,
	   Replace(Replace(Replace(m.definition,'CREATE VIEW','CREATE OR ALTER VIEW'),'GetValidFromInContextInfo','GETUTCDATE'),'GetValidToInContextInfo','GETUTCDATE')
from sys.views v
join sys.sql_modules m 
     on m.object_id = v.object_id
join (Select * from #myEntitiestree where #myEntitiestree.nodeIdType = 'VIEW') as orderedViews
on orderedViews.nodeId = v.name
order by rootNode asc, depth desc



--  All view definition for a gien data entity
select schema_name(v.schema_id) as schema_name,
       v.name as view_name,
       v.create_date as created,
       v.modify_date as last_modified,
	   orderedViews.depth as depth,
	   Replace(Replace(Replace(m.definition,'CREATE VIEW','CREATE OR ALTER VIEW'),'GetValidFromInContextInfo','GETUTCDATE'),'GetValidToInContextInfo','GETUTCDATE')
from sys.views v
join sys.sql_modules m 
     on m.object_id = v.object_id
join (Select * from #myEntitiestree where #myEntitiestree.nodeIdType = 'VIEW') as orderedViews
on orderedViews.nodeId = v.name
where rootNode like '%CUST%V3%'
order by rootNode asc, depth desc




--list all views ready for creation based on tables exported to the lake
select schema_name(v.schema_id) as schema_name,
       v.name as view_name,
       v.create_date as created,
       v.modify_date as last_modified,
	   orderedViews.depth as depth,
	   Replace(Replace(Replace(m.definition,'CREATE VIEW','CREATE OR ALTER VIEW'),'GetValidFromInContextInfo','GETUTCDATE'),'GetValidToInContextInfo','GETUTCDATE')
from sys.views v
join sys.sql_modules m 
     on m.object_id = v.object_id
join (Select * from #myEntitiestree mytree 
where mytree.nodeIdType = 'VIEW' and exists 
(  -- replace this section by selection of your list of tables in the lake
	Select 
	#myEntitiestree.rootNode 
	from #myEntitiestree 
	where parentNodeId is not null and mytree.rootNode = #myEntitiestree.rootNode
	group by rootNode
) ) as orderedViews
on orderedViews.nodeId = v.name
order by rootNode asc, depth desc



--drop table #myEntitiestree
