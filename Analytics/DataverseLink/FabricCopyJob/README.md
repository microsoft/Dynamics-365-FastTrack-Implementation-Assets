There might be scenarios where you need to export data out of Fabric, e.g. temporary feeding data to an existing data warehouse while you are migrating your reporting to Fabric. 

We advise to use CopyJob for these scenarios, see [CopyJob documentation](https://learn.microsoft.com/en-us/fabric/data-factory/what-is-copy-job)  
We do have Change data capture (CDC) enabled in the Microsoft OneLake which makes this solution suitable for large tables as well ([CDC CopyJob documentation](https://learn.microsoft.com/en-us/fabric/data-factory/cdc-copy-job))  

When using CopyJob for synchronizing data out of the lakehouse to an external destination (e.g. Azure SQL database), the CopyJob will create the destination tables based on the schema definition in the data lake. 
This will create all string fields of type nvarchar(MAX) in SQL. 
As mitigation the FnO_CreateTable python script will read the field length from the Finance and operations environment and create a table on Azure SQL with correct field length.

For more information please see [Demo during Office Hours in the Viva Engage - Fabric / Synapse Link](https://microsoft.sharepoint-df.com/:v:/r/teams/synapselinkfordynamics/Shared%20Documents/Apps/Viva%20Engage/OfficeHours_Meeting_Recordings/2025/2025-11-20_Python_Script_FnO_CreateTable.mp4?csf=1&web=1&e=49oFfl)
