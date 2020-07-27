# SQLToLake full export data factory pipeline overview
SQLToLake is a generic Azure data factory solution to enable exporting SQLServer tables data to Azure data lake gen 2 storage account. Pipleline can be used to export any tables available in the source database to Azure storage account in csv or Parquet data format. Pipeline also generates model.json file that describe the table schema in CDM format so that it can be further utilized in Azure Synapse Analytics or Power BI using Dataflow.

## Use cases 
You can use this Data factory solution template for following use cases 
1. Ingest your on-premise Dynamics AX data to Azure data lake in CDM format
2. Ingest other on-premise SQL Database or Azure SQL database to Azure data lake in CDM format
3. As an workaround to Tables in Data Lake feature (Only available in Tier 2+ ), ingest Finance and Operations app data from Tier 1 boxes to Azure data lake and try out SQL-On-Demand with your Finance and Operations data. 

To get more details about end to end use case and scenarios refert to Business application summit session [OND2055: Modernize your F&O Data warehouse with ADLS and Azure Synapse](https://mymbas.microsoft.com/sessions/a18e62c9-d74b-4dd3-88bd-308d6c26f469?source=sessions)


# Prerequisites
- **Azure subscription**. You will require **contributor access** to an existing Azure subscription. If you don't have an Azure subscription, create a [free Azure account](https://azure.microsoft.com/en-us/free/) before you begin. 
- **Azure storage account**. If you don't have a storage account, see [Create an Azure storage account](https://docs.microsoft.com/en-us/azure/storage/common/storage-account-create?tabs=azure-portal#create-a-storage-account) for steps to create one.
- **Azure data factory** - Create an Azure Data Factory resource follow the steps to [create a Data factory](https://docs.microsoft.com/en-us/azure/data-factory/tutorial-copy-data-portal#create-a-data-factory)

# Deploying azure data factory ARM template  
To deploy the data factory solution you can follow bellow steps 
1. Complete the pre-requisites
2. Login to Azure portal and navigate to Azure Storage account and notedown following  
   - **Storage account>Properties>Data Lake storage>Primary endpoint Data Lake storage** - example https://yourdatalakestoraheURU.dfs.core.windows.net/
   - **Storage account> Access keys > Key1> Key** - example XXXXXXXXXXXXXXXXXXXX/XXXXXXXXXXXXXXXXXXXXXXXXXXX== 
3. Note down Azure data factory name that you created earlier
4. Note down your source SQL server database connection string - ex data source=dbserver;initial catalog=axdb;user id=sqladmin;password=PassWord. 

| **Note** 
| :--------------------   
|If your source system is Dynamics 365 for Finance and Operations Tier 1 or Tier 2 environment. You can get the database connection details from Life Cycle Services Environment details page. You would need **Environment Manager or Project Owner access** in LCS to see the database connection details. To Connect Azure data factory to Dynamics 365 for Finance and Operations Tier 1 and Tier 2 boxes, You may also need to RDP access to VM and install Self-hosted integration runtime. For details steps check out next section **Connecting data factory to On-Premise SQL DB or Firewall enabled Azure SQL DB**     


5. Download the [ARM template file](/Analytics/AzureDataFactoryARMTemplates/SQLToADLSFullExport/arm_template.json) to your local directory.
6. Click [Template deployment] https://ms.portal.azure.com/#create/Microsoft.Template
7. Click  Build your own template in the editor option
8. Click load file and locate the ARM template file you downloaded ealrier and click Save.
9. Provide required parameters and Review + create. 
![Custom deployment](/Analytics/AzureDataFactoryARMTemplates/SQLToADLSFullExport/CustomDeployment_LI.jpg)

Following table describes parameters required to deploy the data factory ARM template

| Parameter name                                       | Description                       | Example                |
| :--------------------                                | :---------------------:           | --------------------:  |
|factoryName                                           | Name of your data factory         |SQLToDataLake    |
|SQLDB_connectionString                                | SourceSQL DB connection string    |data source=dbservername.database.windows.net;initial catalog=databasename;user id=userid;password=PassWord             |
|AzureDataLakeStorage_properties_typeProperties_url    | Storage account uri | https://yourdatalakestorage.dfs.core.windows.net|
|Data Lake Gen2Storage_account Key    | Storage account access key | Access key of your storage account|


# Connecting data factory to On-Premise SQL DB or Firewall enabled Azure SQL DB 
To connect Azure data factory to your on-premise environment or firewall enabled Azure SQL DB, you need to create Self-Hosted integration runtime for your Azure data
factory.Follow the documentation link to install and configure Self-Hosted Integration runtime [Create a Self-hosted integration runtime](https://docs.microsoft.com/en-us/azure/data-factory/create-self-hosted-integration-runtime#create-a-self-hosted-ir-via-azure-data-factory-ui) 
and then change the integration runtime for your SQLServerDB link services, validate connection and deploy changes to your data factory.

# Pipeline execution and monitoring 
Once data factory pipeline is deployed and connection to SQL Database and Datalake is validated, you can use Data factory pipeline __SQLTablesToADLS__ to export SQL table data to Azure data lake as shown in the following screenshot. 

![Running pipeline](/Analytics/AzureDataFactoryARMTemplates/SQLToADLSFullExport/ExecutePipeline.png)

Following table describes the pipeline parameters 

| Parameter name                           | Description                                | Example                |
| :--------------------                    | :---------------------:                    | --------------------:  |
|TableNames                                | List of tables (, seperated) to export     | CUSTTABLE,CUSTGROUP    |
|Container                                 | Storage account container name             | dynamicsax             |
|Folder                                    | Folder path                                | DynamicsAX/Tables      |
|FileFormat                                | csv or parquet                             |                        |

To periodically export the tables data you can utilize Azure data factory triggers to export your table data to Azure data lake periodically. To lean more about the [Azure data factory documentation page](https://docs.microsoft.com/en-us/azure/data-factory/)


# Query data files stored in Azure data lake using Synapse Analytics SQL-On-Demand
Once you have Tables data in Azure data lake, you can use Synapse Analytics to create view or external table in Synapse Analytics and query the data using familiar  TSQL query language. 

Following are high level steps to use Synapse Analytics **SQL-On-Demand** to query data stored in ADLS
1. **Create Synapse Workspace:** Follow the documentation to [create synapse workspace](https://docs.microsoft.com/en-us/azure/synapse-analytics/quickstart-create-workspace)
2. **Connect to SQL-On-Demand endpoint:** Once you provisioned Synapse workspace, you can use [Synapse Studio](https://docs.microsoft.com/en-us/azure/synapse-analytics/quickstart-synapse-studio) or SQL Server Management Studio (SSMS 18.5 or higher) or [Azure Data Studio](https://docs.microsoft.com/en-us/sql/azure-data-studio/download-azure-data-studio?toc=/azure/synapse-analytics/toc.json&bc=/azure/synapse-analytics/breadcrumb/toc.json&view=azure-sqldw-latest). For details check [supported tools](https://docs.microsoft.com/en-us/azure/synapse-analytics/sql/connect-overview#supported-tools-for-sql-on-demand-preview)
3. **First time setup:** Before you can query data using TSQL, you need to create Database and datasource to read your storage account. Follow the documentation [First time setup](https://docs.microsoft.com/en-us/azure/synapse-analytics/quickstart-sql-on-demand#first-time-setup)
   
4. **Create views** Once database and credentials are created, you can [query files](https://docs.microsoft.com/en-us/azure/synapse-analytics/quickstart-sql-on-demand#query-csv-files) using TSQL.As next step you can [create view](https://docs.microsoft.com/en-us/azure/synapse-analytics/sql/create-use-views) in the database to reuse the queries.  

| **Note** 
| :--------------------   
|Since the SQL table data generated in Azure data lake follow Common data model standard (ie contains model.json file or menifest.json file to describe the schema) you can use the following script [ModelJsonToViewDefinition](/Analytics/AzureDataFactoryARMTemplates/SQLToADLSFullExport/ModelJsonToViewDefinition.sql) to read model.json and generate view definition. You can then execute the view definition SQL-On-Demand database to create the view. In future, you can expect Synapse Analytics to understand the Common data model natively.         

To learn SQL-On-Demand concepts in details follow the [blog post](https://techcommunity.microsoft.com/t5/azure-synapse-analytics/how-azure-synapse-analytics-enables-you-to-run-t-sql-queries/ba-p/1449171) or use the documentation page [Synapse Analytics documentation](https://docs.microsoft.com/en-us/azure/synapse-analytics/sql/on-demand-workspace-overview)

To get optimal performance when querying data files using Synapse SQL-On-Demand, you get optimal performance if the data file size are ~ < 200 MB size. For you have large tables (data files >1 GB)  then you should plan to partition the files. For simplicity, we have not implemented partioning of data files in this solution, However if you large dataset, you can use bellow pipeline to [partition the large files](https://github.com/microsoft/Dynamics-365-FastTrack-Implementation-guides/blob/master/Analytics/AzureDataFactoryARMTemplates/PartitionFile/readme.md)

# Build and serve report
Once you created views on SQL-On-Demand to read your tables data stored in data lake, you can use any reporting and BI tool such as Excel, SQL Server Reporting services or Power BI to connect to SQL-On_Demand endpoint just like any other Azure SQL database and build reports. Documentation shows how to [connect Power BI with SQL-On-Demand endpoint](https://docs.microsoft.com/en-us/azure/synapse-analytics/sql/tutorial-connect-power-bi-desktop)

