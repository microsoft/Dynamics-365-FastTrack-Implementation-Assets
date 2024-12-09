# Create a virtual data warehouse (Synapse workspace) for your FnO data with Azure Synapse Link    
If you are using Export to Data lake service in Dynamics 365 Finance and Operations with Synapse workspaces, this tool will enable you to create a Synapse workspace with similar data views.

## things to consider before using this tool
When migrating from Export to data lake solution using Synapse Serverless database or Azure SQL database, you may run into the following challenges. This tool provides support for some of the issues.

1. Ensure that the Synapse workspace is configured with case-sensitive (CS) collation Latin1_General_100_BIN2_UTF8. As a result, table names and column names become case-sensitive, and you have to change your existing TSQL script and queries to adapt to case sensitivity.
2. Synapse Link includes tables from FnO as well as Dataverse. If you are only interested in just a subset of tables (ex FnO tables), you have to ignore the rest of the tables from the original lakehouse.
3. Data produced by Dataverse Fabric link may have deleted rows; you need to filter out deleted rows (IsDelete=1) while consuming the data.
4. When choosing a derived table from Finance and Operations apps, columns from the corresponding base table currently aren't included. For example, if you choose the DirPartyTable table (base table), the exported data does not contain fields from the child tables (companyinfo, dirorganizationbase, ominternalorganization, dirperson, omoperatingunit, dirorganization, omteam). To get all the columns into DirPartyTable, you must also add other child tables and then create the view using the recid columns.
5. Translated fields for Enumerated data types are handled by this tool. 

Also see the known limitations and additional changes you need to consider.

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
