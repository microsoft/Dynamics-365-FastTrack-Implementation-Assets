-- Step 1 : create a database if not exist 
--create database AnalyticsLab_Materialized

-- step 2 : Use the database and create following artifacts
use AnalyticsLab_Materialized
-- create master key that will protect the credentials:
--CREATE MASTER KEY ENCRYPTION BY PASSWORD = 'StrongPassword'

-- create a external datasouce for your parquet container folder - datasource name will be used in the pipeline parameter 
CREATE DATABASE SCOPED CREDENTIAL managedIdentity
WITH IDENTITY='Managed Identity'

CREATE EXTERNAL DATA SOURCE [enterprise-data-model] 
WITH 
(LOCATION = N'https://d365folabanalytics.dfs.core.windows.net/enterprise-data-model', 
CREDENTIAL = [managedIdentity])
GO

--create a new schema for parquet files 
Create Schema [sales]
GO


CREATE OR ALTER     PROC [dbo].[CREATEVIEWPARQUET]
(
 @TargetViewName nvarchar(100),
 @DataSource nvarchar(100),
 @Location nvarchar(1000)
)
AS
BEGIN
--declare @TargetViewName nvarchar(100) = '[EDM].[CustTrans]';
--declare @Location nvarchar(1000)= '/Tables/CustTrans/*.parquet'

declare @CreateEDMView nvarchar(4000);

set @CreateEDMView = 'Create OR ALTER View '  + @TargetViewName + ' AS ' +
'SELECT
    *
FROM
    OPENROWSET(
        BULK ''' + @Location +''',FORMAT=''PARQUET'', DATA_SOURCE='''+ @DataSource+''') AS [result]';

Execute sp_executesql @CreateEDMView

END
GO






