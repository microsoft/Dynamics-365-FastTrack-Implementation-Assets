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
  - Storage account URI - example https://yourdatalakestoraheURU.dfs.core.windows.net/
  - Storage account access keys
2. Note down your source SQL server database connection string - ex data source=dbserver;initial catalog=axdb;user id=sqladmin;password=PassWord           
3. Create Azure DataFactory in Azure portal and note down the data factory name

# Deploying azure data factory ARM template  
To deploy the data factory solution you can follow bellow steps 
1. Complete the pre-requisites
2. Download the [ARM template file](/arm_template.json) to your local directory.
3. Click [Temmplate deployment] https://ms.portal.azure.com/#create/Microsoft.Template
4. Click  Build your own template in the editor option
5. Click load file and locate the ARM template file you downloaded ealrier and click Save.
6. Provide required parameters and Review + create. 

Following table describes parameters required to deploy the data factory ARM template

| Parameter name                                       | Description                       | Example                |
| :--------------------                                | :---------------------:           | --------------------:  |
|factoryName                                           | Name of your data factory         |SQLToDataLake    |
|SQLDB_connectionString                                | SourceSQL DB connection string    |data source=dbserver.database.windows.net;initial catalog=axdb;user id=sqladmin;password=PassWord             |
|AzureDataLakeStorage_properties_typeProperties_url    | Storage account uri | https://yourdatalakestorage.dfs.core.windows.net|
|Data Lake Gen2Storage_account Key    | Storage account access key | Access key of your storage account|


# Connecting data factory to On-Premise SQL DB
To connect Azure data factory to your on-premise environment, you need to create Self-Hosted integration runtime for your Azure data factory.Follow the documentation link to install and configure Self-Hosted Integration runtime [ Create a Self-hosted integration runtime](https://docs.microsoft.com/en-us/azure/data-factory/create-self-hosted-integration-runtime#create-a-self-hosted-ir-via-azure-data-factory-ui) and then change the integration runtime for your SQLServerDB link services, validate connection and deploy changes to your data factory.

# Pipeline execution and monitoring 
Once data factory pipeline is deployed and connection to SQL Database and Datalake is validated, you can use Data factory pipeline __SQLTablesToADLS__ to export SQL table data to Azure data lake. 

Following table describes the pipeline parameters 

| Parameter name                           | Description                                | Example                |
| :--------------------                    | :---------------------:                    | --------------------:  |
|TableNames                                | List of tables (, seperated) to export     | CUSTTABLE,CUSTGROUP    |
|Container                                 | Storage account container name             | dynamicsax             |
|Folder                                    | Folder path                                | DynamicsAX/Tables      |
|FileFormat                                | csv or parquet                             |                        |

To periodically export the tables data you can utilize Azure data factory triggers to export your table data to Azure data lake periodically. To lean more about the [Azure data factory documentation page](https://docs.microsoft.com/en-us/azure/data-factory/)



