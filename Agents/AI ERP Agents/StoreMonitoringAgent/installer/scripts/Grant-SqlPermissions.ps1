# Grant-SqlPermissions.ps1
# Run this script AFTER installing the DatabaseMetricsService to grant SQL Server permissions
# to the Virtual Service Account (NT SERVICE\DatabaseMetricsService).
#
# Usage:
#   .\Grant-SqlPermissions.ps1 -SqlServer "localhost" -DatabaseName "RetailOfflineDatabase"

param(
    [Parameter(Mandatory = $false)]
    [string]$SqlServer = "localhost",

    [Parameter(Mandatory = $false)]
    [string]$DatabaseName = "RetailOfflineDatabase"
)

# Require elevation for Invoke-Sqlcmd (sysadmin) and Restart-Service
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "ERROR: This script must be run as Administrator." -ForegroundColor Red
    exit 1
}

$ErrorActionPreference = "Stop"
$serviceName = "NT SERVICE\DatabaseMetricsService"

Write-Host "Granting SQL Server permissions for $serviceName..." -ForegroundColor Cyan
Write-Host "  SQL Server: $SqlServer"
Write-Host "  Database:   $DatabaseName"
Write-Host ""

# Server-level: create login and grant required server permissions
$serverSql = @"
IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = '$serviceName')
BEGIN
    CREATE LOGIN [$serviceName] FROM WINDOWS;
    PRINT 'Created login [$serviceName]';
END
ELSE
    PRINT 'Login [$serviceName] already exists';

GRANT VIEW SERVER STATE TO [$serviceName];
PRINT 'Granted VIEW SERVER STATE to [$serviceName]';

GRANT VIEW ANY DATABASE TO [$serviceName];
PRINT 'Granted VIEW ANY DATABASE to [$serviceName]';
"@

# Database-level: create user, grant VIEW DATABASE STATE, VIEW DEFINITION, and CONNECT
$dbSql = @"
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = '$serviceName')
BEGIN
    CREATE USER [$serviceName] FOR LOGIN [$serviceName];
    PRINT 'Created user [$serviceName]';
END
ELSE
    PRINT 'User [$serviceName] already exists';

GRANT VIEW DATABASE STATE TO [$serviceName];
PRINT 'Granted VIEW DATABASE STATE to [$serviceName]';

GRANT VIEW DEFINITION TO [$serviceName];
PRINT 'Granted VIEW DEFINITION to [$serviceName]';
"@

try {
    Write-Host "Configuring server-level permissions..." -ForegroundColor Yellow
    Invoke-Sqlcmd -ServerInstance $SqlServer -Database "master" -Query $serverSql -ErrorAction Stop
    Write-Host "  Server-level permissions configured." -ForegroundColor Green

    Write-Host "Configuring database-level permissions on [$DatabaseName]..." -ForegroundColor Yellow
    Invoke-Sqlcmd -ServerInstance $SqlServer -Database $DatabaseName -Query $dbSql -ErrorAction Stop
    Write-Host "  Database-level permissions configured." -ForegroundColor Green

    Write-Host ""
    Write-Host "SQL permissions granted successfully." -ForegroundColor Green

    Write-Host "Restarting DatabaseMetricsService..." -ForegroundColor Yellow
    Restart-Service -Name "DatabaseMetricsService" -Force -ErrorAction Stop
    Write-Host "Service restarted successfully." -ForegroundColor Green
}
catch {
    Write-Host "ERROR: $_" -ForegroundColor Red
    Write-Host "Ensure the service is installed (so the VSA exists) and you have sysadmin access to SQL Server." -ForegroundColor Yellow
    exit 1
}
