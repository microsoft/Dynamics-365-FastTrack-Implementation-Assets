# Description

This tool compares table schemas in two databases based on the Aggregate Measurement metadata file.

# Requirements

All tables used in this Aggregate Measurement metadata should have been created in the target Azure Synapse database. This process is typically done in two steps: 1) in Dynamics Finance & Operations navigate to Data Lake > Export using Tables; Once the required tables are exported to the lake you can run the [CDMUtil](https://github.com/microsoft/Dynamics-365-FastTrack-Implementation-Assets) tool to create these tables in Azure Synapse.

# Publishing the binaries

Run the ```dotnet publish``` command below at the root of the project folder:

```
dotnet publish -r win10-x64 --self-contained true
```

For other operating systems, please consult the [runtime identifier catalog](https://docs.microsoft.com/en-us/dotnet/core/rid-catalog).


# Usage

Using connection string:
```
 .\SchemaComparer.exe --path <metadata_file_path> --connection-string "Server=tcp:<sql_pool_name>.sql.azuresynapse.net,1433;Initial Catalog=master;Persist Security Info=False;User ID=<username>;Password=<password>;"
```

Alternatively, you can pass user credentials and server address:

```
 .\SchemaComparer.exe --path <metadata_file_path> --server "<sql_pool_name>.sql.azuresynapse.net" --username <usename> --password <password> --database <database>
```

If you want to use Azure Active Directory authentication you can use a connection string as detailed on this page: [Using Azure Active Directory authentication with SqlClient](https://docs.microsoft.com/en-us/sql/connect/ado-net/sql/azure-active-directory-authentication?view=sql-server-ver15).