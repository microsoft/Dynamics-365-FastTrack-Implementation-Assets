# Description

This tool compares MeasureGroup and Dimension Table schemas in two databases based on the Aggregate Measurement metadata file.

# Requirements

All tables used in this Aggregate Measurement metadata should have been created in both the databases.

# Publishing the binaries

Run the ```dotnet publish``` command below at the root of the project folder:

```
dotnet publish -r win10-x64 --self-contained true
```

For other operating systems, please consult the [runtime identifier catalog](https://docs.microsoft.com/en-us/dotnet/core/rid-catalog).


# Usage

Using connection string:
```
 .\SchemaComparer.exe --path <metadata_file_path> --connection-string "Server=tcp:<sql_pool_name>.sql.azuresynapse.net,1433;Initial Catalog=master;Persist Security Info=False;User ID=<username>;Password=<password>;" --ax-connection-string "<connection_string_to_axdw>"
```

Alternatively, you can pass user credentials and server address:

```
 .\SchemaComparer.exe --path <metadata_file_path>  --server "<sql_pool_name>.sql.azuresynapse.net" --username <synapseusename> --password <synapsepassword> --database <synapsedatabase> --ax-server "<axdwserver>" --ax-username <axdwusename> --ax-password <axdwpassword> --ax-database <axdwdatabase>
```

If you want to use Azure Active Directory authentication you can use a connection string as detailed on this page: [Using Azure Active Directory authentication with SqlClient](https://docs.microsoft.com/en-us/sql/connect/ado-net/sql/azure-active-directory-authentication?view=sql-server-ver15).