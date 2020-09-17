<!--
---
page_type: sample
languages:
- tsql
products:
- sql-server
- azure-sql-database
description: "SQL Maintenance script"
urlFragment: "d365fo-sql-maint"
---
-->
# SQL Maintenance Script

This implemetation asset provides a self-contained T-SQL script for Azure SQL or SQL Server database indexes and statistics maintenance. It was written to provide a straightforward means of running required database maintenance tasks, for pre-production databases of Microsoft Dynamics 365 for Finance and Operations environments, where those tasks are not already covered by a standard feature.

# Contents
| File/folder | Description |
|-------------|-------------|
| `README.md` | This README file. |
| `AzureSQLMaintenance.sql` | The T-SQL script. |

# Using the script
The script is commented quite extensively in line. Please read them. In summary, you will typically set the primary operation mode parameters at the beginning of the script. You can also tune the behavior of the script in the subsequent parameters, though for typcial maintenance scenarios you will not need to. Then execute the script in SQL Server Management Studio while connected to the database you wish to maintain.

[!TIP]
The default operation parameters are set to execute a dry run, where no changes are made to the database. Instead the script outputs what it *would* do if were not a dry run. Set the @DryRun bit to 0 to execute the maintenance.

[!TIP]
Since the F&O system index maintenance batch job does not maintain indexes on a tier-1 environment, you will most likely use @operation 'all' in this case. In a tier-2+ environment, the system index maintenance batch job, if set up correctly, takes care of the indexes, so you will most likely use @operation 'statistics'.

