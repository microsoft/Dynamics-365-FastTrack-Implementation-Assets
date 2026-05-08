# Configure-Service.ps1
# Utility script to update EventLog Sink Config Service settings after installation.
# Configuration is defined in appsettings.json (installed with the service).
# Run this script to apply changes and restart the service.

param(
    [Parameter(Mandatory = $false)]
    [string]$InstallFolder = "$env:ProgramFiles\StoreMonitoring\EventLogSinkConfigService",

    [Parameter(Mandatory = $false)]
    [string]$ConfigFilePath,

    [Parameter(Mandatory = $false)]
    [int]$CollectionIntervalMinutes
)

$ErrorActionPreference = "Stop"
$logFile = Join-Path $InstallFolder "configure-service.log"

function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp - $Message" | Out-File -FilePath $logFile -Append
    Write-Host $Message
}

Write-Log "Starting service configuration..."
Write-Log "Install Folder: $InstallFolder"

$appSettingsPath = Join-Path $InstallFolder "appsettings.json"

if (-not (Test-Path $appSettingsPath)) {
    Write-Log "ERROR: appsettings.json not found at $appSettingsPath"
    exit 1
}

# Update appsettings.json only if parameters were explicitly provided
if ($PSBoundParameters.ContainsKey('ConfigFilePath') -or $PSBoundParameters.ContainsKey('CollectionIntervalMinutes')) {
    try {
        Write-Log "Updating appsettings.json..."
        $json = Get-Content $appSettingsPath -Raw | ConvertFrom-Json

        if ($PSBoundParameters.ContainsKey('ConfigFilePath')) {
            $json.ConfigFilePath = $ConfigFilePath
            Write-Log "  ConfigFilePath = $ConfigFilePath"
        }

        if ($PSBoundParameters.ContainsKey('CollectionIntervalMinutes')) {
            $json.CollectionIntervalMinutes = $CollectionIntervalMinutes
            Write-Log "  CollectionIntervalMinutes = $CollectionIntervalMinutes"
        }

        $json | ConvertTo-Json -Depth 10 | Set-Content $appSettingsPath -Encoding UTF8
        Write-Log "appsettings.json updated successfully"
    }
    catch {
        Write-Log "ERROR updating appsettings.json: $_"
    }
}
else {
    Write-Log "No configuration overrides specified. Using existing appsettings.json values."
}

# Restart the service to pick up any changes
try {
    Write-Log "Restarting EventLogSinkConfigService..."
    Restart-Service -Name "EventLogSinkConfigService" -ErrorAction Stop
    Write-Log "Service restarted successfully"
}
catch {
    Write-Log "ERROR restarting service: $_"
}

Write-Log "Configuration complete"
