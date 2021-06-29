# Description

This tool reads aggregate measurement metadata published by the Entity Store Metadata Exporter tool and creates corresponding views in Azure Synapse.

# Requirements

All tables used in this aggregate measurement metadata should have been created in the target Azure Synapse database. This process is typically done in two steps: 1) in Dynamics Finance & Operations navigate to Data Lake > Export using Tables; Once the required tables are exported to the lake you can run the [CDMUtil](https://github.com/microsoft/Dynamics-365-FastTrack-Implementation-Assets) tool to create these tables in Azure Synapse.

# Usage

Using connection string:
```
 .\EntityStoreToSynapse.exe --path "C:\Downloads\RLXBILedgerCube.zip" --connection-string "Server=tcp:<sql_pool_name>.sql.azuresynapse.net,1433;Initial Catalog=master;Persist Security Info=False;User ID=<username>;Password=<password>;MultipleActiveResultSets=False;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;"
```

Alternatively, you can pass user credentials and server address:

```
 .\EntityStoreToSynapse.exe --path "C:\Downloads\RLXBILedgerCube.zip" --server "<sql_pool_name>.sql.azuresynapse.net" --username <usename> --password <password> --database <database>
```