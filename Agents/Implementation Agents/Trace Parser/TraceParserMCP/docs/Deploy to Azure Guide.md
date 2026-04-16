# Deploy TraceParser MCP Server to Azure App Service

## Complete Step-by-Step Guide

---

## Overview

This guide shows how to deploy the Data API Builder (DAB) MCP Server to Azure App Service using the official DAB Docker container image.

**Architecture:**

```
Azure SQL Database (Trace data)
       ↓
Azure App Service (DAB container with dab-config.json)
       ↓
MCP Clients (Copilot Studio, Claude Desktop, VS Code, etc.)
```

**Key Design Decision:** We use the official DAB Docker image (`mcr.microsoft.com/azure-databases/data-api-builder:1.7.83-rc`) as a container-based App Service, rather than a code-based deployment. This avoids the need to install the .NET SDK or DAB CLI in the container at runtime.

---

## Prerequisites

### Local Requirements

- [ ] Azure subscription with Owner or Contributor role
- [ ] [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli) installed (`az`)
- [ ] PowerShell terminal
- [ ] Existing TraceParser database on local SQL Server (e.g., `localhost\SQLEXPRESS`)
- [ ] [SqlPackage](https://learn.microsoft.com/en-us/sql/tools/sqlpackage/sqlpackage-download) installed (for database migration)

### Verify Prerequisites

```powershell
# Check Azure CLI
az --version

# Login to Azure
az login

# Check SqlPackage
sqlpackage /version
```

> **Note:** You do NOT need .NET SDK or DAB CLI installed locally for Azure deployment. The DAB Docker image includes everything.

---

## Quick Deploy (Automated Script)

The fastest way to deploy is using the included `deploy-to-azure.ps1` script:

```powershell
.\deploy-to-azure.ps1 -SqlPassword "YourSecureP@ssw0rd!" -Location "westus2"
```

This creates all Azure resources, configures the App Service, and deploys the DAB config. See the [Complete Deployment Script](#complete-deployment-script) section for details.

After the script completes, you still need to:
1. [Import your database](#step-2-migrate-database-to-azure-sql) to Azure SQL
2. [Test the endpoints](#step-4-test-the-deployment)

---

## Step 1: Create Azure Resources

### Option A: Using the Automated Script (Recommended)

Run the included deployment script:

```powershell
cd C:\TraceParserMCP
.\deploy-to-azure.ps1 -SqlPassword "YourSecureP@ssw0rd!" -Location "westus2"
```

The script will:
1. Register required Azure resource providers
2. Create a Resource Group (`rg-traceparser-prod`)
3. Create an Azure SQL Server and Database (`TraceParserDB`, S1 tier)
4. Configure SQL Server firewall for Azure services
5. Create a Linux App Service Plan (B1 tier)
6. Create an App Service with the official DAB Docker container
7. Configure app settings (connection string, ports, storage)
8. Deploy `dab-config.json` via zip
9. Restart the app

Skip to [Step 2: Migrate Database](#step-2-migrate-database-to-azure-sql).

### Option B: Using Azure Portal (Manual)

#### 1.1 Create Resource Group

1. Go to [Azure Portal](https://portal.azure.com/)
2. Search for "Resource groups" > Click **Create**
3. Fill in:
    - **Subscription:** Your subscription
    - **Resource group:** `rg-traceparser-prod`
    - **Region:** `West US 2` (or your preferred region)
4. Click **Review + Create** > **Create**

> **Tip:** Some regions (e.g., East US) may reject new SQL server provisioning. `West US 2` and `Central US` work reliably.

#### 1.2 Create Azure SQL Database

1. Search for "SQL databases" > Click **Create**
2. **Basics tab:**
    - **Resource group:** `rg-traceparser-prod`
    - **Database name:** `TraceParserDB`
    - **Server:** Click **Create new**
        - **Server name:** `sql-traceparser-[unique-suffix]` (must be globally unique)
        - **Location:** Same as resource group
        - **Authentication:** SQL authentication
        - **Server admin login:** `sqladmin`
        - **Password:** [Strong password - save this!]
    - **Compute + storage:** Click **Configure database**
        - Select **Standard S1** (100 DTUs, ~$30/month)
        - Click **Apply**
3. **Networking tab:**
    - **Connectivity method:** Public endpoint
    - **Allow Azure services:** Yes
    - **Add current client IP:** Yes
4. Click **Review + Create** > **Create**
5. Wait 5-10 minutes for deployment

> **Important:** Soft-deleted SQL server names cannot be reused. If you get a name conflict, use a different name or add a timestamp suffix.

#### 1.3 Create App Service (Container-Based)

1. Search for "App Services" > Click **Create** > **Web App**
2. **Basics tab:**
    - **Resource group:** `rg-traceparser-prod`
    - **Name:** `app-traceparser-[unique-suffix]` (must be globally unique)
    - **Publish:** **Docker Container** (NOT Code)
    - **Operating System:** Linux
    - **Region:** Same as SQL database
    - **Pricing plan:** Create new > **Basic B1** (~$13/month)
3. **Docker tab:**
    - **Options:** Single Container
    - **Image Source:** Docker Hub or other registries
    - **Image and tag:** `mcr.microsoft.com/azure-databases/data-api-builder:1.7.83-rc`
4. Click **Review + Create** > **Create**

> **Critical:** The image tag must be `1.7.83-rc` (with the `-rc` suffix). MCP features are NOT available in the `:latest` tag or non-RC versions.

#### 1.4 Configure App Service Settings

Go to your App Service > **Configuration** > **Application settings** and add:

| Setting | Value |
|---------|-------|
| `WEBSITES_ENABLE_APP_SERVICE_STORAGE` | `true` |
| `WEBSITES_PORT` | `5000` |
| `AZURE_SQL_CONNECTION_STRING` | `Server=<sql-server>.database.windows.net;Database=TraceParserDB;User Id=sqladmin;Password=<password>;Encrypt=True` |

Then go to **Configuration** > **General settings**:
- **Startup Command:** `--ConfigFileName /home/site/wwwroot/dab-config.json`
- **Always On:** On

> **Why these settings matter:**
> - `WEBSITES_ENABLE_APP_SERVICE_STORAGE=true` mounts `/home` as persistent storage, which is where the deployed config file lives
> - `WEBSITES_PORT=5000` tells App Service that DAB listens on port 5000 (not the default 8080)
> - The startup command is passed as arguments to the container's ENTRYPOINT (`dotnet Azure.DataApiBuilder.Service.dll`), NOT as a standalone command

#### 1.5 Deploy the Configuration File

Create a zip containing only `dab-config.json` and deploy it:

```powershell
Compress-Archive -Path @("dab-config.json") -DestinationPath deploy.zip -Force
az webapp deploy --name <app-name> --resource-group rg-traceparser-prod --src-path deploy.zip --type zip
az webapp restart --name <app-name> --resource-group rg-traceparser-prod
```

### Option C: Using Azure CLI (Manual)

```powershell
# Variables - customize these
$ResourceGroup = "rg-traceparser-prod"
$Location = "westus2"
$SqlServer = "sql-traceparser-$(Get-Date -Format 'yyyyMMddHHmm')"
$SqlAdmin = "sqladmin"
$SqlPassword = "YourSecureP@ssw0rd!"
$AppName = "app-traceparser-$(Get-Date -Format 'yyyyMMddHHmm')"
$DabImage = "mcr.microsoft.com/azure-databases/data-api-builder:1.7.83-rc"

# Register resource providers (required on first deployment)
az provider register --namespace Microsoft.Sql --wait
az provider register --namespace Microsoft.Web --wait

# Create Resource Group
az group create --name $ResourceGroup --location $Location

# Create SQL Server
az sql server create --name $SqlServer --resource-group $ResourceGroup --location $Location --admin-user $SqlAdmin --admin-password $SqlPassword

# Configure firewall to allow Azure services
az sql server firewall-rule create --resource-group $ResourceGroup --server $SqlServer --name AllowAzureServices --start-ip-address 0.0.0.0 --end-ip-address 0.0.0.0

# Create database
az sql db create --resource-group $ResourceGroup --server $SqlServer --name TraceParserDB --service-objective S1

# Create App Service Plan (Linux)
az appservice plan create --name "plan-traceparser" --resource-group $ResourceGroup --location $Location --sku B1 --is-linux

# Create App Service with DAB container image
az webapp create --name $AppName --resource-group $ResourceGroup --plan "plan-traceparser" --container-image-name $DabImage

# Configure app settings
$ConnectionString = "Server=$SqlServer.database.windows.net;Database=TraceParserDB;User Id=$SqlAdmin;Password=$SqlPassword;Encrypt=True"
az webapp config appsettings set --name $AppName --resource-group $ResourceGroup --settings WEBSITES_ENABLE_APP_SERVICE_STORAGE=true AZURE_SQL_CONNECTION_STRING="$ConnectionString" WEBSITES_PORT=5000

# Configure startup command and Always On
az webapp config set --name $AppName --resource-group $ResourceGroup --always-on true --startup-file "--ConfigFileName /home/site/wwwroot/dab-config.json"

# Deploy config file
Compress-Archive -Path @("dab-config.json") -DestinationPath deploy.zip -Force
az webapp deploy --name $AppName --resource-group $ResourceGroup --src-path deploy.zip --type zip

# Restart to pick up changes
az webapp restart --name $AppName --resource-group $ResourceGroup

Write-Host "Deployment complete!"
Write-Host "MCP URL: https://$AppName.azurewebsites.net/mcp"
Write-Host "SQL Server: $SqlServer.database.windows.net"
```

---

## Step 2: Migrate Database to Azure SQL

### 2.1 Prepare the Local Database

**Drop Windows-authenticated users** before export (Azure SQL doesn't support Windows auth):

```sql
-- Connect to your local AxTrace database and check for Windows users
SELECT name, type_desc FROM sys.database_principals WHERE type = 'U'

-- Drop any Windows auth users (example)
DROP USER [DOMAIN\username]
```

> **Important:** Note the dropped users so you can recreate them locally after export.

### 2.2 Export from Local SQL Server

```powershell
sqlpackage /Action:Export /SourceServerName:"localhost\SQLEXPRESS" /SourceDatabaseName:"AxTrace" /TargetFile:"C:\Temp\AxTrace.bacpac" /SourceTrustServerCertificate:True /SourceEncryptConnection:Optional
```

> **Notes:**
> - Use `localhost\SQLEXPRESS` for SQL Express, not `(LocalDB)\MSSQLLocalDB`
> - The `/SourceTrustServerCertificate:True` and `/SourceEncryptConnection:Optional` flags are required for local SQL Server connections
> - Export will fail if Windows-authenticated users exist in the database

### 2.3 Import to Azure SQL

**Option A: Using SqlPackage (Command Line)**

```powershell
sqlpackage /Action:Import /SourceFile:"C:\Temp\AxTrace.bacpac" /TargetServerName:"<sql-server>.database.windows.net" /TargetDatabaseName:"TraceParserDB" /TargetUser:"sqladmin" /TargetPassword:"YourSecureP@ssw0rd!"
```

**Option B: Using SSMS (GUI)**

1. Open SQL Server Management Studio (SSMS)
2. Connect to Azure SQL:
    - **Server:** `<sql-server>.database.windows.net`
    - **Authentication:** SQL Server Authentication
    - **Login:** `sqladmin`
    - **Password:** [Your password]
3. Right-click **Databases** > **Import Data-tier Application**
4. Browse to your `.bacpac` file
5. Follow the wizard to import

### 2.4 Recreate Local Users (Optional)

After export, recreate the dropped Windows users on your local database:

```sql
CREATE USER [DOMAIN\username] FOR LOGIN [DOMAIN\username]
```

---

## Step 3: Configuration Details

### dab-config.json

The DAB configuration file is the same for local and Azure deployment. Key differences in behavior:

| Setting | Value | Notes |
|---------|-------|-------|
| `connection-string` | `@env('AZURE_SQL_CONNECTION_STRING')` | Reads from `.env` locally, App Settings on Azure |
| `host.mode` | `Production` | Disables Swagger UI and detailed errors |
| `mcp.enabled` | `true` | Exposes MCP endpoint at `/mcp` |
| `cors.origins` | `["*"]` | Allow all origins (tighten for production) |

### What NOT to Deploy

Only `dab-config.json` needs to be deployed to Azure. Do NOT include:
- `.env` (connection string is set via App Settings)
- `.config/dotnet-tools.json` (DAB is built into the container image)
- `deploy-to-azure.ps1` (deployment script, not runtime artifact)
- `startup.sh` (not used with container deployment)
- `web.config` (not applicable to Linux containers)

---

## Step 4: Test the Deployment

### 4.1 Check App Service Status

```powershell
# View container logs
az webapp log tail --name <app-name> --resource-group rg-traceparser-prod

# Check app status
az webapp show --name <app-name> --resource-group rg-traceparser-prod --query state
```

### 4.2 Test Endpoints

```powershell
$AppUrl = "https://<app-name>.azurewebsites.net"

# Test REST API
Invoke-RestMethod -Uri "$AppUrl/api/Traces"

# Test session metrics
Invoke-RestMethod -Uri "$AppUrl/api/SessionMetrics"
```

### 4.3 Test MCP Endpoint

The MCP endpoint at `https://<app-name>.azurewebsites.net/mcp` uses Server-Sent Events (SSE) transport. You cannot test it with a simple GET request - it requires an MCP client. When accessed directly, it returns an error about a missing `Mcp-Session-Id` header, which is normal.

Connect via an MCP client to verify (see [Step 5](#step-5-connect-mcp-clients)).

---

## Step 5: Connect MCP Clients

### Claude Desktop / VS Code

Add to your MCP client configuration:

```json
{
  "mcpServers": {
    "TraceParserMCP": {
      "url": "https://<app-name>.azurewebsites.net/mcp"
    }
  }
}
```

### Microsoft Copilot Studio

1. Open [Copilot Studio](https://copilotstudio.microsoft.com/)
2. Navigate to your agent
3. Go to **Tools** > **Add a tool** > **MCP Connector**
4. Configure:
    - **Name:** TraceParser MCP
    - **Description:** Performance analysis for D365 F&O traces
    - **URL:** `https://<app-name>.azurewebsites.net/mcp`
5. Save and test the connection

**Test queries:**
- "Show me all traces"
- "List sessions in trace 2"
- "Find slow SQL statements"
- "Search for methods containing 'inventory'"

---

## Troubleshooting

### App won't start / Container keeps restarting

**Check logs:**

```powershell
az webapp log tail --name <app-name> --resource-group rg-traceparser-prod
```

**Common causes and fixes:**

| Symptom | Cause | Fix |
|---------|-------|-----|
| Exit code 127 | Wrong startup command format | Startup command should be `--ConfigFileName /home/site/wwwroot/dab-config.json` only |
| Config file not found | Missing zip deployment | Re-deploy: `az webapp deploy --src-path deploy.zip --type zip` |
| App starts then stops after ~22s | Port mismatch | Set `WEBSITES_PORT=5000` in app settings |
| Image pull failure | Wrong image tag | Use `1.7.83-rc` (with `-rc` suffix) |

### 503 Service Unavailable on all endpoints

This usually means the container is not running or the port is misconfigured.

1. Check that `WEBSITES_PORT=5000` is set
2. Check that `WEBSITES_ENABLE_APP_SERVICE_STORAGE=true` is set
3. Verify the container image: `mcr.microsoft.com/azure-databases/data-api-builder:1.7.83-rc`
4. Restart: `az webapp restart --name <app-name> --resource-group rg-traceparser-prod`

### Cannot connect to SQL Database

```powershell
# Check firewall rules
az sql server firewall-rule list --server <sql-server> --resource-group rg-traceparser-prod

# Ensure AllowAzureServices rule exists (0.0.0.0 - 0.0.0.0)
```

### MCP endpoint returns "Mcp-Session-Id header required"

This is **normal** when accessing the MCP endpoint directly in a browser. MCP requires a proper MCP client that supports the SSE transport protocol. Use Claude Desktop, VS Code, or Copilot Studio to connect.

### SqlPackage export fails

| Error | Fix |
|-------|-----|
| Windows auth user incompatible | `DROP USER [DOMAIN\user]` before export |
| SSL/TLS error | Add `/SourceTrustServerCertificate:True /SourceEncryptConnection:Optional` |
| Server not found | Use `localhost\SQLEXPRESS` (not LocalDB path) |

---

## Cost Estimate

| Resource | SKU | Monthly Cost |
|----------|-----|-------------|
| Azure SQL (S1) | 100 DTUs | ~$30 |
| App Service (B1) | 1 core, 1.75 GB RAM | ~$13 |
| Bandwidth | 100 GB | ~$8 |
| **Total** | | **~$51/month** |

### Cost Optimization Tips

1. **Scale down SQL during off-hours:**
   ```powershell
   az sql db update --name TraceParserDB --server <sql-server> --resource-group rg-traceparser-prod --service-objective Basic
   ```

2. **Use Azure Reserved Capacity** (1-3 year commit for 40-60% discount)

3. **Enable auto-pause for SQL** (serverless tier) if usage is intermittent

---

## Security Hardening (Optional)

### Enable HTTPS Only

```powershell
az webapp update --name <app-name> --resource-group rg-traceparser-prod --https-only true
```

### Enable Managed Identity

Replace SQL authentication with Azure AD managed identity:

```powershell
# Enable system-assigned managed identity
az webapp identity assign --name <app-name> --resource-group rg-traceparser-prod

# Update connection string to use managed identity
az webapp config appsettings set --name <app-name> --resource-group rg-traceparser-prod --settings AZURE_SQL_CONNECTION_STRING="Server=<sql-server>.database.windows.net;Database=TraceParserDB;Authentication=Active Directory Default;Encrypt=True"
```

> **Note:** You also need to grant the managed identity access to the Azure SQL database. See [Microsoft documentation](https://learn.microsoft.com/en-us/azure/app-service/tutorial-connect-msi-sql-database) for details.

### Enable Application Logging

```powershell
az webapp log config --name <app-name> --resource-group rg-traceparser-prod --application-logging filesystem --level information
```

---

## Complete Deployment Script

The `deploy-to-azure.ps1` script included in this project automates the entire deployment:

```powershell
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

Write-Host "Starting Azure deployment..." -ForegroundColor Cyan

# 0. Register required providers
az provider register --namespace Microsoft.Sql --wait
Stop-OnError "Register Microsoft.Sql"
az provider register --namespace Microsoft.Web --wait
Stop-OnError "Register Microsoft.Web"

# 1. Create Resource Group
az group create --name $ResourceGroup --location $Location
Stop-OnError "Create resource group"

# 2. Create SQL Server
az sql server create --name $SqlServer --resource-group $ResourceGroup --location $Location --admin-user $SqlAdmin --admin-password $SqlPassword
Stop-OnError "Create SQL Server"

# 3. Configure Firewall
az sql server firewall-rule create --resource-group $ResourceGroup --server $SqlServer --name AllowAzureServices --start-ip-address 0.0.0.0 --end-ip-address 0.0.0.0
Stop-OnError "Configure firewall"

# 4. Create Database
az sql db create --resource-group $ResourceGroup --server $SqlServer --name TraceParserDB --service-objective S1
Stop-OnError "Create database"

# 5. Create App Service Plan
az appservice plan create --name "plan-traceparser" --resource-group $ResourceGroup --location $Location --sku B1 --is-linux
Stop-OnError "Create App Service Plan"

# 6. Create App Service with DAB container image
az webapp create --name $AppName --resource-group $ResourceGroup --plan "plan-traceparser" --container-image-name $DabImage
Stop-OnError "Create App Service"

# 7. Configure App Service
$ConnectionString = "Server=$SqlServer.database.windows.net;Database=TraceParserDB;User Id=$SqlAdmin;Password=$SqlPassword;Encrypt=True"
az webapp config appsettings set --name $AppName --resource-group $ResourceGroup --settings WEBSITES_ENABLE_APP_SERVICE_STORAGE=true AZURE_SQL_CONNECTION_STRING="$ConnectionString" WEBSITES_PORT=5000
Stop-OnError "Configure app settings"

az webapp config set --name $AppName --resource-group $ResourceGroup --always-on true --startup-file "--ConfigFileName /home/site/wwwroot/dab-config.json"
Stop-OnError "Configure app startup"

# 8. Deploy config file
Compress-Archive -Path @("dab-config.json") -DestinationPath deploy.zip -Force
az webapp deploy --name $AppName --resource-group $ResourceGroup --src-path deploy.zip --type zip
Stop-OnError "Deploy configuration"

# 9. Restart to pick up changes
az webapp restart --name $AppName --resource-group $ResourceGroup
Stop-OnError "Restart app"

Write-Host "`nDeployment complete!" -ForegroundColor Green
Write-Host "MCP URL: https://$AppName.azurewebsites.net/mcp" -ForegroundColor Cyan
Write-Host "SQL Server: $SqlServer.database.windows.net" -ForegroundColor Cyan
```

**Run it:**

```powershell
cd C:\TraceParserMCP
.\deploy-to-azure.ps1 -SqlPassword "YourSecureP@ssw0rd!"
```

---

## Summary

After completing this guide, you will have:

- Azure SQL Database hosting all trace data
- Azure App Service running the DAB MCP server 24/7 in a container
- Public HTTPS endpoints for REST, GraphQL, and MCP
- MCP endpoint ready for Copilot Studio, Claude Desktop, or any MCP client

**Endpoints:**

| Protocol | URL |
|----------|-----|
| REST | `https://<app-name>.azurewebsites.net/api` |
| GraphQL | `https://<app-name>.azurewebsites.net/graphql` |
| MCP | `https://<app-name>.azurewebsites.net/mcp` |

**Resources:**

- [Azure Data API Builder Documentation](https://learn.microsoft.com/en-us/azure/data-api-builder/)
- [Azure App Service Documentation](https://learn.microsoft.com/en-us/azure/app-service/)
- [Microsoft Copilot Studio](https://copilotstudio.microsoft.com/)
