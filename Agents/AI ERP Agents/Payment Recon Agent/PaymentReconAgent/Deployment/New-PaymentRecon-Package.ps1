<#
.SYNOPSIS
    Creates a clean, timestamped deployment ZIP package with the folder layout:
        README.md
        Deployment\   (scripts, ARM templates, SQL scripts, solution zip, settings template, DEPLOYMENT.md)
        Samples\      (sample CSV files)

.DESCRIPTION
    Builds the package from a temporary staging folder so the ZIP only contains the
    expected files for this release, arranged into README.md at the root, a Deployment
    folder, and a Samples folder. The output ZIP name always includes a timestamp to
    avoid ambiguity between package versions.

    This script lives in the Deployment folder; the package root is its parent.

.PARAMETER OutputDirectory
    Optional output folder for the ZIP file. Defaults to the V1\artifacts folder
    (created if needed).

.PARAMETER PackageNamePrefix
    Optional ZIP filename prefix. Defaults to: PaymentRecon-Azure-Deployment-Automation

.EXAMPLE
    .\New-PaymentRecon-Package.ps1

.EXAMPLE
    .\New-PaymentRecon-Package.ps1 -OutputDirectory "C:\Temp\packages"
#>

[CmdletBinding()]
param(
    [string]$OutputDirectory,
    [string]$PackageNamePrefix = "PaymentRecon-Azure-Deployment-Automation"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# This script is in the Deployment folder; the package root is its parent.
$deploymentDir = $PSScriptRoot
if (-not $deploymentDir) { $deploymentDir = Split-Path -Parent $MyInvocation.MyCommand.Path }
$rootDir    = Split-Path -Parent $deploymentDir
# Samples lives beside the scripts in this source repo (flat layout); in the
# delivered package it sits at the package root (beside the Deployment folder).
$samplesDir = Join-Path $deploymentDir "Samples"
if (-not (Test-Path $samplesDir)) {
    $samplesDir = Join-Path $rootDir "Samples"
}

if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path $deploymentDir 'artifacts'
}
if (-not (Test-Path $OutputDirectory)) {
    New-Item -Path $OutputDirectory -ItemType Directory -Force | Out-Null
}

# Files staged at the ZIP root.
$rootFiles = @(
    "README.md",
    "INSTALL.md"
)
# Files staged under Deployment\ in the ZIP.
$deploymentFiles = @(
    "Install-PaymentRecon.ps1",
    "Install-PaymentRecon.cmd",
    "Deploy-PowerPlatform.ps1",
    "Update-SolutionSqlBinding.ps1",
    "Deploy-PaymentRecon-KeyVault.ps1",
    "Deploy-PaymentRecon-Direct.ps1",
    "New-PaymentRecon-Package.ps1",
    "Deploy-PaymentRecon-Smart.ps1",
    "arm-storage-v4.json",
    "arm-datafactory-v4-keyvault.json",
    "arm-datafactory-v4-direct.json",
    "01_schema.sql",
    "02_indexes.sql",
    "03_seed_rules.sql",
    "PaymentReconSolutionV5.deployment-settings.template.json",
    "DEPLOYMENT.md"
)
# Final tested solution package staged under Deployment\Solutions\ in the ZIP.
# (Single merged solution — Agent V5 contains the Power App, Code App, both flows, and all agents.)
$solutionFiles = @(
    "PaymentReconAgentV5_unmanaged.zip"
)
# Files staged under Samples\ in the ZIP.
$sampleFiles = @(
    "Sample_Commerce Transactions.csv",
    "Sample_payments_accounting_report.csv"
)

# Build the (source -> path inside the package) work list and validate sources.
$items = New-Object System.Collections.Generic.List[object]
foreach ($n in $rootFiles)       { $items.Add([pscustomobject]@{ Source = (Join-Path $deploymentDir $n); Relative = $n }) }
foreach ($n in $deploymentFiles) { $items.Add([pscustomobject]@{ Source = (Join-Path $deploymentDir $n); Relative = (Join-Path "Deployment" $n) }) }
foreach ($n in $solutionFiles)   { $items.Add([pscustomobject]@{ Source = (Join-Path $deploymentDir (Join-Path 'Solutions' $n)); Relative = (Join-Path "Deployment" (Join-Path 'Solutions' $n)) }) }
foreach ($n in $sampleFiles)     { $items.Add([pscustomobject]@{ Source = (Join-Path $samplesDir $n);     Relative = (Join-Path "Samples" $n) }) }

$missing = @($items | Where-Object { -not (Test-Path -LiteralPath $_.Source) } | ForEach-Object { $_.Relative })
if ($missing.Count -gt 0) {
    throw "Cannot create package. Missing required file(s): $($missing -join ', ')"
}

$timeStamp = Get-Date -Format "yyyyMMdd-HHmmss"
$zipName = "$PackageNamePrefix-$timeStamp.zip"
$zipPath = Join-Path $OutputDirectory $zipName

$suffix = 1
while (Test-Path $zipPath) {
    $zipName = "{0}-{1}-{2:00}.zip" -f $PackageNamePrefix, $timeStamp, $suffix
    $zipPath = Join-Path $OutputDirectory $zipName
    $suffix++
}

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("payrecon-package-{0}" -f ([guid]::NewGuid().ToString("N")))
$stagingDir = Join-Path $tempRoot "staging"

try {
    New-Item -Path $stagingDir -ItemType Directory -Force | Out-Null

    foreach ($item in $items) {
        $dst = Join-Path $stagingDir $item.Relative
        $dstDir = Split-Path -Parent $dst
        if (-not (Test-Path $dstDir)) { New-Item -Path $dstDir -ItemType Directory -Force | Out-Null }
        Copy-Item -LiteralPath $item.Source -Destination $dst -Force
    }

    Compress-Archive -Path (Join-Path $stagingDir "*") -DestinationPath $zipPath -CompressionLevel Optimal -Force
    $zipInfo = Get-Item -Path $zipPath -ErrorAction Stop
    $hash = (Get-FileHash -Path $zipPath -Algorithm SHA256).Hash

    Write-Host "Created clean package ZIP:" -ForegroundColor Green
    Write-Host "  $($zipInfo.FullName)" -ForegroundColor Green
    Write-Host "Size: $($zipInfo.Length) bytes" -ForegroundColor Gray
    Write-Host "SHA256: $hash" -ForegroundColor Gray
    Write-Host "Layout: README.md + Deployment\ + Samples\" -ForegroundColor Gray
}
finally {
    if (Test-Path $tempRoot) {
        Remove-Item -Path $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
