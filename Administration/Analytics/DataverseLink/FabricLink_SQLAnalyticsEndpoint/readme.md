# Using Dataverse Link to Microsoft Fabric with SQL Analytics Endpoint and Warehouse

Microsoft Dataverse direct link to Microsoft Fabric enables organizations to extend their Power Apps and Dynamics 365 enterprise applications (Sales), and business processes into Fabric. The Link to Microsoft Fabric feature built into Power Apps makes all your Dynamics 365 (Customer Engagement and Finance and Operations Apps) and Power Apps data available in Microsoft OneLake, the built-in data lake for Microsoft Fabric.

Dataverse also generates an enterprise-ready Fabric Lakehouse and SQL endpoint for your Power Apps and Dynamics 365 data. This makes it easier for data analysts, data engineers, and database admins to combine business data with data already present in OneLake using Spark, Python, or SQL. As data gets updated, changes are reflected in the lakehouse automatically.

Data and BI teams that are currently using SQL Server technologies (Synapse Serverless, Synapse Dedicated Pool, Azure SQL, or SQL Server) to build virtual data warehouses or data mart solutions with Dynamics 365 data can easily migrate their solution to Microsoft Fabric by using Microsoft Fabric SQL Analytics Endpoint and Fabric Datawarehouse workload.

## Setup Link to Microsoft Fabric
Follow the documentation to create Link to Microsoft Fabric  
https://learn.microsoft.com/en-us/power-apps/maker/data-platform/azure-synapse-link-view-in-fabric

## Things to consider before querying data using SQL Analytics Endpoint and Warehouse

When migrating from Export to data lake solution using Synapse Serverless database or Azure SQL database, you may run into the following challenges:
1. Fabric Lakehouse and warehouses by default are configured with case-sensitive (CS) collation Latin1_General_100_BIN2_UTF8. As a result, table names and column names become case-sensitive, and you have to change your existing TSQL script and queries to adapt to case sensitivity.
2. All Dataverse tables that have track changes on are by default selected with Fabric link. If you are only interested in just a subset of tables, you have to ignore the rest of the tables from the original lakehouse.
3. Data produced by Dataverse Fabric link may have deleted rows; you need to filter out deleted rows (IsDelete=1) while consuming the data.
4. When choosing a derived table from Finance and Operations apps, columns from the corresponding base table currently aren't included. For example, if you choose the DirPartyTable table (base table), the exported data does not contain fields from the child tables (companyinfo, dirorganizationbase, ominternalorganization, dirperson, omoperatingunit, dirorganization, omteam). To get all the columns into DirPartyTable, you must also add other child tables and then create the view using the recid columns.
5. Fabric Lakehouse tables' string columns have default collation Latin1_General_100_BIN2_UTF8. As a result, filters and joins on data become case-sensitive. For example, *where custtable.dataareaid = 'usmf'* filter is case-sensitive and only filters data that matches the case.
6. DV Fabric link SQL Endpoint have table and column name in lower case while Export to data lake have metadata in MixedCase. This could be issue if you are directly importing Tables in Power BI and doing transformation in Power Query. Power Query is case sensitive and references of the column name and tablename needs to be adjusted.
7.  Fabric Link tables string length is defaulted to varchar(8000). Fabric engine is optimized with large string length however when copying data to SQL server using pipeline and use the same schema in the target– all string field columns to varchar(8000) can cause perf issue or compatibility issue in SQL Server with existing Export to data lake tables. 

## DVFabricLinkUtil Notebook

[Dataverse Fabric Link Util](DVFabricLinkUtil.ipynb) is generic notebook that overcome above challenges by automating followings
- Creating case-insensitive Warehouses in Fabric
- Connect to Synapse serverless to get "Export to data lake" enabled tables and schema information
- Handling derived tables missing fields, soft-delete, string field collation
- Deploying views on Fabric Datawarehouse
- Bonus: Extract logical DW views and dependencies from Synapse serverless and Connect 
  
## 🚀 How to Use

1. **Clone or Import the Notebook** into your Fabric Workspace.

2. **Update the Configuration Variables** at the top of the notebook:
   ```python
   WORKSPACE_ID = "<your-fabric-workspace-id>"
   FABRIC_LH_DATABASE = "<your-fabric-lakehouse-name>"
   FABRIC_WH_DATABASE = "<your-fabric-warehouse-name>"
   FABRIC_WH_SCHEMA    = "<your-fabric-dw-schema>"
   ...
3. **Run the notebook**

4. **Example Output**
[2025-04-06 20:12:44] INFO - 🏗️ Step 1: Download template files if does not exists.

[2025-04-06 20:12:44] INFO - 📄 File already exists locally: ./builtin/resources/derived_table_map.json

[2025-04-06 20:12:45] INFO - 📄 File already exists locally: ./builtin/resources/get_lh_ddl_as_view.sql

[2025-04-06 20:12:45] INFO - 📄 File already exists locally: ./builtin/resources/get_view_dependency.sql

[2025-04-06 20:12:45] INFO - 🏗️ Step 2/7: Ensure case-insensitive warehouse exists.

[2025-04-06 20:12:45] INFO - ✅ Warehouse 'dataverse_analytics_warehouse1' already exists.

[2025-04-06 20:12:45] INFO - 🔹 Step 3/7: Fetch tables and schema map from Synapse.

[2025-04-06 20:12:46] INFO - 🔁 Step 4/7: Load derived table map.

[2025-04-06 20:12:46] INFO - 🛠️ Step 5/7: Generate view DDL.

[2025-04-06 20:12:49] INFO - 🚀 Step 6/7: Fetch view dependencies.

[2025-04-06 20:12:49] INFO - 🚀 Step 7/7: Deploy views to warehouse.

[2025-04-06 20:12:49] INFO - ✅ Deployed view: DirPartyPrimary_view

[2025-04-06 20:12:49] INFO - ✅ Deployed view: CustomerDim

[2025-04-06 20:12:49] INFO - 🎉 Deployment complete.



