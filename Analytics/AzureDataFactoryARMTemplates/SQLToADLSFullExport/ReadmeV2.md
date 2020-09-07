# SQLToADLS Full Export V2 Highlights  
Following are some highlights of this updated version of data factory solution
1. Creates the folder structure in data lake similar to what F&O Data feed service is going to create
2. Automatically create partition for large tables  
3. Produce schema as Manifest.json format that is the new format of CDM and Data feed service is going to produce this format 
4. With Manifest.json CDM format  and Azure function
5. Pipeline to read metadata and create views in SQLOn-Demand 

# Prerequisites 
- **Azure subscription**. You will require **contributor access** to an existing Azure subscription. If you don't have an Azure subscription, create a [free Azure account](https://azure.microsoft.com/en-us/free/) before you begin. 
- **Azure storage account**. If you don't have a storage account, see [Create an Azure storage account](https://docs.microsoft.com/en-us/azure/storage/common/storage-account-create?tabs=azure-portal#create-a-storage-account) for steps to create one.
- **Azure data factory** - Create an Azure Data Factory resource follow the steps to [create a Data factory](https://docs.microsoft.com/en-us/azure/data-factory/tutorial-copy-data-portal#create-a-data-factory)
- ** Synapse workspace and SQL-on-Demand endpoint [create synapse workspace](https://docs.microsoft.com/en-us/azure/synapse-analytics/quickstart-create-workspace) 
- **Connect to SQL-On-Demand endpoint:** Once you provisioned Synapse workspace, you can use [Synapse Studio](https://docs.microsoft.com/en-us/azure/synapse-analytics/quickstart-synapse-studio) or SQL Server Management Studio (SSMS 18.5 or higher) or [Azure Data Studio](https://docs.microsoft.com/en-us/sql/azure-data-studio/download-azure-data-studio?toc=/azure/synapse-analytics/toc.json&bc=/azure/synapse-analytics/breadcrumb/toc.json&view=azure-sqldw-latest). For details check [supported tools](https://docs.microsoft.com/en-us/azure/synapse-analytics/sql/connect-overview#supported-tools-for-sql-on-demand-preview)
- **First time setup:** Before you can query data using TSQL, you need to create Database and datasource to read your storage account. Follow the documentation [First time setup](https://docs.microsoft.com/en-us/azure/synapse-analytics/quickstart-sql-on-demand#first-time-setup)   
- ** Visual Studio 2019 to build C# CDMUtilSolution Solution and deploy as Azure Function

# High level deployment steps
## Create Azure Application and Secret 
1.[Register an Active directory App](https://docs.microsoft.com/en-us/azure/active-directory/develop/quickstart-register-app) and record Application Id
2.[Create Application Secret](https://docs.microsoft.com/en-us/azure/healthcare-apis/register-confidential-azure-ad-client-app#application-secret) and record Application Secret
3. Get your Azure Tenant ID  Azure Portal > Azure Active Directory > Tenant information > Tenant ID
## Setup Storage Account 
1. In Azure portal, go to Storage account and grant Blob Data Contributor and Blob Data Reader access to applicated created in previous step
2. Create a container dynamics365-financeandoperations
3. Create a folder under container to represent your environment name ie - analyticsPerf87dd1496856e213a.cloudax.dynamics.com
4. Download /SQLToADLSFullExport/example-public-standards.zip
5. Extract and upload all files to root folder ie. environment folder 

## Deploy C# Solution as Azure function 
1.	Clone the repository and open C# solution  in Visual Studio 2019 [Visual Studio Solution](/Analytics/CDMUtilSolution)
3.	Install dependencies and Build the solution to make sure all compiles 
4.  update local.setting.json under CDMUtil_AzureFunctions to as per your environment configurations   
'''{
  "IsEncrypted": false,
  "Values": {
    "MSIAuth": "false", // set this to true if you plan to use Managed Identity auth using Azure function to connect to data lake. 
    "TenantId": "YourTenantId", // Your Azure Tenant ID
    "AppId": "YourAppId", // Your Azure AppId, App must have contributor access to ADLS
    "AppSecret": "AppSecret", // App Secret
    "createDS": "false", // create DS while creating view on Synapse
    "SAS": "Secure Access Signature of your data lake", // only needed when createDS = true, used for created DataSet on Synapse 
    "Password": "979fd422-22c4", // Strong password only needed when createDS = true used for creting a master key on Synapse 
    "SQL-On-Demand": "Server=YourSQLOnDemandDB-ondemand.sql.azuresynapse.net;Database=DBName;User Id=UserId;Password=Password" // Synapsse SQLOn-Demand details 
  }
}'''
5.	Publish the CDMUtil_AzureFunctions Project as Azure function (Ensure that local.Settings.json values are copied during deployment) 
    ![Publish Azure Function](/Analytics/Publish.PNG)
6.	Get your Azure function URL and Key
7.  Ensure that all configuration from local.settings.json in the Azure function app configuration tab.
  ![Azure Function Configurations](/Analytics/AzureFunctionConfiguration.PNG)

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


5. Download the [ARM template file](/Analytics/AzureDataFactoryARMTemplates/SQLToADLSFullExport/arm_templateV2.json) to your local directory.
6. Click [Template deployment] https://ms.portal.azure.com/#create/Microsoft.Template
7. Click  Build your own template in the editor option
8. Click load file and locate the ARM template file you downloaded ealrier and click Save.
9. Provide required parameters and Review + create. 
![Custom deployment](/Analytics/AzureDataFactoryARMTemplates/SQLToADLSFullExport/CustomDeployment_LI.jpg)

2.	Downlaod and Deploy arm_template_V2.json as Data factory 

## Execute pipelines 
1. Execute pipeline SQLTablesToADLS to exort data and create CDM schema 
2. Execute pipeline CreateView to create the views

# Troubleshooting 
1. If your pipleline fails on the Azure function calls, validate your Azure function configuration.
2. you can also debug C# code by running the CDMUtil_AzureFunctions locally and PostMan - Postman template can be found under /SQLToADLSFullExport/CDMUtil.postman_collection you can find input parameters for Azure function in Azure data factory pipeline execution history. 

