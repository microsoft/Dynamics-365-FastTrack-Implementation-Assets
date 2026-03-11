-- Dec 21 - bug fix on data entity - filter deleted rows 
--Dec 9 - Added support for enum translation from globaloptionset 
-- added support for data entity removing mserp_ prefix from column name
-- Prequisites: 
-- 1. Setup synapse link for DV an add tables and have data synced to storage account 
-- 2. To do Enum translation from value to Id, copy the -resolved-cdm.json files to root container  of storage account - you can copy this from existing 
-- export to data lake ChangeFeed folder
-- 3. In storage account, grant Synapse workspace access to roles "Blob data contributor" and "Blob data reader"   
-- Transition Export to data lake to Synapse link for DV easily.

	-- TODO:UPDATE @StorageDS VALUE: Storage account URL including container
	declare @StorageDS nvarchar(1000) = 'https://{yourstorageaccount}.dfs.core.windows.net/{yourcontainer}'
	declare @sourcechema nvarchar(100) = 'dbo'
	-- TODO: Set the flag @incrementalCSV = 1 when  storage account is setup for Incremental folder (CSV data), 0 when synpse link is setup with delta conversion
    declare @incrementalCSV int = 0;
	-- TODO: Set the flag @add_EDL_AuditColumns = 1 to add "Export to data lake" audit coulmns, this may help backward compatibility
	declare @add_EDL_AuditColumns int = 1;

	--TODO:Rowset options is only supported on Synapse Serverless and does not work on SQL Server 2022
	declare @rowsetoptions nvarchar(1000) = ''; -- ', ROWSET_OPTIONS =''{"READ_OPTIONS":["ALLOW_INCONSISTENT_READS"]}''';

	--TODO: set value 1 or 0 to add enum translation - this will add new column for enumtranslation with columnname_$label  
	declare @translate_enums int = 1;

	--TODO: set value 1 or 0 to remove mserp_ prefix from the entity name and column names
	declare @remove_mserp_prefix int = 1;
	
	-- TODO: set value 1 or 0 to convert simple entity optionset values to BYOD enum values
	-- Added to support BYOD simple entities
	-- Requires enum values to be pushed to srsanalysisenums
	declare @translate_BYOD_enums int = 0;

	-- Create the external datasource and return external datasource name
	-- External data sources are used to establish location and connectivity (via database scope credentials) 
	-- between SQL engine and external data store in this case data lake
	-- Creentials can be created using  
	-- 1. MANAGED IDENTITY( Synapse serverless and Azure SQL Managed Instance) - recomended
	-- 2. SHARED ACCESS SIGNATURE (SQL Server 2022 Pollybase)
	-- TODO: Upate @identity an SaaSToken values when using SHARED ACCESS SIGNATURE
	declare @identity nvarchar(100) = 'MANAGED IDENTITY';
	declare @SaaSToken nvarchar(1000) = ''

	--TODO: Update @storageDSUriScheme = adls: with Azure SQL Managed Instance or SQL Server 2022 with Synapse serverless use https:
	declare @storageDSUriScheme nvarchar(100) = 'https:'; 
	declare @externalds_name nvarchar(1000);

	-- Calling sp setupExternalDataSource to create database scope credential and external datasource if does not exists
	exec dvtosql.source_SetupExternalDataSource @StorageDS= @StorageDS, @SaaSToken = @SaaSToken, @storageDSUriScheme= @storageDSUriScheme, @externalds_name = @externalds_name Output;

	declare @modeljson nvarchar(max), @enumtranslation nvarchar(max);

	exec dvtosql.source_GetCdmMetadata @externaldatasource = @externalds_name , @modeljson =@modeljson Output, @enumtranslation=@enumtranslation Output;
	
	--select @modeljson, @enumtranslation
	-- call sp source_createOrAlterViews to create openrowset views on SQL endpoint that supports Data virtualization 
	exec dvtosql.source_createOrAlterViews @externalds_name, @modeljson, @enumtranslation, @incrementalCSV, @add_EDL_AuditColumns, @sourcechema, @rowsetoptions, @translate_enums, @remove_mserp_prefix, @translate_BYOD_enums


	-- Script create external data source and credential with the name of container in the storage account url
	-- In case of permission error  to access data from datalake validate storage url and access control for synapse workspace to data lake
	-- drop external data source and credential and rerun above script again to recreate the credentials and external datasource 
	--drop external data source [YourContainerName]
	--drop DATABASE SCOPED CREDENTIAL [YourContainerName]
