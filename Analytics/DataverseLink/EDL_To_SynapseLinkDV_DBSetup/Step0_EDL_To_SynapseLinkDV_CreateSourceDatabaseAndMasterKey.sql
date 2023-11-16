--STEP 1: Create a new database in Synapse serverless 
-- TODO: UPDATE Database as needed, 
IF NOT EXISTS (SELECT 1 FROM sys.databases WHERE name = 'YourNewDataBaseName')
	create database [YourNewDataBaseName]

GO

-- STEP 2: Switch to new database created
use [YourNewDataBaseName]

--Step 3 : Create Master Key  
-- Create Marker KEY Encryption if not exist - this is required to create database scope credentials 
-- You may choose to create own encryption key instead of generating random as done in script bellow
	DECLARE @randomWord VARCHAR(64) = NEWID();
	DECLARE @createMasterKey NVARCHAR(500) = N'
	IF NOT EXISTS (SELECT * FROM sys.symmetric_keys WHERE name = ''##MS_DatabaseMasterKey##'')
		CREATE MASTER KEY ENCRYPTION BY PASSWORD = '  + QUOTENAME(@randomWord, '''')
	EXECUTE sp_executesql @createMasterKey
