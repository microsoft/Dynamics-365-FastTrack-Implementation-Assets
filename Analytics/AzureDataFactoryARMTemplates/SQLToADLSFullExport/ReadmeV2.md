# Overview 

SQLToLake V2 is a generic solution to export SQLServer (on-premise or Azure SQL) tables data to Azure Data lake Gen 2 account in [Common data model](https://docs.microsoft.com/en-us/common-data-model/) format. Solution utilize Azure data factory pipelines and Azure function based on [CDM SDK](https://github.com/microsoft/CDM/tree/master/objectModel/CSharp) to copy SQL tables data and generate CDM metadata to Azure storage account. Solution can also read the CDM manifest recursively and create view on Synapse Analytics SQL-On-Demand database. 

# Use cases
You can use this Data factory solution  for following use cases
1. Ingest on-premise SQL Database or Azure SQL database to Azure data lake in CDM format
2. Ingest your on-premise Dynamics AX data to Azure data lake in CDM format
3. Ingest Finance and Operations app data from Tier 1 or Tier 2 environment to Azure data lake in CDM format (A workaround to [Tables in Data Lake](https://docs.microsoft.com/en-us/dynamics365/fin-ops-core/dev-itpro/data-entities/finance-data-azure-data-lake) feature to build POC)

# SQLToADLS Full Export V2 Highlights  
If you are new to Azure Data Factory, Azure functions and Synapse Analytics, you should try [Version 1](https://github.com/microsoft/Dynamics-365-FastTrack-Implementation-Assets/blob/master/Analytics/AzureDataFactoryARMTemplates/SQLToADLSFullExport/README.md) first to get familier with some of the basic concepts. Version 2 of Data factory solution, primarly utilize C# solution that is based on CDM SDK deployed as Azure function to automate some of the manual steps to create views in Synapse analytics. This version also generate folder structure and metadata similar to F&O Tables in Lake feature. Following are some highlights of this updated version of data factory solution
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
- **Install Visual Studio 2019**: to build and deploy C# solution as Azure function APP (Download and .NET46 framework install https://dotnet.microsoft.com/download/dotnet-framework/thank-you/net462-developer-pack-offline-installer)
# Deployment steps
## Create Azure Application and Secret 
Create an Azure Active directory application and secret, this  AAD Application is used by Azure function to access Azure storage account to create and read CDM metadata. Follow the bellow steps to create the Azure Active directory application.
1. [Register an Active directory App](https://docs.microsoft.com/en-us/azure/active-directory/develop/quickstart-register-app) and record Application Id
2. [Create Application Secret](https://docs.microsoft.com/en-us/azure/healthcare-apis/register-confidential-azure-ad-client-app#application-secret) and record Application Secret
3. Get your Azure Tenant ID  Azure Portal > Azure Active Directory > Tenant information > Tenant ID
## 

## Deploy C# Solution as Azure function 
1.	Clone the repository [Dynamics-365-FastTrack-Implementation-Assets](https://github.com/microsoft/Dynamics-365-FastTrack-Implementation-Assets)
![Clone](/Analytics/CloneRepository.PNG)
2.  Open C# solution Microsoft.CommonDataModel.sln in Visual Studio 2019 and build
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
4.	Publish the CDMUtil_AzureFunctions Project as Azure function 
    1. Right-click on the project CDMUtil_AzureFunctions from Solution Explorer and select "Publish". 
    2. Select Azure as Target and selct Azure Function Apps ( Windows) 
    3. Click Create new Azure Function App and select subscription and resource group to create Azure function app 
    4. Click on Manage Azure App Service and copy all local configurations to remote
    5. Click Publish
    
    ![Publish Azure Function](/Analytics/DeployingAzureFunction.gif)
5. Open Azure Portal and locate Azure Function App created. 
6.  Ensure that all configuration from local.settings.json in the Azure function app configuration tab. 
  ![Azure Function Configurations](/Analytics/AzureFunctionConfiguration.PNG)

7. To learn more aboubt Azure functions follow the link [Azure functions in Visual Studio](https://docs.microsoft.com/en-us/azure/azure-functions/functions-develop-vs)

## Setup Storage Account 
1. In Azure portal, go to Storage account and grant Blob Data Contributor and Blob Data Reader access to AAD Application created in earlier step
![Storage Access](/Analytics/AADAppStorageAccountAccess.PNG)
2. Create a container dynamics365-financeandoperations
3. Create a folder under container to represent your environment name ie - analyticsPerf87dd1496856e213a.cloudax.dynamics.com
4. Download /SQLToADLSFullExport/example-public-standards.zip
5. Extract and upload all files to root folder as shown bellow 
![StorageAccount](/Analytics/StorageAccount.png)

## Deploy Azure Data Factory Template 
Once Azure function is deployed and Storage account is ready, collect all the parameters as described bellow 
1. Login to Azure portal and navigate to Azure Storage account and notedown following  
   - **Storage account>Properties>Data Lake storage>Primary endpoint Data Lake storage** - example https://yourdatalakestoraheURU.dfs.core.windows.net/
   - **Storage account> Access keys > Key1> Key** - example XXXXXXXXXXXXXXXXXXXX/XXXXXXXXXXXXXXXXXXXXXXXXXXX== 
2. Note down Azure data factory name that you created earlier
3. Note down your source SQL server database connection string - ex data source=dbserver;initial catalog=axdb;user id=sqladmin;password=PassWord. 

| **Note** 
| :--------------------   
|If your source system is Dynamics 365 for **Finance and Operations Tier 1 or Tier 2 environment**. You can get the database connection details from Life Cycle Services Environment details page. You would need **Environment Manager or Project Owner access** in LCS to see the database connection details. To Connect Azure data factory to Dynamics 365 for Finance and Operations Tier 1 and Tier 2 boxes, you need to create **Self-Hosted integration runtime** for your Azure data factory.Follow the documentation link to install and configure Self-Hosted Integration runtime on tier 1 VM or Tier 2 VM [Create a Self-hosted integration runtime](https://docs.microsoft.com/en-us/azure/data-factory/create-self-hosted-integration-runtime#create-a-self-hosted-ir-via-azure-data-factory-ui) and then change the integration runtime for your SQLServerDB link services, validate connection and deploy changes to your data factory.  
|To connect Finance and Operations **Self-Service Tier2** environments, you can follow the documentation [Connecting to Self-Service Tier 2](/Analytics/AzureDataFactoryARMTemplates/SQLToADLSFullExport/ConnectingAFDtoSelf_ServiceDeploymentv2.docx) .Note that Self-Service database connections are only valid for 8 hours. So you have to updated the database crededential in the Data factory connection before excuting the data factory.

4. Navigate to Function App Deployed earlier steps and Notedown Azure function ***URL : Function App > Overview > URL***  example:https://msftcdmutilazurefunction.azurewebsites.net and  Function ***App Key: Function App > App Keys > Host Keys> Value (Name= _master)***  
5. Here is all parameters you need

| Parameter name                                       | Description                       | Example                |
| :--------------------                                | :---------------------:           | --------------------:  |
|factoryName                                           | Name of your data factory         |SQLToDataLake           |
|StorageAccount                                        | name of the storage account       |d365fodatalakestorage   |
|DataLakeGen2Storage_accountKey                        | storage account access key        |Secret key              |
|Container                                             | storage account container         | dynamics365-financeandoperations |  
|RootFolder                                            | root folder                       | jjd365fo2d9ba7ea6d7563beaos.cloudax.dynamics.com | 
|SQLDB_connectionString                                | SourceSQL DB connection string    |data source=dbservername.database.windows.net;initial catalog=databasename;user id=userid;password=PassWord             |    
|CDMUTIL_functionAppUrl                                | Azure function URI                | https://cdmutil.azurewebsites.net|
|CDMUTIL_functionKey                                   | App keys                          | Access key|


6. Download the [ARM template file](/Analytics/AzureDataFactoryARMTemplates/SQLToADLSFullExport/arm_template_V2.json) to your local directory.
7. Click [Template deployment] https://ms.portal.azure.com/#create/Microsoft.Template
8. Click  Build your own template in the editor option
9. Click load file and locate the ARM template file you downloaded ealrier and click Save.
10. Provide required parameters and Review + create. 
![Custom deployment](/Analytics/AzureDataFactoryARMTemplates/SQLToADLSFullExport/CustomDeployment_LI.jpg)

## Execute pipelines 
Once Azure data factory template deployed successfully, navigate to Azure Data Factory solution and execute pipelines
1. Execute pipeline SQLTablesToADLS to exort data create CDM metadata files. 
![Execute](/Analytics/ExecutePipeline.png)
2. Validate the CDM folder structure and metadata. 
![CDMFolder](/Analytics/CDMFolder.PNG)

***If you are missing the manifest files, most likely Azure function failed to authenticate to Storage account. To troubleshoot, validate the Azure function configuration and Storage account access control. You can [debug Azure function locally in Visual studio] (https://dotnetthoughts.net/developing-functions-locally/). Postman collection template can be found under /SQLToADLSFullExport/CDMUtil.postman_collection  ***
3. Execute pipeline CreateView to create the views.
![CreateView](/Analytics/ExecuteCreateView.PNG)
4. Validate view created on Synapse SQL-On-Demand

To learn SQL-On-Demand concepts in details follow the [blog post](https://techcommunity.microsoft.com/t5/azure-synapse-analytics/how-azure-synapse-analytics-enables-you-to-run-t-sql-queries/ba-p/1449171) or use the documentation page [Synapse Analytics documentation](https://docs.microsoft.com/en-us/azure/synapse-analytics/sql/on-demand-workspace-overview)


# Build and serve report
Once you created views on SQL-On-Demand to read your tables data stored in data lake, you can use any reporting and BI tool such as Excel, SQL Server Reporting services or Power BI to connect to SQL-On_Demand endpoint just like any other Azure SQL database and build reports. Documentation shows how to [connect Power BI with SQL-On-Demand endpoint](https://docs.microsoft.com/en-us/azure/synapse-analytics/sql/tutorial-connect-power-bi-desktop)

# Troubleshooting 
1. If your pipleline fails on the Azure function calls, validate your Azure function configuration.
2. you can also debug C# code by running the CDMUtil_AzureFunctions locally and PostMan - Postman template can be found under /SQLToADLSFullExport/CDMUtil.postman_collection you can find input parameters for Azure function in Azure data factory pipeline execution history. 

