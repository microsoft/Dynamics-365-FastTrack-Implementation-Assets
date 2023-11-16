
## Prerequisites
1. Configure Synapse link incremental update feature [Link](https://learn.microsoft.com/en-us/power-apps/maker/data-platform/azure-synapse-incremental-updates)
2. Create a Synapse Workspace [Link](https://docs.microsoft.com/en-us/azure/synapse-analytics/quickstart-create-workspace)
3. Create target Azure SQL Database [Link](https://docs.microsoft.com/en-us/azure/azure-sql/database/single-database-create-quickstart?tabs=azure-portal)

## Setup Source Synapse Serverless SQL Database

1. Create a new database in Synapse Serverless SQL pool and master key [CreateSourceDatabaseAndMasterKey](/Analytics/DataverseLink/EDL_To_SynapseLinkDV_DBSetup/Step0_EDL_To_SynapseLinkDV_CreateSourceDatabaseAndMasterKey.sql)

2. Run the setup script on the database created in step 1. This will create stored procedure and functions in the database. [CreateUpdate_SetupScript](/Analytics/DataverseLink/EDL_To_SynapseLinkDV_DBSetup/Step1_EDL_To_SynapseLinkDV_CreateUpdate_SetupScript.sql)


## Setup Target Azure SQL/Synapse Dedicated pool or Azure Database

### Azure SQL Database 
Run the setup script on the target Azure SQL database
[CreateUpdate_SetupScript](/Analytics/DataverseLink/EDL_To_SynapseLinkDV_DBSetup/Step1_EDL_To_SynapseLinkDV_CreateUpdate_SetupScript.sql)

### Azure Synapse Dedicated Pool
Run the setup Run the setup script on the target Synapse dedicated pool database
[CreateUpdate_SetupScript_DW](/Analytics/DataverseLink/CloudDataWarehouse_SynapseDW/Step1_EDL_To_SynapseLinkDV_CreateUpdate_SetupScript_DW.sql)

## Setup Synapse Pipeline 

1. Download Synapse pipeline template from the following file [Pipeline_DVLinkToSQL_IncrementalCopy](/Analytics/DataverseLink/DataIntegration/DVLinkToSQL_IncrementalCopy.zip)
2. Import the pipeline template from the template downloaded in step 1.
3. Update the pipeline parameters as per your environment 
4. Run the pipeline 




