# Overview 

This is C# solution that is built utilizing CDM SDK to simplyfy reading and write CDM metadata. One of the key feature of the solution to read CDM manifest recursively and create view on Synapse Analytics SQL-On-Demand database. 

# Use cases

You can use this solution for following use cases
1. Read the CDM metadata created by Finance and Operations Export to Data lake feature and create view on Synapse Analytics SQL-On-Demand  
2. Read CDM metadata and produce TSQL Statement to create table definition to Azure SQL Database 
3. Write CDM metadata and folder structure to Azure storage based on the input request

# Prerequisites 
- **Install Visual Studio 2019**: to build C# solution you need to Download and Install Visual Studio 2019 and .NET46 framework install https://dotnet.microsoft.com/download/dotnet-framework/thank-you/net462-developer-pack-offline-installer)
- **Synapse Analytics Workspace** [create synapse workspace](https://docs.microsoft.com/en-us/azure/synapse-analytics/quickstart-create-workspace) 
- **Connect to SQL-On-Demand endpoint:** Once you provisioned Synapse workspace, you can use [Synapse Studio](https://docs.microsoft.com/en-us/azure/synapse-analytics/quickstart-synapse-studio) 
or SQL Server Management Studio (SSMS 18.5 or higher) 
or [Azure Data Studio](https://docs.microsoft.com/en-us/sql/azure-data-studio/download-azure-data-studio?toc=/azure/synapse-analytics/toc.json&bc=/azure/synapse-analytics/breadcrumb/toc.json&view=azure-sqldw-latest). 
For details check [supported tools](https://docs.microsoft.com/en-us/azure/synapse-analytics/sql/connect-overview#supported-tools-for-sql-on-demand-preview)


## Setup Storage Account 
1. In Azure portal, go to Storage account and grant Blob Data Contributor and Blob Data Reader access to Azure Function App MSI
![Storage Access](/Analytics/AADAppStorageAccountAccess.PNG)

## Setup Azure Synapse Analytics and SQL-On-Demand(Serverless)
ADF solution can also read the CDM metadata and create views on SQL-OnDemand.To use the automation complete following steps
1. **Create Database:** Before you can create views and external table to query data using TSQL, you need to create Database. 
```SQL
CREATE DATABASE AXDB
```
2. **Create datasource:**
```SQL
-- create master key that will protect the credentials:
CREATE MASTER KEY ENCRYPTION BY PASSWORD = <enter very strong password here>

-- create credentials for containers in our demo storage account
-- Replace your storage account location and provide shared access signature
CREATE DATABASE SCOPED CREDENTIAL mydatalake
WITH IDENTITY='SHARED ACCESS SIGNATURE',  
SECRET = 'sv=2018-03-28&ss=bf&srt=sco&sp=rl&st=2019-10-14T12%3A10%3A25Z&se=2061-12-31T12%3A10%3A00Z&sig=KlSU2ullCscyTS0An0nozEpo4tO5JAgGBvw%2FJX2lguw%3D'
GO
CREATE EXTERNAL DATA SOURCE mydatalakeds WITH (
    LOCATION = 'https://mydatalake.dfs.core.windows.net',
    CREDENTIAL = mydatalake
);
```
3. **Create Azure Function MSI App as User on SQL:**
```SQL
use AXDB
go
-- replace with your Azure functionName
Create user [ABCCDMUtilAzureFunctions] FROM EXTERNAL PROVIDER;
alter role db_owner Add member [ABCCDMUtilAzureFunctions]
```
For more details follow the documentation [First time setup](https://docs.microsoft.com/en-us/azure/synapse-analytics/quickstart-sql-on-demand#first-time-setup)   

## Functions overview 

1. ***/manifestToSynapseView***
  Method: Post
  Headers: TenantId, StorageAccount, RootFolder, ManifestLocation, ManifestName, DataSourceName, SQLEndPoint
  Description : Connect to storage account using MSI auth and read manifest file recursively, create view definition and execute script to Synapse SQL-On-Demand to create view defintion
 
2. ***/manifestToSQLDDL***
  TenantId, StorageAccount, RootFolder, ManifestLocation, ManifestName
  Description : Connect to storage account using MSI auth and read manifest file recursively, create view definition and execute script to Synapse SQL-On-Demand to create view defintion
3. ***/getManifestDefinition***
   Method: Get
   Headers: TableList= CUSTTABLE,NUMBERSEQUENCETABLE 
   Solution maintain a Json file that is used to Map the tables with their relative path in the Storage account. This can be used to identify folder location of the table when writing CDM metadata for a table. 
4. ***/createManifest***
 Method: Post,
 headers: TenantId, StorageAccount, RootFolder, LocalFolder, CreateModelJson 
 
# Using CDMUtil Solution 
1.	Clone the repository [Dynamics-365-FastTrack-Implementation-Assets](https://github.com/microsoft/Dynamics-365-FastTrack-Implementation-Assets)
![Clone](/Analytics/CloneRepository.PNG)
2. Open C# solution Microsoft.CommonDataModel.sln in Visual Studio 2019 and build

## Using CDM Solution Locally 
1. Right Click on Project CDMUtil_AzureFunctions and set as Startup project 
2. Click Debug - Azure Function CLI will open up 
3. Download and install [Postman](https://www.postman.com/downloads/) if you dont have it already.
4. Import [PostmanCollection](/Analytics/CDMUtilSolution/CDMUtil.postman_collection)
5. Collection contains request for all methods with sample header value 
5. Change the header values as per your environment for requests and send the request 
6. In case error you can debug the local code.

## Deploy C# Solution as Azure function 
1.	Publish the CDMUtil_AzureFunctions Project as Azure function 
    1. Right-click on the project CDMUtil_AzureFunctions from Solution Explorer and select "Publish". 
    2. Select Azure as Target and selct Azure Function Apps ( Windows) 
    3. Click Create new Azure Function App and select subscription and resource group to create Azure function app 
    4. Click Publish ![Publish Azure Function](/Analytics/DeployAzureFunction.gif)
2. Open Azure Portal and locate Azure Function App created.
3. ***Enable MSI*** go to Identity tab enable [System managed identity](/Analytics/EnableMSI.PNG) 
4. Add Azure Function MSI app to SQL-On-Demand - follow steps above "Create Azure Function MSI App as User on SQL" 
5. Use Postman to valudate. You can further utilize ultilize any other integration tools such as Logic App, Azure data factory ect to create endto end integration 
5. To learn more aboubt Azure functions follow the link [Azure functions in Visual Studio](https://docs.microsoft.com/en-us/azure/azure-functions/functions-develop-vs)
 
