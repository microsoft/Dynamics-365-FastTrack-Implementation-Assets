# Build WiX v4 Installer Script
# This script builds the EventLog Sink Config Service MSI installer using WiX v4 SDK

param(
    [Parameter(Mandatory = $false)]
    [ValidateSet("Debug", "Release")]
    [string]$Configuration = "Release"
)

$ErrorActionPreference = "Stop"
$ScriptDir = $PSScriptRoot
$InstallerRoot = Split-Path $ScriptDir -Parent
$RepoRoot = Split-Path $InstallerRoot -Parent
$ServiceDir = Join-Path $RepoRoot "services\EventLogSinkConfigService"
$WixProjectDir = Join-Path $InstallerRoot "WixProject"

function Test-DotNetSdk {
    try {
        $sdkList = dotnet --list-sdks 2>&1
        if ($sdkList -match "8\.0\.\d+") {
            return $true
        }
    }
    catch {
        return $false
    }
    return $false
}

Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "  Building EventLog Sink Config Service Installer" -ForegroundColor Cyan
Write-Host "  Using WiX v4 SDK-style project" -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Paths:" -ForegroundColor Gray
Write-Host "  Repository Root: $RepoRoot" -ForegroundColor Gray
Write-Host "  Service Dir:     $ServiceDir" -ForegroundColor Gray
Write-Host "  WiX Project:     $WixProjectDir" -ForegroundColor Gray
Write-Host ""

# Check prerequisites
Write-Host "[1/4] Checking prerequisites..." -ForegroundColor Yellow

$dotnet8Installed = Test-DotNetSdk

Write-Host ""
Write-Host "  Prerequisites Status:" -ForegroundColor Cyan
Write-Host "    .NET 8.0 SDK: $(if ($dotnet8Installed) { 'Installed' } else { 'NOT FOUND' })" -ForegroundColor $(if ($dotnet8Installed) { 'Green' } else { 'Red' })
Write-Host ""

if (-not $dotnet8Installed) {
    Write-Error ".NET 8.0 SDK not found!"
    Write-Host ""
    Write-Host "Please download and install from:" -ForegroundColor Yellow
    Write-Host "  https://dotnet.microsoft.com/download/dotnet/8.0" -ForegroundColor White
    exit 1
}

Write-Host "  All prerequisites satisfied!" -ForegroundColor Green

# Build the main service
Write-Host ""
Write-Host "[2/4] Building EventLogSinkConfigService..." -ForegroundColor Yellow
Push-Location $ServiceDir
try {
    dotnet publish -c $Configuration -r win-x64 --self-contained false
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to build EventLogSinkConfigService"
    }
    Write-Host "  EventLogSinkConfigService built successfully" -ForegroundColor Green
}
finally {
    Pop-Location
}

# Prepare installer resources
Write-Host ""
Write-Host "[3/4] Preparing installer resources..." -ForegroundColor Yellow
Push-Location $WixProjectDir
try {
    if (-not (Test-Path "Icon.ico")) {
        Write-Host "  Creating placeholder icon..." -ForegroundColor Yellow
        # Create a simple ICO file (this is a minimal valid ICO)
        $iconBytes = [byte[]]@(
            0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x10, 0x10, 0x00, 0x00, 0x01, 0x00, 0x20, 0x00, 0x68, 0x04,
            0x00, 0x00, 0x16, 0x00, 0x00, 0x00, 0x28, 0x00, 0x00, 0x00, 0x10, 0x00, 0x00, 0x00, 0x20, 0x00
        )
        [System.IO.File]::WriteAllBytes("$WixProjectDir\Icon.ico", $iconBytes)
    }

    if (-not (Test-Path "License.rtf")) {
        Write-Host "  Creating placeholder license..." -ForegroundColor Yellow
        @"
{\rtf1\ansi\deff0
{\fonttbl{\f0 Times New Roman;}}
\f0\fs24 EventLog Sink Config Service License Agreement\par
\par
This software is provided "as is" without warranty of any kind.\par
}
"@ | Out-File -FilePath "License.rtf" -Encoding ascii
    }

    Write-Host "  Resources prepared" -ForegroundColor Green
}
finally {
    Pop-Location
}

# Build the installer using WiX v4 SDK
Write-Host ""
Write-Host "[4/4] Building MSI installer with WiX v4..." -ForegroundColor Yellow

Push-Location $WixProjectDir
try {
    # WiX v4 uses dotnet build - NuGet packages are restored automatically
    dotnet build -c $Configuration -p:Platform=x64

    if ($LASTEXITCODE -ne 0) {
        throw "WiX v4 build failed"
    }

    Write-Host "  MSI built successfully" -ForegroundColor Green
}
finally {
    Pop-Location
}

# Find the output MSI
$MsiPath = Get-ChildItem -Path "$WixProjectDir\bin\$Configuration" -Filter "*.msi" -Recurse | Select-Object -First 1

Write-Host ""
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "  Build Complete!" -ForegroundColor Green
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Installer location:" -ForegroundColor Yellow
if ($MsiPath) {
    Write-Host "  $($MsiPath.FullName)" -ForegroundColor White
}
else {
    Write-Host "  $WixProjectDir\bin\$Configuration\x64\EventLogSinkConfigService.Installer.msi" -ForegroundColor White
}
Write-Host ""
