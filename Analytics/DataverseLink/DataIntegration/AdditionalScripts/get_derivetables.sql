-- With the synapse link derived tables such as DirPartyTable, EcoResProduct may have missing fields as compared to database or Export to data lake feature
-- The reason is Synapse link goes through application layer and only extract field that are available in the table
-- the workaround to solve missing columns is to add applicable child tables to synapse link and create view joining the derived tables on target system
-- this script given the parent table name can identify all related child  table and also the join statement that can be used to represent the final data  
-- add the parent table information
with parenttable as 
(
select t.NAME as ParentTableName, string_agg(convert(nvarchar(max),'['+ T.Name + '].[' + s.Name + ']'), ',') as parenttablecolumns
	from TABLEIDTABLE T
	left outer join TABLEFIELDIDTABLE s on s.TableId = T.ID and s.NAME not like 'DEL_%'
	-- add addtional parent tables as applicable
	where t.NAME in ('DIRPARTYTABLE', 'EcoResProduct')
	group by T.NAME
),
DerivedTables AS
(
SELECT
      DerivedTable.Name as derivedTable,
	  DerivedTable.ID as derivedTableId,
      BaseTable.NAME as BaseTable,
	  BaseTable.ID as BaseTableId
FROM dbo.TableIdTable DerivedTable
 JOIN dbo.SYSANCESTORSTABLE TableInheritance on TableInheritance.TableId = DerivedTable.ID
LEFT JOIN dbo.TableIdTable BaseTable on BaseTable.ID = TableInheritance.ParentId
where TableInheritance.ParentId != TableInheritance.TableId
and BaseTable.NAME in (select ParentTableName from  parenttable)
),
RecursiveCTE AS (
    -- Base case: Get derived tables for the top base tables
    SELECT 
        basetable AS TopBaseTable, 
		basetableId AS TopBaseTableId, 
        derivedtable AS LeafTable,
        derivedtableId AS LeafTableId
    FROM 
        DerivedTables
    WHERE 
        basetable NOT IN (SELECT derivedtable FROM DerivedTables)
    UNION ALL

    SELECT 
        r.TopBaseTable, 
		r.TopBaseTableId,
        t.derivedtable AS LeafTable,
		t.derivedTableId
    FROM 
        DerivedTables t
    INNER JOIN 
        RecursiveCTE r ON t.basetable = r.LeafTable
    WHERE 
        t.derivedtable NOT IN (SELECT basetable FROM DerivedTables)
)

-- Select results from the CTE
select 
parenttable,
childtables,
'select ' + parenttablecolumns + ',' + derivedTableColumns + ' FROM ' + parenttable +  ' AS ' +  
parenttable + ' ' +  joinclause as synapselinkjoinstatement
from 
(
select 
parentTable,
STRING_AGG(convert(nvarchar(max),childtable), ',') as childtables,
STRING_AGG(convert(nvarchar(max),derivedTableColumns), ',') as derivedTableColumns,
STRING_AGG(convert(nvarchar(max),joinclause), ' ') as joinclause,
parenttablecolumns
from 
(SELECT 
    TopBaseTable AS parenttable,
	TopBaseTableId AS parentTableId,
	LeafTable AS childtable,
    LeafTableId AS LeafTableId,
	string_agg(convert(nvarchar(max),'['+ LeafTable + '].[' + s.Name + ']'), ',')  as derivedTableColumns,
	'LEFT OUTER JOIN ' + LeafTable + ' AS ' + LeafTable + ' ON ' + TopBaseTable +'.recid = ' + LeafTable + '.recid' AS joinclause,
	p.parenttablecolumns
FROM 
    RecursiveCTE r1
	join parenttable p on p.ParentTableName = r1.TopBaseTable 
	left outer join TABLEFIELDIDTABLE s on s.TableId = LeafTableId
	and s.NAME not like 'DEL_%'
	and s.Name not in (select value from string_split('RELATIONTYPE,modifieddatetime,modifiedby,modifiedtransactionid,dataareaid,recversion,partition,sysrowversion,recid,tableid,versionnumber,createdon,modifiedon,isDelete,PartitionId,createddatetime,createdby,createdtransactionid,PartitionId,sysdatastatecode', ','))
GROUP BY 
    TopBaseTable, TopBaseTableId, LeafTable, LeafTableId, parenttablecolumns
) x 
group by  parentTable, parenttablecolumns
) y


