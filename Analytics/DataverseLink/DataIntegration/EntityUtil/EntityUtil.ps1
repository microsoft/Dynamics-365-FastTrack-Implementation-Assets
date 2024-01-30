# Load the JSON configuration file
$config = Get-Content -Path ".\config.json" | ConvertFrom-Json

# Define the path to be used to create the dependencies.json file
$AXDBDependenciesJson = '.\dependencies.json'

# Define the path to be used to find the Replace Syntax json files
$ReplaceViewSyntaxFile = '.\ReplaceViewSyntax.json'
$ReplaceFabricViewSyntaxFile = '.\ReplaceFabricViewSyntax.json'

# Get the content of syntaxt files file
$replaceSyntaxtArray = Get-Content -Raw -Path $ReplaceViewSyntaxFile | ConvertFrom-Json
$replaceFabricSyntaxtArray = Get-Content -Raw -Path $ReplaceFabricViewSyntaxFile | ConvertFrom-Json

# Read the metadata from the the dependencies.json file
$dependencyContent = Get-Content -Raw -Path $AXDBDependenciesJson | ConvertFrom-Json
$dependencyArray = $dependencyContent.AXDBDependencies

$createMissingTables = $config.createMissingTables

# Source database name (the raw data)
$sourceDatabaseName = $config.sourceDatabaseName
# Target database name (the database where the views will be created)
$targetDatabaseName = $config.targetDatabaseName

# Create the connection sting for a target database 
# Tested against Azure SQL database and Azure Synapse Serverless
$targetServerName = $config.targetServerName
$targetConnectionString = "Server=$($targetServerName);Database=$($targetDatabaseName)"

# Database schema we are using
$dbSchema = $config.dbSchema

# Create SQL connection
$targetConnection = New-Object System.Data.SqlClient.SqlConnection($targetConnectionString)

# When running incremental CSV export from Synapse LInk, if there aren't any records the pipeline doesn't create the table
# therefore this script was added to use the reference database to create the tables in the target if required.\
$serverlessReferenceDatabaseName = $config.sourceDatabaseName 
$serverlessReferenceServerName = $config.sourceServerName 
$serverlessReferenceConnectionString = "Server=$($serverlessReferenceServerName);Database=$($serverlessReferenceDatabaseName)"
$serverlessReferenceConnection = New-Object System.Data.SqlClient.SqlConnection($serverlessReferenceConnectionString)

# if the connection string does not contain sql login then get the tocken
if (!$targetConnectionString.ToLower().Contains("uid=") -and !$targetConnectionString.ToLower().Contains("USER ID="))
{
    Write-Host "AAD authentication"
    # Define SQL connection string
    $tenantId = $config.tenantId

    # Login to AAD tenant and get access token
    az login --tenant $tenantId *> $null
    $accessToken = az account get-access-token --resource https://database.windows.net/ --query accessToken -o tsv
    #Write-Host "Complete authentication prompt with your default browser"

    # Set AAD access token
    $targetConnection.AccessToken = $accessToken

    # Set AAD access token for reference connection in case it is needed.
    $serverlessReferenceConnection.AccessToken = $accessToken
}
 
if ($targetConnectionString -like "*-ondemand.sql.azuresynapse.net*")
{
    $TargetEndpointType = "Synapse_Serverless"
}
elseif ($targetConnectionString -like "*.sql.azuresynapse.net*")
{
     $TargetEndpointType = "Synapse_Dedicated"
}
elseif ($targetConnectionString -like "*.pbidedicated.windows.net*")
{
    $TargetEndpointType = "MS_Fabric"
    $createMissingTables = $false

}
else 
{
    $TargetEndpointType = "SQL"
}

   
# Open the SQL connection
$targetConnection.Open()

if ($serverlessReferenceDatabaseName -ne "")
{
    $serverlessReferenceConnection.Open(); # Being used for incremental CSV
}

# Show connection state
Write-Host "Connection state:" + $targetConnection.State

# Get the list of required tables from the dependencies.josn file and write them to the screen
$dependentTables = $dependencyArray | Where-Object { $_.objectType -eq "USER_TABLE" } 
$TableCount = $dependentTables.Count

$dependentTablesList = ($dependentTables.entityName) -join ","
$dependentTablesList = $dependentTablesList.ToLower();

write-host "Dependent tables:($TableCount):$dependentTablesList"

# Check to see if any tables are missing from the target database
$queryMissingTables = "select string_agg(value, ',') as MissingTables from string_split('$dependentTablesList', ',')
where value not in (select TABLE_NAME from INFORMATION_SCHEMA.TABLES)";

# Create a SqlCommand object and set its properties
$targetCommand = $targetConnection.CreateCommand()

$targetCommand.CommandText = $queryMissingTables
$targetCommand.CommandType = [System.Data.CommandType]::Text

# Execute the queryMissingTables statement
$dataReader = $targetCommand.ExecuteReader()

$missingTables = ""
while ($dataReader.Read())
{
    $missingTables += $dataReader.GetValue(0)
}

write-host "Missing tables:$missingTables" -ForegroundColor Red

$targetConnection.Close()

if ($createMissingTables -eq $false -and $missingTables -ne "")
{
    Write-Host "Add missing tables and rerun pipeline before running EntityUtil." -ForegroundColor Green
    return;
}


# Loop through each object in the JSON array
foreach ($dependency in $dependencyArray) 
{
    $entityName  =  $dependency.entityName;
    $objectType  =  $dependency.objectType;
    $depth       =  $dependency.depth;
    $definitions =  $dependency.definitions;
    $columnList  =  $dependency.columnList;
        
    $ddl = $null
    
    $createAzureSQLTable = $false;
    $createTableWithArrayTypeColumns = $false;
    
    # write-host "Object Type: $objectType, Create Missing Tables: $createMissingTables"  
   
    if ($objectType -eq "USER_TABLE" -and $createMissingTables -eq $true)
    {
        # Check to see if the table is a "missing table"
        if ($entityName.ToLower() -in $missingTables.Split(','))
        {
            Write-Host "$entityName found in the list $missingTables."
            write-host "Creating table" 
            if ($TargetEndpointType -like "SQL")
            { 
                $ddl = "SELECT COLUMN_NAME, DATA_TYPE, CHARACTER_MAXIMUM_LENGTH
                        FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = '$($entityName.ToLower())'"
                $createAzureSQLTable = $true;   
                
            }
        }
       
    }
        
    if ($objectType -eq "VIEW")
    {

        $ddl =$definitions;

        if ($TargetEndpointType -ne "Synapse_Dedicated")
        {
            $ddl = $ddl.Replace("CREATE VIEW", "CREATE OR ALTER VIEW");
        }
        
        $ddl = $ddl.Replace("[dbo].GetValidFromInContextInfo()", "GETUTCDATE()");
        $ddl = $ddl.Replace("[dbo].GetValidToInContextInfo()", "GETUTCDATE()");
        $ddl = $ddl.Replace("dbo.GetValidFromInContextInfo()", "GETUTCDATE()");
        $ddl = $ddl.Replace("dbo.GetValidToInContextInfo()", "GETUTCDATE()");
        $ddl = $ddl.Replace("GetValidFromInContextInfo()", "GETUTCDATE()");
        $ddl = $ddl.Replace("GetValidToInContextInfo()", "GETUTCDATE()");

        $ddl = $ddl.Replace("SELECT ValidFromInContextInfo FROM [dbo].GetValidFromDateInContextInfoAsTable()", "GETUTCDATE()");
        $ddl = $ddl.Replace("SELECT ValidToInContextInfo FROM [dbo].GetValidToDateInContextInfoAsTable()", "GETUTCDATE()");
        $ddl = $ddl.Replace("SELECT ValidFromInContextInfo FROM dbo.GetValidFromDateInContextInfoAsTable()", "GETUTCDATE()");
        $ddl = $ddl.Replace("SELECT ValidToInContextInfo FROM dbo.GetValidToDateInContextInfoAsTable()", "GETUTCDATE()");
        $ddl = $ddl.Replace("SELECT ValidFromInContextInfo FROM GetValidFromDateInContextInfoAsTable()", "GETUTCDATE()");
        $ddl = $ddl.Replace("SELECT ValidToInContextInfo FROM GetValidToDateInContextInfoAsTable()", "GETUTCDATE()");
        
        
        # Filter the JSON array 
        $replaceSyntaxArray = $replaceSyntaxtArray | Where-Object { $_.ViewName -eq $entityName }
        
        foreach ($replaceSyntax in $replaceSyntaxArray) 
        {
          #  Write-host "$entityName Replacing the syntax";
           $ddl = $ddl.Replace($replaceSyntax.Key,$replaceSyntax.Value)
           
        }


        if ($TargetEndpointType -eq "MS_Fabric")
        {
            
            # if this is being run on Fabric, it is assumed that you are creating inherited tables,
            # thus including the replace statement to ensure views are created correctly
            # Read the list of inherited tables to be created Split the comma-separated values
            $tableList = $config.inheritedTablesToBeCreated -split ','
            $ddl = $ddl.ToLower();
            # Loop through the values
            foreach ($table in $tableList) 
            {
                if ($ddl -like "* $table *")
                {
                    $ddl = $ddl -replace $table, ("$table" + "_view")
                }
            }

            # There are some case sensitive statements that need to be updated for Fabric
            # Filter the JSON array 
            $replaceFabricSyntaxArray = $replaceFabricSyntaxtArray | Where-Object { $_.ViewName -eq $entityName }
        
            foreach ($replaceFabricSyntax in $replaceFabricSyntaxArray) 
            {
              #  Write-host "$entityName Replacing the syntax";
               $ddl = $ddl.Replace($replaceFabricSyntax.Key,$replaceFabricSyntax.Value)
           
            }
            
        }

        

        Write-Host "Generated SQL statement for the VIEW $entityName :"
        #  Write-host "$ddl";
            
    }

    # Execute the DDL statement
    if ($ddl -ne $null)
    {
        try 
        {
            # Create a SqlCommand object and set its properties
            $targetConnection.Open()
            $targetCommand = $targetConnection.CreateCommand()
            $targetCommand.CommandText = $ddl
            
         #   Write-Host "Query to execute :$ddl" -Foregroundcolor Green
            
            if ($createAzureSQLTable -eq $false)
            {
                $result = $targetCommand.ExecuteNonQuery()
            }
            elseif ($createMissingTables) # Shouldn't be necessary for delta lake / parquet source
            {

                # this assume that the pipeline has been run to create the Azure SQL database from the incremental Synapse Link feed
                # this is only required when there are no records, as the stored procedures do not create the Azure SQL databases

                # Generate the CREATE TABLE statement
                $createTableStatement = "CREATE TABLE $($dbSchema.ToLower()).$($entityName.ToLower()) ("
                
                # Create a new connection scring to read from serverless database
                $sourceServerlessCommand = $serverlessReferenceConnection.CreateCommand()
                $sourceServerlessCommand.CommandText = $ddl
                $sourceServerlessCommand.CommandType = [System.Data.CommandType]::Text

                # Execute the query and fetch the results
                $reader = $sourceServerlessCommand.ExecuteReader()

                while ($reader.Read()) 
                {
                    $columnName = $reader["COLUMN_NAME"]
                    $dataType = $reader["DATA_TYPE"]
                    $maxLength = $reader["CHARACTER_MAXIMUM_LENGTH"]

                    # Append the column definition to the CREATE TABLE statement
                    if ($maxLength.ToString() -ne "") 
                    {
                        $createTableStatement += "[$columnName] $dataType($maxLength),"
                    } 
                    else 
                    {
                        $createTableStatement += "[$columnName] $dataType,"
                    }
                }
                    
                # Remove the trailing comma and close the statement
                $createTableStatement = $createTableStatement.TrimEnd(',') + ");"
                # Display the generated CREATE TABLE statement
                # Write-Host "Generated SQL statement:"
                # Write-Host $createTableStatement
               

                $targetCommand.CommandText = $createTableStatement
                $targetCommand.ExecuteNonQuery()

                $reader.Close()
            }

            Write-Host "$entityName :Table/Entity created successfully" -Foregroundcolor Green
        }
        catch 
        {
            # Catch block will be executed when an error occurs in the try block
            Write-Host "$entityName :Table/Entity failed with error:" + $_.Exception.Message -Foregroundcolor Red
            # Write-Host "DDL:$ddl"  -Foregroundcolor Yellow
        }
        finally
        {
           
            $targetConnection.close()
        }
    }

}


