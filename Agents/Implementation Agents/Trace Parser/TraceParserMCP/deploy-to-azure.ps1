<#
.SYNOPSIS
    Deploy TraceParser MCP Server to Azure App Service
.DESCRIPTION
    Provisions Azure resources (SQL Server, Database, App Service) and deploys
    the Data API Builder MCP server as a container-based App Service.

.DISCLAIMER
    This script is provided as sample/reference code only under the MIT License.
    It is not an official Microsoft product or service. Microsoft makes no warranties,
    express or implied, and assumes no liability for its use. You are responsible for
    reviewing, testing, and validating this script before running it in your environment.
    Use at your own risk.

    Copyright (c) Microsoft Corporation.
#>

param(
    [string]$ResourceGroup = "rg-traceparser-prod",
    [string]$Location = "westus2",
    [string]$SqlAdmin = "sqladmin",
    [string]$SqlPassword = "YourStrongP@ssw0rd!"
)

function Stop-OnError([string]$StepName) {
    if ($LASTEXITCODE -ne 0) {
        Write-Host "FAILED at: $StepName (exit code $LASTEXITCODE)" -ForegroundColor Red
        exit 1
    }
}

# Generate unique names
$timestamp = Get-Date -Format "yyyyMMddHHmm"
$SqlServer = "sql-traceparser-$timestamp"
$AppName = "app-traceparser-$timestamp"
$DabImage = "mcr.microsoft.com/azure-databases/data-api-builder:1.7.83-rc"

Write-Host "🚀 Starting Azure deployment..." -ForegroundColor Cyan

# 0. Register required providers
Write-Host "`n📋 Registering resource providers..." -ForegroundColor Yellow
az provider register --namespace Microsoft.Sql --wait
Stop-OnError "Register Microsoft.Sql"
az provider register --namespace Microsoft.Web --wait
Stop-OnError "Register Microsoft.Web"

# 1. Create Resource Group
Write-Host "`n📦 Creating resource group..." -ForegroundColor Yellow
az group create --name $ResourceGroup --location $Location
Stop-OnError "Create resource group"

# 2. Create SQL Server
Write-Host "`n🗄️  Creating SQL Server..." -ForegroundColor Yellow
az sql server create --name $SqlServer --resource-group $ResourceGroup --location $Location --admin-user $SqlAdmin --admin-password $SqlPassword
Stop-OnError "Create SQL Server"

# 3. Configure Firewall
Write-Host "`n🔒 Configuring firewall..." -ForegroundColor Yellow
az sql server firewall-rule create --resource-group $ResourceGroup --server $SqlServer --name AllowAzureServices --start-ip-address 0.0.0.0 --end-ip-address 0.0.0.0
Stop-OnError "Configure firewall"

# 4. Create Database
Write-Host "`n💾 Creating database..." -ForegroundColor Yellow
az sql db create --resource-group $ResourceGroup --server $SqlServer --name TraceParserDB --service-objective S1
Stop-OnError "Create database"

# 5. Create App Service Plan
Write-Host "`n⚙️  Creating App Service Plan..." -ForegroundColor Yellow
az appservice plan create --name "plan-traceparser" --resource-group $ResourceGroup --location $Location --sku B1 --is-linux
Stop-OnError "Create App Service Plan"

# 6. Create App Service with DAB container image
Write-Host "`n🌐 Creating App Service..." -ForegroundColor Yellow
az webapp create --name $AppName --resource-group $ResourceGroup --plan "plan-traceparser" --container-image-name $DabImage
Stop-OnError "Create App Service"

# 7. Configure App Service
Write-Host "`n⚙️  Configuring App Service..." -ForegroundColor Yellow
$ConnectionString = "Server=$SqlServer.database.windows.net;Database=TraceParserDB;User Id=$SqlAdmin;Password=$SqlPassword;Encrypt=True"

az webapp config appsettings set --name $AppName --resource-group $ResourceGroup --settings WEBSITES_ENABLE_APP_SERVICE_STORAGE=true AZURE_SQL_CONNECTION_STRING="$ConnectionString" WEBSITES_PORT=5000
Stop-OnError "Configure app settings"

az webapp config set --name $AppName --resource-group $ResourceGroup --always-on true --startup-file "--ConfigFileName /home/site/wwwroot/dab-config.json"
Stop-OnError "Configure app startup"

# 8. Deploy config files
Write-Host "`n📤 Deploying configuration..." -ForegroundColor Yellow
Compress-Archive -Path @("dab-config.json") -DestinationPath deploy.zip -Force

az webapp deploy --name $AppName --resource-group $ResourceGroup --src-path deploy.zip --type zip
Stop-OnError "Deploy configuration"

# 9. Restart to pick up changes
Write-Host "`n🔄 Restarting app..." -ForegroundColor Yellow
az webapp restart --name $AppName --resource-group $ResourceGroup
Stop-OnError "Restart app"

Write-Host "`n✅ Deployment complete!" -ForegroundColor Green
Write-Host "`nMCP URL: https://$AppName.azurewebsites.net/mcp" -ForegroundColor Cyan
Write-Host "SQL Server: $SqlServer.database.windows.net" -ForegroundColor Cyan
