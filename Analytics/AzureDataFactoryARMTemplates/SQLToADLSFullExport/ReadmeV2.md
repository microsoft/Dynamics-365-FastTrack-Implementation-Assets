# Overview 

SQLToLake V2 is a generic solution to export SQLServer (on-premise or Azure SQL) tables data to Azure Data lake Gen 2 account in [Common data model](https://docs.microsoft.com/en-us/common-data-model/) format. Solution utilize Azure data factory pipelines and Azure function based on [CDM SDK](https://github.com/microsoft/CDM/tree/master/objectModel/CSharp) to copy SQL tables data and generate CDM metadata to Azure storage account. Solution can also read the CDM manifest recursively and create view on Synapse Analytics SQL-On-Demand database. 

# Use cases
You can use this Data factory solution  for following use cases
1. Ingest on-premise SQL Database or Azure SQL database to Azure data lake in CDM format
2. Ingest your on-premise Dynamics AX data to Azure data lake in CDM format
3. Ingest Finance and Operations app data from Tier 1 or Tier 2 environment to Azure data lake in CDM format (A workaround to [Tables in Data Lake](https://docs.microsoft.com/en-us/dynamics365/fin-ops-core/dev-itpro/data-entities/finance-data-azure-data-lake) feature to build POC)

# SQLToADLS Full Export V2 Highlights  
If you are new to Azure Data Factory, Azure functions and Synapse Analytics, we recomend to try [Version 1](https://github.com/microsoft/Dynamics-365-FastTrack-Implementation-Assets/blob/master/Analytics/AzureDataFactoryARMTemplates/SQLToADLSFullExport/README.md) first to get familier with some of the basic concepts. Version 2 of Data factory solution, primarly utilize C# solution that is based on CDM SDK deployed as Azure function to automate some of the manual steps to create views in Synapse analytics. This version also generate folder structure and metadata similar to F&O Tables in Lake feature. Following are some highlights of this updated version of data factory solution
1. Generate Finance and Operations [CDM folder structure](https://github.com/microsoft/CDM/tree/master/schemaDocuments/core/operationsCommon/Tables) in data lake
2. Automatically partition data for large tables  
3. Geneate metadata in [Manifest](https://docs.microsoft.com/en-us/common-data-model/cdm-manifest) format.  
5. Read metadata (manifest) and create views in SQLOn-Demand 

# Prerequisites 
- **Azure subscription**. You will require **contributor access** to an existing Azure subscription. If you don't have an Azure subscription, create a [free Azure account](https://azure.microsoft.com/en-us/free/) before you begin. 
- **Azure storage account**. If you don't have a storage account, see [Create an Azure storage account](https://docs.microsoft.com/en-us/azure/storage/common/storage-account-create?tabs=azure-portal#create-a-storage-account) for steps to create one.
- **Azure data factory** - Create an Azure Data Factory resource follow the steps to [create a Data factory](https://docs.microsoft.com/en-us/azure/data-factory/tutorial-copy-data-portal#create-a-data-factory)
- **Synapse Analytics Workspace** [create synapse workspace](https://docs.microsoft.com/en-us/azure/synapse-analytics/quickstart-create-workspace) 
- **Connect to SQL-On-Demand endpoint:** Once you provisioned Synapse workspace, you can use [Synapse Studio](https://docs.microsoft.com/en-us/azure/synapse-analytics/quickstart-synapse-studio) or SQL Server Management Studio (SSMS 18.5 or higher) or [Azure Data Studio](https://docs.microsoft.com/en-us/sql/azure-data-studio/download-azure-data-studio?toc=/azure/synapse-analytics/toc.json&bc=/azure/synapse-analytics/breadcrumb/toc.json&view=azure-sqldw-latest). For details check [supported tools](https://docs.microsoft.com/en-us/azure/synapse-analytics/sql/connect-overview#supported-tools-for-sql-on-demand-preview)
- **Create Database:** Before you can query data using TSQL, you need to create Database. Follow the documentation [First time setup](https://docs.microsoft.com/en-us/azure/synapse-analytics/quickstart-sql-on-demand#first-time-setup)   
- **Install Visual Studio 2019**: C# solution  Azure function C# Solution  
# Deployment steps
## Create Azure Application and Secret 
Create an Azure Active directory application and secret, this  AAD Application is used by Azure function to access Azure storage account to create and read CDM metadata. Follow the bellow steps to create the Azure Active directory application.
1. [Register an Active directory App](https://docs.microsoft.com/en-us/azure/active-directory/develop/quickstart-register-app) and record Application Id
2. [Create Application Secret](https://docs.microsoft.com/en-us/azure/healthcare-apis/register-confidential-azure-ad-client-app#application-secret) and record Application Secret
3. Get your Azure Tenant ID  Azure Portal > Azure Active Directory > Tenant information > Tenant ID
## 

## Deploy C# Solution as Azure function 
1.	[Clone the repository] https://github.com/microsoft/Dynamics-365-FastTrack-Implementation-Assets and open C# solution in Visual Studio 2019 [Visual Studio Solution](/Analytics/CDMUtilSolution)
2.	Build the solution
3.  update local.setting.json under CDMUtil_AzureFunctions to as per your environment configurations   
```json
{
  "IsEncrypted": false,
  "Values": {
    // These parameters are used by Azure function to authenticate to Azure storage account to create and read metadata files
    "MSIAuth": "false", // 1st: If set to true then Azure function will use Managed Identity to authenticate to Azure storage account. 
    "TenantId": "YourTenantId", // 2nd: Azure Tenant ID, AppId and AppSecret - used to authenticate to Azure storage account.
    "AppId": "YourAppId", 
    "AppSecret": "AppSecret", 
    "SharedKey":"ADLSSharedKey", // 3rd auth option - Azure function will use shared key to authenticate to datalake
    // These parameters are used by to create view on Synapse Analytics SQL-On-Demand
    "createDS": "false", // create DS while creating view on Synapse
    "SAS": "Secure Access Signature of your data lake", // only needed when createDS = true, used for created DataSet on Synapse 
    "Password": "979fd422-22c4", // Strong password only needed when createDS = true used for creting a master key on Synapse 
    "SQL-On-Demand": "Server=YourSQLOnDemandDB-ondemand.sql.azuresynapse.net;Database=DBName;User Id=UserId;Password=Password" // Synapsse SQLOn-Demand Connection details 
  }
}
```
4.	Publish the CDMUtil_AzureFunctions Project as Azure function (Ensure that local.Settings.json values are copied during deployment) 
    ![Publish Azure Function](/Analytics/Publish.PNG)
5.	Get your Azure function URL and Key
6.  Ensure that all configuration from local.settings.json in the Azure function app configuration tab.
  ![Azure Function Configurations](/Analytics/AzureFunctionConfiguration.PNG)

## Setup Storage Account 
1. In Azure portal, go to Storage account and grant Blob Data Contributor and Blob Data Reader access to AAD Application created in previous step
![Storage Access](/Analytics/AADAppStorageAccountAccess.PNG)
2. Create a container dynamics365-financeandoperations
3. Create a folder under container to represent your environment name ie - analyticsPerf87dd1496856e213a.cloudax.dynamics.com
4. Download /SQLToADLSFullExport/example-public-standards.zip
5. Extract and upload all files to root folder ie. environment folder 

## Deploy Azure Data Factory Template 
1. Collect all parameters values 

| Parameter name                                       | Description                       | Example                |
| :--------------------                                | :---------------------:           | --------------------:  |
|factoryName                                           | Name of your data factory         |SQLToDataLake           |
|StorageAccount                                        | name of the storage account       |d365fodatalakestorage   |
|DataLakeGen2Storage_accountKey                        | storage account access key        |Secret key              |
|Container                                             | storage account container         | dynamics365-financeandoperations |  
|RootFolder                                            | root folder                       | jjd365fo2d9ba7ea6d7563beaos.cloudax.dynamics.com | 
|SQLDB_connectionString                                | SourceSQL DB connection string    |data source=dbservername.database.windows.net;initial catalog=databasename;user id=userid;password=PassWord             |    
|CDMUTIL_functionAppUrl                                | Azure function URI                | https://cdmutil.azurewebsites.net|
|CDMUTIL_functionKey                                   | Function key                      | Access key|


2. Download the [ARM template file](/Analytics/AzureDataFactoryARMTemplates/SQLToADLSFullExport/arm_templateV2.json) to your local directory.
3. Click [Template deployment] https://ms.portal.azure.com/#create/Microsoft.Template
4. Click  Build your own template in the editor option
5. Click load file and locate the ARM template file you downloaded ealrier and click Save.
6. Provide required parameters and Review + create. 
![Custom deployment](/Analytics/AzureDataFactoryARMTemplates/SQLToADLSFullExport/CustomDeployment_LI.jpg)

## Execute pipelines 
1. Execute pipeline SQLTablesToADLS to exort data and create CDM metadata

2. Execute pipeline CreateView to create the views

# Troubleshooting 
1. If your pipleline fails on the Azure function calls, validate your Azure function configuration.
2. you can also debug C# code by running the CDMUtil_AzureFunctions locally and PostMan - Postman template can be found under /SQLToADLSFullExport/CDMUtil.postman_collection you can find input parameters for Azure function in Azure data factory pipeline execution history. 

