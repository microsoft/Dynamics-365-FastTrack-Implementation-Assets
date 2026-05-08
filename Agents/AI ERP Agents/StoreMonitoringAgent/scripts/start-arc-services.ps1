# Start Azure Arc Services Script
# This will restart Arc and resume AMA log sending
# Run as Administrator

param(
    [Parameter(Mandatory = $false)]
    [switch]$EnableAutoStart
)

# Check if running as Administrator
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
$isAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Error "This script must be run as Administrator."
    exit 1
}

Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "  Starting Azure Arc Services" -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host ""

$arcServices = @("himds", "GCArcService", "ExtensionService", "ArcProxy")

# Display current status
Write-Host "Current Status:" -ForegroundColor Yellow
Get-Service -Name $arcServices | Format-Table Name, DisplayName, Status, StartType -AutoSize
Write-Host ""

# Enable auto-start if requested
if ($EnableAutoStart) {
    Write-Host "Enabling auto-start..." -ForegroundColor Yellow
    foreach ($service in $arcServices) {
        try {
            Set-Service -Name $service -StartupType Automatic
            # Disable delayed start - set to immediate automatic
            $regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\$service"
            Set-ItemProperty -Path $regPath -Name "DelayedAutostart" -Value 0 -ErrorAction SilentlyContinue
            Write-Host "  [OK] Enabled: $service" -ForegroundColor Green
        }
        catch {
            Write-Warning "  [X] Failed to enable $service : $($_.Exception.Message)"
        }
    }
    Write-Host ""
}

# Start services in order
Write-Host "Starting Arc services..." -ForegroundColor Yellow

# Start himds first (core service)
try {
    Start-Service -Name "himds"
    Write-Host "  [OK] Started: himds" -ForegroundColor Green
    Start-Sleep -Seconds 2
}
catch {
    Write-Warning "  [X] Failed to start himds: $($_.Exception.Message)"
}

# Start other services
$otherServices = @("GCArcService", "ExtensionService", "ArcProxy")
foreach ($service in $otherServices) {
    try {
        $svc = Get-Service -Name $service -ErrorAction SilentlyContinue
        if ($svc -and $svc.Status -ne "Running") {
            Start-Service -Name $service
            Write-Host "  [OK] Started: $service" -ForegroundColor Green
        }
        else {
            Write-Host "  [-] Already running: $service" -ForegroundColor Gray
        }
    }
    catch {
        Write-Warning "  [X] Failed to start $service : $($_.Exception.Message)"
    }
}

Write-Host ""
Write-Host "Waiting for services to stabilize..." -ForegroundColor Yellow
Start-Sleep -Seconds 5

# Display final status
Write-Host ""
Write-Host "Final Status:" -ForegroundColor Yellow
Get-Service -Name $arcServices | Format-Table Name, Status, StartType -AutoSize

# Check if AMA processes are running
Write-Host ""
Write-Host "AMA Process Status:" -ForegroundColor Yellow
$amaProcesses = Get-Process | Where-Object { $_.Name -match "AMA|MonAgent" }
if ($amaProcesses) {
    $amaProcesses | Format-Table Name, Id, StartTime -AutoSize
}
else {
    Write-Host "  AMA processes not yet started (may take 1-2 minutes)" -ForegroundColor Gray
}

Write-Host ""
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "  Arc Services Started" -ForegroundColor Green
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Impact:" -ForegroundColor Yellow
Write-Host "  - AMA will resume sending logs to Azure" -ForegroundColor Cyan
Write-Host "  - May take 1-2 minutes for AMA to fully start" -ForegroundColor Cyan
Write-Host "  - Logs will appear in Log Analytics workspace" -ForegroundColor Cyan
Write-Host ""

Write-Host "To stop Arc services, run:" -ForegroundColor Gray
Write-Host "  .\stop-arc-services.ps1" -ForegroundColor Gray
Write-Host ""
