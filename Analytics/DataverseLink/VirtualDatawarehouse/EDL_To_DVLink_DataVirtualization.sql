-- Prequisites: 
-- 1. Setup synapse link for DV an add tables and have data synced to storage account 
-- 2. To do Enum translation from value to Id, copy the -resolved-cdm.json files to root container  of storage account - you can copy this from existing 
-- export to data lake ChangeFeed folder
-- 3. In storage account, grant Synapse workspace access to roles "Blob data contributor" and "Blob data reader"   
-- Transition Export to data lake to Synapse link for DV easily.

--STEP 1: Create a new database in Synapse serverless 
-- TODO: UPDATE Database as needed, 
IF NOT EXISTS (SELECT 1 FROM sys.databases WHERE name = 'finance_sandbox_operations_dynamics_com_dataverse_delta')
	create database [finance_sandbox_operations_dynamics_com_dataverse_delta] COLLATE Latin1_General_100_CI_AS_SC_UTF8

-- STEP 2: Change the database name as application -- 
use [finance_sandbox_operations_dynamics_com_dataverse_delta]

-- Create Marker KEY Encryption if not exist - this is required to create database scope credentials 
-- You may choose to create own encryption key instead of generating random as done in script bellow
	DECLARE @randomWord VARCHAR(64) = NEWID();
	DECLARE @createMasterKey NVARCHAR(500) = N'
	IF NOT EXISTS (SELECT * FROM sys.symmetric_keys WHERE name = ''##MS_DatabaseMasterKey##'')
		CREATE MASTER KEY ENCRYPTION BY PASSWORD = '  + QUOTENAME(@randomWord, '''')
	EXECUTE sp_executesql @createMasterKey

-- STEP 3: Change parameters and run the bellow script   
	-- TODO:UPDATE @StorageDS VALUE: Storage account URL including container
	declare @StorageDS nvarchar(1000) = 'https://ftfinanced365fo.dfs.core.windows.net/dataverse-financecds-unqc2dfa2ec0ee14ae4a9036c9734cba'
	declare @tableschema nvarchar(100) = 'dbo'

	-- TODO: Set the flag delta = 0 when above storage account is setup for Incremental folder (CSV data), 1 when synpse link is setup for delta conversion
	declare @delta int = 1;

-- TODO: Set the flag @add_EDL_AuditColumns = 1 to add "Export to data lake" audit coulmns, this may help backward compatibility
	declare @add_EDL_AuditColumns int = 1;
	declare @addcolumns nvarchar(max) = '';


	declare @Storage nvarchar(1000) = (select value from string_split(@StorageDS, '/', 1) where ordinal = 3)
	declare @Container nvarchar(1000) = (select value from string_split(@StorageDS, '/', 1) where ordinal = 4)
	declare @environment nvarchar(1000) = (select value from string_split(@StorageDS, '/', 1) where ordinal = 4)

	-- Create 'Managed Identity' 'Database Scoped Credentials' if not exist
	-- database scope credentials is used to access storage account 
	Declare @CreateCredentials nvarchar(max) =  replace(replace(
		'
		IF NOT EXISTS(select * from sys.database_credentials where name = ''{environment}'')
			CREATE DATABASE SCOPED CREDENTIAL [{environment}] WITH IDENTITY=''Managed Identity''
	
		IF NOT EXISTS(select * from sys.external_data_sources where name = ''{environment}'')
			CREATE EXTERNAL DATA SOURCE [{environment}] WITH (
				LOCATION = ''{StorageDS}'',
				CREDENTIAL = [{environment}])
		',
		'{environment}', @environment),
		'{StorageDS}', @StorageDS)
		;

	execute sp_executesql  @CreateCredentials;


	-- set createviewddl template and columns variables 
	declare @CreateViewDDL nvarchar(max); 
	if @delta  = 1
	begin	
		if @add_EDL_AuditColumns = 1
		begin
			set @addcolumns = '{tablename}.SinkCreatedOn as DataLakeModified_DateTime, cast(null as varchar(100)) as [$FileName], {tablename}.recid as _SysRowId,cast({tablename}.versionnumber as varchar(100)) as LSN,convert(datetime2,null) as LastProcessedChange_DateTime,'
		end 
		set @CreateViewDDL =
		'CREATE OR ALTER VIEW  {tableschema}.{tablename}  AS 
		 SELECT 
		 {selectcolumns}
		 FROM  OPENROWSET
		 ( BULK ''deltalake/{tablename}_partitioned/'',  
		  FORMAT = ''delta'', 
		  DATA_SOURCE = ''{environment}''
		 ) 
		 WITH
		 (
			{datatypes}
		 ) as {tablename}';
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
		  PARSER_VERSION = ''1.0'', 
		  DATA_SOURCE = ''{environment}'', 
		  ROWSET_OPTIONS =''{"READ_OPTIONS":["ALLOW_INCONSISTENT_READS"]}''
		) 
		WITH
		(
			{datatypes}
		) as {tablename} ';
	end;


declare @ddl_tables nvarchar(max);
declare @ddl_fno_derived_tables nvarchar(max);
declare @parmdefinition nvarchar(500);

-- read model.json from the root folder
declare @modeljson nvarchar(max);
set @parmdefinition = N'@modeljson nvarchar(max) OUTPUT';
declare @getmodelJson nvarchar(max) = 
'SELECT     
	@modeljson= replace(jsonContent, ''cdm:'', '''')
FROM
	OPENROWSET(
		BULK ''model.json'',
		DATA_SOURCE = ''{environment}'',
		FORMAT = ''CSV'',
		FIELDQUOTE = ''0x0b'',
		FIELDTERMINATOR =''0x0b'',
		ROWTERMINATOR = ''0x0b''
	)
	WITH 
	(
		jsonContent varchar(MAX)
	) AS r'

set @getmodelJson = replace(@getmodelJson, '{environment}',@environment);

print(@getmodelJson);

execute sp_executesql @getmodelJson, @ParmDefinition, @modeljson=@modeljson OUTPUT;

-- Currently Synapse link generate Enum field data value as string as compared to int value in Export to data lake like No Yes instead of 0, 1.
--  (This is expected to be fixed in synapse link in coming month via F&O hotfix)
-- The workaround here collects enum translation from cdm.json files that were produced by export to data lake feature in ChangeFeed folder.
-- and prepare a table with tablename, columnname, enumtranslation in the format CASE fieldname when 'No' then 0 when 'Yes' then 1 

declare @enumtranslation nvarchar(max) 
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
		BULK ''*.cdm.json'',
		DATA_SOURCE = ''{environment}'',
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
)y;', '{environment}', @environment) ;


print(@getenumtranslation);
-- get enumtranslationdata from .cdmjson files and store it in variable @enumtranslation as 
execute sp_executesql @getenumtranslation, @ParmDefinition, @enumtranslation=@enumtranslation OUTPUT;

--Read JSON variables @enumtranslation and @modeljson in tabular format and insert into temp table
-- #table_field_enum_map (tablename, columnname, enum)
-- #cdmmetadata(tableschema, tablename, selectcolumns, datatypes, columnnames) 
with table_field_enum_map as 
(
	select 
		tablename, 
		columnname, 
		enum as enumtranslation 
	from string_split(@enumtranslation, ';')
	cross apply openjson(value) 
	with (tablename nvarchar(100),columnname nvarchar(100), enum nvarchar(max))
),
cdmmetadata as 
(
	select 
		@tableschema as tableschema,
		tablename as tablename,
		string_agg(convert(varchar(max), selectcolumn), ',')  as selectcolumns,
		string_agg(convert(varchar(max), + '[' + columnname + '] ' +  sqldatatype) , ',')  as datatypes,
		string_agg(convert(varchar(max), columnname), ',') as columnnames
	from 
	(select  
		t.[tablename],
		name as columnname,
		case    
			when datatype = 'string'   then IsNull(replace('(' + em.enumtranslation + ')','~',''''),  + 'isNull(['+  t.tablename + '].['+  name + '], '''')') + ' AS [' + name  + ']' 
			when datatype = 'datetime' then 'isNull(['+  t.tablename + '].['  + name + '], ''1900-01-01'') AS [' + name  + ']' 
			when datatype = 'datetimeoffset' then 'isNull(['+  t.tablename + '].['  + name + '], ''1900-01-01'') AS [' + name  + ']' 
			else '['+  t.tablename + '].[' + name + ']' 
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

-- generate ddl for view definitions for each tables in cdmmetadata table in the bellow format. 
-- Begin try  
	-- execute sp_executesql N'create or alter view schema.tablename as selectcolumns from openrowset(...) tablename '  
-- End Try 
--Begin catch 
	-- print ERROR_PROCEDURE() + ':' print ERROR_MESSAGE() 
--end catch

select 
	@ddl_tables = string_agg(convert(nvarchar(max), viewDDL ), ';')
	FROM (
			select 
			'begin try  execute sp_executesql N''' +
			replace(replace(replace(replace(replace(replace(@CreateViewDDL, 			
			'{tableschema}',@tableschema),
			'{selectcolumns}', @addcolumns + selectcolumns), 
			'{tablename}', tablename), 
			'{environment}', @environment), 
			'{datatypes}', datatypes),
			'''','''''')  
			+ '''' + ' End Try Begin catch print ERROR_PROCEDURE() + '':'' print ERROR_MESSAGE() end catch' as viewDDL
			from cdmmetadata
		)x		

-- execute @ddl_tables 
print(@ddl_tables)
execute sp_executesql @ddl_tables;

-- There is  difference in Synapse link and Export to data lake when exporting derived base tables like dirpartytable
-- For base table (Dirpartytable), Export to data lake includes all columns from the derived tables. However Synapse link only exports columns that in the AOT. 
-- This step overide the Dirpartytable view and columns from other derived tables , making table dirpartytable backward compatible
-- Table Inheritance data is available in AXBD
declare @tableinheritance nvarchar(max) = '[{"parenttable":"AgreementHeader","childtables":[{"childtable":"PurchAgreementHeader"},{"childtable":"SalesAgreementHeader"}]},{"parenttable":"AgreementHeaderExt_RU","childtables":[{"childtable":"PurchAgreementHeaderExt_RU"},{"childtable":"SalesAgreementHeaderExt_RU"}]},{"parenttable":"AgreementHeaderHistoryExt_RU","childtables":[{"childtable":"PurchAgreementHeaderHistoryExt_RU"},{"childtable":"SalesAgreementHeaderHistoryExt_RU"}]},{"parenttable":"AifEndpointActionValueMap","childtables":[{"childtable":"AifPortValueMap"},{"childtable":"InterCompanyTradingValueMap"}]},{"parenttable":"BankLCLine","childtables":[{"childtable":"BankLCExportLine"},{"childtable":"BankLCImportLine"}]},{"parenttable":"CAMDataAllocationBase","childtables":[{"childtable":"CAMDataFormulaAllocationBase"},{"childtable":"CAMDataHierarchyAllocationBase"},{"childtable":"CAMDataPredefinedDimensionMemberAllocationBase"}]},{"parenttable":"CAMDataCostAccountingLedgerSourceEntryProvider","childtables":[{"childtable":"CAMDataCostAccountingLedgerCostElementEntryProvider"},{"childtable":"CAMDataCostAccountingLedgerStatisticalMeasureProvider"}]},{"parenttable":"CAMDataDataConnectorDimension","childtables":[{"childtable":"CAMDataDataConnectorChartOfAccounts"},{"childtable":"CAMDataDataConnectorCostObjectDimension"}]},{"parenttable":"CAMDataDataConnectorSystemInstance","childtables":[{"childtable":"CAMDataDataConnectorSystemInstanceAX"}]},{"parenttable":"CAMDataDataOrigin","childtables":[{"childtable":"CAMDataDataOriginDocument"}]},{"parenttable":"CAMDataDimension","childtables":[{"childtable":"CAMDataCostElementDimension"},{"childtable":"CAMDataCostObjectDimension"},{"childtable":"CAMDataStatisticalDimension"}]},{"parenttable":"CAMDataDimensionHierarchy","childtables":[{"childtable":"CAMDataDimensionCategorizationHierarchy"},{"childtable":"CAMDataDimensionClassificationHierarchy"}]},{"parenttable":"CAMDataDimensionHierarchyNode","childtables":[{"childtable":"CAMDataDimensionHierarchyNodeComposite"},{"childtable":"CAMDataDimensionHierarchyNodeLeaf"}]},{"parenttable":"CAMDataImportedDimensionMember","childtables":[{"childtable":"CAMDataImportedCostElementDimensionMember"},{"childtable":"CAMDataImportedCostObjectDimensionMember"},{"childtable":"CAMDataImportedStatisticalDimensionMember"}]},{"parenttable":"CAMDataImportedTransactionEntry","childtables":[{"childtable":"CAMDataImportedBudgetEntry"},{"childtable":"CAMDataImportedGeneralLedgerEntry"}]},{"parenttable":"CAMDataJournalCostControlUnitBase","childtables":[{"childtable":"CAMDataJournalCostControlUnit"}]},{"parenttable":"CAMDataSourceDocumentLine","childtables":[{"childtable":"CAMDataSourceDocumentLineDetail"}]},{"parenttable":"CAMDataTransactionVersion","childtables":[{"childtable":"CAMDataActualVersion"},{"childtable":"CAMDataBudgetVersion"},{"childtable":"CAMDataCalculation"},{"childtable":"CAMDataOverheadCalculation"},{"childtable":"CAMDataSourceTransactionVersion"}]},{"parenttable":"CaseDetailBase","childtables":[{"childtable":"CaseDetail"},{"childtable":"CustCollectionsCaseDetail"},{"childtable":"HcmFMLACaseDetail"}]},{"parenttable":"CatProductReference","childtables":[{"childtable":"CatCategoryProductReference"},{"childtable":"CatClassifiedProductReference"},{"childtable":"CatDistinctProductReference"},{"childtable":"CatExternalQuoteProductReference"}]},{"parenttable":"CustCollectionsLinkTable","childtables":[{"childtable":"CustCollectionsLinkActivitiesCustTrans"},{"childtable":"CustCollectionsLinkCasesActivities"}]},{"parenttable":"CustInterestTransLineIdRef","childtables":[{"childtable":"CustInterestTransLineIdRef_MarkupTrans"},{"childtable":"CustnterestTransLineIdRef_Invoice"}]},{"parenttable":"CustInvoiceLineTemplate","childtables":[{"childtable":"CustInvoiceMarkupTransTemplate"},{"childtable":"CustInvoiceStandardLineTemplate"}]},{"parenttable":"CustVendDirective_PSN","childtables":[{"childtable":"CustDirective_PSN"},{"childtable":"VendDirective_PSN"}]},{"parenttable":"CustVendRoutingSlip_PSN","childtables":[{"childtable":"CustRoutingSlip_PSN"},{"childtable":"VendRoutingSlip_PSN"}]},{"parenttable":"DMFRules","childtables":[{"childtable":"DMFRulesNumberSequence"}]},{"parenttable":"EcoResApplicationControl","childtables":[{"childtable":"EcoResCatalogControl"},{"childtable":"EcoResComponentControl"}]},{"parenttable":"EcoResNomenclature","childtables":[{"childtable":"EcoResDimBasedConfigurationNomenclature"},{"childtable":"EcoResProductVariantNomenclature"},{"childtable":"EngChgProductCategoryNomenclature"},{"childtable":"PCConfigurationNomenclature"}]},{"parenttable":"EcoResNomenclatureSegment","childtables":[{"childtable":"EcoResNomenclatureSegmentAttributeValue"},{"childtable":"EcoResNomenclatureSegmentColorDimensionValue"},{"childtable":"EcoResNomenclatureSegmentColorDimensionValueName"},{"childtable":"EcoResNomenclatureSegmentConfigDimensionValue"},{"childtable":"EcoResNomenclatureSegmentConfigDimensionValueName"},{"childtable":"EcoResNomenclatureSegmentConfigGroupItemId"},{"childtable":"EcoResNomenclatureSegmentConfigGroupItemName"},{"childtable":"EcoResNomenclatureSegmentNumberSequence"},{"childtable":"EcoResNomenclatureSegmentProductMasterName"},{"childtable":"EcoResNomenclatureSegmentProductMasterNumber"},{"childtable":"EcoResNomenclatureSegmentSizeDimensionValue"},{"childtable":"EcoResNomenclatureSegmentSizeDimensionValueName"},{"childtable":"EcoResNomenclatureSegmentStyleDimensionValue"},{"childtable":"EcoResNomenclatureSegmentStyleDimensionValueName"},{"childtable":"EcoResNomenclatureSegmentTextConstant"},{"childtable":"EcoResNomenclatureSegmentVersionDimensionValue"},{"childtable":"EcoResNomenclatureSegmentVersionDimensionValueName"}]},{"parenttable":"EcoResProduct","childtables":[{"childtable":"EcoResDistinctProduct"},{"childtable":"EcoResDistinctProductVariant"},{"childtable":"EcoResProductMaster"}]},{"parenttable":"EcoResProductMasterDimensionValue","childtables":[{"childtable":"EcoResProductMasterColor"},{"childtable":"EcoResProductMasterConfiguration"},{"childtable":"EcoResProductMasterSize"},{"childtable":"EcoResProductMasterStyle"},{"childtable":"EcoResProductMasterVersion"}]},{"parenttable":"EcoResProductWorkspaceConfiguration","childtables":[{"childtable":"EcoResProductDiscreteManufacturingWorkspaceConfiguration"},{"childtable":"EcoResProductMaintainWorkspaceConfiguration"},{"childtable":"EcoResProductProcessManufacturingWorkspaceConfiguration"},{"childtable":"EcoResProductVariantMaintainWorkspaceConfiguration"}]},{"parenttable":"EngChgEcmOriginals","childtables":[{"childtable":"EngChgEcmOriginalEcmAttribute"},{"childtable":"EngChgEcmOriginalEcmBom"},{"childtable":"EngChgEcmOriginalEcmBomTable"},{"childtable":"EngChgEcmOriginalEcmFormulaCoBy"},{"childtable":"EngChgEcmOriginalEcmFormulaStep"},{"childtable":"EngChgEcmOriginalEcmProduct"},{"childtable":"EngChgEcmOriginalEcmRoute"},{"childtable":"EngChgEcmOriginalEcmRouteOpr"},{"childtable":"EngChgEcmOriginalEcmRouteTable"}]},{"parenttable":"FBGeneralAdjustmentCode_BR","childtables":[{"childtable":"FBGeneralAdjustmentCodeICMS_BR"},{"childtable":"FBGeneralAdjustmentCodeINSSCPRB_BR"},{"childtable":"FBGeneralAdjustmentCodeIPI_BR"},{"childtable":"FBGeneralAdjustmentCodePISCOFINS_BR"}]},{"parenttable":"HRPLimitAgreementException","childtables":[{"childtable":"HRPLimitAgreementCompException"},{"childtable":"HRPLimitAgreementJobException"}]},{"parenttable":"IntercompanyActionPolicy","childtables":[{"childtable":"IntercompanyAgreementActionPolicy"}]},{"parenttable":"PaymCalendarRule","childtables":[{"childtable":"PaymCalendarCriteriaRule"},{"childtable":"PaymCalendarLocationRule"}]},{"parenttable":"PCConstraint","childtables":[{"childtable":"PCExpressionConstraint"},{"childtable":"PCTableConstraint"}]},{"parenttable":"PCProductConfiguration","childtables":[{"childtable":"PCTemplateConfiguration"},{"childtable":"PCVariantConfiguration"}]},{"parenttable":"PCTableConstraintColumnDefinition","childtables":[{"childtable":"PCTableConstraintDatabaseColumnDef"},{"childtable":"PCTableConstraintGlobalColumnDef"}]},{"parenttable":"PCTableConstraintDefinition","childtables":[{"childtable":"PCDatabaseRelationConstraintDefinition"},{"childtable":"PCGlobalTableConstraintDefinition"}]},{"parenttable":"RetailMediaResource","childtables":[{"childtable":"RetailImageResource"}]},{"parenttable":"RetailPeriodicDiscount","childtables":[{"childtable":"GUPFreeItemDiscount"},{"childtable":"RetailDiscountMixAndMatch"},{"childtable":"RetailDiscountMultibuy"},{"childtable":"RetailDiscountOffer"},{"childtable":"RetailDiscountThreshold"},{"childtable":"RetailShippingThresholdDiscounts"}]},{"parenttable":"RetailProductAttributesLookup","childtables":[{"childtable":"RetailAttributesGlobalLookup"},{"childtable":"RetailAttributesLegalEntityLookup"}]},{"parenttable":"RetailPubRetailChannelTable","childtables":[{"childtable":"RetailPubRetailMCRChannelTable"},{"childtable":"RetailPubRetailOnlineChannelTable"},{"childtable":"RetailPubRetailStoreTable"}]},{"parenttable":"RetailTillLayoutZoneReferenceLegacy","childtables":[{"childtable":"RetailTillLayoutButtonGridZoneLegacy"},{"childtable":"RetailTillLayoutImageZoneLegacy"},{"childtable":"RetailTillLayoutReportZoneLegacy"}]},{"parenttable":"SCTTracingActivity","childtables":[{"childtable":"SCTTracingActivity_Purch"}]},{"parenttable":"SysMessageTarget","childtables":[{"childtable":"SysMessageCompanyTarget"},{"childtable":"SysWorkloadMessageCompanyTarget"},{"childtable":"SysWorkloadMessageHubCompanyTarget"}]},{"parenttable":"SysPolicyRuleType","childtables":[{"childtable":"SysPolicySourceDocumentRuleType"}]},{"parenttable":"TradeNonStockedConversionLog","childtables":[{"childtable":"TradeNonStockedConversionChangeLog"},{"childtable":"TradeNonStockedConversionCheckLog"}]},{"parenttable":"UserRequest","childtables":[{"childtable":"VendRequestUserRequest"},{"childtable":"VendUserRequest"}]},{"parenttable":"VendRequest","childtables":[{"childtable":"VendRequestCategoryExtension"},{"childtable":"VendRequestCompany"},{"childtable":"VendRequestStatusChange"}]},{"parenttable":"VendVendorRequest","childtables":[{"childtable":"VendVendorRequestNewCategory"},{"childtable":"VendVendorRequestNewVendor"}]},{"parenttable":"WarrantyGroupConfigurationItem","childtables":[{"childtable":"RetailWarrantyApplicableChannel"},{"childtable":"WarrantyApplicableProduct"},{"childtable":"WarrantyGroupData"}]},{"parenttable":"AgreementHeaderHistory","childtables":[{"childtable":"PurchAgreementHeaderHistory"},{"childtable":"SalesAgreementHeaderHistory"}]},{"parenttable":"AgreementLine","childtables":[{"childtable":"AgreementLineQuantityCommitment"},{"childtable":"AgreementLineVolumeCommitment"}]},{"parenttable":"AgreementLineHistory","childtables":[{"childtable":"AgreementLineQuantityCommitmentHistory"},{"childtable":"AgreementLineVolumeCommitmentHistory"}]},{"parenttable":"BankLC","childtables":[{"childtable":"BankLCExport"},{"childtable":"BankLCImport"}]},{"parenttable":"BenefitESSTileSetupBase","childtables":[{"childtable":"BenefitESSTileSetupBenefit"},{"childtable":"BenefitESSTileSetupBenefitCredit"}]},{"parenttable":"BudgetPlanElementDefinition","childtables":[{"childtable":"BudgetPlanColumn"},{"childtable":"BudgetPlanRow"}]},{"parenttable":"BusinessEventsEndpoint","childtables":[{"childtable":"BusinessEventsAzureBlobStorageEndpoint"},{"childtable":"BusinessEventsAzureEndpoint"},{"childtable":"BusinessEventsEventGridEndpoint"},{"childtable":"BusinessEventsEventHubEndpoint"},{"childtable":"BusinessEventsFlowEndpoint"},{"childtable":"BusinessEventsServiceBusQueueEndpoint"},{"childtable":"BusinessEventsServiceBusTopicEndpoint"}]},{"parenttable":"CAMDataCostAccountingPolicy","childtables":[{"childtable":"CAMDataAccountingUnitOfMeasurePolicy"},{"childtable":"CAMDataCostAccountingAccountPolicy"},{"childtable":"CAMDataCostAccountingLedgerPolicy"},{"childtable":"CAMDataCostAllocationPolicy"},{"childtable":"CAMDataCostBehaviorPolicy"},{"childtable":"CAMDataCostControlUnitPolicy"},{"childtable":"CAMDataCostDistributionPolicy"},{"childtable":"CAMDataCostFlowAssumptionPolicy"},{"childtable":"CAMDataCostRollupPolicy"},{"childtable":"CAMDataInputMeasurementBasisPolicy"},{"childtable":"CAMDataInventoryValuationMethodPolicy"},{"childtable":"CAMDataLedgerDocumentAccountingPolicy"},{"childtable":"CAMDataOverheadRatePolicy"},{"childtable":"CAMDataRecordingIntervalPolicy"}]},{"parenttable":"CAMDataJournal","childtables":[{"childtable":"CAMDataBudgetEntryTransferJournal"},{"childtable":"CAMDataCalculationJournal"},{"childtable":"CAMDataCostAllocationJournal"},{"childtable":"CAMDataCostBehaviorCalculationJournal"},{"childtable":"CAMDataCostDistributionJournal"},{"childtable":"CAMDataGeneralLedgerEntryTransferJournal"},{"childtable":"CAMDataOverheadRateCalculationJournal"},{"childtable":"CAMDataSourceEntryTransferJournal"},{"childtable":"CAMDataStatisticalEntryTransferJournal"}]},{"parenttable":"CAMDataSourceDocumentAttributeValue","childtables":[{"childtable":"CAMDataSourceDocumentAttributeValueAmount"},{"childtable":"CAMDataSourceDocumentAttributeValueDate"},{"childtable":"CAMDataSourceDocumentAttributeValueQuantity"},{"childtable":"CAMDataSourceDocumentAttributeValueString"}]},{"parenttable":"CatPunchoutRequest","childtables":[{"childtable":"CatCXMLPunchoutRequest"}]},{"parenttable":"CatUserReview","childtables":[{"childtable":"CatUserReviewProduct"},{"childtable":"CatUserReviewVendor"}]},{"parenttable":"CatVendProdCandidateAttributeValue","childtables":[{"childtable":"CatVendorBooleanValue"},{"childtable":"CatVendorCurrencyValue"},{"childtable":"CatVendorDateTimeValue"},{"childtable":"CatVendorFloatValue"},{"childtable":"CatVendorIntValue"},{"childtable":"CatVendorTextValue"}]},{"parenttable":"CustInvLineBillCodeCustomFieldBase","childtables":[{"childtable":"CustInvLineBillCodeCustomFieldBool"},{"childtable":"CustInvLineBillCodeCustomFieldDateTime"},{"childtable":"CustInvLineBillCodeCustomFieldInt"},{"childtable":"CustInvLineBillCodeCustomFieldReal"},{"childtable":"CustInvLineBillCodeCustomFieldText"}]},{"parenttable":"DIOTAdditionalInfoForNoVendor_MX","childtables":[{"childtable":"DIOTAddlInfoForNoVendorLedger_MX"},{"childtable":"DIOTAddlInfoForNoVendorProj_MX"}]},{"parenttable":"DirPartyTable","childtables":[{"childtable":"CompanyInfo"},{"childtable":"DirOrganization"},{"childtable":"DirOrganizationBase"},{"childtable":"DirPerson"},{"childtable":"OMInternalOrganization"},{"childtable":"OMOperatingUnit"},{"childtable":"OMTeam"}]},{"parenttable":"DOMRules","childtables":[{"childtable":"DOMCatalogAmountFulfillmentTypeRules"},{"childtable":"DOMCatalogMinimumInventoryRules"},{"childtable":"DOMCatalogRules"},{"childtable":"DOMCatalogShipPriorityRules"},{"childtable":"DOMOrgFulfillmentTypeRules"},{"childtable":"DOMOrgLocationOfflineRules"},{"childtable":"DOMOrgMaximumDistanceRules"},{"childtable":"DOMOrgMaximumOrdersRules"},{"childtable":"DOMOrgMaximumRejectsRules"}]},{"parenttable":"DOMRulesLine","childtables":[{"childtable":"DOMRulesLineCatalogAmountFulfillmentTypeRules"},{"childtable":"DOMRulesLineCatalogMinimumInventoryRules"},{"childtable":"DOMRulesLineCatalogRules"},{"childtable":"DOMRulesLineCatalogShipPriorityRules"},{"childtable":"DOMRulesLineOrgFulfillmentTypeRules"},{"childtable":"DOMRulesLineOrgLocationOfflineRules"},{"childtable":"DOMRulesLineOrgMaximumDistanceRules"},{"childtable":"DOMRulesLineOrgMaximumOrdersRules"},{"childtable":"DOMRulesLineOrgMaximumRejectsRules"}]},{"parenttable":"EcoResCategory","childtables":[{"childtable":"PCClass"}]},{"parenttable":"EcoResInstanceValue","childtables":[{"childtable":"CatalogProductInstanceValue"},{"childtable":"CustomerInstanceValue"},{"childtable":"EcoResCategoryInstanceValue"},{"childtable":"EcoResEngineeringProductCategoryAttributeInstanceValue"},{"childtable":"EcoResProductInstanceValue"},{"childtable":"EcoResReleasedEngineeringProductVersionAttributeInstanceValue"},{"childtable":"GUPPriceTreeInstanceValue"},{"childtable":"GUPRebateDateInstanceValue"},{"childtable":"GUPRetailChannelInstanceValue"},{"childtable":"GUPSalesQuotationInstanceValue"},{"childtable":"GUPSalesTableInstanceValue"},{"childtable":"PCComponentInstanceValue"},{"childtable":"RetailCatalogProdInternalOrgInstanceVal"},{"childtable":"RetailChannelInstanceValue"},{"childtable":"RetailInternalOrgProductInstanceValue"},{"childtable":"RetailSalesTableInstanceValue"},{"childtable":"TMSLoadBuildStrategyAttribValueSet"}]},{"parenttable":"EcoResProductVariantDimensionValue","childtables":[{"childtable":"EcoResProductVariantColor"},{"childtable":"EcoResProductVariantConfiguration"},{"childtable":"EcoResProductVariantSize"},{"childtable":"EcoResProductVariantStyle"},{"childtable":"EcoResProductVariantVersion"}]},{"parenttable":"EcoResValue","childtables":[{"childtable":"EcoResBooleanValue"},{"childtable":"EcoResCurrencyValue"},{"childtable":"EcoResDateTimeValue"},{"childtable":"EcoResFloatValue"},{"childtable":"EcoResIntValue"},{"childtable":"EcoResReferenceValue"},{"childtable":"EcoResTextValue"}]},{"parenttable":"EntAssetMaintenancePlanLine","childtables":[{"childtable":"EntAssetMaintenancePlanLineCounter"},{"childtable":"EntAssetMaintenancePlanLineTime"}]},{"parenttable":"HRPDefaultLimit","childtables":[{"childtable":"HRPDefaultLimitCompensationRule"},{"childtable":"HRPDefaultLimitJobRule"}]},{"parenttable":"KanbanQuantityPolicyDemandPeriod","childtables":[{"childtable":"KanbanQuantityDemandPeriodFence"},{"childtable":"KanbanQuantityDemandPeriodSeason"}]},{"parenttable":"MarkupMatchingTrans","childtables":[{"childtable":"VendInvoiceInfoLineMarkupMatchingTrans"},{"childtable":"VendInvoiceInfoSubMarkupMatchingTrans"}]},{"parenttable":"MarkupPeriodChargeInvoiceLineBase","childtables":[{"childtable":"MarkupPeriodChargeInvoiceLineBaseMonetary"},{"childtable":"MarkupPeriodChargeInvoiceLineBaseQuantity"},{"childtable":"MarkupPeriodChargeInvoiceLineBaseQuantityMinAmount"}]},{"parenttable":"PayrollPayStatementLine","childtables":[{"childtable":"PayrollPayStatementBenefitLine"},{"childtable":"PayrollPayStatementEarningLine"},{"childtable":"PayrollPayStatementTaxLine"}]},{"parenttable":"PayrollProviderTaxRegion","childtables":[{"childtable":"PayrollTaxRegionForSymmetry"}]},{"parenttable":"PayrollTaxEngineTaxCode","childtables":[{"childtable":"PayrollTaxEngineTaxCodeForSymmetry"}]},{"parenttable":"PayrollTaxEngineWorkerTaxRegion","childtables":[{"childtable":"PayrollWorkerTaxRegionForSymmetry"}]},{"parenttable":"PCPriceElement","childtables":[{"childtable":"PCPriceBasePrice"},{"childtable":"PCPriceExpressionRule"}]},{"parenttable":"PCRuntimeCache","childtables":[{"childtable":"PCRuntimeCacheXml"}]},{"parenttable":"PCTemplateAttributeBinding","childtables":[{"childtable":"PCTemplateCategoryAttribute"},{"childtable":"PCTemplateConstant"}]},{"parenttable":"RetailChannelTable","childtables":[{"childtable":"RetailDirectSalesChannel"},{"childtable":"RetailMCRChannelTable"},{"childtable":"RetailOnlineChannelTable"},{"childtable":"RetailStoreTable"}]},{"parenttable":"RetailPeriodicDiscountLine","childtables":[{"childtable":"GUPFreeItemDiscountLine"},{"childtable":"RetailDiscountLineMixAndMatch"},{"childtable":"RetailDiscountLineMultibuy"},{"childtable":"RetailDiscountLineOffer"},{"childtable":"RetailDiscountLineThresholdApplying"}]},{"parenttable":"RetailReturnPolicyLine","childtables":[{"childtable":"RetailReturnInfocodePolicyLine"},{"childtable":"RetailReturnReasonCodePolicyLine"}]},{"parenttable":"RetailTillLayoutZoneReference","childtables":[{"childtable":"RetailTillLayoutButtonGridZone"},{"childtable":"RetailTillLayoutImageZone"},{"childtable":"RetailTillLayoutReportZone"}]},{"parenttable":"ServicesParty","childtables":[{"childtable":"ServicesCustomer"},{"childtable":"ServicesEmployee"}]},{"parenttable":"SysPolicyRule","childtables":[{"childtable":"CatCatalogPolicyRule"},{"childtable":"HcmBenefitEligibilityRule"},{"childtable":"HRPDefaultLimitRule"},{"childtable":"HRPLimitAgreementRule"},{"childtable":"HRPLimitRequestCurrencyRule"},{"childtable":"PayrollPremiumEarningGenerationRule"},{"childtable":"PurchReApprovalPolicyRuleTable"},{"childtable":"PurchReqControlRFQRule"},{"childtable":"PurchReqControlRule"},{"childtable":"PurchReqSourcingPolicyRule"},{"childtable":"RequisitionPurposeRule"},{"childtable":"RequisitionReplenishCatAccessPolicyRule"},{"childtable":"RequisitionReplenishControlRule"},{"childtable":"SysPolicySourceDocumentRule"},{"childtable":"TrvPolicyRule"},{"childtable":"TSPolicyRule"}]},{"parenttable":"SysTaskRecorderNode","childtables":[{"childtable":"SysTaskRecorderNodeAnnotationUserAction"},{"childtable":"SysTaskRecorderNodeCommandUserAction"},{"childtable":"SysTaskRecorderNodeFormUserAction"},{"childtable":"SysTaskRecorderNodeFormUserActionInputOutput"},{"childtable":"SysTaskRecorderNodeInfoUserAction"},{"childtable":"SysTaskRecorderNodeMenuItemUserAction"},{"childtable":"SysTaskRecorderNodePropertyUserAction"},{"childtable":"SysTaskRecorderNodeScope"},{"childtable":"SysTaskRecorderNodeTaskUserAction"},{"childtable":"SysTaskRecorderNodeUserAction"},{"childtable":"SysTaskRecorderNodeValidationUserAction"}]},{"parenttable":"SysUserRequest","childtables":[{"childtable":"HcmWorkerUserRequest"},{"childtable":"VendVendorPortalUserRequest"}]},{"parenttable":"TrvEnhancedData","childtables":[{"childtable":"TrvEnhancedCarRentalData"},{"childtable":"TrvEnhancedHotelData"},{"childtable":"TrvEnhancedItineraryData"}]}]'
declare @backwardcompatiblecolumns nvarchar(max) = '_SysRowId,DataLakeModified_DateTime,$FileName,LSN,LastProcessedChange_DateTime';
declare @exlcudecolumns nvarchar(max) = 'Id,SinkCreatedOn,SinkModifiedOn,modifieddatetime,modifiedby,modifiedtransactionid,dataareaid,recversion,partition,sysrowversion,recid,tableid,versionnumber,createdon,modifiedon,isDelete,PartitionId,createddatetime,createdby,createdtransactionid,PartitionId,sysdatastatecode';

--Read JSON variables @enumtranslation and @modeljson in tabular format 
-- table_field_enum_map (tablename, columnname, enum)
-- cdmmetadata(tableschema, tablename, selectcolumns, datatypes, columnnames)
With table_field_enum_map as 
(
	select 
	tablename, 
	columnname, 
	enum as enumtranslation 
	from string_split(@enumtranslation, ';')
	cross apply openjson(value) 
	with (tablename nvarchar(100), columnname nvarchar(100), enum nvarchar(max))
),
cdmmetadata as 
	(select 
			@tableschema as tableschema,
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
				else '['+  t.tablename + '].[' + name + ']' 
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
),
 table_hierarchy as
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
		) x
		group by parenttable
)

select 
	@ddl_fno_derived_tables = string_agg(convert(nvarchar(max), viewDDL ), ';')
	FROM (
			select 
			'begin try  execute sp_executesql N''' +
			replace(replace(replace(replace(replace(replace(@CreateViewDDL + ' ' + h.joins, 			
			'{tableschema}',@tableschema),
			'{selectcolumns}', @addcolumns + selectcolumns + ',' + h.columnnamelists), 
			'{tablename}', tablename), 
			'{environment}', @environment), 
			'{datatypes}', datatypes),
			'''','''''')  
			+ '''' + ' End Try Begin catch print ERROR_PROCEDURE() + '':'' print ERROR_MESSAGE() end catch' as viewDDL
			from cdmmetadata c
			inner join table_hierarchy h on c.tablename = h.parenttable
  	) X;

print(@ddl_fno_derived_tables)
execute sp_executesql @ddl_fno_derived_tables;