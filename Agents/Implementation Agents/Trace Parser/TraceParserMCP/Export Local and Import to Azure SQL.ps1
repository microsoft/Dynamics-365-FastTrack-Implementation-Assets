<#
.SYNOPSIS
    Export and Import D365 F&O Trace Data to Azure SQL
.DESCRIPTION
    Exports a single trace with all related data from source DB and imports to Azure SQL,
    handling table dependencies and referential integrity.
.PARAMETER SourceServer
    Source SQL Server instance
.PARAMETER SourceDatabase
    Source database name
.PARAMETER DestinationServer
    Azure SQL Server (e.g., yourserver.database.windows.net)
.PARAMETER DestinationDatabase
    Azure SQL Database name
.PARAMETER TraceId
    The TraceId to export/import
.EXAMPLE
    .\Export-Import-Trace.ps1 -SourceServer "localhost" -SourceDatabase "TraceParserDB" -DestinationServer "yourserver.database.windows.net" -DestinationDatabase "TraceParserAzure" -TraceId 2

.DISCLAIMER
    This script is provided as sample/reference code only under the MIT License.
    It is not an official Microsoft product or service. Microsoft makes no warranties,
    express or implied, and assumes no liability for its use. You are responsible for
    reviewing, testing, and validating this script before running it in your environment.
    Use at your own risk.

    Copyright (c) Microsoft Corporation.
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$SourceServer,
    
    [Parameter(Mandatory=$true)]
    [string]$SourceDatabase,
    
    [Parameter(Mandatory=$true)]
    [string]$DestinationServer,
    
    [Parameter(Mandatory=$true)]
    [string]$DestinationDatabase,
    
    [Parameter(Mandatory=$true)]
    [int]$TraceId,
    
    [Parameter(Mandatory=$false)]
    [string]$SourceUsername,
    
    [Parameter(Mandatory=$false)]
    [string]$SourcePassword,
    
    [Parameter(Mandatory=$false)]
    [string]$DestinationUsername,
    
    [Parameter(Mandatory=$false)]
    [string]$DestinationPassword,
    
    [Parameter(Mandatory=$false)]
    [string]$ExportPath = ".\TraceExport_$TraceId",
    
    [Parameter(Mandatory=$false)]
    [switch]$UseWindowsAuth
)

# Import required module
Import-Module SqlServer -ErrorAction SilentlyContinue
if (-not (Get-Module -Name SqlServer)) {
    Write-Host "Installing SqlServer module..." -ForegroundColor Yellow
    Install-Module -Name SqlServer -Scope CurrentUser -Force
    Import-Module SqlServer
}

# Create export directory
if (-not (Test-Path $ExportPath)) {
    New-Item -ItemType Directory -Path $ExportPath | Out-Null
}

Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "D365 F&O Trace Export/Import Tool" -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "TraceId: $TraceId" -ForegroundColor Green
Write-Host "Export Path: $ExportPath" -ForegroundColor Green
Write-Host ""

# Build connection strings
function Get-ConnectionString {
    param(
        [string]$Server,
        [string]$Database,
        [string]$Username,
        [string]$Password,
        [bool]$UseWindowsAuth
    )
    
    if ($UseWindowsAuth) {
        return "Server=$Server;Database=$Database;Integrated Security=True;TrustServerCertificate=True;"
    } else {
        return "Server=$Server;Database=$Database;User Id=$Username;Password=$Password;Encrypt=True;TrustServerCertificate=False;"
    }
}

$sourceConnString = Get-ConnectionString -Server $SourceServer -Database $SourceDatabase `
    -Username $SourceUsername -Password $SourcePassword -UseWindowsAuth $UseWindowsAuth

$destConnString = Get-ConnectionString -Server $DestinationServer -Database $DestinationDatabase `
    -Username $DestinationUsername -Password $DestinationPassword -UseWindowsAuth $false

# Export queries in dependency order
$exportQueries = @{
    "01_Traces" = "SELECT * FROM Traces WHERE TraceId = $TraceId"
    
    "02_Users" = @"
SELECT DISTINCT u.*
FROM Users u
INNER JOIN UserSessions us ON u.UserId = us.UserId
WHERE us.TraceId = $TraceId
"@
    
    "03_UserSessions" = "SELECT * FROM UserSessions WHERE TraceId = $TraceId"
    
    "04_UserSessionProcessThreads" = @"
SELECT pt.*
FROM UserSessionProcessThreads pt
INNER JOIN UserSessions us ON pt.SessionId = us.SessionId
WHERE us.TraceId = $TraceId
"@
    
    "05_MethodNames" = @"
SELECT DISTINCT mn.*
FROM MethodNames mn
WHERE EXISTS (
    SELECT 1 FROM TraceLines tl
    INNER JOIN UserSessionProcessThreads pt ON tl.ThreadId = pt.ThreadId
    INNER JOIN UserSessions us ON pt.SessionId = us.SessionId
    WHERE us.TraceId = $TraceId AND mn.MethodHash = tl.MethodHash
)
"@
    
    "06_QueryStatements" = @"
SELECT DISTINCT qs.*
FROM QueryStatements qs
WHERE EXISTS (
    SELECT 1 FROM TraceLines tl
    INNER JOIN UserSessionProcessThreads pt ON tl.ThreadId = pt.ThreadId
    INNER JOIN UserSessions us ON pt.SessionId = us.SessionId
    WHERE us.TraceId = $TraceId AND qs.QueryStatementHash = tl.QueryStatementHash
)
"@
    
    "07_QueryTables" = @"
SELECT DISTINCT qt.*
FROM QueryTables qt
WHERE EXISTS (
    SELECT 1 FROM TraceLines tl
    INNER JOIN UserSessionProcessThreads pt ON tl.ThreadId = pt.ThreadId
    INNER JOIN UserSessions us ON pt.SessionId = us.SessionId
    WHERE us.TraceId = $TraceId AND qt.QueryTableHash = tl.QueryTableHash
)
"@
    
    "08_TraceLines" = @"
SELECT tl.*
FROM TraceLines tl
INNER JOIN UserSessionProcessThreads pt ON tl.ThreadId = pt.ThreadId
INNER JOIN UserSessions us ON pt.SessionId = us.SessionId
WHERE us.TraceId = $TraceId
"@
}

# Function to export data to CSV
function Export-TableData {
    param(
        [string]$ConnectionString,
        [string]$Query,
        [string]$OutputFile
    )
    
    try {
        $connection = New-Object System.Data.SqlClient.SqlConnection($ConnectionString)
        $connection.Open()
        
        $command = $connection.CreateCommand()
        $command.CommandText = $Query
        $command.CommandTimeout = 600 # 10 minutes
        
        $adapter = New-Object System.Data.SqlClient.SqlDataAdapter($command)
        $dataset = New-Object System.Data.DataSet
        $rowCount = $adapter.Fill($dataset)
        
        if ($rowCount -gt 0) {
            $dataset.Tables[0] | Export-Csv -Path $OutputFile -NoTypeInformation -Encoding UTF8
            Write-Host "  ✓ Exported $rowCount rows to $OutputFile" -ForegroundColor Green
        } else {
            Write-Host "  ⚠ No data found (0 rows)" -ForegroundColor Yellow
        }
        
        $connection.Close()
        return $rowCount
    }
    catch {
        Write-Host "  ✗ Error exporting: $_" -ForegroundColor Red
        if ($connection.State -eq 'Open') { $connection.Close() }
        return 0
    }
}

# Function to import data using SqlBulkCopy
function Import-TableData {
    param(
        [string]$ConnectionString,
        [string]$CsvFile,
        [string]$TableName
    )
    
    try {
        if (-not (Test-Path $CsvFile)) {
            Write-Host "  ⚠ File not found: $CsvFile" -ForegroundColor Yellow
            return 0
        }
        
        # Read CSV
        $data = Import-Csv -Path $CsvFile
        if ($data.Count -eq 0) {
            Write-Host "  ⚠ No data in CSV file" -ForegroundColor Yellow
            return 0
        }
        
        # Create DataTable
        $dataTable = New-Object System.Data.DataTable
        $data[0].PSObject.Properties | ForEach-Object {
            $dataTable.Columns.Add($_.Name) | Out-Null
        }
        
        foreach ($row in $data) {
            $dataRow = $dataTable.NewRow()
            foreach ($property in $row.PSObject.Properties) {
                $value = $property.Value
                if ([string]::IsNullOrWhiteSpace($value)) {
                    $dataRow[$property.Name] = [DBNull]::Value
                } else {
                    $dataRow[$property.Name] = $value
                }
            }
            $dataTable.Rows.Add($dataRow)
        }
        
        # Bulk insert
        $connection = New-Object System.Data.SqlClient.SqlConnection($ConnectionString)
        $connection.Open()
        
        $bulkCopy = New-Object System.Data.SqlClient.SqlBulkCopy($connection)
        $bulkCopy.DestinationTableName = $TableName
        $bulkCopy.BatchSize = 5000
        $bulkCopy.BulkCopyTimeout = 600
        
        # Enable IDENTITY_INSERT if needed
        $identityColumns = @("TraceId", "UserId", "SessionId", "ThreadId")
        $hasIdentity = $false
        foreach ($col in $identityColumns) {
            if ($dataTable.Columns.Contains($col)) {
                $hasIdentity = $true
                break
            }
        }
        
        if ($hasIdentity) {
            $cmd = $connection.CreateCommand()
            $cmd.CommandText = "SET IDENTITY_INSERT $TableName ON"
            $cmd.ExecuteNonQuery() | Out-Null
        }
        
        $bulkCopy.WriteToServer($dataTable)
        
        if ($hasIdentity) {
            $cmd.CommandText = "SET IDENTITY_INSERT $TableName OFF"
            $cmd.ExecuteNonQuery() | Out-Null
        }
        
        Write-Host "  ✓ Imported $($dataTable.Rows.Count) rows to $TableName" -ForegroundColor Green
        
        $connection.Close()
        return $dataTable.Rows.Count
    }
    catch {
        Write-Host "  ✗ Error importing to ${TableName}: $_" -ForegroundColor Red
        if ($connection -and $connection.State -eq 'Open') { $connection.Close() }
        return 0
    }
}

# PHASE 1: EXPORT
Write-Host "`n[PHASE 1: EXPORT FROM SOURCE]" -ForegroundColor Cyan
Write-Host "Source: $SourceServer.$SourceDatabase`n" -ForegroundColor Gray

$exportStats = @{}
foreach ($item in $exportQueries.GetEnumerator() | Sort-Object Name) {
    $tableName = $item.Name
    $query = $item.Value
    $outputFile = Join-Path $ExportPath "$tableName.csv"
    
    Write-Host "Exporting $tableName..." -ForegroundColor White
    $rowCount = Export-TableData -ConnectionString $sourceConnString -Query $query -OutputFile $outputFile
    $exportStats[$tableName] = $rowCount
}

Write-Host "`nExport Summary:" -ForegroundColor Cyan
$totalRows = ($exportStats.Values | Measure-Object -Sum).Sum
Write-Host "Total rows exported: $totalRows" -ForegroundColor Green

# PHASE 2: IMPORT
Write-Host "`n[PHASE 2: IMPORT TO AZURE SQL]" -ForegroundColor Cyan
Write-Host "Destination: $DestinationServer.$DestinationDatabase`n" -ForegroundColor Gray

# Table mapping (CSV prefix -> actual table name)
$tableMapping = @{
    "01_Traces" = "Traces"
    "02_Users" = "Users"
    "03_UserSessions" = "UserSessions"
    "04_UserSessionProcessThreads" = "UserSessionProcessThreads"
    "05_MethodNames" = "MethodNames"
    "06_QueryStatements" = "QueryStatements"
    "07_QueryTables" = "QueryTables"
    "08_TraceLines" = "TraceLines"
}

$importStats = @{}
foreach ($item in $tableMapping.GetEnumerator() | Sort-Object Name) {
    $filePrefix = $item.Name
    $tableName = $item.Value
    $csvFile = Join-Path $ExportPath "$filePrefix.csv"
    
    Write-Host "Importing to $tableName..." -ForegroundColor White
    $rowCount = Import-TableData -ConnectionString $destConnString -CsvFile $csvFile -TableName $tableName
    $importStats[$tableName] = $rowCount
}

Write-Host "`nImport Summary:" -ForegroundColor Cyan
$totalImported = ($importStats.Values | Measure-Object -Sum).Sum
Write-Host "Total rows imported: $totalImported" -ForegroundColor Green

# PHASE 3: VERIFICATION
Write-Host "`n[PHASE 3: VERIFICATION]" -ForegroundColor Cyan

try {
    $connection = New-Object System.Data.SqlClient.SqlConnection($destConnString)
    $connection.Open()
    
    $verifyQuery = @"
SELECT 
    (SELECT COUNT(*) FROM Traces WHERE TraceId = $TraceId) as TraceCount,
    (SELECT COUNT(*) FROM UserSessions WHERE TraceId = $TraceId) as SessionCount,
    (SELECT COUNT(*) FROM TraceLines tl 
     INNER JOIN UserSessionProcessThreads pt ON tl.ThreadId = pt.ThreadId
     INNER JOIN UserSessions us ON pt.SessionId = us.SessionId
     WHERE us.TraceId = $TraceId) as TraceLinesCount
"@
    
    $command = $connection.CreateCommand()
    $command.CommandText = $verifyQuery
    $reader = $command.ExecuteReader()
    
    if ($reader.Read()) {
        Write-Host "✓ Trace records: $($reader['TraceCount'])" -ForegroundColor Green
        Write-Host "✓ Sessions: $($reader['SessionCount'])" -ForegroundColor Green
        Write-Host "✓ Trace lines: $($reader['TraceLinesCount'])" -ForegroundColor Green
    }
    
    $reader.Close()
    $connection.Close()
    
    Write-Host "`n✓ Migration completed successfully!" -ForegroundColor Green
}
catch {
    Write-Host "⚠ Verification failed: $_" -ForegroundColor Yellow
}

Write-Host "`n==================================================" -ForegroundColor Cyan
Write-Host "Export files saved to: $ExportPath" -ForegroundColor Gray
Write-Host "==================================================" -ForegroundColor Cyan
