-- Setup Synapse Database for firsttime using Managed identity
-- Optional: Create MASTER KEY if not exists in database:

Create DATABASE Dynamics365_FinOps;
Go 

use Dynamics365_FinOps
--CREATE MASTER KEY ENCRYPTION BY PASSWORD = 'Pass1Word123'

-- Add Synapse Workspace MSI to storage account - Blob Data Reader and Blob Data Contributor Access 

CREATE DATABASE SCOPED CREDENTIAL SynapseIdentity
WITH IDENTITY = 'Managed Identity';

-- Drop EXTERNAL DATA SOURCE [finance_dynamics365_financeandoperations]  

CREATE EXTERNAL DATA SOURCE [finance_dynamics365_financeandoperations] 
WITH (LOCATION = N'https://ftfinanced365fo.dfs.core.windows.net/dynamics365-financeandoperations/dynamics365-financeandoperations/', 
CREDENTIAL = [SynapseIdentity])
GO
-- 

-- create external files formats
CREATE EXTERNAL FILE FORMAT CSV
WITH (  
    FORMAT_TYPE = DELIMITEDTEXT,
    FORMAT_OPTIONS ( FIELD_TERMINATOR = ',', STRING_DELIMITER = '"', FIRST_ROW = 1   )
);
GO
CREATE EXTERNAL FILE FORMAT ParquetFormat WITH (  FORMAT_TYPE = PARQUET );

-- Create Schema 
Create Schema CDC
GO;
/* To Create views 
--  Utilize CDMUTil Console application  
-- https://github.com/microsoft/Dynamics-365-FastTrack-Implementation-Assets/tree/master/Analytics/CDMUtilSolution#option-1---cdmutil-console-app
*/
GO;

CREATE OR ALTER VIEW [CDC].[ChangeFeedTables] AS
SELECT
    r.filepath(1) AS [TABLE_NAME]
	,max(r.filepath(2)) AS [LAST_UPDATED_CDC_FILE]
FROM OPENROWSET(
    BULK 'ChangeFeed/*/*.csv',
        DATA_SOURCE = 'finance_dynamics365_financeandoperations',
        FORMAT = 'CSV',
        PARSER_VERSION = '2.0',
        FIRSTROW = 1) 
		With(FirstColum nvarchar(100))
		as r
GROUP BY
    r.filepath(1)
GO
