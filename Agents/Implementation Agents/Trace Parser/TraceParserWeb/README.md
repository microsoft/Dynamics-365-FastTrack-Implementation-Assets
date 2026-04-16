# TraceParserWeb

Blazor Server web app + Azure Function for uploading and importing D365 ETL traces.

## Solution Structure

```
TraceParserWeb.sln
├── deploy.ps1                      Azure provisioning (Storage + Function + Blazor Web App)
├── TraceParserWeb/                 Blazor Server, net9.0
│   ├── Components/Pages/Upload/    ETL upload page (/upload)
│   └── Services/EtlUploadService.cs  Blob upload + import status polling
└── TraceParserFunction/            Azure Function, net8.0-windows (ETW requires Windows)
    ├── ParseEtlFunction.cs         Blob trigger entry point
    ├── EtlParser.cs                ETWTraceEventSource → DataTable (D365 event dispatch)
    └── SqlImporter.cs              Dimension caches + SqlBulkCopy → CopyTraceLinesFromStage SP
```

## How It Works

1. User navigates to `/upload`, enters a session name, selects an `.etl` file
2. Blazor uploads the blob to Azure Storage (`etl-uploads/{sessionName}/{fileName}`)
3. Azure Function blob trigger fires, reads the ETL via `ETWTraceEventSource`
4. Function bulk-inserts rows into `StageTraceLines`, then calls `CopyTraceLinesFromStage` SP
5. Blazor polls `GET /api/Traces?$filter=TraceName eq '{sessionName}'` via DAB until import completes

## Existing Azure Resources (reused)

| Resource | Name |
|---|---|
| Resource Group | `rg-traceparser-prod` (westus2) |
| SQL Server | `<your-sql-server>.database.windows.net` |
| Database | `TraceParserDB` |
| DAB App Service | `<your-dab-app>.azurewebsites.net` |

## Deploying New Resources

```powershell
# Creates: Storage Account + Function App (EP1 Windows) + Blazor Web App (B2)
.\deploy.ps1
```

After deploy, set the client secret manually:
```bash
az webapp config appsettings set --name <web-app-name> --resource-group rg-traceparser-prod \
  --settings AzureAd__ClientSecret="<secret-from-entra-id>"
```

Then publish:
```bash
# Function
cd TraceParserFunction
func azure functionapp publish <func-app-name> --dotnet-isolated

# Blazor
cd TraceParserWeb
dotnet publish -c Release -o publish
Compress-Archive -Path publish\* -DestinationPath publish.zip
az webapp deploy --name <web-app-name> --resource-group rg-traceparser-prod --src-path publish.zip --type zip
```

## Local Development

Prerequisites: [Azurite](https://github.com/Azure/Azurite), [Azure Functions Core Tools v4](https://learn.microsoft.com/azure/azure-functions/functions-run-local)

```bash
# Terminal 1 — Storage emulator
azurite --location .azurite

# Terminal 2 — Azure Function
cd TraceParserFunction
func start

# Terminal 3 — Blazor
cd TraceParserWeb
dotnet run
```

`appsettings.json` already has `StorageConnectionString = "UseDevelopmentStorage=true"` for local use.

Navigate to `https://localhost:5001/upload`, session name `v1-T17-local`, upload a `.etl` file.

## Authentication

Microsoft Identity (Entra ID) with MSAL. App registration:
- Tenant: `<YOUR_ENTRA_TENANT_ID>`
- Client ID: `<YOUR_ENTRA_CLIENT_ID>`

For local dev, add to `appsettings.Development.json` or user secrets:
```json
{
  "AzureAd": {
    "ClientSecret": "<from-entra-id-app-registration>"
  }
}
```
