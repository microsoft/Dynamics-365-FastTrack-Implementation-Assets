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
The script is commented quite extensively in line. Please read the comments. While you can have the script create a stored procedure, then execute the stored procedure as needed, it is more commonly run directly. The T-SQL related to creating a stored procedure is commented out by default. To run it directly, you will just set the primary operation mode parameters at the beginning of the script and then run it. You can also tune the behavior of the script in the subsequent parameters, though for typical maintenance scenarios you will not need to. Once you have configured the script as required, execute it in SQL Server Management Studio, while connected to the database you wish to maintain.

> [!TIP]
> The default operation parameters are set to execute a dry run, where no changes are made to the database. Instead the script outputs what it *would* do if were not a dry run. Set the @DryRun bit to 0 to execute the maintenance.

> [!TIP]
> The F&O system index maintenance batch job has been deprecated, effective January 28th, 2021. Index maintenance on Azure SQL instances will be performed automatically by Microsoft going forward. See https://docs.microsoft.com/en-us/dynamics365/fin-ops-core/dev-itpro/get-started/removed-deprecated-features-platform-updates#feature-removed-effective-january-28-2021. Since this does not apply to tier-1 environments, to the extent that you wish to run database maintainenance on one, you will most likely use @operation 'all'. Since tier-2+ environments use Azure SQL, you would most likely use only @operation 'statistics', if you need to update statistics immediately.

