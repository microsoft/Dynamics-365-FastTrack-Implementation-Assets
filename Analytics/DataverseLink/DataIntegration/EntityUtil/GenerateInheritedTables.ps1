function Generate-Inherited-Tables(){
    # This fuction has been specifically written to create inherited as views in a non-dbo database schema i.e., $dbSchemaTarget
    # This function has been written to work on the serverless lake replica database or Fabric Link  

    # Load the JSON configuration file
    $config = Get-Content -Path ".\config.json" | ConvertFrom-Json

    
    # Define the path to be used to create the query debugging file
    $debuggingQueryFile = '.\debuggingQuery.txt'

    # Define the path to be used to find the tableinheritance.json file which contains the parent and child tables
    $tableInheritanceFileLocation = '.\tableinheritance.json'

    # Get the content of tableinheritance file
    $tableInheritanceSyntaxtArray = Get-Content -Raw -Path $tableInheritanceFileLocation # | ConvertFrom-Json
    $tableInheritanceSyntaxtArray = $tableInheritanceSyntaxtArray.ToLower()

    $tableInheritanceJSONSyntaxt = $tableInheritanceSyntaxtArray | ConvertFrom-Json

    # Create the connection sting for a target database 
    # Only relevant for Fabric
    # Target database name 
    $targetDatabaseName = $config.targetDatabaseName
    $targetServerName = $config.targetServerName
    $targetConnectionString = "Server=$($targetServerName);Database=$($targetDatabaseName)"

    # Source database name (if serverless replica, then the source must be the same as target)
    $sourceDatabaseName = $config.sourceDatabaseName
    # Target database name (if serverless replica, then the source must be the same as target)
    $targetDatabaseName = $config.targetDatabaseName

    # Create SQL connection
    $targetConnection = New-Object System.Data.SqlClient.SqlConnection($targetConnectionString)
    $createAlterViewConnection = New-Object System.Data.SqlClient.SqlConnection($targetConnectionString)

    # Database schema we are using
    $dbSchema = $config.dbSchema
    $dbSchemaTarget = $config.dbSchemaTarget

    # Columns that are required for backward compatibility
    $backwardcompatiblecolumns = $config.backwardcompatiblecolumns

    # Columns that need to be excluded
    $exlcudecolumns = $config.exlcudecolumns


    

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
        $createAlterViewConnection.AccessToken = $accessToken
    }
 
    if ((($targetConnectionString -like "*.pbidedicated.windows.net*") -or
        ($targetConnectionString -like "*.datawarehouse.fabric.microsoft.com*")) -and
        ($dbSchemaTarget -ne "") -and
        ($dbSchemaTarget -ne "dbo"))
    {
        $TargetEndpointType = "MS_Fabric"
    }
    elseif (($targetConnectionString -like "*-ondemand.sql.azuresynapse.net*") -and   
            ($dbSchemaTarget -ne "") -and # want to ensure that inherited tables are being made in a target schema
            ($dbSchemaTarget -ne "dbo"))
    {
        $TargetEndpointType = "Synapse_Serverless"
    }
    else 
    {
        Write-Host "Generating inherited tables via EntityUtil is only for Fabric, or in the serverless replica database." -ForegroundColor Red
        Write-Host "The target db schema cannot be dbo." -ForegroundColor Red
        Write-Host "If run on the serverless lakehouse, the target and source database servers and name must be the same." -ForegroundColor Red
        return;
    }

  
    # Open the SQL connection
    $targetConnection.Open()

    # Show connection state
    Write-Host "Connection state:" + $targetConnection.State

    # Read the list of inherited tables to be created Split the comma-separated values
    $tableList = $config.inheritedTablesToBeCreated -split ','

    $requiredTables = $null

    # Loop through each entry in the JSON structure
    foreach ($parentObject in $tableInheritanceJSONSyntaxt) 
    {
        # Check if the current entry has a target parent table
        if ($tableList -contains $parentObject.parenttable) 
        {
           # Write-Host "Found Parent Table: $($parentObject.parenttable)"

            if ($requiredTables -eq $null)
            {
                $requiredTables = $parentObject.parenttable
            }
            else
            {
                $requiredTables = $requiredTables + ',' + $parentObject.parenttable
            }
            # Loop through child tables and process them
            foreach ($childTable in $parentObject.childtables) 
            {
               # Write-Host "  Child Table: $($childTable.childtable)"
                $requiredTables = $requiredTables + ',' + $childTable.childtable
                # Add your code to process child tables here
            }

            # Remove the found parent table from the list of targets
            $tableList = $tableList -ne $parentObject.parenttable

            # Exit the loop if all target parent tables are found
            if ($tableList.Count -eq 0) 
            {
                break
            }
        }   
    }

    # Check for any target parent tables that were not found
    foreach ($missingParentTable in $tableList) 
    {
        Write-Host "Parent table '$missingParentTable' not found."
    }

    Write-Host "Required tables: $requiredTables"

    # Check to see if any tables are missing from the target database
    $queryMissingTables = "select string_agg(value, ',') as MissingTables from string_split('$requiredTables', ',')
    where value not in (select TABLE_NAME from INFORMATION_SCHEMA.TABLES)";
#    Write-Host $queryMissingTables
  
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
    
    $targetConnection.Close()

    if ($missingTables -ne "")
    {
        Write-Host "All of the tables need to be present before the inherited tables can be created. Add the missing tables below and rerun this script."
        write-host "Missing tables: $missingTables" -ForegroundColor Red
        return;
    }

    

    # Note: Fabic is case sensative, thus excludedcolumns has columns repeated with different cases

    $query = "select 
	parenttable,
	string_agg(convert(nvarchar(max),childtable), ',') as childtables,
	string_agg(convert(nvarchar(max),joinclause), ' ') as joins,
	string_agg(convert(nvarchar(max),columnnamelist), ',') as columnnamelists
	from (
		select 
		parenttable, 
		childtable,
		'LEFT OUTER JOIN ' + childtable + ' AS ' + childtable + ' ON ' + parenttable +'.recid = ' + childtable + '.recid' AS joinclause,
		(select 
			STRING_AGG(convert(varchar(max),  '[' + TABLE_NAME + '].'+ '[' + COLUMN_NAME + ']'   + ' AS [' + COLUMN_NAME + ']'), ',') 
			from INFORMATION_SCHEMA.COLUMNS C
			where TABLE_SCHEMA = '$($dbSchema)'
			and TABLE_NAME  = childtable
			and COLUMN_NAME not in (select value from string_split('$($backwardcompatiblecolumns)' + ',' + '$($exlcudecolumns)', ','))
		) as columnnamelist
		from openjson('$($tableInheritanceSyntaxtArray.ToLower())') 
		with (parenttable nvarchar(200), childtables nvarchar(max) as JSON) 
		cross apply openjson(childtables) with (childtable nvarchar(200))
		where childtable in (select TABLE_NAME from INFORMATION_SCHEMA.COLUMNS C where TABLE_SCHEMA = '$($dbSchema)' and C.TABLE_NAME  = childtable)
		) x
		group by parenttable"

    # Write-Host $query

    # Save the query for debugging to a file
    # $query | Out-File $debuggingQueryFile

    try
    {
        # Create a SqlCommand object and set its properties
        $targetConnection.Open()
        $targetCommand = $targetConnection.CreateCommand()
        $targetCommand.CommandText = $query
        $targetCommand.CommandType = [System.Data.CommandType]::Text

        # Execute the query and fetch the results
        $reader = $targetCommand.ExecuteReader()

        $createAlterViewConnection.Open(); 

        while ($reader.Read()) 
        {
        

            $parenttable = $reader["parenttable"]
            $childtables = $reader["childtables"]
            $joins = $reader["joins"]
            $columnnamelists = $reader["columnnamelists"]

            # Write-Host $parenttable + ', ' + $childtables + ', ' + $joins + ', ' + $columnnamelists

            # If using this approach the parent table fields are not added
            # 21 Aug 2024 Updating to review _view as they are being created in a different schema

            # $ddl = "
            # declare @parenttablecolumns nvarchar(max);
            # declare @createalterviewstmt nvarchar(max);

            # SELECT @parenttablecolumns = STRING_AGG(convert(varchar(max),  '[' + TABLE_NAME + '].'+ '[' + COLUMN_NAME + ']'   + ' AS [' + COLUMN_NAME + ']'), ',') 
			#    from INFORMATION_SCHEMA.COLUMNS C
			#    where TABLE_SCHEMA = '$($dbSchema)'
			#    and TABLE_NAME  = '$($parenttable)';
        
            # set @createalterviewstmt = 'create or alter view [$($dbSchemaTarget)].[$($parenttable)_view] as select ' + @parenttablecolumns + ', $($columnnamelists)
            # FROM [$($dbSchema)].[$($parenttable)] AS [$($parenttable)]
            # $($joins);'
        
             $ddl = "
             declare @parenttablecolumns nvarchar(max);
             declare @createalterviewstmt nvarchar(max);

             SELECT @parenttablecolumns = cast(N'' AS nvarchar(MAX)) + STRING_AGG(convert(varchar(max),  '[' + TABLE_NAME + '].'+ '[' + COLUMN_NAME + ']'   + ' AS [' + COLUMN_NAME + ']'), ',') 
			    from INFORMATION_SCHEMA.COLUMNS C
			    where TABLE_SCHEMA = '$($dbSchema)'
			    and TABLE_NAME  = '$($parenttable)';
        
             set @createalterviewstmt = cast(N'' AS nvarchar(MAX)) + N'create or alter view [$($dbSchemaTarget)].[$($parenttable)] as select ' + @parenttablecolumns + N', $($columnnamelists)';
             set @createalterviewstmt = @createalterviewstmt + cast(N'' AS nvarchar(MAX)) + N' FROM [$($dbSchema)].[$($parenttable)] AS [$($parenttable)]';
             set @createalterviewstmt = @createalterviewstmt + cast(N'' AS nvarchar(MAX)) + N'$($joins);'

            EXEC sp_executesql @createalterviewstmt;
            "           

            # Save the query for debugging to a file
            $ddl | Out-File $debuggingQueryFile

            $createAlterViewCommand = $createAlterViewConnection.CreateCommand()
            $createAlterViewCommand.CommandText = $ddl
            $createAlterViewCommand.CommandType = [System.Data.CommandType]::Text
            $createAlterViewCommand.ExecuteNonQuery();

            Write-Host "Created inherited table: $parenttable."
        }
    }
    catch
    {
        # Catch block will be executed when an error occurs in the try block
        Write-Host "$parenttable : inherited table creation failed with error:" + $_.Exception.Message -Foregroundcolor Red
    }
    finally
    {
        $targetConnection.Close()
        $createAlterViewConnection.Close()
    }
                
}

Generate-Inherited-Tables

