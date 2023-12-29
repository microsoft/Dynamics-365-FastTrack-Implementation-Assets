-- Dec 29, 2023 - Added options to derived tables SQL to fix for incremental CSV version
--Dec 13 - Filter deleted rows from delta tables  
--Dec 9 - Added support for enum translation from globaloptionset 
-- added support for data entity removing mserp_ prefix from column name
-- fixed bug in derived table view creation - when there not all child tables are present
--Last updated - Nov 28, 2023 - Fixed bug syntax error while creating/updating derived base tables views with joins of child table  
IF NOT EXISTS (SELECT * FROM sys.schemas WHERE name = 'dvtosql')
BEGIN
    EXEC('CREATE SCHEMA dvtosql')
END
GO

CREATE OR ALTER PROC dvtosql.source_SetupExternalDataSource(@StorageDS nvarchar(2000), @SaaSToken nvarchar(1000) ='',
@storageDSUriScheme nvarchar(100) = 'adls:', @externalds_name nvarchar(1000) OUTPUT)
AS 
	declare @identity nvarchar(1000);
	declare @secret nvarchar(1000)

	if @SaaSToken = ''
		begin
			set @identity= 'MANAGED IDENTITY';
			set @secret = '';
		end
	else
		begin
			set @identity = 'SHARED ACCESS SIGNATURE';
			set @secret   = replace(', SECRET = ''{SaaSToken}''', '{SaaSToken}',@SaaSToken);
		end
	
	set @externalds_name = (select value from string_split(@StorageDS, '/', 1) where ordinal = 4)
	declare @externalDS_Location nvarchar(1000) = replace(@StorageDS, 'https:', @storageDSUriScheme)

	-- Create 'Managed Identity' 'Database Scoped Credentials' if not exist
	-- database scope credentials is used to access storage account 
	Declare @CreateCredentials nvarchar(max) =  replace(replace(replace(replace(
		'
		IF NOT EXISTS(select * from sys.database_credentials where name = ''{externalds_name}'')
			CREATE DATABASE SCOPED CREDENTIAL [{externalds_name}] WITH IDENTITY=''{identity}'' {Secret}

		IF NOT EXISTS(select * from sys.external_data_sources where name = ''{externalds_name}'')
			CREATE EXTERNAL DATA SOURCE [{externalds_name}] WITH (
				LOCATION = ''{extenralDS_Location}'',
				CREDENTIAL = [{externalds_name}])
		',
		'{externalds_name}', @externalds_name),
		'{extenralDS_Location}', @externalDS_Location),
		'{identity}', @identity),
		'{secret}', @Secret)
		;

	execute sp_executesql  @CreateCredentials;

GO

CREATE OR ALTER PROC dvtosql.source_GetCdmMetadata(@externaldatasource nvarchar(1000),  @modeljson nvarchar(max) Output, @enumtranslation nvarchar(max) Output)
AS 
declare @parmdefinition nvarchar(1000);
-- read model.json from the root folder
set @parmdefinition = N'@modeljson nvarchar(max) OUTPUT';
declare @getmodelJson nvarchar(max) = 
'SELECT     
	@modeljson= replace(jsonContent, ''cdm:'', '''')
FROM
	OPENROWSET(
		BULK ''model.json'',
		DATA_SOURCE = ''{externaldatasource}'',
		FORMAT = ''CSV'',
		FIELDQUOTE = ''0x0b'',
		FIELDTERMINATOR =''0x0b'',
		ROWTERMINATOR = ''0x0b''
	)
	WITH 
	(
		jsonContent varchar(MAX)
	) AS r'

set @getmodelJson = replace(@getmodelJson, '{externaldatasource}',@externaldatasource);

execute sp_executesql @getmodelJson, @ParmDefinition, @modeljson=@modeljson OUTPUT;

--print(@getmodelJson);
--declare @enumtranslation nvarchar(max) 
set @parmdefinition = N'@enumtranslation nvarchar(max) OUTPUT';

declare @getenumtranslation nvarchar(max) = 
replace('select 
	@enumtranslation = string_agg(convert(nvarchar(max),enumtranslation), '';'')
from (
select ''{"tablename":"''+ tablename + ''","columnname":"'' + columnname + ''","enum":"'' +
''CASE ['' + columnname + '']'' +  string_agg( convert(nvarchar(max),  '' WHEN ~''+enumvalue+''~ THEN '' + convert(nvarchar(10),enumid)) , '' '' ) + '' END"}'' as enumtranslation
FROM (SELECT 
		tablename,
		columnname,
		enum,
		enumid,
		enumvalue
	FROM OPENROWSET(
		BULK ''enumtranslation/*.cdm.json'',
		DATA_SOURCE = ''{externaldatasource}'',
		FORMAT = ''CSV'',
		fieldterminator =''0x0b'',
		fieldquote = ''0x0b'',
		rowterminator = ''0x0b''
		)
		with (doc nvarchar(max)) as r
		cross apply openjson (doc) with (tablename nvarchar(max) ''$.definitions[0].entityName'', definitions nvarchar(max) as JSON )
		cross apply OPENJSON(definitions, ''$[0].hasAttributes'')  
						WITH (columnname  nvarchar(200) ''$.name'',  datatype NVARCHAR(50) ''$.dataFormat'' , maxLength int ''$.maximumLength'' 
						,scale int ''$.traits[0].arguments[1].value'', 
						enum nvarchar(max) ''$.appliedTraits[3].arguments[0].value'', 
						constantvalues nvarchar(max) ''$.appliedTraits[3].arguments[1].value.entityReference.constantValues'' as JSON)
		cross apply OPENJSON(constantvalues) with (enumid nvarchar(100) ''$[3]'', enumvalue nvarchar(100) ''$[2]'' )
		where  1=1
		and enum is not null
		and JSON_QUERY(doc, ''$.definitions[0]'') is not null
	) x
	group by tablename,columnname, enum
)y;', '{externaldatasource}', @externaldatasource) ;

--print(@getenumtranslation);
begin try
execute sp_executesql @getenumtranslation, @ParmDefinition, @enumtranslation=@enumtranslation OUTPUT; 
end try 
begin catch

END CATCH;


set @modeljson = isnull(@modeljson, '{}') ;
set @enumtranslation = isnull(@enumtranslation, '{}') ;

GO


CREATE or ALTER FUNCTION dvtosql.source_GetSQLMetadataFromSQL
(
	@SourceSchema nvarchar(100)
)
RETURNS TABLE 
AS
RETURN 
select
	(select 
		TABLE_NAME as tablename,
		string_agg(convert(varchar(max), QUOTENAME(COLUMN_NAME)), ',') as selectcolumns,
		string_agg(convert(varchar(max), QUOTENAME(COLUMN_NAME) + SPACE(1) +  
		DATA_TYPE +
		CASE 
			WHEN DATA_TYPE LIKE '%char%' AND CHARACTER_MAXIMUM_LENGTH = -1 THEN '(max)'
			WHEN CHARACTER_MAXIMUM_LENGTH IS NOT NULL THEN '(' + CAST(CHARACTER_MAXIMUM_LENGTH AS VARCHAR) + ')'
			WHEN DATA_TYPE IN ('decimal', 'numeric') THEN '(' + CAST(NUMERIC_PRECISION AS VARCHAR) + ', ' + CAST(NUMERIC_SCALE AS VARCHAR) + ')'
		ELSE '' END), ',') as datatypes,
		string_agg(convert(varchar(max), QUOTENAME(COLUMN_NAME)), ',') as columnnames
	from INFORMATION_SCHEMA.COLUMNS
	WHERE TABLE_SCHEMA = @SourceSchema
	and TABLE_NAME not in ('_controltableforcopy,TargetMetadata,OptionsetMetadata,StateMetadata,StatusMetadata,GlobalOptionsetMetadata')
	and TABLE_NAME not like '%_partitioned'
	group by TABLE_NAME
	FOR JSON PATH
	) sqlmetadata

GO
CREATE or ALTER FUNCTION dvtosql.source_GetSQLMetadataFromCDM
(	
	@modeljson nvarchar(max),
	@enumtranslation nvarchar(max) = '{}'
)
RETURNS TABLE 
AS
RETURN 
(
with table_field_enum_map as 
(
	select 
		tablename, 
		columnname, 
		enum as enumtranslation 
	from string_split(@enumtranslation, ';')
	cross apply openjson(value) 
	with (tablename nvarchar(100),columnname nvarchar(100), enum nvarchar(max))
)

	select 
		tablename as tablename,
		string_agg(convert(varchar(max), selectcolumn), ',') as selectcolumns,
		string_agg(convert(varchar(max), + '[' + columnname + '] ' +  sqldatatype) , ',') as datatypes,
		string_agg(convert(varchar(max), columnname), ',') as columnnames
	from 
	(select  
		t.[tablename] as tablename,
		name as columnname,
		case    
			when datatype = 'string'   then IsNull(replace('(' + em.enumtranslation + ')','~',''''),  + 'isNull(['+  t.tablename + '].['+  name + '], '''')') + ' AS [' + name  + ']' 
			when datatype = 'datetime' then 'isNull(['+  t.tablename + '].['  + name + '], ''1900-01-01'') AS [' + name  + ']' 
			when datatype = 'datetimeoffset' then 'isNull(['+  t.tablename + '].['  + name + '], ''1900-01-01'') AS [' + name  + ']' 
			else '['+  t.tablename + '].[' + name + ']' + ' AS [' + name  + ']' 
		end as selectcolumn,
		datatype as datatype,
		case      
			when datatype ='guid' then 'nvarchar(100)'    
			when datatype = 'string' and  (maxlength >= 8000 or  maxlength < 1 or maxlength is null)  then 'nvarchar(max)'    
			when datatype = 'string' and  maxlength < 8000 then 'nvarchar(' + try_convert(nvarchar(5),maxlength) + ')'
			when datatype = 'int64' then 'bigint'   
			when datatype = 'datetime' then 'datetime2' 
			when datatype = 'datetimeoffset' then 'datetime2' 
			when datatype = 'boolean' then 'bit'   
			when datatype = 'double' then 'real'    
			when datatype = 'decimal' then 'decimal(' + try_convert(varchar(10), [precision]) + ',' + try_convert(varchar(10), [scale])+ ')'  
			else datatype 
		end as sqldatatype
	from openjson(@modeljson) with(entities nvarchar(max) as JSON) 
	cross apply openjson (entities) with([tablename] NVARCHAR(200) '$.name', [attributes] NVARCHAR(MAX) '$.attributes' as JSON ) t
	cross apply openjson(attributes) with ( name varchar(200) '$.name',  datatype varchar(50) '$.dataType' , maxlength int '$.maxLength' ,precision int '$.traits[0].arguments[0].value' ,scale int '$.traits[0].arguments[1].value') c   
	left outer join table_field_enum_map em on t.[tablename] = em.tablename and c.name = em.columnname
	) metadata
	group by tablename

)
GO


create or alter view GlobalOptionsetMetadata 
	AS SELECT 
			'' as EntityName,
			'' as OptionSetName,
			'' as GlobalOptionSetName,
			0 as LocalizedLabelLanguageCode,
			0 as [Option] ,
			'' as ExternalValue

GO
	
CREATE OR ALTER     FUNCTION [dvtosql].[source_GetEnumTranslation]
(
)
RETURNS TABLE 
AS

Return
select  string_agg(convert(nvarchar(max),'{"tablename":"'+ tablename + '","enumtranslation":",' + enumstringcolumns + '"}'), ';' ) as enumtranslation
from 

(
	select 
		tablename,
		string_agg(convert(nvarchar(max),enumtranslation), ',') as enumstringcolumns
		from (
		select 
		tablename,
		columnname ,
		'CASE [' + tablename + '].[' + columnname + ']' +  string_agg( convert(nvarchar(max),  ' WHEN '+convert(nvarchar(10),enumid)) + ' THEN ''' + enumvalue , ''' ' ) + ''' END AS ' + columnname + '_$label'  
		as enumtranslation
		FROM (SELECT 
			EntityName as tablename,
			OptionSetName as columnname,
			GlobalOptionSetName as enum,
			[Option] as enumid ,
			ExternalValue as enumvalue
			from GlobalOptionsetMetadata
			where LocalizedLabelLanguageCode = 1033 -- this is english
			and OptionSetName not in ('sysdatastatecode') 
			) x
		group by tablename,columnname, enum
		)y
		group by tablename
	) optionsetmetadata

GO



CREATE or ALTER PROC dvtosql.source_createOrAlterViews
(
	@externalds_name nvarchar(1000), 
	@modeljson nvarchar(max),
	@enumtranslation nvarchar(max),
	@incrementalCSV int,  
	@add_EDL_AuditColumns int, 
	@tableschema nvarchar(10)='dbo', 
	@rowsetoptions nvarchar(2000) ='',
	@translate_enums int = 0,
	@remove_mserp_from_columnname  int = 0
)
AS

	-- set createviewddl template and columns variables 
	declare @CreateViewDDL nvarchar(max); 
	declare @addcolumns nvarchar(max) = '';
	declare @GlobalOptionSetMetadataTemplate nvarchar(max)='' 
	declare @filter_deleted_rows nvarchar(200) =  ' '

	-- setup the ddl template 
	if @incrementalCSV  = 0
	begin	
		if @add_EDL_AuditColumns = 1
			begin
				set @addcolumns = '{tablename}.PartitionId,{tablename}.SinkModifiedOn as DataLakeModified_DateTime, cast(null as varchar(100)) as [$FileName], {tablename}.recid as _SysRowId,cast({tablename}.versionnumber as varchar(100)) as LSN,convert(datetime2,null) as LastProcessedChange_DateTime,'
			end 
		else 
			set @addcolumns = '{tablename}.PartitionId,';

		set @CreateViewDDL =
		'CREATE OR ALTER VIEW  {tableschema}.{tablename}  AS 
		 SELECT 
		 {selectcolumns}
		 FROM  OPENROWSET
		 ( BULK ''deltalake/{tablename}_partitioned/'',  
		  FORMAT = ''delta'', 
		  DATA_SOURCE = ''{externaldsname}''
		 ) 
		 WITH
		 (
			{datatypes}, [PartitionId] int
		 ) as {tablename}';

		set @filter_deleted_rows =  ' where {tablename}.IsDelete is null '
		
		set @GlobalOptionSetMetadataTemplate = 'create or alter view GlobalOptionsetMetadata 
		AS
		SELECT *
		FROM  OPENROWSET
				( BULK ''deltalake/GlobalOptionsetMetadata_partitioned/'',  
					FORMAT = ''delta'', 
					DATA_SOURCE = ''{externaldsname}''
				) as GlobalOptionsetMetadata'
	
	end
	else 
	begin
		
		if @add_EDL_AuditColumns = 1
			begin
				set @addcolumns = 'cast(replace({tablename}.filepath(1),''.'', '':'') as datetime2) as DataLakeModified_DateTime, cast({tablename}.filepath(1) +''{tablename}'' + {tablename}.filepath(2) as varchar(100)) as [$FileName], {tablename}.recid as _SysRowId, cast({tablename}.versionnumber as varchar(100)) as LSN, convert(datetime2,null) as LastProcessedChange_DateTime,'
			end
		else
			begin
				-- for incremental folder(CSV) filepath(1) is the timestamp folder - we still want to add DataLakeModified_DateTime to enable folder ellimination when fetching increemntal data
				set @addcolumns = 'cast(replace({tablename}.filepath(1),''.'', '':'') as datetime2) as DataLakeModified_DateTime,'
			end
		
		set @CreateViewDDL =
		'CREATE OR ALTER VIEW  {tableschema}.{tablename}  AS 
		SELECT 
			{selectcolumns}
		FROM  OPENROWSET
		( BULK ''*/{tablename}/*.csv'',  
		  FORMAT = ''CSV'', 
		  DATA_SOURCE = ''{externaldsname}''
		  {options}
		) 
		WITH
		(
			{datatypes}
		) as {tablename} ';

set @GlobalOptionSetMetadataTemplate = 'create or alter view GlobalOptionsetMetadata 
AS
SELECT *
FROM  OPENROWSET
		( BULK ''*/OptionsetMetadata/GlobalOptionsetMetadata.csv'',  
		  FORMAT = ''CSV'', 
		  DATA_SOURCE = ''{externaldsname}''
		) 
		WITH
		(
			[OptionSetName] [varchar](max),
			[Option] [bigint],
			[IsUserLocalizedLabel] [bit],
			[LocalizedLabelLanguageCode] [bigint],
			[LocalizedLabel] [varchar](max),
			[GlobalOptionSetName] [varchar](max),
			[EntityName] [varchar](max),
			[ExternalValue] [varchar](max)

		) as GlobalOptionsetMetadata
		where GlobalOptionsetMetadata.filepath(1) = 
		(select top 1 lastfolder
		 FROM  OPENROWSET
		( BULK ''Changelog/changelog.info'',  
		  FORMAT = ''CSV'', 
		  DATA_SOURCE = ''{externaldsname}''
		) 
		WITH
		(
			lastfolder nvarchar(100)
		) as changelog
		)' 
	end;

-- Generate globaloptionset view 
set @GlobalOptionSetMetadataTemplate = replace(@GlobalOptionSetMetadataTemplate,'{externaldsname}', @externalds_name)
execute sp_executesql @GlobalOptionSetMetadataTemplate;

drop table if exists #cdmmetadata;
	create table #cdmmetadata
	(
		tablename nvarchar(200) COLLATE Database_Default,	
		selectcolumns nvarchar(max) COLLATE Database_Default,
		datatypes nvarchar(max) COLLATE Database_Default,	
		columnnames nvarchar(max) COLLATE Database_Default
	);

	insert into #cdmmetadata (tablename, selectcolumns, datatypes, columnnames)
	select tablename, selectcolumns, datatypes, columnnames from dvtosql.source_GetSQLMetadataFromCDM(@modeljson, @enumtranslation) as cdm

drop table if exists #enumtranslation;
	create table #enumtranslation
	(
		tablename nvarchar(200) COLLATE Database_Default,	
		enumtranslation nvarchar(max) default('')
	);

	IF (@translate_enums = 1)
	BEGIN
		declare @enumtranslation_optionset nvarchar(max);
		select @enumtranslation_optionset = enumtranslation  from [dvtosql].[source_GetEnumTranslation]()

		insert into #enumtranslation
		select 
			tablename, 
			enumtranslation 
		from string_split(@enumtranslation_optionset, ';')
		cross apply openjson(value) 
		with (tablename nvarchar(100), enumtranslation nvarchar(max))
	END
	--select * from #cdmmetadata

-- generate ddl for view definitions for each tables in cdmmetadata table in the bellow format. 
-- Begin try  
	-- execute sp_executesql N'create or alter view schema.tablename as selectcolumns from openrowset(...) tablename '  
-- End Try 
--Begin catch 
	-- print ERROR_PROCEDURE() + ':' print ERROR_MESSAGE() 
--end catch
declare @ddl_tables nvarchar(max);

select 
	@ddl_tables = string_agg(convert(nvarchar(max), viewDDL ), ';')
	FROM (
			select 
			'begin try  execute sp_executesql N''' +
			replace(replace(replace(replace(replace(replace(replace(@CreateViewDDL + @filter_deleted_rows, 			
			'{tableschema}',@tableschema),
			'{selectcolumns}', 
				case when c.tablename  COLLATE Database_Default like 'mserp_%' then '' else  @addcolumns end + 
				c.selectcolumns  COLLATE Database_Default +  
				isnull(enumtranslation COLLATE Database_Default, '')), 
			'{tablename}', c.tablename), 
			'{externaldsname}', @externalds_name), 
			'{datatypes}', c.datatypes),
			'{options}', @rowsetoptions),
			'''','''''')  
			+ '''' + ' End Try Begin catch print ERROR_PROCEDURE() + '':'' print ERROR_MESSAGE() end catch' as viewDDL
			from #cdmmetadata as c
			left outer join #enumtranslation as e on c.tablename = e.tablename
		)x		

-- execute @ddl_tables 

If @remove_mserp_from_columnname = 1
BEGIN
	declare @mserp_prefix nvarchar(100) = '';
	set @ddl_tables = replace(replace(@ddl_tables, 'mserp_createdon', 'fno_createdon'),'mserp_Id', 'fno_Id');
	set @mserp_prefix = 'AS [mserp_';
	set @ddl_tables = replace(@ddl_tables, @mserp_prefix, '[')
	print @mserp_prefix;
END 
--select @ddl_tables
execute sp_executesql @ddl_tables;

-- There is  difference in Synapse link and Export to data lake when exporting derived base tables like dirpartytable
-- For base table (Dirpartytable), Export to data lake includes all columns from the derived tables. However Synapse link only exports columns that in the AOT. 
-- This step overide the Dirpartytable view and columns from other derived tables , making table dirpartytable backward compatible
-- Table Inheritance data is available in AXBD
declare @ddl_fno_derived_tables nvarchar(max);
declare @tableinheritance nvarchar(max) = '[{"parenttable":"AgreementHeader","childtables":[{"childtable":"PurchAgreementHeader"},{"childtable":"SalesAgreementHeader"}]},{"parenttable":"AgreementHeaderExt_RU","childtables":[{"childtable":"PurchAgreementHeaderExt_RU"},{"childtable":"SalesAgreementHeaderExt_RU"}]},{"parenttable":"AgreementHeaderHistoryExt_RU","childtables":[{"childtable":"PurchAgreementHeaderHistoryExt_RU"},{"childtable":"SalesAgreementHeaderHistoryExt_RU"}]},{"parenttable":"AifEndpointActionValueMap","childtables":[{"childtable":"AifPortValueMap"},{"childtable":"InterCompanyTradingValueMap"}]},{"parenttable":"BankLCLine","childtables":[{"childtable":"BankLCExportLine"},{"childtable":"BankLCImportLine"}]},{"parenttable":"CAMDataAllocationBase","childtables":[{"childtable":"CAMDataFormulaAllocationBase"},{"childtable":"CAMDataHierarchyAllocationBase"},{"childtable":"CAMDataPredefinedDimensionMemberAllocationBase"}]},{"parenttable":"CAMDataCostAccountingLedgerSourceEntryProvider","childtables":[{"childtable":"CAMDataCostAccountingLedgerCostElementEntryProvider"},{"childtable":"CAMDataCostAccountingLedgerStatisticalMeasureProvider"}]},{"parenttable":"CAMDataDataConnectorDimension","childtables":[{"childtable":"CAMDataDataConnectorChartOfAccounts"},{"childtable":"CAMDataDataConnectorCostObjectDimension"}]},{"parenttable":"CAMDataDataConnectorSystemInstance","childtables":[{"childtable":"CAMDataDataConnectorSystemInstanceAX"}]},{"parenttable":"CAMDataDataOrigin","childtables":[{"childtable":"CAMDataDataOriginDocument"}]},{"parenttable":"CAMDataDimension","childtables":[{"childtable":"CAMDataCostElementDimension"},{"childtable":"CAMDataCostObjectDimension"},{"childtable":"CAMDataStatisticalDimension"}]},{"parenttable":"CAMDataDimensionHierarchy","childtables":[{"childtable":"CAMDataDimensionCategorizationHierarchy"},{"childtable":"CAMDataDimensionClassificationHierarchy"}]},{"parenttable":"CAMDataDimensionHierarchyNode","childtables":[{"childtable":"CAMDataDimensionHierarchyNodeComposite"},{"childtable":"CAMDataDimensionHierarchyNodeLeaf"}]},{"parenttable":"CAMDataImportedDimensionMember","childtables":[{"childtable":"CAMDataImportedCostElementDimensionMember"},{"childtable":"CAMDataImportedCostObjectDimensionMember"},{"childtable":"CAMDataImportedStatisticalDimensionMember"}]},{"parenttable":"CAMDataImportedTransactionEntry","childtables":[{"childtable":"CAMDataImportedBudgetEntry"},{"childtable":"CAMDataImportedGeneralLedgerEntry"}]},{"parenttable":"CAMDataJournalCostControlUnitBase","childtables":[{"childtable":"CAMDataJournalCostControlUnit"}]},{"parenttable":"CAMDataSourceDocumentLine","childtables":[{"childtable":"CAMDataSourceDocumentLineDetail"}]},{"parenttable":"CAMDataTransactionVersion","childtables":[{"childtable":"CAMDataActualVersion"},{"childtable":"CAMDataBudgetVersion"},{"childtable":"CAMDataCalculation"},{"childtable":"CAMDataOverheadCalculation"},{"childtable":"CAMDataSourceTransactionVersion"}]},{"parenttable":"CaseDetailBase","childtables":[{"childtable":"CaseDetail"},{"childtable":"CustCollectionsCaseDetail"},{"childtable":"HcmFMLACaseDetail"}]},{"parenttable":"CatProductReference","childtables":[{"childtable":"CatCategoryProductReference"},{"childtable":"CatClassifiedProductReference"},{"childtable":"CatDistinctProductReference"},{"childtable":"CatExternalQuoteProductReference"}]},{"parenttable":"CustCollectionsLinkTable","childtables":[{"childtable":"CustCollectionsLinkActivitiesCustTrans"},{"childtable":"CustCollectionsLinkCasesActivities"}]},{"parenttable":"CustInterestTransLineIdRef","childtables":[{"childtable":"CustInterestTransLineIdRef_MarkupTrans"},{"childtable":"CustnterestTransLineIdRef_Invoice"}]},{"parenttable":"CustInvoiceLineTemplate","childtables":[{"childtable":"CustInvoiceMarkupTransTemplate"},{"childtable":"CustInvoiceStandardLineTemplate"}]},{"parenttable":"CustVendDirective_PSN","childtables":[{"childtable":"CustDirective_PSN"},{"childtable":"VendDirective_PSN"}]},{"parenttable":"CustVendRoutingSlip_PSN","childtables":[{"childtable":"CustRoutingSlip_PSN"},{"childtable":"VendRoutingSlip_PSN"}]},{"parenttable":"DMFRules","childtables":[{"childtable":"DMFRulesNumberSequence"}]},{"parenttable":"EcoResApplicationControl","childtables":[{"childtable":"EcoResCatalogControl"},{"childtable":"EcoResComponentControl"}]},{"parenttable":"EcoResNomenclature","childtables":[{"childtable":"EcoResDimBasedConfigurationNomenclature"},{"childtable":"EcoResProductVariantNomenclature"},{"childtable":"EngChgProductCategoryNomenclature"},{"childtable":"PCConfigurationNomenclature"}]},{"parenttable":"EcoResNomenclatureSegment","childtables":[{"childtable":"EcoResNomenclatureSegmentAttributeValue"},{"childtable":"EcoResNomenclatureSegmentColorDimensionValue"},{"childtable":"EcoResNomenclatureSegmentColorDimensionValueName"},{"childtable":"EcoResNomenclatureSegmentConfigDimensionValue"},{"childtable":"EcoResNomenclatureSegmentConfigDimensionValueName"},{"childtable":"EcoResNomenclatureSegmentConfigGroupItemId"},{"childtable":"EcoResNomenclatureSegmentConfigGroupItemName"},{"childtable":"EcoResNomenclatureSegmentNumberSequence"},{"childtable":"EcoResNomenclatureSegmentProductMasterName"},{"childtable":"EcoResNomenclatureSegmentProductMasterNumber"},{"childtable":"EcoResNomenclatureSegmentSizeDimensionValue"},{"childtable":"EcoResNomenclatureSegmentSizeDimensionValueName"},{"childtable":"EcoResNomenclatureSegmentStyleDimensionValue"},{"childtable":"EcoResNomenclatureSegmentStyleDimensionValueName"},{"childtable":"EcoResNomenclatureSegmentTextConstant"},{"childtable":"EcoResNomenclatureSegmentVersionDimensionValue"},{"childtable":"EcoResNomenclatureSegmentVersionDimensionValueName"}]},{"parenttable":"EcoResProduct","childtables":[{"childtable":"EcoResDistinctProduct"},{"childtable":"EcoResDistinctProductVariant"},{"childtable":"EcoResProductMaster"}]},{"parenttable":"EcoResProductMasterDimensionValue","childtables":[{"childtable":"EcoResProductMasterColor"},{"childtable":"EcoResProductMasterConfiguration"},{"childtable":"EcoResProductMasterSize"},{"childtable":"EcoResProductMasterStyle"},{"childtable":"EcoResProductMasterVersion"}]},{"parenttable":"EcoResProductWorkspaceConfiguration","childtables":[{"childtable":"EcoResProductDiscreteManufacturingWorkspaceConfiguration"},{"childtable":"EcoResProductMaintainWorkspaceConfiguration"},{"childtable":"EcoResProductProcessManufacturingWorkspaceConfiguration"},{"childtable":"EcoResProductVariantMaintainWorkspaceConfiguration"}]},{"parenttable":"EngChgEcmOriginals","childtables":[{"childtable":"EngChgEcmOriginalEcmAttribute"},{"childtable":"EngChgEcmOriginalEcmBom"},{"childtable":"EngChgEcmOriginalEcmBomTable"},{"childtable":"EngChgEcmOriginalEcmFormulaCoBy"},{"childtable":"EngChgEcmOriginalEcmFormulaStep"},{"childtable":"EngChgEcmOriginalEcmProduct"},{"childtable":"EngChgEcmOriginalEcmRoute"},{"childtable":"EngChgEcmOriginalEcmRouteOpr"},{"childtable":"EngChgEcmOriginalEcmRouteTable"}]},{"parenttable":"FBGeneralAdjustmentCode_BR","childtables":[{"childtable":"FBGeneralAdjustmentCodeICMS_BR"},{"childtable":"FBGeneralAdjustmentCodeINSSCPRB_BR"},{"childtable":"FBGeneralAdjustmentCodeIPI_BR"},{"childtable":"FBGeneralAdjustmentCodePISCOFINS_BR"}]},{"parenttable":"HRPLimitAgreementException","childtables":[{"childtable":"HRPLimitAgreementCompException"},{"childtable":"HRPLimitAgreementJobException"}]},{"parenttable":"IntercompanyActionPolicy","childtables":[{"childtable":"IntercompanyAgreementActionPolicy"}]},{"parenttable":"PaymCalendarRule","childtables":[{"childtable":"PaymCalendarCriteriaRule"},{"childtable":"PaymCalendarLocationRule"}]},{"parenttable":"PCConstraint","childtables":[{"childtable":"PCExpressionConstraint"},{"childtable":"PCTableConstraint"}]},{"parenttable":"PCProductConfiguration","childtables":[{"childtable":"PCTemplateConfiguration"},{"childtable":"PCVariantConfiguration"}]},{"parenttable":"PCTableConstraintColumnDefinition","childtables":[{"childtable":"PCTableConstraintDatabaseColumnDef"},{"childtable":"PCTableConstraintGlobalColumnDef"}]},{"parenttable":"PCTableConstraintDefinition","childtables":[{"childtable":"PCDatabaseRelationConstraintDefinition"},{"childtable":"PCGlobalTableConstraintDefinition"}]},{"parenttable":"RetailMediaResource","childtables":[{"childtable":"RetailImageResource"}]},{"parenttable":"RetailPeriodicDiscount","childtables":[{"childtable":"GUPFreeItemDiscount"},{"childtable":"RetailDiscountMixAndMatch"},{"childtable":"RetailDiscountMultibuy"},{"childtable":"RetailDiscountOffer"},{"childtable":"RetailDiscountThreshold"},{"childtable":"RetailShippingThresholdDiscounts"}]},{"parenttable":"RetailProductAttributesLookup","childtables":[{"childtable":"RetailAttributesGlobalLookup"},{"childtable":"RetailAttributesLegalEntityLookup"}]},{"parenttable":"RetailPubRetailChannelTable","childtables":[{"childtable":"RetailPubRetailMCRChannelTable"},{"childtable":"RetailPubRetailOnlineChannelTable"},{"childtable":"RetailPubRetailStoreTable"}]},{"parenttable":"RetailTillLayoutZoneReferenceLegacy","childtables":[{"childtable":"RetailTillLayoutButtonGridZoneLegacy"},{"childtable":"RetailTillLayoutImageZoneLegacy"},{"childtable":"RetailTillLayoutReportZoneLegacy"}]},{"parenttable":"SCTTracingActivity","childtables":[{"childtable":"SCTTracingActivity_Purch"}]},{"parenttable":"SysMessageTarget","childtables":[{"childtable":"SysMessageCompanyTarget"},{"childtable":"SysWorkloadMessageCompanyTarget"},{"childtable":"SysWorkloadMessageHubCompanyTarget"}]},{"parenttable":"SysPolicyRuleType","childtables":[{"childtable":"SysPolicySourceDocumentRuleType"}]},{"parenttable":"TradeNonStockedConversionLog","childtables":[{"childtable":"TradeNonStockedConversionChangeLog"},{"childtable":"TradeNonStockedConversionCheckLog"}]},{"parenttable":"UserRequest","childtables":[{"childtable":"VendRequestUserRequest"},{"childtable":"VendUserRequest"}]},{"parenttable":"VendRequest","childtables":[{"childtable":"VendRequestCategoryExtension"},{"childtable":"VendRequestCompany"},{"childtable":"VendRequestStatusChange"}]},{"parenttable":"VendVendorRequest","childtables":[{"childtable":"VendVendorRequestNewCategory"},{"childtable":"VendVendorRequestNewVendor"}]},{"parenttable":"WarrantyGroupConfigurationItem","childtables":[{"childtable":"RetailWarrantyApplicableChannel"},{"childtable":"WarrantyApplicableProduct"},{"childtable":"WarrantyGroupData"}]},{"parenttable":"AgreementHeaderHistory","childtables":[{"childtable":"PurchAgreementHeaderHistory"},{"childtable":"SalesAgreementHeaderHistory"}]},{"parenttable":"AgreementLine","childtables":[{"childtable":"AgreementLineQuantityCommitment"},{"childtable":"AgreementLineVolumeCommitment"}]},{"parenttable":"AgreementLineHistory","childtables":[{"childtable":"AgreementLineQuantityCommitmentHistory"},{"childtable":"AgreementLineVolumeCommitmentHistory"}]},{"parenttable":"BankLC","childtables":[{"childtable":"BankLCExport"},{"childtable":"BankLCImport"}]},{"parenttable":"BenefitESSTileSetupBase","childtables":[{"childtable":"BenefitESSTileSetupBenefit"},{"childtable":"BenefitESSTileSetupBenefitCredit"}]},{"parenttable":"BudgetPlanElementDefinition","childtables":[{"childtable":"BudgetPlanColumn"},{"childtable":"BudgetPlanRow"}]},{"parenttable":"BusinessEventsEndpoint","childtables":[{"childtable":"BusinessEventsAzureBlobStorageEndpoint"},{"childtable":"BusinessEventsAzureEndpoint"},{"childtable":"BusinessEventsEventGridEndpoint"},{"childtable":"BusinessEventsEventHubEndpoint"},{"childtable":"BusinessEventsFlowEndpoint"},{"childtable":"BusinessEventsServiceBusQueueEndpoint"},{"childtable":"BusinessEventsServiceBusTopicEndpoint"}]},{"parenttable":"CAMDataCostAccountingPolicy","childtables":[{"childtable":"CAMDataAccountingUnitOfMeasurePolicy"},{"childtable":"CAMDataCostAccountingAccountPolicy"},{"childtable":"CAMDataCostAccountingLedgerPolicy"},{"childtable":"CAMDataCostAllocationPolicy"},{"childtable":"CAMDataCostBehaviorPolicy"},{"childtable":"CAMDataCostControlUnitPolicy"},{"childtable":"CAMDataCostDistributionPolicy"},{"childtable":"CAMDataCostFlowAssumptionPolicy"},{"childtable":"CAMDataCostRollupPolicy"},{"childtable":"CAMDataInputMeasurementBasisPolicy"},{"childtable":"CAMDataInventoryValuationMethodPolicy"},{"childtable":"CAMDataLedgerDocumentAccountingPolicy"},{"childtable":"CAMDataOverheadRatePolicy"},{"childtable":"CAMDataRecordingIntervalPolicy"}]},{"parenttable":"CAMDataJournal","childtables":[{"childtable":"CAMDataBudgetEntryTransferJournal"},{"childtable":"CAMDataCalculationJournal"},{"childtable":"CAMDataCostAllocationJournal"},{"childtable":"CAMDataCostBehaviorCalculationJournal"},{"childtable":"CAMDataCostDistributionJournal"},{"childtable":"CAMDataGeneralLedgerEntryTransferJournal"},{"childtable":"CAMDataOverheadRateCalculationJournal"},{"childtable":"CAMDataSourceEntryTransferJournal"},{"childtable":"CAMDataStatisticalEntryTransferJournal"}]},{"parenttable":"CAMDataSourceDocumentAttributeValue","childtables":[{"childtable":"CAMDataSourceDocumentAttributeValueAmount"},{"childtable":"CAMDataSourceDocumentAttributeValueDate"},{"childtable":"CAMDataSourceDocumentAttributeValueQuantity"},{"childtable":"CAMDataSourceDocumentAttributeValueString"}]},{"parenttable":"CatPunchoutRequest","childtables":[{"childtable":"CatCXMLPunchoutRequest"}]},{"parenttable":"CatUserReview","childtables":[{"childtable":"CatUserReviewProduct"},{"childtable":"CatUserReviewVendor"}]},{"parenttable":"CatVendProdCandidateAttributeValue","childtables":[{"childtable":"CatVendorBooleanValue"},{"childtable":"CatVendorCurrencyValue"},{"childtable":"CatVendorDateTimeValue"},{"childtable":"CatVendorFloatValue"},{"childtable":"CatVendorIntValue"},{"childtable":"CatVendorTextValue"}]},{"parenttable":"CustInvLineBillCodeCustomFieldBase","childtables":[{"childtable":"CustInvLineBillCodeCustomFieldBool"},{"childtable":"CustInvLineBillCodeCustomFieldDateTime"},{"childtable":"CustInvLineBillCodeCustomFieldInt"},{"childtable":"CustInvLineBillCodeCustomFieldReal"},{"childtable":"CustInvLineBillCodeCustomFieldText"}]},{"parenttable":"DIOTAdditionalInfoForNoVendor_MX","childtables":[{"childtable":"DIOTAddlInfoForNoVendorLedger_MX"},{"childtable":"DIOTAddlInfoForNoVendorProj_MX"}]},{"parenttable":"DirPartyTable","childtables":[{"childtable":"CompanyInfo"},{"childtable":"DirOrganization"},{"childtable":"DirOrganizationBase"},{"childtable":"DirPerson"},{"childtable":"OMInternalOrganization"},{"childtable":"OMOperatingUnit"},{"childtable":"OMTeam"}]},{"parenttable":"DOMRules","childtables":[{"childtable":"DOMCatalogAmountFulfillmentTypeRules"},{"childtable":"DOMCatalogMinimumInventoryRules"},{"childtable":"DOMCatalogRules"},{"childtable":"DOMCatalogShipPriorityRules"},{"childtable":"DOMOrgFulfillmentTypeRules"},{"childtable":"DOMOrgLocationOfflineRules"},{"childtable":"DOMOrgMaximumDistanceRules"},{"childtable":"DOMOrgMaximumOrdersRules"},{"childtable":"DOMOrgMaximumRejectsRules"}]},{"parenttable":"DOMRulesLine","childtables":[{"childtable":"DOMRulesLineCatalogAmountFulfillmentTypeRules"},{"childtable":"DOMRulesLineCatalogMinimumInventoryRules"},{"childtable":"DOMRulesLineCatalogRules"},{"childtable":"DOMRulesLineCatalogShipPriorityRules"},{"childtable":"DOMRulesLineOrgFulfillmentTypeRules"},{"childtable":"DOMRulesLineOrgLocationOfflineRules"},{"childtable":"DOMRulesLineOrgMaximumDistanceRules"},{"childtable":"DOMRulesLineOrgMaximumOrdersRules"},{"childtable":"DOMRulesLineOrgMaximumRejectsRules"}]},{"parenttable":"EcoResCategory","childtables":[{"childtable":"PCClass"}]},{"parenttable":"EcoResInstanceValue","childtables":[{"childtable":"CatalogProductInstanceValue"},{"childtable":"CustomerInstanceValue"},{"childtable":"EcoResCategoryInstanceValue"},{"childtable":"EcoResEngineeringProductCategoryAttributeInstanceValue"},{"childtable":"EcoResProductInstanceValue"},{"childtable":"EcoResReleasedEngineeringProductVersionAttributeInstanceValue"},{"childtable":"GUPPriceTreeInstanceValue"},{"childtable":"GUPRebateDateInstanceValue"},{"childtable":"GUPRetailChannelInstanceValue"},{"childtable":"GUPSalesQuotationInstanceValue"},{"childtable":"GUPSalesTableInstanceValue"},{"childtable":"PCComponentInstanceValue"},{"childtable":"RetailCatalogProdInternalOrgInstanceVal"},{"childtable":"RetailChannelInstanceValue"},{"childtable":"RetailInternalOrgProductInstanceValue"},{"childtable":"RetailSalesTableInstanceValue"},{"childtable":"TMSLoadBuildStrategyAttribValueSet"}]},{"parenttable":"EcoResProductVariantDimensionValue","childtables":[{"childtable":"EcoResProductVariantColor"},{"childtable":"EcoResProductVariantConfiguration"},{"childtable":"EcoResProductVariantSize"},{"childtable":"EcoResProductVariantStyle"},{"childtable":"EcoResProductVariantVersion"}]},{"parenttable":"EcoResValue","childtables":[{"childtable":"EcoResBooleanValue"},{"childtable":"EcoResCurrencyValue"},{"childtable":"EcoResDateTimeValue"},{"childtable":"EcoResFloatValue"},{"childtable":"EcoResIntValue"},{"childtable":"EcoResReferenceValue"},{"childtable":"EcoResTextValue"}]},{"parenttable":"EntAssetMaintenancePlanLine","childtables":[{"childtable":"EntAssetMaintenancePlanLineCounter"},{"childtable":"EntAssetMaintenancePlanLineTime"}]},{"parenttable":"HRPDefaultLimit","childtables":[{"childtable":"HRPDefaultLimitCompensationRule"},{"childtable":"HRPDefaultLimitJobRule"}]},{"parenttable":"KanbanQuantityPolicyDemandPeriod","childtables":[{"childtable":"KanbanQuantityDemandPeriodFence"},{"childtable":"KanbanQuantityDemandPeriodSeason"}]},{"parenttable":"MarkupMatchingTrans","childtables":[{"childtable":"VendInvoiceInfoLineMarkupMatchingTrans"},{"childtable":"VendInvoiceInfoSubMarkupMatchingTrans"}]},{"parenttable":"MarkupPeriodChargeInvoiceLineBase","childtables":[{"childtable":"MarkupPeriodChargeInvoiceLineBaseMonetary"},{"childtable":"MarkupPeriodChargeInvoiceLineBaseQuantity"},{"childtable":"MarkupPeriodChargeInvoiceLineBaseQuantityMinAmount"}]},{"parenttable":"PayrollPayStatementLine","childtables":[{"childtable":"PayrollPayStatementBenefitLine"},{"childtable":"PayrollPayStatementEarningLine"},{"childtable":"PayrollPayStatementTaxLine"}]},{"parenttable":"PayrollProviderTaxRegion","childtables":[{"childtable":"PayrollTaxRegionForSymmetry"}]},{"parenttable":"PayrollTaxEngineTaxCode","childtables":[{"childtable":"PayrollTaxEngineTaxCodeForSymmetry"}]},{"parenttable":"PayrollTaxEngineWorkerTaxRegion","childtables":[{"childtable":"PayrollWorkerTaxRegionForSymmetry"}]},{"parenttable":"PCPriceElement","childtables":[{"childtable":"PCPriceBasePrice"},{"childtable":"PCPriceExpressionRule"}]},{"parenttable":"PCRuntimeCache","childtables":[{"childtable":"PCRuntimeCacheXml"}]},{"parenttable":"PCTemplateAttributeBinding","childtables":[{"childtable":"PCTemplateCategoryAttribute"},{"childtable":"PCTemplateConstant"}]},{"parenttable":"RetailChannelTable","childtables":[{"childtable":"RetailDirectSalesChannel"},{"childtable":"RetailMCRChannelTable"},{"childtable":"RetailOnlineChannelTable"},{"childtable":"RetailStoreTable"}]},{"parenttable":"RetailPeriodicDiscountLine","childtables":[{"childtable":"GUPFreeItemDiscountLine"},{"childtable":"RetailDiscountLineMixAndMatch"},{"childtable":"RetailDiscountLineMultibuy"},{"childtable":"RetailDiscountLineOffer"},{"childtable":"RetailDiscountLineThresholdApplying"}]},{"parenttable":"RetailReturnPolicyLine","childtables":[{"childtable":"RetailReturnInfocodePolicyLine"},{"childtable":"RetailReturnReasonCodePolicyLine"}]},{"parenttable":"RetailTillLayoutZoneReference","childtables":[{"childtable":"RetailTillLayoutButtonGridZone"},{"childtable":"RetailTillLayoutImageZone"},{"childtable":"RetailTillLayoutReportZone"}]},{"parenttable":"ServicesParty","childtables":[{"childtable":"ServicesCustomer"},{"childtable":"ServicesEmployee"}]},{"parenttable":"SysPolicyRule","childtables":[{"childtable":"CatCatalogPolicyRule"},{"childtable":"HcmBenefitEligibilityRule"},{"childtable":"HRPDefaultLimitRule"},{"childtable":"HRPLimitAgreementRule"},{"childtable":"HRPLimitRequestCurrencyRule"},{"childtable":"PayrollPremiumEarningGenerationRule"},{"childtable":"PurchReApprovalPolicyRuleTable"},{"childtable":"PurchReqControlRFQRule"},{"childtable":"PurchReqControlRule"},{"childtable":"PurchReqSourcingPolicyRule"},{"childtable":"RequisitionPurposeRule"},{"childtable":"RequisitionReplenishCatAccessPolicyRule"},{"childtable":"RequisitionReplenishControlRule"},{"childtable":"SysPolicySourceDocumentRule"},{"childtable":"TrvPolicyRule"},{"childtable":"TSPolicyRule"}]},{"parenttable":"SysTaskRecorderNode","childtables":[{"childtable":"SysTaskRecorderNodeAnnotationUserAction"},{"childtable":"SysTaskRecorderNodeCommandUserAction"},{"childtable":"SysTaskRecorderNodeFormUserAction"},{"childtable":"SysTaskRecorderNodeFormUserActionInputOutput"},{"childtable":"SysTaskRecorderNodeInfoUserAction"},{"childtable":"SysTaskRecorderNodeMenuItemUserAction"},{"childtable":"SysTaskRecorderNodePropertyUserAction"},{"childtable":"SysTaskRecorderNodeScope"},{"childtable":"SysTaskRecorderNodeTaskUserAction"},{"childtable":"SysTaskRecorderNodeUserAction"},{"childtable":"SysTaskRecorderNodeValidationUserAction"}]},{"parenttable":"SysUserRequest","childtables":[{"childtable":"HcmWorkerUserRequest"},{"childtable":"VendVendorPortalUserRequest"}]},{"parenttable":"TrvEnhancedData","childtables":[{"childtable":"TrvEnhancedCarRentalData"},{"childtable":"TrvEnhancedHotelData"},{"childtable":"TrvEnhancedItineraryData"}]}]'
declare @backwardcompatiblecolumns nvarchar(max) = '_SysRowId,DataLakeModified_DateTime,$FileName,LSN,LastProcessedChange_DateTime';
declare @exlcudecolumns nvarchar(max) = 'Id,SinkCreatedOn,SinkModifiedOn,modifieddatetime,modifiedby,modifiedtransactionid,dataareaid,recversion,partition,sysrowversion,recid,tableid,versionnumber,createdon,modifiedon,isDelete,PartitionId,createddatetime,createdby,createdtransactionid,PartitionId,sysdatastatecode';

with table_hierarchy as
(
	select 
	parenttable,
	string_agg(convert(nvarchar(max),childtable), ',') as childtables,
	string_agg(convert(nvarchar(max),joinclause), ' ') as joins,
	string_agg(convert(nvarchar(max),columnnamelist), ',') as columnnamelists
	from (
		select 
		parenttable, 
		childtable,
		'LEFT OUTER JOIN ' + childtable + ' AS ' + childtable + ' ON ' + parenttable +'.recid = ' + childtable + '.recid' AS joinclause,
		(select 
			STRING_AGG(convert(varchar(max),  '[' + TABLE_NAME + '].'+ '[' + COLUMN_NAME + ']'   + ' AS [' + COLUMN_NAME + ']'), ',') 
			from INFORMATION_SCHEMA.COLUMNS C
			where TABLE_SCHEMA = @tableschema
			and TABLE_NAME  = childtable
			and COLUMN_NAME not in (select value from string_split(@backwardcompatiblecolumns + ',' + @exlcudecolumns, ','))
		) as columnnamelist
		from openjson(@tableinheritance) 
		with (parenttable nvarchar(200), childtables nvarchar(max) as JSON) 
		cross apply openjson(childtables) with (childtable nvarchar(200))
		where childtable in (select TABLE_NAME from INFORMATION_SCHEMA.COLUMNS C where TABLE_SCHEMA = @tableschema and C.TABLE_NAME  = childtable)
		) x
		group by parenttable
)

select 
	@ddl_fno_derived_tables = string_agg(convert(nvarchar(max), viewDDL ), ';')
	FROM (
			select 
			'begin try  execute sp_executesql N''' +
			replace(replace(replace(replace(replace(replace(replace(@CreateViewDDL  + ' ' + h.joins + @filter_deleted_rows, 			
			'{tableschema}',@tableschema),
			'{selectcolumns}', @addcolumns + selectcolumns  COLLATE Database_Default +  isnull(enumtranslation COLLATE Database_Default, '') + ',' + h.columnnamelists COLLATE Database_Default), 
			'{tablename}', c.tablename), 
			'{externaldsname}', @externalds_name), 
			'{datatypes}', c.datatypes),
			'{options}', @rowsetoptions),
			'''','''''')  
			+ '''' + ' End Try Begin catch print ERROR_PROCEDURE() + '':'' print ERROR_MESSAGE() end catch' as viewDDL
			from #cdmmetadata c
			left outer join #enumtranslation as e on c.tablename = e.tablename
			inner join table_hierarchy h on c.tablename = h.parenttable
  	) X;

print(@ddl_fno_derived_tables)
execute sp_executesql @ddl_fno_derived_tables;

GO

CREATE or ALTER PROC dvtosql.source_GetNewDataToCopy
(
	@controltable nvarchar(max), 
	@sourcetableschema nvarchar(10),
	@environment nvarchar(1000), 
	@incrementalCSV int =1, 
	@externaldatasource nvarchar(1000) = '', 
	@lastdatetimemarker datetime2 = '1900-01-01' 
)
AS

drop table if exists #controltable;
CREATE TABLE #controltable
	(
		[tableschema] [varchar](20) null,
		[tablename] [varchar](255) null,
		[datetime_markercolumn] varchar(100),
		[bigint_markercolumn] varchar(100),
		[environment] varchar(1000),
		[lastdatetimemarker] nvarchar(100) ,
		lastcopystatus int,
		lastbigintmarker bigint,
		[active] int,
		[incremental] int,
		[selectcolumns] nvarchar(max) null,
		[datatypes] nvarchar(max) null,
		[columnnames] nvarchar(max) null
	);

insert into #controltable (tableschema, tablename,datetime_markercolumn,bigint_markercolumn, environment, lastdatetimemarker, lastcopystatus, lastbigintmarker, active, incremental, selectcolumns, datatypes, columnnames)
select tableschema, tablename, datetime_markercolumn,bigint_markercolumn, environment, lastdatetimemarker, lastcopystatus, lastbigintmarker, active, incremental, selectcolumns, datatypes, columnnames  from openjson(@controltable)
	with (tableschema nvarchar(100), tablename nvarchar(200), datetime_markercolumn varchar(100),bigint_markercolumn varchar(100), lastdatetimemarker nvarchar(100), active int, incremental int, environment nvarchar(100) ,lastcopystatus int,lastbigintmarker bigint, 
	columnnames nvarchar(max), selectcolumns nvarchar(max), datatypes nvarchar(max) )

select 
	@lastdatetimemarker= min(lastdatetimemarker) 
from #controltable 
where 
	[active] = 1 and
	lastcopystatus != 1	and 
	lastdatetimemarker != '1900-01-01T00:00:00';

set  @lastdatetimemarker = isnull(@lastdatetimemarker, '1900-01-01T00:00:00')


declare @tablelist_inNewFolders nvarchar(max);
declare @minfoldername nvarchar(100) = '';
declare @maxfoldername nvarchar(100) = '';
declare @SelectTableData nvarchar(max);
declare @newdatetimemarker datetime2 = getdate();
declare @whereClause nvarchar(200) = ' where {datetime_markercolumn} between ''{lastdatetimemarker}'' and ''{newdatetimemarker}'' and {bigint_markercolumn} > {lastbigintmarker}';

set @SelectTableData  = 'SELECT * from {tableschema}.{tablename}';

IF (@incrementalCSV = 1)
	BEGIN;
		
		declare @ParmDefinition NVARCHAR(500);
		declare @newfolders nvarchar(max); 

		-- get newFolders and max modeljson by listing out model.json files in each timestamp folders */model.json
		-- @lastFolderMarker helps  elliminate folders and find new folders created after this folder
		SET @ParmDefinition = N'@minfoldername nvarchar(max) OUTPUT, @maxfoldername nvarchar(100) OUTPUT, @tablelist_inNewFolders nvarchar(max) OUTPUT';

		declare @getNewFolders nvarchar(max) = 
		'SELECT     
		@minfoldername = min(minfolder),
		@maxfoldername = max(maxfolderPath),  
		@tablelist_inNewFolders = string_agg(convert(nvarchar(max), x.tablename),'','')
		from 
		(
			select 
			tablename,
			min(r.filepath(1)) as minfolder,
			max(r.filepath(1)) as maxfolderPath
			FROM
				OPENROWSET(
					BULK ''*/model.json'',
					DATA_SOURCE = ''{externaldatasource}'',
					FORMAT = ''CSV'',
					FIELDQUOTE = ''0x0b'',
					FIELDTERMINATOR =''0x0b'',
					ROWTERMINATOR = ''0x0b''
				)
				WITH 
				(
					jsonContent varchar(MAX)
				) AS r
				cross apply openjson(jsonContent) with (entities nvarchar(max) as JSON)
				cross apply openjson (entities) with([tablename] NVARCHAR(200) ''$.name'', [partitions] NVARCHAR(MAX) ''$.partitions'' as JSON ) t
				where r.filepath(1) >''{lastFolderMarker}'' and [partitions] != ''[]''
				group by tablename
			) x';

		set @getNewFolders = replace(replace (@getNewFolders, '{externaldatasource}',@externaldatasource), '{lastFolderMarker}', FORMAT(@lastdatetimemarker, 'yyyy-MM-ddTHH.mm.ssZ'));

		print(@getNewFolders)

		execute sp_executesql @getNewFolders, @ParmDefinition, @tablelist_inNewFolders=@tablelist_inNewFolders OUTPUT, @maxfoldername=@maxfoldername OUTPUT, @minfoldername=@minfoldername OUTPUT;

		print ('Folder to process:' + @minfoldername + '...' + @maxfoldername)
		print('Tables in new folders:' + @tablelist_inNewFolders)
		print ('New marker value:' + @maxfoldername);

		set @newdatetimemarker =  convert(datetime2, replace(@maxfoldername, '.', ':'));
	END;

	select 
		tableschema,
		tablename,
		lastdatetimemarker,
		@newdatetimemarker as newdatetimemarker ,
		replace(replace(replace(replace(replace(replace(replace(convert(nvarchar(max),@SelectTableData  + (case when incremental =1 then @whereClause else '' end)), 
		'{tableschema}', @sourcetableschema),
		'{tablename}', tablename),
		'{lastdatetimemarker}', lastdatetimemarker),
		'{newdatetimemarker}', @newdatetimemarker),
		'{lastbigintmarker}', lastbigintmarker),
		'{datetime_markercolumn}', datetime_markercolumn),
		'{bigint_markercolumn}', bigint_markercolumn)
		 as selectquery,
		 datatypes
	from #controltable
	where 
		(@incrementalCSV = 0 OR tablename in (select value from string_split(@tablelist_inNewFolders, ','))) and 
		[active] = 1 and 
		lastcopystatus != 1


GO


CREATE or ALTER PROC dvtosql.target_GetSetSQLMetadata
(
	@tableschema nvarchar(10), 
	@StorageDS nvarchar(2000) = '', 
	@sqlMetadata nvarchar(max) = '{}', 
	@datetime_markercolumn nvarchar(100)= 'SinkModifiedOn',
	@bigint_markercolumn nvarchar(100) = 'versionnumber',
	@lastdatetimemarker nvarchar(max) = '1900-01-01',
	@controltable nvarchar(max) OUTPUT
)
AS

declare  @storageaccount nvarchar(1000);
declare  @container nvarchar(1000);
declare  @externalds_name nvarchar(1000);
declare  @fullexportList nvarchar(max)= 'GlobalOptionsetMetadata,OptionsetMetadata,StateMetadata,StatusMetadata,TargetMetadata';

if @StorageDS != ''
begin
	set @storageaccount = (select value from string_split(@StorageDS, '/', 1) where ordinal = 3)
	set @container = (select value from string_split(@StorageDS, '/', 1) where ordinal = 4)
end

IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dvtosql].[_controltableforcopy]') AND type in (N'U'))
	CREATE TABLE [dvtosql].[_controltableforcopy]
	(
		[tableschema] [varchar](20) null,
		[tablename] [varchar](255) null,
		[datetime_markercolumn] varchar(100),
		[bigint_markercolumn] varchar(100),
		[storageaccount] varchar(1000) null,
		[container] varchar(1000) null,
		[environment] varchar(1000) null,
		[datapath] varchar(1000) null,
		[lastcopystartdatetime] [datetime2](7) null,
		[lastcopyenddatetime] [datetime2](7) null,
		[lastdatetimemarker] [datetime2](7) default '1/1/1900',
		[lastbigintmarker] bigint default -1,
		[lastcopystatus] [int] default 0,
		[refreshinterval] [int] default 60,
		[active] [int] default 1,
		[incremental] [int] default 1,
		[selectcolumns] nvarchar(max) null,
		[datatypes] nvarchar(max) null,
		[columnnames] nvarchar(max) null
	);

	IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dvtosql].[_datalaketosqlcopy_log]') AND type in (N'U'))
		CREATE TABLE [dvtosql].[_datalaketosqlcopy_log]
		(
			[pipelinerunid] [varchar](200) NOT NULL,
			[tablename] [varchar](200) NOT NULL,
			[minfolder] [varchar](100) NULL,
			[maxfolder] [varchar](100) NULL,
			[copystatus] [int] NULL default(0),
			[rowsinserted] [bigint] NULL default(0),
			[rowsupdated] [bigint] NULL default(0),
			[rowsdeleted] [bigint] NULL default(0),
			[startdatetime] [datetime2](7),
			[enddatetime] [datetime2](7) NULL
		);

With sqlmetadata as 
(
	select * 
	from openjson(@sqlmetadata) with([tablename] NVARCHAR(200), [selectcolumns] NVARCHAR(MAX), datatypes NVARCHAR(MAX), columnnames NVARCHAR(MAX)) t
)

MERGE INTO [dvtosql].[_controltableforcopy] AS target
	USING sqlmetadata AS source
	ON target.tableschema = @tableschema and  target.tablename = source.tablename
	WHEN MATCHED AND (target.datatypes != source.datatypes) THEN 
		UPDATE SET  target.datatypes = source.datatypes, target.selectcolumns = source.selectcolumns, target.columnnames = source.columnnames 
	WHEN NOT MATCHED BY TARGET THEN 
		INSERT (tableschema, tablename, datetime_markercolumn, bigint_markercolumn, storageaccount, container, environment, datapath, selectcolumns, datatypes, columnnames)
		VALUES (@tableschema, tablename, @datetime_markercolumn,@bigint_markercolumn, @storageaccount, @container, @container, '*' + tablename + '*.csv', selectcolumns, datatypes, columnnames);

	-- update full export tables
	update [dvtosql].[_controltableforcopy] 
		set incremental = 0
	where tablename in (select value from string_split(@fullexportList, ','));


	select 
		[tableschema], 
		[tablename], 
		[datetime_markercolumn],
		[bigint_markercolumn],
		case 
			when @lastdatetimemarker  = '1900-01-01' Then isnull([lastdatetimemarker], '')  
			else @lastdatetimemarker 
		end as lastdatetimemarker,
		lastbigintmarker,
		lastcopystatus,
		[active],
		environment,  
		incremental,
		datatypes, 
		columnnames,
		replace(selectcolumns, '''','''''') as selectcolumns
	from [dvtosql].[_controltableforcopy]
	where  [active] = 1


GO

CREATE OR ALTER PROC dvtosql.target_preDataCopy
	(
		@pipelinerunId nvarchar(100), 
		@tableschema nvarchar(10), 
		@tablename nvarchar(200),
		@columnnames nvarchar(max),
		@lastdatetimemarker nvarchar(100),
		@newdatetimemarker nvarchar(100),
		@debug_mode int = 0
	)
	AS
	declare @precopydata nvarchar(max) = replace(replace(replace(replace(replace(replace(convert(nvarchar(max),'print(''--creating table {schema}._new_{tablename}--'');
	IF EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N''[{schema}].[_new_{tablename}]'') AND type in (N''U'')) 
	BEGIN
		DROP TABLE [{schema}].[_new_{tablename}] 
	END

	CREATE TABLE [{schema}].[_new_{tablename}] ({columnnames})

	INSERT INTO  [dvtosql].[_datalaketosqlcopy_log](pipelinerunid, tablename, minfolder,maxfolder) 
	values(''{pipelinerunId}'', ''{tablename}'', ''{lastdatetimemarker}'',''{newdatetimemarker}'' )

	update [dvtosql].[_controltableforcopy]
	set lastcopystatus = 1, [lastcopystartdatetime] = getutcdate()
	where tablename = ''{tablename}'' AND  tableschema = ''{schema}''
	')
	,'{columnnames}', @columnnames)
	,'{schema}', @tableschema)
	,'{tablename}', @tablename)

	,'{pipelinerunId}', @pipelinerunId)
	,'{lastdatetimemarker}', @lastdatetimemarker)
	,'{newdatetimemarker}', @newdatetimemarker)
	;

	IF  @debug_mode = 0 
		Execute sp_executesql @precopydata;
	ELSE 
		print (@precopydata);

GO


CREATE OR ALTER PROC [dvtosql].target_dedupAndMerge
(
@tablename nvarchar(100),
@schema nvarchar(10),
@newdatetimemarker datetime2,
@debug_mode bit = 0
)
AS 

declare @insertCount bigint,
        @updateCount bigint,
        @deleteCount bigint,
        @versionnumber bigint;

declare @incremental int;

select top 1
	@incremental = incremental 
from [dvtosql].[_controltableforcopy]
where 
	tableschema = @schema AND
	tablename = @tablename;  

update [dvtosql].[_controltableforcopy]
set 
	lastcopystatus = 1, 
	[lastcopystartdatetime] = getutcdate()
where 
	tableschema = @schema AND
	tablename = @tablename;  


if (@incremental = 0)
BEGIN
	declare @fullcopy nvarchar(max) = replace(replace('IF EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N''[{schema}].[_new_{tablename}]'') AND type in (N''U'')) 
		BEGIN
			print(''--full export - swap table --'')
		
			IF OBJECT_ID(''{schema}.{tablename}'', ''U'') IS NOT NULL 
			exec sp_rename ''{schema}.{tablename}'', ''_old_{tablename}'';

			exec sp_rename ''{schema}._new_{tablename}'', ''{tablename}'';
	
			IF OBJECT_ID(''{schema}._old_{tablename}'', ''U'') IS NOT NULL 
				DROP TABLE {schema}._old_{tablename};
		END'
	,'{schema}', @schema)
	,'{tablename}', @tablename);

	IF  @debug_mode = 0 
		Execute sp_executesql @fullcopy;
	ELSE 
		print (@fullcopy);
END
ELSE
BEGIN;
	-- dedup and merge
	declare @dedupData nvarchar(max) = replace(replace('print(''--De-duplicate the data in {schema}._new_{tablename}--'');
	IF EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N''[{schema}].[_new_{tablename}]'') AND type in (N''U'')) 
	BEGIN
		WITH CTE AS
		( SELECT ROW_NUMBER() OVER (PARTITION BY Id ORDER BY versionnumber DESC) AS rn FROM {schema}._new_{tablename}
		)
		DELETE FROM CTE WHERE rn > 1;

		DELETE FROM {schema}._new_{tablename} Where IsDelete = 1;
	END'
	,'{schema}', @schema)
	,'{tablename}', @tablename);

	IF  @debug_mode = 0 
		Execute sp_executesql @dedupData;
	ELSE 
		print (@dedupData);

	DECLARE @ParmDefinition NVARCHAR(500);
	SET @ParmDefinition = N'@insertCount bigint OUTPUT, @updateCount bigint  OUTPUT, @deleteCount bigint  OUTPUT, @versionnumber bigint  OUTPUT';


	declare @renameTableAndCreateIndex nvarchar(max) = replace(replace('IF EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N''[{schema}].[_new_{tablename}]'') AND type in (N''U'')) 
	AND NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N''[{schema}].[{tablename}]'') AND type in (N''U'')) 
	BEGIN

	print(''--_new_{tablename} exists and {tablename} does not exists ...rename the table --'')
	exec sp_rename ''{schema}._new_{tablename}'', ''{tablename}''
 
	print(''-- -- create index on table----'')
	IF EXISTS ( SELECT 1 FROM information_schema.columns WHERE table_name = ''{tablename}'' AND column_name = ''Id'') 
		AND NOT EXISTS ( SELECT 1 FROM sys.indexes WHERE name = ''{tablename}_id_idx'' AND object_id = OBJECT_ID(''{tablename}''))
	BEGIN
		CREATE UNIQUE INDEX {tablename}_id_idx ON {tablename}(Id) with (ONLINE = ON);
	END;

	IF EXISTS ( SELECT 1 FROM information_schema.columns WHERE table_name = ''{tablename}'' AND column_name = ''recid'') 
		AND NOT EXISTS ( SELECT 1 FROM sys.indexes WHERE name = ''{tablename}_recid_idx'' AND object_id = OBJECT_ID(''{tablename}''))
	BEGIN
		CREATE UNIQUE INDEX {tablename}_RecId_Idx ON {tablename}(recid) with (ONLINE = ON);
	END;

	IF EXISTS ( SELECT 1 FROM information_schema.columns WHERE table_name = ''{tablename}'' AND column_name = ''versionnumber'') 
		AND NOT EXISTS ( SELECT 1 FROM sys.indexes WHERE name = ''{tablename}_versionnumber_idx'' AND object_id = OBJECT_ID(''{tablename}''))
	BEGIN
		CREATE  INDEX {tablename}_versionnumber_Idx ON {tablename}(versionnumber) with (ONLINE = ON);
	END;

	select @versionnumber = max(versionnumber), @insertCount = count(1) from  {schema}.{tablename};


	END'
	,'{schema}', @schema)
	,'{tablename}', @tablename);

	IF  @debug_mode = 0 
		Execute sp_executesql @renameTableAndCreateIndex,@ParmDefinition, @insertCount=@insertCount OUTPUT, @updateCount=@updateCount OUTPUT,@deleteCount=@deleteCount OUTPUT, @versionnumber = @versionnumber OUTPUT;
	ELSE
		print (@renameTableAndCreateIndex)

	DECLARE @updatestatements NVARCHAR(MAX);
	DECLARE @insertcolumns NVARCHAR(MAX);
	DECLARE @valuescolumns NVARCHAR(MAX);

	-- Generate update statements
	SELECT @updateStatements = STRING_AGG(convert(nvarchar(max),'target.[' + column_name + '] = source.[' + column_name + ']'), ', ') 
	FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME =@tablename and TABLE_SCHEMA = @schema AND column_name <> 'Id' AND column_name <> '$FileName'; 

	-- For the insert columns and values
	SELECT @insertColumns = STRING_AGG(convert(nvarchar(max), '[' + column_name) +']', ', ') FROM INFORMATION_SCHEMA.COLUMNS 
		WHERE TABLE_NAME =@tablename and TABLE_SCHEMA = @schema  AND column_name <> '$FileName';

	SELECT @valuesColumns = STRING_AGG(convert(nvarchar(max),'source.[' + column_name + ']'), ', ') FROM INFORMATION_SCHEMA.COLUMNS 
		WHERE TABLE_NAME =@tablename and TABLE_SCHEMA = @schema AND column_name <> '$FileName';


	DECLARE @mergedata nvarchar(max) = replace(replace(replace(replace(replace(
	convert(nvarchar(max),'IF EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N''[{schema}].[_new_{tablename}]'') AND type in (N''U'')) 
	BEGIN;
	print(''-- Merge data from _new_{tablename} to {tablename}----'')

	DECLARE @MergeOutput TABLE (
		MergeAction NVARCHAR(10)
	);

	MERGE INTO {schema}.{tablename} AS target
	USING {schema}._new_{tablename} AS source
	ON target.Id = source.Id
	WHEN MATCHED AND (target.versionnumber < source.versionnumber) THEN 
		UPDATE SET {updatestatements}
	WHEN NOT MATCHED BY TARGET THEN 
		INSERT ({insertcolumns}) 
		VALUES ({valuescolumns})
	OUTPUT $action INTO @MergeOutput(MergeAction );

	 select @insertCount = [INSERT],
			   @updateCount = [UPDATE],
			   @deleteCount = [DELETE]
		  from (select MergeAction from @MergeOutput) mergeResultsPlusEmptyRow     
		 pivot (count(MergeAction) 
		   for MergeAction in ([INSERT],[UPDATE],[DELETE])) 
			as mergeResultsPivot;

	select @versionnumber = max(versionnumber) from  {schema}.{tablename};
	
	drop table {schema}._new_{tablename};


	END;')
	,'{schema}', @schema),
	'{tablename}', @tablename),
	'{updatestatements}', @updatestatements),
	'{insertcolumns}', @insertcolumns),
	'{valuescolumns}', @valuescolumns)

	IF  @debug_mode = 0 
		Execute sp_executesql @mergedata, @ParmDefinition, @insertCount=@insertCount OUTPUT, @updateCount=@updateCount OUTPUT,@deleteCount=@deleteCount OUTPUT, @versionnumber = @versionnumber OUTPUT;
	ELSE 
		print(@mergedata);

	update [dvtosql].[_controltableforcopy]
	set lastcopystatus = 0, lastdatetimemarker = @newdatetimemarker,  [lastcopyenddatetime] = getutcdate(), lastbigintmarker = @versionnumber
	where tablename = @tablename AND  tableschema = @schema
END 

GO





