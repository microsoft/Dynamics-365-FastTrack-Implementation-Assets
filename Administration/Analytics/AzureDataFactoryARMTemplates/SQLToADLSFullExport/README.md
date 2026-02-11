# Overview 

SQLToADLS is a generic sample solution to export SQLServer (on-premise or Azure SQL) tables data to Azure Data Lake Gen 2 storage account in [Common data model](https://docs.microsoft.com/en-us/common-data-model/) format. Solution utilize Azure data factory pipelines and Azure function based on [CDM SDK](https://github.com/microsoft/CDM/tree/master/objectModel/CSharp) to copy SQL tables data and generate CDM metadata to Azure storage account.  

# Use cases
You can use this Data factory solution  for following use cases
1. Ingest on-premise SQL Database or Azure SQL database to Azure Data Lake in CDM format
2. Ingest your on-premise Dynamics AX data to Azure Data Lake in CDM format
3. Ingest Finance and Operations app data from Cloud Hosted Dev Environment or Tier 2 environment to Azure Data Lake in CDM format (A workaround to [Tables in Data Lake](https://docs.microsoft.com/en-us/dynamics365/fin-ops-core/dev-itpro/data-entities/finance-data-azure-data-lake) feature to build POC)

# SQLToADLS Full Export Highlights  
SQLToADLS solution generate folder structure, data and metadata similar to F&O Export to data lake feature. Following are some highlights of this 

1. Export F&O Tables data to Azure data lake.
2. Automatically partition data for large tables.  
3. Geneate [CDM metadata](https://docs.microsoft.com/en-us/common-data-model/cdm-manifest).  


# Prerequisites 
- **Azure subscription**. You will require **contributor access** to an existing Azure subscription. If you don't have an Azure subscription, create a [free Azure account](https://azure.microsoft.com/en-us/free/) before you begin. 
- **Azure storage account**. If you don't have a storage account, see [Create an Azure storage account](https://docs.microsoft.com/en-us/azure/storage/common/storage-account-create?tabs=azure-portal#create-a-storage-account) for steps to create one.
- **Azure data factory** - Create an Azure Data Factory resource follow the steps to [create a Data factory](https://docs.microsoft.com/en-us/azure/data-factory/tutorial-copy-data-portal#create-a-data-factory)

# Deployment steps

## Deploy C# Solution as Azure function 
[Deploy CDMUtil as Azure Function App](/Analytics/CDMUtilSolution/deploycdmutil.md) as per the instruction.

## Collect Azure Data Factory Deployment Parameters 
Once Azure function is deployed and Storage account is ready, collect all the parameters as described bellow 
1. Login to Azure portal and navigate to Azure Storage account and notedown following  
   - **Storage account>Properties>Data Lake storage>Primary endpoint Data Lake storage** - example https://yourdatalakestoraheURU.dfs.core.windows.net/
   - **Storage account> Access keys > Key1> Key** - example XXXXXXXXXXXXXXXXXXXX/XXXXXXXXXXXXXXXXXXXXXXXXXXX== 
2. Note down Azure data factory name that you created earlier
3. Note down your **Source SQL server database** connection string - ex data source=dbserver;initial catalog=axdb;user id=sqladmin;password=PassWord. 
4. Navigate to Function App Deployed earlier steps and Notedown Azure function ***URL : Function App > Overview > URL***  example:https://msftcdmutilazurefunction.azurewebsites.net 
and  Function ***App Key: Function App > App Keys > Host Keys> Value (Name= _master)***  
5. Here are all the parameters that you need to deploy Azure data factory

| Parameter name                   | Description                       | Example                |
| :--------------------            | :---------------------:           | --------------------:  |
|factoryName                       | Name of your data factory         |SQLToDataLake           |
|StorageAccount                    | name of the storage account       |d365fodatalakestorage   |
|DataLakeGen2Storage_accountKey    | storage account access key        |Secret key              |
|Container                         | storage account container         | dynamics365-financeandoperations |  
|RootFolder                        | root folder                       | jjd365fo2d9ba7ea6d7563beaos.cloudax.dynamics.com | 
|SQLDB_connectionString            | SourceSQL DB connection string    |data source=dbservername.database.windows.net;initial catalog=databasename;user id=userid;password=PassWord             |    
|CDMUTIL_functionAppUrl            | Azure function URI                | https://cdmutil.azurewebsites.net|
|CDMUTIL_functionKey               | App keys                          | Access key|
|TenantId                          | TenandId                          | Guid|
|DataSourceName                    | DataSourceName on SQL-On-Demand   | Datasource name created on SQL-OnDemand|
|SQLEndPoint                       | Connection details of SQL-On-Demand|Server=d365ftazuresynapsedemo-ondemand.sql.azuresynapse.net;Database=AXDB|

## Deploy Azure Data Factory Template 
1. Download the [ARM template file](/Analytics/AzureDataFactoryARMTemplates/SQLToADLSFullExport/arm_template_V2.json) to your local directory.
2. Click [Template deployment] https://ms.portal.azure.com/#create/Microsoft.Template
3. Click  Build your own template in the editor option
4. Click load file and locate the ARM template file you downloaded ealrier and click Save.
5. Provide required parameters and Review + create. 
![Custom deployment](/Analytics/AzureDataFactoryARMTemplates/SQLToADLSFullExport/CustomDeployment_LI.jpg)

## Connecting to Finance and Operations Cloud Hosted Tier 1 Environment or Sandbox Tier 2 
If your source system is Dynamics 365 for **Finance and Operations Cloud Hosteed Dev or Tier 2 environment**. 
You can get the database connection details from Life Cycle Services Environment details page. 
You would need **Environment Manager or Project Owner access** in LCS to see the database connection details. 

### Cloud Hosted Tier 1 environment  
1. To Connect Azure data factory to Dynamics 365 for Finance and Operations Cloud Hosted Development environment 
you need to create **Self-Hosted integration runtime** for your Azure data factory.
2. Follow the documentation link to install and configure Self-Hosted Integration runtime on the VM 
[Create a Self-hosted integration runtime](https://docs.microsoft.com/en-us/azure/data-factory/create-self-hosted-integration-runtime#create-a-self-hosted-ir-via-azure-data-factory-ui) 
3. Change the integration runtime for your SQLServerDB link services, validate connection and deploy changes to your data factory.  

### Connecting to Tier 2 environment 
1. To connect Azure data factory to tier 2 environment you dont need Self-Hosted Integration Runtime as Tier 2 envirinment uses Azure SQL
2. However Tier 2 Azure SQL Database are firewall enabled so you have to whitelist the IP address of Azure data factory to connect
3. Follow the documentation [Connecting to Tier 2 database](/Analytics/AzureDataFactoryARMTemplates/SQLToADLSFullExport/ConnectingAFDtoSelf_ServiceDeploymentv2.docx) .
Note that Self-Service database connections are only valid for 8 hours. So you have to updated the database crededential in the Data factory connection before excutin

## Execute pipeline to export data and CDM metadata
Once Azure data factory template deployed successfully, navigate to Azure Data Factory solution and execute pipelines
1. Execute pipeline SQLTablesToADLS to exort data create CDM metadata files. 
![Execute](/Analytics/ExecutePipeline.png)
2. Validate the CDM folder structure and metadata. 
![CDMFolder](/Analytics/CDMFolder.PNG)

***If you are missing the manifest files, most likely Azure function failed to authenticate to Storage account. To troubleshoot, validate the Azure function configuration and Storage account access control. You can [debug Azure function locally in Visual studio] (https://dotnetthoughts.net/developing-functions-locally/). Postman collection template can be found under /SQLToADLSFullExport/CDMUtil.postman_collection  ***

## Use CDMUtil to create views/external tables on Synapse 
Utilize [CDMUtilSolution](/Analytics/CDMUtilSolution/readme.md) to create view or external table on Synapse Analytics.


# Build and serve report
Once you created views on SQL-On-Demand to read your tables data stored in data lake, you can use any reporting and BI tool such as Excel, SQL Server Reporting services or Power BI to connect to SQL-On_Demand endpoint just like any other Azure SQL database and build reports. Documentation shows how to [connect Power BI with SQL-On-Demand endpoint](https://docs.microsoft.com/en-us/azure/synapse-analytics/sql/tutorial-connect-power-bi-desktop)

# Troubleshooting 
1. If your pipleline fails on the Azure function calls, validate your Azure function configuration.
2. you can also debug C# code by running the CDMUtil_AzureFunctions locally and PostMan - Postman template can be found under /SQLToADLSFullExport/CDMUtil.postman_collection you can find input parameters for Azure function in Azure data factory pipeline execution history. 

