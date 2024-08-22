# 29 Dec, 2023 - Added clause to avoid deleting GlobalOptionsetMetadata, if deleted the SQL script needs to be rerun.
param (
    [string]$param1
)


function Delete-Views(){
# only created for debugging/testing purposes
# this should never be used against the replica serverless database created by the Synapse Link for finance and operations apps data
# only the Azure SQL database or serverless databases created to support the pipeline

    # Load the JSON configuration file
    $config = Get-Content -Path ".\config.json" | ConvertFrom-Json

    
    # Define your Azure Synapse Analytics (SQL Data Warehouse) server and database details
    if ($param1 -eq "target")
    {
        $databaseName = $config.targetDatabaseName
        $serverName = $config.targetServerName
        $connectionString = "Server=$($serverName);Database=$($databaseName)"
    }
    else
    {
        $databaseName = $config.sourceDatabaseName
        $serverName = $config.sourceServerName
        $connectionString = "Server=$($serverName);Database=$($databaseName)"
    }

    $dbSchema = $config.dbSchema
    $dbSchemaForControlTable = $config.dbSchemaForControlTable

    #4. Create SQL connection
    $connection = New-Object System.Data.SqlClient.SqlConnection($connectionString)

    # if the connection string does not contains sql login then get the tocken
    if (!$connectionString.ToLower().Contains("uid=") -and !$connectionString.ToLower().Contains("USER ID="))
    {
        Write-Host "AAD authentication"
        # Define SQL connection string
        $tenantId = $config.tenantId 

        # Login to AAD tenant and get access token
        az login --tenant $tenantId *> $null
        $accessToken = az account get-access-token --resource https://database.windows.net/ --query accessToken -o tsv
        # Write-Host "Complete authentication prompt with your default browser"

        # Set AAD access token
        $connection.AccessToken = $accessToken
    }

    

    try {
        # 5. Open the SQL connection
        $connection.Open()

        # Query the database for a list of views
        $query = "SELECT table_name, table_type, table_schema 
                 FROM information_schema.TABLES 
                 WHERE (TABLE_TYPE = 'VIEW' OR TABLE_TYPE = 'BASE TABLE') AND (TABLE_SCHEMA = '$dbSchema' OR TABLE_SCHEMA = '$dbSchemaForControlTable')"

        # Write-Host $query
        $command = $connection.CreateCommand()
        $command.CommandText = $query

        $reader = $command.ExecuteReader()

        while ($reader.Read()) {
            $objectName = $reader["table_name"]
            $objectType = $reader["table_type"] 
            $objectschema =$reader["table_schema"]
             
            # deleting GlobalOptionsetMetadata or srsanalysisenums can add additional steps when rerunning, so skipping deleting them            
            if (($objectName -ne "GlobalOptionsetMetadata") -or 
                ($objectName -ne "srsanalysisenums"))
            {
                # Close the DataReader before executing any other command
                $reader.Close()
        
                # Delete the object
                if ($objectType -eq "VIEW")
                {
                    $deleteQuery = "DROP VIEW [$objectschema].[$objectName]"
                }
                else
                {
                    $deleteQuery = "DROP TABLE [$objectschema].[$objectName]"
                }

               # Write-Host $deleteQuery

                $deleteCommand = $connection.CreateCommand()
                $deleteCommand.CommandText = $deleteQuery
                $deleteCommand.ExecuteNonQuery()

               # Write-Host "Deleted $objectType : $objectName"
         
                # Re-open the DataReader for the next query
                $reader = $command.ExecuteReader()
            }
        }
    } catch {
        Write-Host "Error: $($_.Exception.Message)"
    } finally {
        $connection.Close()
    }

    Write-Host "All views and tables have been deleted from the database."
}

Delete-Views