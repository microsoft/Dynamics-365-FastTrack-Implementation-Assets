Step 1: Create a new database in Synapse Serveless SQL pool.

```sql
--STEP 1: Create a new database in Synapse serverless 
-- TODO: UPDATE Database as needed, 
IF NOT EXISTS (SELECT 1 FROM sys.databases WHERE name = 'YourNewDataBaseName')
	create database [YourNewDataBaseName]

-- STEP 2: Switch to new database created
--use [YourNewDataBaseName]

--Step 3 : Create Master Key  
-- Create Marker KEY Encryption if not exist - this is required to create database scope credentials 
-- You may choose to create own encryption key instead of generating random as done in script bellow
	DECLARE @randomWord VARCHAR(64) = NEWID();
	DECLARE @createMasterKey NVARCHAR(500) = N'
	IF NOT EXISTS (SELECT * FROM sys.symmetric_keys WHERE name = ''##MS_DatabaseMasterKey##'')
		CREATE MASTER KEY ENCRYPTION BY PASSWORD = '  + QUOTENAME(@randomWord, '''')
	EXECUTE sp_executesql @createMasterKey

```

Step 2: Run the setup script on the database created in step 1. This will create stored procedure and functions in the database. 

[Setup](/EDL_To_SynapseLinkDV_DBSetup/Step1_EDL_To_SynapseLinkDV_CreateUpdate_SetupScript.sql)

Step 3: Run the following script to create openrowset views for all the delta tables on the Synapse serverless database

```sql
-- Prequisites: 
-- 1. Setup synapse link for DV an add tables and have data synced to storage account 
-- 2. To do Enum translation from value to Id, copy the -resolved-cdm.json files to root container  of storage account - you can copy this from existing 
-- export to data lake ChangeFeed folder
-- 3. In storage account, grant Synapse workspace access to roles "Blob data contributor" and "Blob data reader"   
-- Transition Export to data lake to Synapse link for DV easily.

	-- TODO:UPDATE @StorageDS VALUE: Storage account URL including container
	declare @StorageDS nvarchar(1000) = 'https://YourDatalake.dfs.core.windows.net/YourContainer'
	declare @sourcechema nvarchar(100) = 'dbo'
	-- TODO: Set the flag @incrementalCSV = 1 when  storage account is setup for Incremental folder (CSV data), 0 when synpse link is setup with delta conversion
    declare @incrementalCSV int = 0;
	-- TODO: Set the flag @add_EDL_AuditColumns = 1 to add "Export to data lake" audit coulmns, this may help backward compatibility
	declare @add_EDL_AuditColumns int = 0;

	--TODO:Rowset options is only supported on Synapse Serverless and does not work on SQL Server 2022
	declare @rowsetoptions nvarchar(1000) = ''; -- ', ROWSET_OPTIONS =''{"READ_OPTIONS":["ALLOW_INCONSISTENT_READS"]}''';
	
	-- Create the external datasource and return external datasource name
	-- External data sources are used to establish location and connectivity (via database scope credentials) 
	-- between SQL engine and external data store in this case data lake
	-- Creentials can be created using  
	-- 1. MANAGED IDENTITY( Synapse serverless and Azure SQL Managed Instance) 
	-- 2. SHARED ACCESS SIGNATURE (SQL Server 2022 Pollybase)
	-- TODO: Upate @identity an SaaSToken values when using SHARED ACCESS SIGNATURE
	declare @identity nvarchar(100) = 'SHARED ACCESS SIGNATURE';
	declare @SaaSToken nvarchar(1000) = ''

	--TODO: Update @storageDSUriScheme = adls: with Azure SQL Managed Instance or SQL Server 2022
	declare @storageDSUriScheme nvarchar(100) = 'https:'; 
	declare @externalds_name nvarchar(1000);

	-- Calling sp setupExternalDataSource to create database scope credential and external datasource if does not exists
	exec dvtosql.source_SetupExternalDataSource @StorageDS= @StorageDS, @SaaSToken = @SaaSToken, @storageDSUriScheme= @storageDSUriScheme, @externalds_name = @externalds_name Output;

	declare @modeljson nvarchar(max), @enumtranslation nvarchar(max);

	exec dvtosql.source_GetCdmMetadata @externaldatasource = @externalds_name , @modeljson =@modeljson Output, @enumtranslation=@enumtranslation Output;
	
	--select @modeljson, @enumtranslation
	-- call sp source_createOrAlterViews to create openrowset views on SQL endpoint that supports Data virtualization 
	exec dvtosql.source_createOrAlterViews @externalds_name, @modeljson, @enumtranslation, @incrementalCSV, @add_EDL_AuditColumns, @sourcechema, @rowsetoptions

```
