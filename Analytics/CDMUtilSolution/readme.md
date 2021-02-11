# Overview 
CDMUtil is C# solution that can read CDM metadata recursively and produce TSQL DDL Statement to create View or Extenral table on Synapse Analytics Serverless SQL Pool database. 
You can use this solution to read the CDM metadata created by Finance and Operations Export to Data lake feature and create view or external tables on Synapse Analytics Serverless SQL Pool database.

# Setup Azure Synapse Analytics Workspace
- **Create Synapse Analytics Workspace** [create synapse workspace](https://docs.microsoft.com/en-us/azure/synapse-analytics/quickstart-create-workspace) 
- **Connect to SQL-On-Demand endpoint:** Once you provisioned Synapse workspace, you can use [Synapse Studio](https://docs.microsoft.com/en-us/azure/synapse-analytics/quickstart-synapse-studio) 
or SQL Server Management Studio (SSMS 18.5 or higher) 
or [Azure Data Studio](https://docs.microsoft.com/en-us/sql/azure-data-studio/download-azure-data-studio?toc=/azure/synapse-analytics/toc.json&bc=/azure/synapse-analytics/breadcrumb/toc.json&view=azure-sqldw-latest). 
For details check [supported tools](https://docs.microsoft.com/en-us/azure/synapse-analytics/sql/connect-overview#supported-tools-for-sql-on-demand-preview)
- To learn basics and get started on Synapse Analytics [Get Started](https://azure.microsoft.com/en-us/blog/quickly-get-started-with-samples-in-azure-synapse-analytics/)

## Synapse Analytics Serverless SQL Pool- First time setup 
To create views or external tables from CDM metadata on Synapse Serverless SQL Pool you need to complete basics setup. 
Follow the steps bellow to complete the first time setup

1. **Create Database:** 
Before you can create views and external table to query data using TSQL, you need to create Database. 
```SQL
CREATE DATABASE AXDB
```

2. **Create datasource:**
To run queries using serverless SQL pool, create data source that serverless SQL pool can use use to access files in storage. 
Execute the following code snippet to create data source:
```SQL
-- create master key that will protect the credentials:
CREATE MASTER KEY ENCRYPTION BY PASSWORD = <enter very strong password here>

-- create credentials for co for your storage account

-- Option 1: you can create credential using managed identity . When using managed identity make sure to add Storage account blob data reader access
-- https://docs.microsoft.com/en-us/azure/synapse-analytics/sql/develop-storage-files-storage-access-control?tabs=managed-identity

CREATE DATABASE SCOPED CREDENTIAL myenvironment
WITH IDENTITY='Managed Identity'

-- Option2 : Create Crednetial using Shared Access Signature
-- Replace your storage account location 
-- Generare Shared access signature for your storage account from Azure portal and replace Secret value with generated SAS Secret
CREATE DATABASE SCOPED CREDENTIAL myenvironment
WITH IDENTITY='SHARED ACCESS SIGNATURE',  
SECRET = 'sv=2018-03-28&ss=bf&srt=sco&sp=rl&st=2019-10-14T12%3A10%3A25Z&se=2061-12-31T12%3A10%3A00Z&sig=KlSU2ullCscyTS0An0nozEpo4tO5JAgGBvw%2FJX2lguw%3D'
GO

CREATE EXTERNAL DATA SOURCE myenvironmentds WITH (
    LOCATION = 'https://mydatalake.dfs.core.windows.net/dynamics365-financeandoperations/myenvironment.cloudax.dynamics.com',
    CREDENTIAL = myenvironment
);


```

3. **Create external files formats:**
To create external tables on SQL Pool, you need to create external file format. You can use bellow sample scropt to create external file format
```
-- create external files formats
CREATE EXTERNAL FILE FORMAT CSV
WITH (  
    FORMAT_TYPE = DELIMITEDTEXT,
    FORMAT_OPTIONS ( FIELD_TERMINATOR = ',', STRING_DELIMITER = '"', FIRST_ROW = 1   )
);
GO
CREATE EXTERNAL FILE FORMAT ParquetFormat WITH (  FORMAT_TYPE = PARQUET );
```
4. **Create Schema:**
You can create Schema to logically seperate different types of artifacts 
```
-- Create Schema 
create Schema Tables;
Create Schema ChangeFeed
```
5. **Create AAD User:**
Use following script to create AAD users on Serverless SQL Pool.
```SQL
-- create AAD users 
--Step 1-  create AAD Login
use master
go
CREATE LOGIN [jiyada@microsoft.com] FROM EXTERNAL PROVIDER;
-- Step 2 
-- Option 1 - Add server level so to grant access to all databases 
	ALTER SERVER ROLE  sysadmin  ADD MEMBER [jiyada@microsoft.com];

--Option 2 - Add database level access to 
	use AXDB -- Use your DB name
	go
	CREATE USER jiyada FROM LOGIN [jiyada@microsoft.com];
	alter role db_owner Add member jiyada -- Type USER name from step 2
```
6. **Create MSI App as User:**
You can deploy CDMUtil solution as FunctionApp to fully automate the view or external table creation. You can use this sample script to add MSI App as user such as (Azure function App, Azure Data Factory etc) 
```SQL
-- Use this script sample to create MSI App User on SQLPool Serverless (Make sure to login with AAD credential)
--replace with your MSI App Name Azure functionName
use AXDB
go
Create user [ABCCDMUtilAzureFunctions] FROM EXTERNAL PROVIDER;
alter role db_owner Add member [ABCCDMUtilAzureFunctions]
```

## Setup Storage Account 
For CDMUtil solution to read CDM metadata from your storage account, ***application user*** must grant ***Blob Data Contributor*** and ***Blob Data Reader*** access to your AAD account.
1. In Azure portal, go to Storage account and grant Blob Data Contributor and Blob Data Reader access to current user 
2. In case solution is Deployed as Azure Function Apps, you must enable ***System managed identity*** and grant MSI app Blob Data Contributor and Blob Data Reader access 
![Storage Access](/Analytics/AADAppStorageAccountAccess.PNG)

# Using CDMUtil Solution
You can utilize the CDMUtil application to read CDM metadata and create External table or view on  Synapse Serverless SQL Pool 

## Option 1 - CDMUtil Console App 
For simple POC scenario you can execute the CDM Util solution as a Console Application and create view or external table on Synapse Serverless SQL Pool.
1. Download the Console Application executable [CDMUtilConsoleApp.zip](/Analytics/CDMUtilSolution/CDMUtilConsoleApp.zip)
2. Extract the zip file and extract to local folder 
3. Open CDMUtil_ConsoleApp.dll.config file and update the parameters as per your setup
4. Console application will use AccessKey to read cdm files from data lake and use sql login to create view on synapse serverless
```XML
<?xml version="1.0" encoding="utf-8" ?>
<configuration>
  <appSettings>
   <add key="TenantId" value="00000000-86f1-41af-91ab-0000000" />
    <add key="StorageAccount" value="mylake.dfs.core.windows.net" />
    <add key="AccessKey" value="YourStorageAccountAccessKey" />
     <add key="RootFolder" value="/dynamics365-financeandoperations/Yourenvironmentfolder.dynamics.com" />
    <add key="ManifestFilePath" value="/Tables/Tables.manifest.cdm.json" />
    <add key="TargetDbConnectionString" value="Server=yoursynapse-ondemand.sql.azuresynapse.net;Database=YourDB;Uid=sqluser;Pwd=Password" />
    <add key="DataSourceName" value="yourdatasourcename" />
    <add key="DDLType" value="SynapseView" />
    <add key="Schema" value="dbo" />
    <add key="FileFormat" value="CSV" />
    <add key="CovertDateTime" value ="false"/>
  </appSettings>
</configuration>
```
4. Run CDMUtil_ConsoleApp.exe
5. Application will use current users to connect to storage account to read the CDM metadata, convert it to SQL DDL statements and execute on the Synapse.

## Option 2 - Deploy CDMUtil as Azure Function App
For advance automation scenarios, you can deploy the CDMUtil solution as Azure function to automate end to end process of creating or updating view and external table on Synapse. 
1. **Install Visual Studio 2019**: to build C# solution you need to Download and Install Visual Studio 2019 and .NET46 framework install https://dotnet.microsoft.com/download/dotnet-framework/thank-you/net462-developer-pack-offline-installer)
2.	Clone the repository [Dynamics-365-FastTrack-Implementation-Assets](https://github.com/microsoft/Dynamics-365-FastTrack-Implementation-Assets)
![Clone](/Analytics/CloneRepository.PNG)
3. Open C# solution Microsoft.CommonDataModel.sln in Visual Studio 2019 and build

### Functions overview 

1. ***/manifestToSQL:*** 
This function connect to storage account using MSI auth and read manifest file recursively, create TSQL DDL definition and execute to Synapse Serverless SQL Poll to create view or external tables defintion.

**Method**: Post

| Headers           | Example   |
| ----------------- |:--------------|
|TenantId          | 979fd422-22c4-4a36-bea6-1cf87b6502dd|
|StorageAccount    | ftanalyticsd365fo.dfs.core.windows.net      |
|RootFolder         |/dynamics365-financeandoperations/analytics.sandbox.operations.dynamics.com/|
|ManifestLocation   |ChangeFeed|
|ManifestName       |ChangeFeed|
|DataSourceName     |analytics|
|SQLEndPoint        |Server=ftsasynapseworkspace-ondemand.sql.azuresynapse.net;Database=Anylytics_AXDB|
|DDLType            |SynapseView or SynapseExternalTable or SqlTable|

2. ***/manifestToSQLDDL:***
This function, connect to storage account using MSI auth and read manifest file recursively, create TSQL DDL definition for view or external tables defintion for SQL Pool and return the DDL definition as result.

**Method**: Post

| Headers           | Example   |
| ----------------- |:--------------|
|TenantId           | 979fd422-22c4-4a36-bea6-1cf87b6502dd|
|StorageAccount     | ftanalyticsd365fo.dfs.core.windows.net      |
|RootFolder         |/dynamics365-financeandoperations/analytics.sandbox.operations.dynamics.com/|
|ManifestLocation   |ChangeFeed|
|ManifestName       |ChangeFeed|
|DataSourceName     |analytics|
|DDLType            |SynapseView or SynapseExternalTable or SqlTable|

3. ***/getManifestDefinition:***
This function is used for creating CDM metadata. Solution maintain a Json file that is used to Map the tables with their relative path in the Storage account. This can be used to identify folder location of the table when writing CDM metadata for a table. 
**Method**: Get

| Headers           | Example   |
| ----------------- |:--------------|
|TableList|CUSTTABLE,NUMBERSEQUENCETABLE|


4. ***/createManifest***
This function is used for creating CDM metadata.
**Method**: Post

| Headers           | Example   |
| ----------------- |:--------------|
|TenantId           | 979fd422-22c4-4a36-bea6-1cf87b6502dd|
|StorageAccount     | ftanalyticsd365fo.dfs.core.windows.net|
|RootFolder         |/dynamics365-financeandoperations/analytics.sandbox.operations.dynamics.com/|
|LocalFolder        |/Tables/Custom/ABCTables|
|CreateModelJson    |true|

**Body**: 
```Json
{
  "manifestName": "Customers",
  "entityDefinitions": [
    {
      "name": "CustGroup",
      "description": "CustGroup",
      "corpusPath": "/jjd365fo2d9ba7ea6d7563beaos.cloudax.dynamics.com/Tables/Customers/CustGroup.cdm.json/CustGroup",
      "dataPartitionLocation": "/CustGroup",
      "partitionPattern": "*.csv",
      "attributes": [
        {
          "name": "CUSTGROUP",
          "dataType": "string",
          "isNullable": "true",
          "description": "CUSTGROUP"
        },
        {
          "name": "NAME",
          "dataType": "string",
          "isNullable": "true",
          "description": "NAME"
        },
        {
          "name": "DATAAREAID",
          "dataType": "string",
          "isNullable": "true",
          "description": "DATAAREAID"
        },
        {
          "name": "RECID",
          "dataType": "bigInteger",
          "isNullable": "true",
          "description": "RECID"
        }
      ]
    }
  ]
}
```

## Using CDMUtil FunctionApp Locally 
For debugging or executing the CDM Util solution locally, follow bellow steps to execute CDMUtil application localy 
1. Right Click on Project CDMUtil_AzureFunctions and set as Startup project 
2. In Visual Studio select account for authentication Tools>Options>Azure Service Authentication> Account selection
3. Selected account must have Storage Blob Data Contributor and Storage Blob Data Reader access on the Storage account and AAD access on the SQL-On-Demand endpoint
4. Click Debug - Azure Function CLI will open up 
5. Download and install [Postman](https://www.postman.com/downloads/) if you dont have it already.
6. Import [PostmanCollection](/Analytics/CDMUtilSolution/CDMUtil.postman_collection)
7. Collection contains request for all methods with sample header value 
8. Change the header values as per your environment for requests and send the request 
9. If you get into error, you can debug the local code using Visual Studio.

## Deploy CDMUtil application as Azure function 
Follow the steps bellow to deploy CDMUtil application as Azure function app
1.	Publish the CDMUtil_AzureFunctions Project as Azure function 
    1. Right-click on the project CDMUtil_AzureFunctions from Solution Explorer and select "Publish". 
    2. Select Azure as Target and selct Azure Function Apps ( Windows) 
    3. Click Create new Azure Function App and select subscription and resource group to create Azure function app 
    4. Click Publish ![Publish Azure Function](/Analytics/DeployAzureFunction.gif)
2. Open Azure Portal and locate Azure Function App created.
3. ***Enable MSI*** go to Identity tab enable [System managed identity](/Analytics/EnableMSI.PNG) 
4. On the Storage account grant Azure Function Storage Blob Data Contributor and Storage Blob Data Reader access 
5. Add Azure Function MSI app to SQL-On-Demand - follow steps above "Create Azure Function MSI App as User on SQL" 
6. You can further utilize  any other integration tools such as Logic App, Azure data factory to call Azure functions and create end to end integration 
7. To learn more aboubt Azure functions follow the link [Azure functions in Visual Studio](https://docs.microsoft.com/en-us/azure/azure-functions/functions-develop-vs)

## Create Data Entities as View on Synapse SQL Serverless
Once you have created Tables as view or external table. You can create additional view on Synapse Serverless. Customer that are using BYOD for reporting and BI scenarios with Dynamics 365 for Finance and Operations Apps, may wants to create BYOD Statging table or Data Entity Schema as view so that their reports and solution can work without much of change. As you might know that Data entities in AXDB are nothing but views, so you can copy the view definition and create that on Synapse SQL Serveless to get the same schema as you have in BYOD. 

Once tables views are present you can copy the view definition of Data entities from AXDB and create view on synapse. Sometime entities may have several level of dependencies on tables or views and help with that you can use bellow script that you can execute on the AXDB and get the view definition with dependencies 

![View Definition and Dependency](/Analytics/CDMUtilSolution/ViewsAndDependencies.sql)

 
