-- Follow the steps to create SQL user for SQL-On-Demand endpoint. To query data stored in Azure data lake via SQL-On-Demand using SQL user security context
-- You will also need to create credentials and grant reference or create view or extenral tables using datasource 

/*****************Option 1 - to create and grant server level access do following***********************/ 

--Step 1 -- create a sql user 
use master; 
CREATE LOGIN [serverUser] WITH PASSWORD = 'Password'; 

-- Step 2  --
ALTER SERVER ROLE  sysadmin  ADD MEMBER [newuser];


/*****************Option 2 - To grant database level access do following***********************/ 

-- Step 1 - create login 
CREATE LOGIN [dbUser] WITH PASSWORD = 'PassWord'; 
-- Step 2 - create user and add roles 
USE [AXDWLake] 
CREATE USER [dbUser] FOR LOGIN [dbUser] 
ALTER ROLE db_owner ADD MEMBER [dbUser]

-- Step 3 -- Create credential for the root of storage account with Shared access key( needed only one time) validate if credential already exists using select * from Sys.Credentials
CREATE CREDENTIAL [https://lakestorage.dfs.core.windows.net] With identity ='SHARED ACCESS SIGNATURE', 
SECRET = 'sv=2019-10-10&ssssssssssssssssssssssssssssr=https&sig=a6%s%3D' 

--Step 4 -- Grant user reference on credentials 
use master
GRANT REFERENCES ON CREDENTIAL::[https://lakestorage.dfs.core.windows.net] TO [dbUser]
