# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.
#
# DISCLAIMER: This script is provided as sample/reference code for educational
# and demonstration purposes only. It is provided "as-is" without warranty of
# any kind. Microsoft does not operate or support deployments created with this
# script. You are responsible for reviewing, testing, and securing any
# resources deployed in your own environment.
#
# deploy-customer.ps1 - End-to-End Azure Deployment Script
# Provisions Azure resources AND deploys the MCP server in one step.
#
# Usage:
#   .\deploy-customer.ps1 -AppName my-release-planner          # Quick start
#   .\deploy-customer.ps1 -AppName my-mcp -Location westus2    # Custom region
#   .\deploy-customer.ps1 -AppName my-mcp -Sku S1              # Custom tier
#
# Prerequisites: Azure CLI, Node.js 20+, npm, Python 3
#
# If you have multiple Azure subscriptions, set the target first:
#   az account set --subscription "Your Subscription Name"
#   .\deploy-customer.ps1 -AppName my-release-planner

param(
    [string]$AppName = "rel-planner-mcp",
    [string]$ResourceGroup = "$AppName-rg",
    [string]$Location = "eastus",
    [string]$Sku = "B1",
    [string]$OwnerTag = ""
)

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "================================================" -ForegroundColor Cyan
Write-Host "  MCP Server - Azure End-to-End Deployment" -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  App Name:       $AppName"
Write-Host "  Resource Group:  $ResourceGroup"
Write-Host "  Location:        $Location"
Write-Host "  SKU:             $Sku"
Write-Host ""

# ─── Step 1: Prerequisites ───────────────────────────────────────────────────

Write-Host "[Step  1/12] Checking prerequisites..." -ForegroundColor Yellow

function Test-Prerequisite($Command, $DisplayName, $InstallUrl) {
    if (-not (Get-Command $Command -ErrorAction SilentlyContinue)) {
        Write-Host "  ERROR: $DisplayName is required but not found." -ForegroundColor Red
        Write-Host "  Install from: $InstallUrl" -ForegroundColor Gray
        exit 1
    }
    $version = & $Command --version 2>&1 | Select-Object -First 1
    Write-Host "  $DisplayName : $version" -ForegroundColor Green
}

Test-Prerequisite "az"      "Azure CLI" "https://aka.ms/installazurecliwindows"
Test-Prerequisite "node"    "Node.js"   "https://nodejs.org"
Test-Prerequisite "npm"     "npm"       "https://nodejs.org"

# Python3 may be 'python3' or 'python' on Windows
$pythonCmd = $null
if (Get-Command "python3" -ErrorAction SilentlyContinue) {
    $pythonCmd = "python3"
} elseif (Get-Command "python" -ErrorAction SilentlyContinue) {
    $pyVer = & python --version 2>&1
    if ($pyVer -match "Python 3") {
        $pythonCmd = "python"
    }
}
if (-not $pythonCmd) {
    Write-Host "  ERROR: Python 3 is required but not found." -ForegroundColor Red
    Write-Host "  Install from: https://www.python.org/downloads/" -ForegroundColor Gray
    exit 1
}
$pyVersion = & $pythonCmd --version 2>&1
Write-Host "  Python   : $pyVersion" -ForegroundColor Green

# ─── Step 2: Azure Login ─────────────────────────────────────────────────────

Write-Host ""
Write-Host "[Step  2/12] Checking Azure login..." -ForegroundColor Yellow

$account = $null
try {
    $account = az account show 2>$null | ConvertFrom-Json
} catch {}

if (-not $account) {
    Write-Host "  Not logged in. Running 'az login'..." -ForegroundColor Yellow
    az login
    if ($LASTEXITCODE -ne 0) { Write-Host "  ERROR: Azure login failed." -ForegroundColor Red; exit 1 }
    $account = az account show | ConvertFrom-Json
}

Write-Host "  Subscription: $($account.name) ($($account.id))" -ForegroundColor Green

# ─── Step 3: Resource Group ──────────────────────────────────────────────────

Write-Host ""
Write-Host "[Step  3/12] Creating resource group..." -ForegroundColor Yellow

$rgExists = az group exists --name $ResourceGroup 2>$null
if ($rgExists -eq "true") {
    Write-Host "  Resource group '$ResourceGroup' already exists. Skipping." -ForegroundColor Gray
} else {
    $rgArgs = @("group", "create", "--name", $ResourceGroup, "--location", $Location)
    if ($OwnerTag) { $rgArgs += "--tags"; $rgArgs += "Owner=$OwnerTag" }
    az @rgArgs --output none
    if ($LASTEXITCODE -ne 0) { Write-Host "  ERROR: Failed to create resource group." -ForegroundColor Red; exit 1 }
    Write-Host "  Resource group '$ResourceGroup' created." -ForegroundColor Green
}

# ─── Step 4: App Service Plan ────────────────────────────────────────────────

Write-Host ""
Write-Host "[Step  4/12] Creating App Service plan..." -ForegroundColor Yellow

$PlanName = "$AppName-plan"
$planCheck = az appservice plan show --name $PlanName --resource-group $ResourceGroup 2>$null
if ($planCheck) {
    Write-Host "  App Service plan '$PlanName' already exists. Skipping." -ForegroundColor Gray
} else {
    az appservice plan create `
        --name $PlanName `
        --resource-group $ResourceGroup `
        --location $Location `
        --sku $Sku `
        --is-linux `
        --output none
    if ($LASTEXITCODE -ne 0) { Write-Host "  ERROR: Failed to create App Service plan." -ForegroundColor Red; exit 1 }
    Write-Host "  App Service plan '$PlanName' created ($Sku, Linux)." -ForegroundColor Green
}

# ─── Step 5: Web App ─────────────────────────────────────────────────────────

Write-Host ""
Write-Host "[Step  5/12] Creating Web App..." -ForegroundColor Yellow

$appCheck = az webapp show --name $AppName --resource-group $ResourceGroup 2>$null
if ($appCheck) {
    Write-Host "  Web App '$AppName' already exists. Skipping." -ForegroundColor Gray
} else {
    az webapp create `
        --name $AppName `
        --resource-group $ResourceGroup `
        --plan $PlanName `
        --runtime "NODE:20-lts" `
        --output none
    if ($LASTEXITCODE -ne 0) { Write-Host "  ERROR: Failed to create Web App." -ForegroundColor Red; exit 1 }
    Write-Host "  Web App '$AppName' created (Node.js 20 LTS)." -ForegroundColor Green
}

# ─── Step 6: App Configuration ───────────────────────────────────────────────

Write-Host ""
Write-Host "[Step  6/12] Configuring app settings..." -ForegroundColor Yellow

# Remove conflicting build settings (may not exist, ignore errors)
az webapp config appsettings delete `
    --name $AppName `
    --resource-group $ResourceGroup `
    --setting-names CUSTOM_BUILD_COMMAND PRE_BUILD_COMMAND POST_BUILD_COMMAND WEBSITE_NODE_DEFAULT_VERSION 2>$null | Out-Null

# Set required settings
az webapp config appsettings set `
    --name $AppName `
    --resource-group $ResourceGroup `
    --settings WEBSITE_RUN_FROM_PACKAGE=1 SCM_DO_BUILD_DURING_DEPLOYMENT=false `
    --output none
if ($LASTEXITCODE -ne 0) { Write-Host "  ERROR: Failed to set app settings." -ForegroundColor Red; exit 1 }

# Set startup command
az webapp config set `
    --name $AppName `
    --resource-group $ResourceGroup `
    --startup-file "node build/index-mcp.js" `
    --output none
if ($LASTEXITCODE -ne 0) { Write-Host "  ERROR: Failed to set startup command." -ForegroundColor Red; exit 1 }

Write-Host "  App settings configured." -ForegroundColor Green

# ─── Step 7: Install Dependencies ────────────────────────────────────────────

Write-Host ""
Write-Host "[Step  7/12] Installing dependencies..." -ForegroundColor Yellow
npm install
if ($LASTEXITCODE -ne 0) { Write-Host "  ERROR: npm install failed." -ForegroundColor Red; exit 1 }
Write-Host "  Dependencies installed." -ForegroundColor Green

# ─── Step 8: Build TypeScript ────────────────────────────────────────────────

Write-Host ""
Write-Host "[Step  8/12] Building TypeScript..." -ForegroundColor Yellow
npm run build
if ($LASTEXITCODE -ne 0) { Write-Host "  ERROR: TypeScript build failed." -ForegroundColor Red; exit 1 }
Write-Host "  Build complete." -ForegroundColor Green

# ─── Step 9: Staging Directory ───────────────────────────────────────────────

Write-Host ""
Write-Host "[Step  9/12] Creating staging directory..." -ForegroundColor Yellow
if (Test-Path deploy-staging) { Remove-Item -Recurse -Force deploy-staging }
New-Item -ItemType Directory -Force -Path deploy-staging | Out-Null
Copy-Item -Recurse build deploy-staging/
Copy-Item package.json deploy-staging/
Copy-Item package-lock.json deploy-staging/
Write-Host "  Staging directory created." -ForegroundColor Green

# ─── Step 10: Production Dependencies ────────────────────────────────────────

Write-Host ""
Write-Host "[Step 10/12] Installing production dependencies..." -ForegroundColor Yellow
Push-Location deploy-staging
npm ci --omit=dev 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
    Pop-Location
    Write-Host "  ERROR: npm ci failed." -ForegroundColor Red
    exit 1
}
Pop-Location
Write-Host "  Production dependencies installed." -ForegroundColor Green

# ─── Step 11: Create ZIP ─────────────────────────────────────────────────────

Write-Host ""
Write-Host "[Step 11/12] Creating deployment package..." -ForegroundColor Yellow
if (Test-Path deploy.zip) { Remove-Item deploy.zip }

# IMPORTANT: Use Python zipfile, NOT Compress-Archive.
# Compress-Archive creates backslash paths that break WEBSITE_RUN_FROM_PACKAGE on Linux.
& $pythonCmd -c @"
import zipfile, os
with zipfile.ZipFile('deploy.zip', 'w', zipfile.ZIP_DEFLATED) as zf:
    for root, dirs, files in os.walk('deploy-staging'):
        for f in files:
            fp = os.path.join(root, f)
            arcname = os.path.relpath(fp, 'deploy-staging').replace(os.sep, '/')
            zf.write(fp, arcname)
"@
if ($LASTEXITCODE -ne 0) { Write-Host "  ERROR: Failed to create ZIP." -ForegroundColor Red; exit 1 }
$zipSize = (Get-Item deploy.zip).Length / 1MB
Write-Host "  Package created: deploy.zip ($([math]::Round($zipSize, 1)) MB)" -ForegroundColor Green

# ─── Step 12: Deploy ─────────────────────────────────────────────────────────

Write-Host ""
Write-Host "[Step 12/12] Deploying to Azure..." -ForegroundColor Yellow
az webapp deploy `
    --name $AppName `
    --resource-group $ResourceGroup `
    --src-path deploy.zip `
    --type zip
if ($LASTEXITCODE -ne 0) { Write-Host "  ERROR: Deployment failed." -ForegroundColor Red; exit 1 }

# ─── Cleanup ──────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "Cleaning up..." -ForegroundColor Yellow
Remove-Item -Recurse -Force deploy-staging -ErrorAction SilentlyContinue
Remove-Item deploy.zip -ErrorAction SilentlyContinue

# ─── Health Check ─────────────────────────────────────────────────────────────

$hostname = az webapp show --name $AppName --resource-group $ResourceGroup --query defaultHostName --output tsv

Write-Host "Waiting for app to start..." -ForegroundColor Yellow
$maxRetries = 6
$retryCount = 0
$healthy = $false
while ($retryCount -lt $maxRetries) {
    Start-Sleep -Seconds 10
    try {
        $response = Invoke-WebRequest -Uri "https://$hostname/health" -UseBasicParsing -TimeoutSec 10 -ErrorAction SilentlyContinue
        if ($response.StatusCode -eq 200) {
            $healthy = $true
            break
        }
    } catch {}
    $retryCount++
    Write-Host "  Retry $retryCount/$maxRetries..." -ForegroundColor Gray
}

# ─── Done ─────────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "================================================" -ForegroundColor Green
Write-Host "  Deployment Complete!" -ForegroundColor Green
Write-Host "================================================" -ForegroundColor Green
Write-Host ""
Write-Host "  App Name:       $AppName"
Write-Host "  Resource Group:  $ResourceGroup"
Write-Host "  Location:        $Location"
Write-Host "  MCP Endpoint:    https://$hostname/mcp"
Write-Host "  Health Check:    https://$hostname/health"
if ($healthy) {
    Write-Host "  Status:          HEALTHY" -ForegroundColor Green
} else {
    Write-Host "  Status:          NOT YET RESPONDING (may still be starting)" -ForegroundColor Yellow
}
Write-Host ""
Write-Host "Next step: Connect to Copilot Studio" -ForegroundColor Cyan
Write-Host "  1. Open https://copilotstudio.microsoft.com" -ForegroundColor Gray
Write-Host "  2. Go to Tools > Add an MCP server" -ForegroundColor Gray
Write-Host "  3. Set URL to: https://$hostname/mcp" -ForegroundColor Gray
Write-Host "  4. Set Authentication to: None" -ForegroundColor Gray
Write-Host ""
