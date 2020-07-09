# SQLToLake full export datafactory pipeline overview
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
- **Azure data factory** - Create an Azure DataFactory resource follow the steps to [create a Data factory](https://docs.microsoft.com/en-us/azure/data-factory/tutorial-copy-data-portal#create-a-data-factory)

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
|If your source system is Dynamics 365 for Finance and Operations Tier 1 or Tier 2 environment. You can get the database connection details from Life Cycle Services Environment details page. You would need Environment Manager or Project Owner access in LCS to see the database connection details. To Connect Azure data factory to Dynamics 365 for Finance and Operations Tier 1 and Tier 2 boxes, You may also need to RDP access to VM and install Self-hosted integration runtime. For details steps check out next section **Connecting data factory to On-Premise SQL DB or Firewall enabled Azure SQL DB**     


5. Download the [ARM template file](/Analytics/AzureDataFactoryARMTemplates/SQLToADLSFullExport/arm_template.json) to your local directory.
6. Click [Temmplate deployment] https://ms.portal.azure.com/#create/Microsoft.Template
7. Click  Build your own template in the editor option
8. Click load file and locate the ARM template file you downloaded ealrier and click Save.
9. Provide required parameters and Review + create. 
![Custom deployment](/Analytics/AzureDataFactoryARMTemplates/SQLToADLSFullExport/CustomDeployment_LI.jpg)

Following table describes parameters required to deploy the data factory ARM template

| Parameter name                                       | Description                       | Example                |
| :--------------------                                | :---------------------:           | --------------------:  |
|factoryName                                           | Name of your data factory         |SQLToDataLake    |
|SQLDB_connectionString                                | SourceSQL DB connection string    |data source=dbserver.database.windows.net;initial catalog=axdb;user id=sqladmin;password=PassWord             |
|AzureDataLakeStorage_properties_typeProperties_url    | Storage account uri | https://yourdatalakestorage.dfs.core.windows.net|
|Data Lake Gen2Storage_account Key    | Storage account access key | Access key of your storage account|


# Connecting data factory to On-Premise SQL DB or Firewall enabled Azure SQL DB 
To connect Azure data factory to your on-premise environment or firewall enabled Azure SQL DB, you need to create Self-Hosted integration runtime for your Azure data
factory.Follow the documentation link to install and configure Self-Hosted Integration runtime [ Create a Self-hosted integration runtime](https://docs.microsoft.com/en
us/azure/data-factory/create-self-hosted-integration-runtime#create-a-self-hosted-ir-via-azure-data-factory-ui) 
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
Once you have Tables data in Azure data lake, you can use Synapse Analytics to create view or external table in Synapse Analytics and query the data using familier TSQL query langauage. To learn more about SQL-On-Demand use the document link [Synapse Analytics documentation](https://docs.microsoft.com/en-us/azure/synapse-analytics/sql/on-demand-workspace-overview)


