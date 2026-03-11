# Create a virtual data warehouse (Synapse workspace) for your FnO data with Azure Synapse Link    
If you are using Export to Data lake service in Dynamics 365 Finance and Operations with Synapse serverless and transition to Synapse link with delta lake, this tool will enable you to create a Synapse SQL Serverless database with similar data views and hence elliminating need to rework on exisitng downstream ETL script or reports.

## things to consider before using this tool
When migrating from Export to data lake solution to [Synapse Link delta format](https://learn.microsoft.com/en-us/power-apps/maker/data-platform/azure-synapse-link-select-fno-data#add-finance-and-operations-tables-in-azure-synapse-link). 
Synapse link does following 
1. Export initial and incremental data to datalake and use synapse spark pool to convert data into deltalake format
2. Create a [Lake Database](https://learn.microsoft.com/en-us/azure/synapse-analytics/database-designer/concepts-lake-database) in the Synapse workspace. The lake database is exposed in Synapse SQL serverless SQL pool and Apache Spark providing users with the capability to decouple storage from compute. The metadata that is associated with the lake database makes it easy for different compute engines.

Lake databases and Synapse link have some differences that makes it difficult to transition existing scripts and solution as is - following are limitations of Lake database in Synapse 
1.Lake database does when using from SQL Serverless Endpoint does not allow to create any objects in dbo schema
2. Lake database objects in SQL serverles endpoint use case sensitive collation Latin1_General_100_BIN2_UTF8 collation for string fields. As a result, filters and joins on data become case-sensitive. For example, where custtable.dataareaid = 'usmf' filter is case-sensitive and only filters data that matches the case.

In addition to this there are some known differences between Export to data lake and Synapse link that can again be challenging to transition existing solutions without any change 
1. Data produced by Datavervse Synapse link may have deleted rows; you need to filter out deleted rows (IsDelete=1) while consuming the data.
2. When choosing a derived table from Finance and Operations apps, columns from the corresponding base table currently aren't included. For example, if you choose the DirPartyTable table (base table), the exported data does not contain fields from the child tables (companyinfo, dirorganizationbase, ominternalorganization, dirperson, omoperatingunit, dirorganization, omteam). To get all the columns into DirPartyTable, you must also add other child tables and then create the view using the recid columns.
3. Audit fields such as DataLakeModifiedDateTime are different Synapse Link so if you are using those field in your solution, you may need to adjust those scripts.

## Synapse Serverless SQL Virtual Datawarehouse solution 
Since Synapse link export data in your datalake in deltalake format, you can easily create the openrowset views on deltalake using Synapse serveless database to mitigate above limitations. Following scripts provides a generic implementation to automate the openrowset view creation on Synapse serverless database and also address some of the differences between Export to data lake and Synapse link. 

## Setup instructions 

Step 1: Create a new database in Synapse Serverless SQL pool and master key [CreateSourceDatabaseAndMasterKey](/Analytics/DataverseLink/EDL_To_SynapseLinkDV_DBSetup/Step0_EDL_To_SynapseLinkDV_CreateSourceDatabaseAndMasterKey.sql)

Step 2: Run the setup script on the database created in step 1. This will create stored procedure and functions in the database [CreateUpdate_SetupScript](/Analytics/DataverseLink/EDL_To_SynapseLinkDV_DBSetup/Step1_EDL_To_SynapseLinkDV_CreateUpdate_SetupScript.sql)

Step 3: Run the following script to create openrowset views for all the delta tables on the Synapse serverless database [SynapseLinkDV_DataVirtualization](/Analytics/DataverseLink/VirtualDatawarehouse/Step2_1_EDL_To_SynapseLinkDV_DataVirtualization.sql)

## Known limitations and changes you need to consider 
1. Export to data lake renamed data fields if they conflicted with SQL reserved words. With Synapse Link, the field name matches the application-level metadata, rather than the underlying database field name that Export to Data Lake used.  For those SQL reserved words as field names, you should see the field in Synapse Link without the _ suffix.  For an example

LEVEL_ becomes level
PERCENT_ becomes percent
COMMENT_ becomes comment
USER_ becomes user
NUMBER_ becomes number
RESOURCE_ becomes resource
GROUP_ becomes group
KEY_ becomes key
DEFAULT_ becomes default
EXECUTE_ becomes execute
ROWCOUNT_ becomes rowcount
The Synapse workspace created with the tool above doesn't accommodate field level changes. In case your reports use these fields, you may consider changng them within the report or within the workspace. 

2. Certain unsupported fields (ex. VendPayModeTable.DimUse*) which array data types are not yet supported by Synapse Link.
3. Fields that are deprecated at the application level, but still included with Export to Data Lake data feeds will no longer be present in Synapse Link, such as the *TZID or DEL_* fields.

## data validation 
You need to validate data obtained from Synapse Link (ie. the workspace created using this tool), with the data obtained from Export to Data lake. 
