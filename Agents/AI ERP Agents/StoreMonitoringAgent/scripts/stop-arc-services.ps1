# Stop Azure Arc Services Script
# This will stop Arc and prevent AMA from sending logs
# Run as Administrator

param(
    [Parameter(Mandatory = $false)]
    [switch]$DisableAutoStart
)

# Check if running as Administrator
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
$isAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Error "This script must be run as Administrator."
    exit 1
}

Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "  Stopping Azure Arc Services" -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host ""

$arcServices = @("himds", "GCArcService", "ExtensionService", "ArcProxy")

# Display current status
Write-Host "Current Status:" -ForegroundColor Yellow
Get-Service -Name $arcServices | Format-Table Name, DisplayName, Status, StartType -AutoSize
Write-Host ""

# Stop services
Write-Host "Stopping Arc services..." -ForegroundColor Yellow
foreach ($service in $arcServices) {
    try {
        $svc = Get-Service -Name $service -ErrorAction SilentlyContinue
        if ($svc -and $svc.Status -eq "Running") {
            Stop-Service -Name $service -Force
            Write-Host "  [OK] Stopped: $service" -ForegroundColor Green
        }
        else {
            Write-Host "  [-] Already stopped: $service" -ForegroundColor Gray
        }
    }
    catch {
        Write-Warning "  [X] Failed to stop $service : $($_.Exception.Message)"
    }
}

Write-Host ""

# Optionally disable auto-start
if ($DisableAutoStart) {
    Write-Host "Disabling auto-start..." -ForegroundColor Yellow
    foreach ($service in $arcServices) {
        try {
            Set-Service -Name $service -StartupType Disabled
            Write-Host "  [OK] Disabled: $service" -ForegroundColor Green
        }
        catch {
            Write-Warning "  [X] Failed to disable $service : $($_.Exception.Message)"
        }
    }
    Write-Host ""
}

# Display final status
Write-Host "Final Status:" -ForegroundColor Yellow
Get-Service -Name $arcServices | Format-Table Name, Status, StartType -AutoSize

Write-Host ""
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "  Arc Services Stopped" -ForegroundColor Green
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Impact:" -ForegroundColor Yellow
Write-Host "  - AMA will NOT send logs to Azure" -ForegroundColor Cyan
Write-Host "  - Device is still registered in Azure Arc" -ForegroundColor Cyan
Write-Host "  - Services will restart on reboot (unless disabled)" -ForegroundColor Cyan
Write-Host ""

if (-not $DisableAutoStart) {
    Write-Host "To prevent auto-start on reboot, run:" -ForegroundColor Gray
    Write-Host "  .\stop-arc-services.ps1 -DisableAutoStart" -ForegroundColor Gray
    Write-Host ""
}

Write-Host "To restart Arc services, run:" -ForegroundColor Gray
Write-Host "  .\start-arc-services.ps1" -ForegroundColor Gray
Write-Host ""
