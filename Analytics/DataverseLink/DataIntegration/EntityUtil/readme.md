## Overview:
The utility provided and outlined below is built to assist in migrating from BYOD to Synapse Link. As known there are [rules](https://learn.microsoft.com/en-us/dynamics365/fin-ops-core/dev-itpro/data-entities/rowversion-change-track#enable-row-version-change-tracking-for-data-entities)  that need to be followed by entities so that they can be exported via Synapse Link. As not all entities support these rules this utility has been created to recreate those entities that are not supported as views in an Azure Synapse database or an Azure SQL database. 

If the customer would like to leverage Fabric, this tool can be used to create the entities as VIEWS within Fabric. However it is necessary to create all of the inherited tables, as views, within Fabric first, therefore it is necessary to run "Select 5" before "Select 2".
 
Note: Caution should be taken if data is being used for integration as near-real-time data integrity is not guaranteed. 

## Prerequisites
If you are creating the VIEWS within the serverless database or an Azure SQL database, you can use the pipeline available [here](https://github.com/microsoft/Dynamics-365-FastTrack-Implementation-Assets/tree/master/Analytics/DataverseLink/DataIntegration) to generate the database metadata structure that will be used as the basis for the VIEWs.

## Steps to execute EntityUtil:
1.	Copy files to a location where they will be run.
2.	Edit the config.json file with the necessary values.
3.	Execute "RunEntityUtil.ps1".

  	Select 1 to generate the dependencies.json file

  	Select 2 to generate the entities.

  	Select 3 to delete all the tables and views in target db.

  	Select 4 to delete all the tables and views in source db.
 
    Select 5 to create the inherited tables in Fabric or the serverless lake replica database.

  	Select Q to quit.

 ## Dynamics Bites
 [Introduction to EntityUtil and generating entity schemas](https://youtu.be/_A7pPN73QpA).

 [Create a virtual data warehouse and use EntityUtil to create complex entities](https://youtu.be/ARb19RTns0Q).

 [Use EntityUtil to create complex entites in the lake database](https://youtu.be/GgrgIsfYEdg).


## Config.json parameters explained

|Parameter	| Description	| Example and/or notes|
|-----------|---------------|---------------------|
|createMissingTables	| Used to determine if the script will create any tables that are missing from the target database.|	true or false When using the incremental CSV configured Synapse Link, if there are missing tables this can be used to stop the execution, until the tables have been exported via Synapse Link and the pipeline run again.|
|tenantId	| This is the GUID for the Azure tenant where the data lake is stored.|	guid|
|sourceDatabaseName	| The name of the serverless database that was create during the implementation of the pipeline.	| Required if using the Incremental CSV export option and there are tables without data. Also required if you want to delete all the tables and views from the source database.|
|sourceServerName	| The name of the serverless server that hosts the serverless database.	| Required if using the Incremental CSV export option and there are tables without data. Also required if you want to delete all the tables and views from the source database.|
|targetServerName	| This is the name of the Azure Synapse server or the database server where the where the new views will be created.|	"exampleSynapse-ondemand.sql.azuresynapse.net" OR "exampledb.database.windows.net" |
|targetDatabaseName	| This is the name of the database where the views (entities) will be created.|	e.g., "d365_entities_database"|
|dbSchema	| This is the name of the database schema that will be used.|	e.g., "dbo"|
|dbSchemaTarget| If you want to create the entities in a specific database schema, you specify it here. The schema must already exist in the database. This has only been tested against Fabric Link and the serverless lake replica database. You must first create the derived tables in the same scheam. | e.g., "d365" | 
|dbSchemaForControlTable| During the setup of the pipeline, some control tables are created, this is the schema where the control tables are created.	| e.g., “dvtosql”|
|entityList	| A comma separate list of entities that need to be created in the target database.	|e.g., "CustCustomerV3Entity,VendVendorV2Entity,GeneralJournalAccountEntryEntity"|
|sandboxServerName	| Used by GenerateEntityDependency.ps1, this is the server name that will be used to identify all of the tables and entities that are required to generate the listed entities, and create the dependencies.json file. 	Currently tested against a tier 2+ environment, this value can be retrieved from LCS. | e.g., "spa-srv-n-d365zzz-a.database.windows.net"|
|sandboxDatabaseName	| Used by GenerateEntityDependency.ps1, this is the database name that will be used to identify all of the tables and entities that are required to generate the listed entities, and create the dependencies.json file. 	Currently test against a tier 2+ environment, this value can be retrieved from LCS.| e.g., "db_d3_ans_ax_20239_0104_da6"|
|Sandboxuid	| In order to get access to the sandbox a user will need to get JIT write access to the sandbox database, after requesting JIT access this is the user name that is created by the system.	Currently tested against a tier 2+ environment, this value can be retrieved from LCS.| e.g., "JIT-user-85q1h"|
|sandboxPwd	| In order to get access to the sandbox a user will need to get JIT write access to the sandbox database, after requesting JIT access this is the password that is created by the system.	Currently test against a tier 2+ environment, this value can be retrieved from LCS.|
|backwardcompatiblecolumns | Required to support creating VIEWS in Fabric and Export To Data Lake migration. |
|exlcudecolumns | Required to support creating VIEWS in Fabric and case sensitivity | 


## Overview of files

| Name	 | Description |
|---------------------|----------------------|
|RunEntityUtil.ps1 |	This script is executed to run the utility. It will present a prompt to ask the user which part of the process they want to execute.|
|GenerateEntityDependency.ps1	| This script will generate the file dependencies.json which contains the metadata for all of the tables required to support the entities that need to be created, as well as the metadata for the entities themselves. It also identifies the dependencies so that the tables and entities can be created in the correct order. It retrieves all of this information by directly reading the information from an SQL database. The current version has been tested against a sandbox environment. |
|EntityUtil.ps1	| This script will create all of the views within an Azure Synapse serverless database or an Azure SQL database where each VIEW represents one of the entities within dependencies.json.|
|DeleteViewsFromSynapse.ps1	| Will delete all of the views from the source or target database. Shouldn't be needed as each T-SQL statement is a CREATE OR ALTER VIEW however it has been provided so that if necessary it is easier to remove all views and tables so that the process can be run again with an empty database, starting with the pipeline.|
|config.json	| Contains the values that need to be updated to run the utility against a specific customer's environment. Values outlined below.|
|dependencies.json | Generated by GenerateEntityDependency.ps1 and contains the metadata for all of the tables and entities required to create the listed entities.|
|ReplaceViewSyntax.json	| There are some values that are not supported, thus this file is used to substitute text from dependencies.json with text that is supported. |
|tableinheritance.json | Contains information on the parent and child tables used by inherited tables. |
|GenerateInheritedTables.ps1 | Required to support creating VIEWS in Fabric, this script will create the inherited tables within Fabric with a sufix of _view | 


## Common errors

| Error message | Resolution |
|---------------|------------|
|az : The term 'az' is not recognized as the name of a cmdlet, function, script file, or operable program. Check the spelling of the name, or if a path was included, verify that the path is correct and try again. | **Install Azure CLI:** If you haven't already installed the Azure CLI, you need to do so. You can download and install it from the official Microsoft Azure CLI website: [Azure CLI Installation](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli). <br> **Check Installation Path:** After installing the Azure CLI, make sure to check the installation path and ensure it's added to your system's PATH environment variable. By default, the installation directory should be added to the PATH during installation, but it's a good idea to double-check. <br> **Restart PowerShell:** If you've just installed the Azure CLI or made changes to your PATH environment variable, you might need to restart your PowerShell session for the changes to take effect. Close and reopen PowerShell or open a new PowerShell window. <br> **Verify Azure CLI Installation:** To verify that the Azure CLI is correctly installed and accessible from PowerShell, open a PowerShell window and run the following command: <br> az --version <br> This command should display the version of the Azure CLI, indicating that it's recognized and available for use. If you continue to encounter issues, please ensure that the Azure CLI was installed correctly and that your system's PATH variable includes the directory where the "az" executable is located. Additionally, make sure there are no typos or case sensitivity issues when running the "az" command. |
|Exception calling "ExecuteNonQuery" with "0" argument(s): "Invalid column name 'column name'."| If you are trying to create the views in Fabric, check that all of the inherited tables have been created before running step 2|
|<<Entity Name>Entity name> : Table/Entity failed with error: + Exception calling "ExecuteNonQuery" with "0" argument(s): "Invalid column name '<<column name>column name>'."| If you are trying to create the views in Serverless or Azure SQL, check that all of the child tables necessary to create the inherited tables have been added before running the pipeline again and running step 2|
|<<Entity Name>Entity name> : Table/Entity failed with error: + Exception calling "ExecuteNonQuery" with "0" argument(s): "Invalid column name '<<column name>column name>_'."|Synapse Link is adding an underscore (__) to key words, to workaround this you can update the file ReplaceViewSyntax.json with syntax similar to:,{"Key": "T1.<<column name>column name>_", "Value": "T1.<<column name>column name>", "ViewName": "<<entity name>entity name>"} To validate the syntax of the SQL that needs to be written to the file ReplaceViewSyntax.json, you can edit the file EntityUtil.ps1. Search the script for the line ""#  Write-host "$ddl";" and remove the hash (#) save the file and run EntityUtil again. It will then write the SQL syntax to the screen.
 

