<#
.SYNOPSIS
    Deploy TraceParserWeb (Blazor + Azure Function + Storage) to Azure.
    Reuses existing SQL Server and DAB App Service from deploy-to-azure.ps1.

.DESCRIPTION
    Creates only the new resources needed for the website:
      - Azure Storage Account (blob trigger + Blazor data protection)
      - Azure Function App (Windows Premium EP1, net8.0-windows, ETW parser)
      - Azure Web App (Windows B2, net9.0, Blazor Server)

.NOTES
    Existing resources required (from prior deploy-to-azure.ps1 run):
      - Resource Group (default: rg-traceparser-prod)
      - A deployed DAB App Service (provide name via -DabAppName)
#>

param(
    [string]$ResourceGroup = "rg-traceparser-prod",
    [string]$Location      = "westus2",

    [Parameter(Mandatory)]
    [string]$DabAppName,

    [Parameter(Mandatory)]
    [string]$TenantId,

    [Parameter(Mandatory)]
    [string]$ClientId,

    [Parameter(Mandatory)]
    [string]$CopilotEnvironmentId,

    [string]$CopilotSchemaName = "copilots_header_cd9c8"
)

function Stop-OnError([string]$Step) {
    if ($LASTEXITCODE -ne 0) { Write-Host "FAILED at: $Step" -ForegroundColor Red; exit 1 }
}

$timestamp = Get-Date -Format "yyyyMMddHHmm"

# Retrieve connection string from existing DAB app
Write-Host "`n🔑 Retrieving SQL connection string from existing DAB app..." -ForegroundColor Yellow
$ConnectionString = (az webapp config appsettings list `
    --name $DabAppName `
    --resource-group $ResourceGroup `
    --query "[?name=='AZURE_SQL_CONNECTION_STRING'].value" -o tsv)
Stop-OnError "Retrieve connection string"

$DabUrl = "https://$DabAppName.azurewebsites.net"

# ── 1. Storage Account ────────────────────────────────────────────────────────
$StorageName = "sttraceparser$timestamp"
Write-Host "`n💾 Creating Storage Account: $StorageName..." -ForegroundColor Yellow
az storage account create `
    --name $StorageName `
    --resource-group $ResourceGroup `
    --location $Location `
    --sku Standard_LRS `
    --kind StorageV2
Stop-OnError "Create Storage Account"

$StorageConnStr = (az storage account show-connection-string `
    --name $StorageName `
    --resource-group $ResourceGroup `
    --query connectionString -o tsv)
Stop-OnError "Get Storage connection string"

# ── 2. Function App (Windows Premium EP1) ────────────────────────────────────
$FuncPlan = "plan-func-traceparser"
$FuncName = "func-traceparser-$timestamp"

Write-Host "`n⚡ Creating Function App Plan: $FuncPlan..." -ForegroundColor Yellow
az functionapp plan create `
    --name $FuncPlan `
    --resource-group $ResourceGroup `
    --location $Location `
    --sku EP1 `
    --is-windows
Stop-OnError "Create Function App Plan"

Write-Host "`n⚡ Creating Function App: $FuncName..." -ForegroundColor Yellow
az functionapp create `
    --name $FuncName `
    --resource-group $ResourceGroup `
    --plan $FuncPlan `
    --storage-account $StorageName `
    --runtime dotnet-isolated `
    --runtime-version 8 `
    --os-type Windows `
    --functions-version 4
Stop-OnError "Create Function App"

Write-Host "`n⚙️  Configuring Function App settings..." -ForegroundColor Yellow
az functionapp config appsettings set `
    --name $FuncName `
    --resource-group $ResourceGroup `
    --settings `
        AzureWebJobsStorage="$StorageConnStr" `
        AZURE_SQL_CONNECTION_STRING="$ConnectionString" `
        FUNCTIONS_WORKER_RUNTIME=dotnet-isolated
Stop-OnError "Configure Function App settings"

# ── 3. Blazor Web App (Windows B2) ───────────────────────────────────────────
$WebPlan = "plan-web-traceparser"
$WebName = "web-traceparser-$timestamp"

Write-Host "`n🌐 Creating Web App Plan: $WebPlan..." -ForegroundColor Yellow
az appservice plan create `
    --name $WebPlan `
    --resource-group $ResourceGroup `
    --location $Location `
    --sku B2
Stop-OnError "Create Web App Plan"

Write-Host "`n🌐 Creating Web App: $WebName..." -ForegroundColor Yellow
az webapp create `
    --name $WebName `
    --resource-group $ResourceGroup `
    --plan $WebPlan `
    --runtime "dotnet:9"
Stop-OnError "Create Web App"

Write-Host "`n⚙️  Configuring Web App settings..." -ForegroundColor Yellow
az webapp config appsettings set `
    --name $WebName `
    --resource-group $ResourceGroup `
    --settings `
        EtlImport__StorageConnectionString="$StorageConnStr" `
        EtlImport__DabBaseUrl="$DabUrl" `
        AzureAd__TenantId="$TenantId" `
        AzureAd__ClientId="$ClientId" `
        CopilotStudio__EnvironmentId="$CopilotEnvironmentId" `
        CopilotStudio__SchemaName="$CopilotSchemaName"
Stop-OnError "Configure Web App settings"

# NOTE: AzureAd__ClientSecret must be set manually:
#   az webapp config appsettings set --name $WebName --resource-group $ResourceGroup --settings AzureAd__ClientSecret="<secret>"

Write-Host "`n✅ Deployment complete!" -ForegroundColor Green
Write-Host ""
Write-Host "Storage:  $StorageName"                             -ForegroundColor Cyan
Write-Host "Function: https://$FuncName.azurewebsites.net"     -ForegroundColor Cyan
Write-Host "Blazor:   https://$WebName.azurewebsites.net"      -ForegroundColor Cyan
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "  1. Set AzureAd__ClientSecret on the web app (from Entra ID app registration)"
Write-Host "  2. Deploy Function:  cd TraceParserFunction && func azure functionapp publish $FuncName --dotnet-isolated"
Write-Host "  3. Deploy Blazor:    cd TraceParserWeb && dotnet publish -c Release -o publish && az webapp deploy --name $WebName --resource-group $ResourceGroup --src-path publish.zip --type zip"
