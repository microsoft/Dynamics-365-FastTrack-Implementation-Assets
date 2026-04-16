# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.
#
# DISCLAIMER: This script is provided as sample/reference code for educational
# and demonstration purposes only. It is provided "as-is" without warranty of
# any kind. Microsoft does not operate or support deployments created with this
# script. You are responsible for reviewing, testing, and securing any
# resources deployed in your own environment.
#
# deploy.ps1 - Azure App Service Deployment Script
# Deploys the MCP server using WEBSITE_RUN_FROM_PACKAGE (bypasses Oryx build)
#
# Usage:
#   .\deploy.ps1                                          # Deploy with defaults
#   .\deploy.ps1 -AppName my-app -ResourceGroup my-rg    # Custom names
#   .\deploy.ps1 -Setup                                   # First-time Azure setup + deploy

param(
    [string]$AppName = "rel-planner-mcp-server",
    [string]$ResourceGroup = "rel-planner-mcp-server-rg",
    [switch]$Setup
)

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "================================================" -ForegroundColor Cyan
Write-Host "  MCP Server - Azure Deployment" -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan
Write-Host ""

# One-time Azure setup
if ($Setup) {
    Write-Host "[1/3] Removing conflicting settings..." -ForegroundColor Yellow
    az webapp config appsettings delete `
        --name $AppName `
        --resource-group $ResourceGroup `
        --setting-names CUSTOM_BUILD_COMMAND PRE_BUILD_COMMAND POST_BUILD_COMMAND WEBSITE_NODE_DEFAULT_VERSION 2>$null | Out-Null

    Write-Host "[2/3] Configuring Azure App Settings..." -ForegroundColor Yellow
    az webapp config appsettings set `
        --name $AppName `
        --resource-group $ResourceGroup `
        --settings WEBSITE_RUN_FROM_PACKAGE=1 SCM_DO_BUILD_DURING_DEPLOYMENT=false
    if ($LASTEXITCODE -ne 0) { Write-Host "ERROR: Failed to set app settings" -ForegroundColor Red; exit 1 }

    Write-Host "[3/3] Setting startup command..." -ForegroundColor Yellow
    az webapp config set `
        --name $AppName `
        --resource-group $ResourceGroup `
        --startup-file "node build/index-mcp.js"
    if ($LASTEXITCODE -ne 0) { Write-Host "ERROR: Failed to set startup command" -ForegroundColor Red; exit 1 }

    Write-Host ""
    Write-Host "Azure setup complete." -ForegroundColor Green
    Write-Host ""
}

# Step 1: Build TypeScript
Write-Host "[Step 1/5] Building TypeScript..." -ForegroundColor Yellow
npm run build
if ($LASTEXITCODE -ne 0) { Write-Host "ERROR: TypeScript build failed" -ForegroundColor Red; exit 1 }
Write-Host "  Build complete." -ForegroundColor Green

# Step 2: Create staging directory
Write-Host "[Step 2/5] Creating staging directory..." -ForegroundColor Yellow
if (Test-Path deploy-staging) { Remove-Item -Recurse -Force deploy-staging }
New-Item -ItemType Directory -Force -Path deploy-staging | Out-Null
Copy-Item -Recurse build deploy-staging/
Copy-Item package.json deploy-staging/
Copy-Item package-lock.json deploy-staging/
Write-Host "  Staging directory created." -ForegroundColor Green

# Step 3: Install production dependencies only
Write-Host "[Step 3/5] Installing production dependencies..." -ForegroundColor Yellow
Push-Location deploy-staging
npm ci --omit=dev 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
    Pop-Location
    Write-Host "ERROR: npm ci failed" -ForegroundColor Red
    exit 1
}
Pop-Location
Write-Host "  Production dependencies installed." -ForegroundColor Green

# Step 4: Create ZIP (using Python to ensure forward-slash paths for Linux compatibility)
Write-Host "[Step 4/5] Creating deployment package..." -ForegroundColor Yellow
if (Test-Path deploy.zip) { Remove-Item deploy.zip }
python3 -c @"
import zipfile, os
with zipfile.ZipFile('deploy.zip', 'w', zipfile.ZIP_DEFLATED) as zf:
    for root, dirs, files in os.walk('deploy-staging'):
        for f in files:
            fp = os.path.join(root, f)
            arcname = os.path.relpath(fp, 'deploy-staging').replace(os.sep, '/')
            zf.write(fp, arcname)
"@
if ($LASTEXITCODE -ne 0) { Write-Host "ERROR: Failed to create ZIP" -ForegroundColor Red; exit 1 }
$zipSize = (Get-Item deploy.zip).Length / 1MB
Write-Host "  Package created: deploy.zip ($([math]::Round($zipSize, 1)) MB)" -ForegroundColor Green

# Step 5: Deploy to Azure
Write-Host "[Step 5/5] Deploying to Azure..." -ForegroundColor Yellow
az webapp deploy `
    --name $AppName `
    --resource-group $ResourceGroup `
    --src-path deploy.zip `
    --type zip
if ($LASTEXITCODE -ne 0) { Write-Host "ERROR: Deployment failed" -ForegroundColor Red; exit 1 }

# Cleanup
Write-Host ""
Write-Host "Cleaning up..." -ForegroundColor Yellow
Remove-Item -Recurse -Force deploy-staging
Remove-Item deploy.zip

# Verify
Write-Host ""
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

Write-Host ""
Write-Host "================================================" -ForegroundColor Green
Write-Host "  Deployment Complete!" -ForegroundColor Green
Write-Host "================================================" -ForegroundColor Green
Write-Host ""
Write-Host "  MCP Endpoint:  https://$hostname/mcp"
Write-Host "  Health Check:  https://$hostname/health"
if ($healthy) {
    Write-Host "  Status:        HEALTHY" -ForegroundColor Green
} else {
    Write-Host "  Status:        NOT YET RESPONDING (may still be starting)" -ForegroundColor Yellow
}
Write-Host ""
