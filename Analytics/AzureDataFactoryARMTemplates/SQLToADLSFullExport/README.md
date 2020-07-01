# SQLToLake full export datafactory pipeline overview
SQLToLake is a generic Azure data factory solution to enable exporting SQLServer tables data to Azure data lake gen 2 storage account. Pipleline can be used to export any tables available in the source database to Azure storage account in csv or Parquet data format. Pipeline also generates model.json file that describe the table schema in CDM format so that it can be further utilized in Azure Synapse Analytics or Power BI using Dataflow.

## Use cases 
You can use this Data factory solution template for following use cases 
1. Ingest your on-premise Dynamics AX data to Azure data lake in CDM format
2. Ingest other on-premise SQL Database or Azure SQL database to Azure data lake in CDM format
3. As an workaround to Tables in Data Lake feature (Only available in Tier 2+ ), ingest Finance and Operations app data from Tier 1 boxes to Azure data lake and try out SQL-On-Demand with your Finance and Operations data. 


# Pre-requisites 
To deploy data factory pipeline solution, you need to provision and collect following pre-requisites
1. If you do not have an existing Azure data lake storage account, create a new Azure Storage Account and note down
  a. Storage account URI - example https://yourdatalakestoraheURU.dfs.core.windows.net/
  b. Storage account access keys
2. Note down your source SQL server database connection string - ex data source=dbserver;initial catalog=axdb;user id=sqladmin;password=PassWord           
3. Create Azure DataFactory in Azure portal and note down the data factory name

# Deploying azure data factory ARM template  
To deploy the data factory solution you can use Azure portal template deployment https://ms.portal.azure.com/#create/Microsoft.Template, load the ARM template, provide required parameters and deploy. 

Following table describes parameters required to deploy the data factory ARM template

| Parameter name                                       | Description                       | Example                |
| :--------------------                                | :---------------------:           | --------------------:  |
|factoryName                                           | Name of your data factory         |SQLToDataLake    |
|SQLDB_connectionString                                | SourceSQL DB connection string    |data source=dbserver.database.windows.net;initial catalog=axdb;user id=sqladmin;password=PassWord             |
|AzureDataLakeStorage_properties_typeProperties_url    | Storage account uri | https://yourdatalakestoraheURU.dfs.core.windows.net|
|Data Lake Gen2Storage_account Key    | Storage account access key | Access key of your storage account|


# Connecting data factory to On-Premise SQL DB
To connect Azure data factory to your on-premise environment, you can install Self hosted integration runtime and use th  
https://docs.microsoft.com/en-us/azure/data-factory/concepts-integration-runtime#self-hosted-integration-runtime
1. Create a Self-Hosted Integration runtime 
2. Install and configure integration run time on on-prem environment 
3. Change dataset SQLServerDB to on-prem integration runtime 


# Pipeline execution and monitoring 
Once data factory pipeline is deployed and connection is validated, you can use Data factory pipeline __SQLTablesToADLS__ to export SQL table data to Azure data lake. 

Following table describes the pipeline parameters 

| Parameter name                           | Description                                | Example                |
| :--------------------                    | :---------------------:                    | --------------------:  |
|TableNames                                | List of tables (, seperated) to export     | CUSTTABLE,CUSTGROUP    |
|Container                                 | Storage account container name             | dynamicsax             |
|Folder                                    | Folder path                                | DynamicsAX/Tables      |
|FileFormat                                | csv or parquet                             |                        |




