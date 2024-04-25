-- With the synapse link derived tables such as DirPartyTable, EcoResProduct may have missing fields as compared to database or Export to data lake feature
-- The reason is Synapse link goes through application layer and only extract field that are available in the table
-- the workaround to solve missing columns is to add applicable child tables to synapse link and create view joining the derived tables on target system
-- this script given the parent table name can identify all related child  table and also the join statement that can be used to represent the final data  
-- add the parent table information
WITH parenttable AS 
(
SELECT t.NAME AS ParentTableName, STRING_AGG(CONVERT(NVARCHAR(MAX),'['+ T.Name + '].[' + s.Name + ']'), ',') AS parenttablecolumns
	FROM TABLEIDTABLE T
	LEFT OUTER JOIN TABLEFIELDIDTABLE s ON s.TableId = T.ID AND s.NAME NOT LIKE 'DEL_%'
	-- add addtional parent tables as applicable
	WHERE t.NAME IN (
		--'DirOrganizationBase', --supporting the duplicate example
		'DirPartyTable',
		'EcoResProduct'
	)
	GROUP BY T.NAME
),
DerivedTables AS
(
SELECT
      DerivedTable.Name AS derivedTable,
	  DerivedTable.ID AS derivedTableId,
      BaseTable.NAME AS BaseTable,
	  BaseTable.ID AS BaseTableId
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
,DistrinctRecursiveCTE as ( 
/*
DistrinctRecursiveCTE Added to remove duplication from recursive cte resulting from leaf tables. 
Ex: adding DirOrganizationBase in CTE parenttable duplicated CompanyInfo,DirOrganization,OMInternalOrganization,OMOperatingUnit,OMTeam resulting in duplicated column output in the view definition.
Users may not know what tables are considered base vs derived and could add any table into the first CTE
*/
SELECT DISTINCT RecursiveCTE.TopBaseTable,
                    RecursiveCTE.TopBaseTableId,
                    RecursiveCTE.LeafTable,
                    RecursiveCTE.LeafTableId
	FROM RecursiveCTE
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
    DistrinctRecursiveCTE r1
	join parenttable p on p.ParentTableName = r1.TopBaseTable 
	left outer join TABLEFIELDIDTABLE s on s.TableId = LeafTableId
	and s.NAME not like 'DEL_%'
	and s.Name not in (select value from string_split('RELATIONTYPE,modifieddatetime,modifiedby,modifiedtransactionid,dataareaid,recversion,partition,sysrowversion,recid,tableid,versionnumber,createdon,modifiedon,isDelete,PartitionId,createddatetime,createdby,createdtransactionid,PartitionId,sysdatastatecode', ','))
GROUP BY 
    TopBaseTable, TopBaseTableId, LeafTable, LeafTableId, parenttablecolumns
) x 
group by  parentTable, parenttablecolumns
) y
