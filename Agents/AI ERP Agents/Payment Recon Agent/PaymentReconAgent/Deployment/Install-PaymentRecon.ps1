<#
.SYNOPSIS
    Payment Recon V1 installer (Create or Update).

.DESCRIPTION
    At startup it asks whether this is a first-time install or an update:

      [1] First-time install (Create) - the PROVEN install flow, unchanged: runs the
          Azure (Direct) deployment with a fresh sign-in, then signs in to Power Platform
          and imports the solution (bootstrapping connections).
      [2] Update an existing install   - starts with the resource group, reads every
          component, and CREATES only what is missing while REUSING what already exists
          (an existing Azure SQL database is reused and its data preserved). This path is
          delegated to the discovery-driven engine Deploy-PaymentRecon-Smart.ps1.

    Azure uses the Direct variant (no Key Vault). SQL admin credentials are prompted at
    runtime by the underlying scripts and are never written to disk.
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Force a neutral console palette for this installer session so inherited shell
# themes/colors do not produce a full-screen blue background.
if ($Host -and $Host.UI -and $Host.UI.RawUI) {
    $Host.UI.RawUI.BackgroundColor = "Black"
    $Host.UI.RawUI.ForegroundColor = "Gray"
    Clear-Host
}
$esc = [char]27
Write-Host "$esc[0m$esc[37;40m$esc[2J$esc[H" -NoNewline

trap {
    Write-Host "`n[ERROR] $($_.Exception.Message)" -ForegroundColor Red
    throw
}

function Read-RequiredValue {
    param([Parameter(Mandatory)] [string]$Prompt)

    while ($true) {
        $value = Read-Host $Prompt
        if (-not [string]::IsNullOrWhiteSpace($value)) {
            return $value.Trim()
        }
        Write-Host "Value is required." -ForegroundColor Yellow
    }
}

function Read-CustomerPrefix {
    while ($true) {
        $p = (Read-RequiredValue "Customer prefix (5-10 lowercase letters/numbers)").ToLowerInvariant()
        if ($p -match '^[a-z0-9]{5,10}$') { return $p }
        Write-Host "Prefix must be 5-10 lowercase letters or numbers." -ForegroundColor Yellow
    }
}

function Read-InstallMode {
    while ($true) {
        Write-Host ""
        Write-Host "Is this a first-time install or an update of an existing one?" -ForegroundColor Cyan
        Write-Host "  [1] First-time install (Create a new deployment)"
        Write-Host "  [2] Update an existing install (asks for the resource group)"
        Write-Host "  [Q] Quit"
        switch ((Read-Host "Enter choice [1/2/Q]").ToUpperInvariant()) {
            "1" { return "Create" }
            "2" { return "Update" }
            "Q" { return "Quit" }
            default { Write-Host "Please choose 1, 2, or Q." -ForegroundColor Yellow }
        }
    }
}

function Get-PacCommand {
    $pac = Get-Command pac -ErrorAction SilentlyContinue
    if (-not $pac) {
        throw "Power Platform CLI (pac) was not found. Install it first, then rerun this installer: https://aka.ms/PowerAppsCLI"
    }
    return $pac.Source
}

function Clear-DeploymentSignIns {
    Write-Host "`n==> Clearing cached sign-in tokens..." -ForegroundColor Cyan

    # Power Platform auth profiles are created and removed by Deploy-PowerPlatform.ps1.
    # Here we only clear the in-memory Azure context. Combined with the deploy
    # script's Disable-AzContextAutosave, this leaves no reusable token behind.
    if (Get-Command Disconnect-AzAccount -ErrorAction SilentlyContinue) {
        Disconnect-AzAccount -ErrorAction SilentlyContinue | Out-Null
    }
    if (Get-Command Clear-AzContext -ErrorAction SilentlyContinue) {
        Clear-AzContext -Scope Process -Force -ErrorAction SilentlyContinue
    }
    Write-Host "Cleared cached Azure sign-in for this session." -ForegroundColor Gray
}

$scriptDir = $PSScriptRoot
if (-not $scriptDir) { $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path }

Write-Host "`n============================================================" -ForegroundColor Magenta
Write-Host "  Payment Recon V1 - Installer (Create or Update)" -ForegroundColor Magenta
Write-Host "============================================================" -ForegroundColor Magenta

$mode = Read-InstallMode
if ($mode -eq "Quit") { return }

# =========================== UPDATE (new) ===========================
# Resource-group driven: read every component, create what is missing, reuse the rest.
if ($mode -eq "Update") {
    $engine = Join-Path $scriptDir "Deploy-PaymentRecon-Smart.ps1"
    if (-not (Test-Path $engine)) { throw "Update engine not found: $engine" }
    $null = Get-PacCommand

    $resourceGroup  = Read-RequiredValue "Existing resource group to update (e.g. <prefix>-paymentrecon-rg)"
    $customerPrefix = $null
    if ($resourceGroup -notmatch '^[a-z0-9]{5,10}-paymentrecon-rg$') {
        Write-Host "Resource group is not in the '<prefix>-paymentrecon-rg' form; enter the prefix." -ForegroundColor Yellow
        $customerPrefix = Read-CustomerPrefix
    }
    $environmentUrl = Read-RequiredValue "Target Power Platform environment URL (e.g. https://org.crm.dynamics.com)"

    Write-Host "`n==> Update an existing install" -ForegroundColor Cyan
    Write-Host "    Reads each component and CREATES only what is missing, REUSING what exists" -ForegroundColor Gray
    Write-Host "    (existing SQL data is preserved)." -ForegroundColor Gray

    $engineArgs = @{ Mode = 'Redeploy'; ResourceGroupName = $resourceGroup; EnvironmentUrl = $environmentUrl; Execute = $true }
    if ($customerPrefix) { $engineArgs.CustomerPrefix = $customerPrefix }
    & $engine @engineArgs
    return
}

# ================= CREATE (proven install flow - unchanged) =================
# Key Vault variant hidden for now (planned for a later version): always Direct.
Write-Host "This installer will ask for Azure sign-in first, then Power Platform sign-in." -ForegroundColor Gray
Write-Host "Power Platform sign-in is automatic: browser first, then device-code fallback when needed." -ForegroundColor Gray
Write-Host "Cached sign-ins are intentionally not reused for either step." -ForegroundColor Gray

$azureScript = Join-Path $scriptDir "Deploy-PaymentRecon-Direct.ps1"
if (-not (Test-Path $azureScript)) {
    throw "Azure deployment script not found: $azureScript"
}

# Pre-flight: ensure pac exists before the long Azure deploy so we fail fast.
$null = Get-PacCommand

try {
    Write-Host "`n==> Azure deployment" -ForegroundColor Cyan
    Write-Host "A fresh Azure sign-in (browser window) will be requested even if a cached Az context exists." -ForegroundColor Gray
    Write-Host "Azure tokens are kept in memory only and are not written to disk." -ForegroundColor Gray
    $settingsPath = Join-Path $scriptDir "PaymentReconSolutionV5.deployment-settings.json"
    if (Test-Path $settingsPath) {
        Remove-Item -Path $settingsPath -Force -ErrorAction SilentlyContinue
    }
    $settingsStartUtc = [DateTime]::UtcNow
    & $azureScript -ForceAzureLogin

    if (-not (Test-Path $settingsPath)) {
        throw "Power Platform deployment settings file was not generated: $settingsPath"
    }
    $settingsInfo = Get-Item -Path $settingsPath -ErrorAction Stop
    if ($settingsInfo.LastWriteTimeUtc -lt $settingsStartUtc.AddSeconds(-2)) {
        throw "Power Platform deployment settings file appears stale (not regenerated by this run): $settingsPath"
    }
    if ($settingsInfo.Length -le 0) {
        throw "Power Platform deployment settings file is empty: $settingsPath"
    }

    # Two independent solutions ship in Solutions\ (source repo) or beside this
    # script under Solutions\ (delivered package). Code App is imported first.
    function Resolve-SolutionZipPath {
        param([string]$Dir, [string]$Name)
        $candidate = Join-Path $Dir (Join-Path 'Solutions' $Name)
        if (Test-Path $candidate) { return $candidate }
        return (Join-Path $Dir $Name)
    }
    $solutionZip = Resolve-SolutionZipPath -Dir $scriptDir -Name "PaymentReconAgentV5_unmanaged.zip"
    if (-not (Test-Path $solutionZip)) {
        throw "Power Platform solution zip not found: $solutionZip"
    }

    Write-Host "`n==> Power Platform solution import" -ForegroundColor Cyan
    $environmentUrl = Read-RequiredValue -Prompt "Enter target Power Platform environment URL (for example, https://org.crm.dynamics.com)"

    $powerPlatformScript = Join-Path $scriptDir "Deploy-PowerPlatform.ps1"
    if (-not (Test-Path $powerPlatformScript)) {
        throw "Power Platform deployment script not found: $powerPlatformScript"
    }
    $powerPlatformLogPath = Join-Path $scriptDir ("deploy-powerplatform-{0}.log" -f (Get-Date -Format "yyyyMMdd-HHmmss"))
    Write-Host "Power Platform log file: $powerPlatformLogPath" -ForegroundColor Gray

    # The standalone script handles browser sign-in, verification, import, and
    # removal of its own temporary auth profile. It throws on any failure, which
    # propagates to the trap handler above.
    $powerPlatformArgs = @{
        EnvironmentUrl           = $environmentUrl
        SolutionZip              = $solutionZip
        SettingsFile             = $settingsPath
        LogFile                  = $powerPlatformLogPath
        SignInMode               = 'AutoFallback'
        BootstrapConnectionSetup = $true
    }
    & $powerPlatformScript @powerPlatformArgs

    Write-Host "`n============================================================" -ForegroundColor Magenta
    Write-Host "  Payment Recon deployment complete" -ForegroundColor Magenta
    Write-Host "============================================================" -ForegroundColor Magenta
    Write-Host "Azure settings used for Power Platform import: $settingsPath" -ForegroundColor Gray
    Write-Host ""
}
finally {
    # Always clear the Azure sign-in for this session, even on partial failure.
    # (Deploy-PowerPlatform.ps1 removes its own Power Platform auth profile.)
    Clear-DeploymentSignIns
}
