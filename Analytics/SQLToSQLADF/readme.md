# SQL To SQL COPY 

This is a sample ADF and SQL based generic solution template that can be used to copy incremental data from one SQL server database to another. Solution uses SQL ChangeTracking feature on the source database to identify incremental changes and export incremental changes to destination database and merge it.

# Deployment Steps

## Setup Source and Destination Database
1. Identify Source and Destination database
2. Connect to source database and execute [Source SQL Script](SQLToSQLCopy_Source.sql)
3. Connect to destination database and execute [Destination SQL Script](SQLToSQLCopy_Source.sql)

## Create and deploy Azure Data Factory Template 
1. Create a Azure Data Factory Resource in Azure Subscription 
1. Note down Source and Destination Database connection string 
2. Download the [ARM template file](arm_template.json) to your local directory.
3. Click [Template deployment] https://ms.portal.azure.com/#create/Microsoft.Template
4. Click build your own template in the editor option
5. Click load file and locate the ARM template file TemplateForDataFactory.json and click Save.
6. Provide required parameters and review + create.

## Execute pipeline
1. Open Azure Data Factory Resouce and Click Author and Monitor 
2. Click Manage> Linked Services and validate Source and Destination database link services.  
4. Click Author and Execute FULL_EXPORT_SQL_TO_SQL, Provide table name as parameter 
5. FULL_EXPORT_SCHEDULE pipeline can be used to add multiple tables for export 
6. Montitor the pipeline execution 
7. Execute INCREMENTAL_SQL_TO_SQL manually or via schedule trigger to execute incremental data copy from source to destination
