# Configure-Service.ps1
# This script configures the Database Metrics Service after installation.
# It updates appsettings.json with the SQL connection settings and starts the service.
# The service runs as a Virtual Service Account (NT SERVICE\DatabaseMetricsService).
# SQL Server permissions must be configured separately using Grant-SqlPermissions.ps1.

param(
    [Parameter(Mandatory = $true)]
    [string]$InstallFolder,
    
    [Parameter(Mandatory = $true)]
    [string]$SqlServer,
    
    [Parameter(Mandatory = $true)]
    [string]$DatabaseName
)

$ErrorActionPreference = "Stop"
$logFile = Join-Path $InstallFolder "install-config.log"

function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp - $Message" | Out-File -FilePath $logFile -Append
    Write-Host $Message
}

Write-Log "Starting service configuration..."
Write-Log "Install Folder: $InstallFolder"
Write-Log "SQL Server: $SqlServer"
Write-Log "Database: $DatabaseName"

# Update appsettings.json
try {
    $appSettingsPath = Join-Path $InstallFolder "appsettings.json"
    
    if (Test-Path $appSettingsPath) {
        Write-Log "Updating appsettings.json..."
        $json = Get-Content $appSettingsPath -Raw | ConvertFrom-Json
        
        $json.ServerName = $SqlServer
        $json.DatabaseName = $DatabaseName
        $json.ConnectionStrings.DefaultConnection = "Server=$SqlServer;Database=$DatabaseName;Integrated Security=True;Connection Timeout=30;Encrypt=Mandatory;TrustServerCertificate=True;"
        
        $json | ConvertTo-Json -Depth 10 | Set-Content $appSettingsPath -Encoding UTF8
        Write-Log "appsettings.json updated successfully"
    }
    else {
        Write-Log "WARNING: appsettings.json not found at $appSettingsPath"
    }
}
catch {
    Write-Log "ERROR updating appsettings.json: $_"
}

# Start the service
try {
    Write-Log "Starting DatabaseMetricsService..."
    Start-Service -Name "DatabaseMetricsService" -ErrorAction Stop
    Write-Log "Service started successfully"
}
catch {
    Write-Log "ERROR starting service: $_"
}

Write-Log "Configuration complete"
