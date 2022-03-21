-- Use bellow steps to add AAD users to SQL-On-Demand. In order to query data AAD users would also need Blob data reader access in Azure data lake
use master
go
--Step 1-  create AAD Login
CREATE LOGIN [jiyada@microsoft.com] FROM EXTERNAL PROVIDER;

-- Step 2 

-- Option 1 - Add server level so to grant access to all databases 
	ALTER SERVER ROLE  sysadmin  ADD MEMBER [jiyada@microsoft.com];

--Option 2 - Add database level access to 
	use AXDBLake -- Use your DB name
	go
	CREATE USER jiyada FROM LOGIN [jiyada@microsoft.com];
	alter role db_owner Add member jiyada -- Type USER name from step 2


-- Use bellow script to create MSI authentication such as Azure function 
use AXDB
go

Create user [ABCCDMUtilAzureFunctions] FROM EXTERNAL PROVIDER;
alter role db_owner Add member [ABCCDMUtilAzureFunctions]