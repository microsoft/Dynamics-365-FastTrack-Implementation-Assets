# Revoke-SqlPermissions.ps1
# Run this script BEFORE or AFTER uninstalling the DatabaseMetricsService to remove
# the SQL Server login and database user for the Virtual Service Account.
#
# Usage:
#   .\Revoke-SqlPermissions.ps1 -SqlServer "localhost" -DatabaseName "RetailOfflineDatabase"

param(
    [Parameter(Mandatory = $false)]
    [string]$SqlServer = "localhost",

    [Parameter(Mandatory = $false)]
    [string]$DatabaseName = "RetailOfflineDatabase"
)

# Require elevation for Invoke-Sqlcmd (sysadmin) operations
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "ERROR: This script must be run as Administrator." -ForegroundColor Red
    exit 1
}

$ErrorActionPreference = "Stop"
$serviceName = "NT SERVICE\DatabaseMetricsService"

Write-Host "Removing SQL Server permissions for $serviceName..." -ForegroundColor Cyan
Write-Host "  SQL Server: $SqlServer"
Write-Host "  Database:   $DatabaseName"
Write-Host ""

# Database-level: drop user
$dbSql = @"
IF EXISTS (SELECT 1 FROM sys.database_principals WHERE name = '$serviceName')
BEGIN
    DROP USER [$serviceName];
    PRINT 'Dropped user [$serviceName]';
END
ELSE
    PRINT 'User [$serviceName] does not exist';
"@

# Server-level: drop login
$serverSql = @"
IF EXISTS (SELECT 1 FROM sys.server_principals WHERE name = '$serviceName')
BEGIN
    DROP LOGIN [$serviceName];
    PRINT 'Dropped login [$serviceName]';
END
ELSE
    PRINT 'Login [$serviceName] does not exist';
"@

try {
    Write-Host "Removing database user from [$DatabaseName]..." -ForegroundColor Yellow
    Invoke-Sqlcmd -ServerInstance $SqlServer -Database $DatabaseName -Query $dbSql -ErrorAction Stop
    Write-Host "  Database user removed." -ForegroundColor Green

    Write-Host "Removing server login..." -ForegroundColor Yellow
    Invoke-Sqlcmd -ServerInstance $SqlServer -Database "master" -Query $serverSql -ErrorAction Stop
    Write-Host "  Server login removed." -ForegroundColor Green

    Write-Host ""
    Write-Host "SQL permissions revoked successfully." -ForegroundColor Green
}
catch {
    Write-Host "ERROR: $_" -ForegroundColor Red
    Write-Host "Ensure you have sysadmin access to SQL Server." -ForegroundColor Yellow
    exit 1
}
