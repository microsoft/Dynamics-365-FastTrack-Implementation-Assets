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

The chat page's **Switch Agent** dialog changes only the agent name, environment ID and schema name. It reuses the signed-in user and the server-configured app registration; it does not switch authentication tenants or client credentials. The selected agent must be accessible through that existing sign-in.

Configure credentials on the server, not in the browser. Saved agent profiles contain only agent identifiers. Older saved profiles remain readable, but their tenant/client fields are ignored and omitted when profiles are saved again.

For local dev, add to `appsettings.Development.json` or user secrets:
```json
{
  "AzureAd": {
    "ClientSecret": "<from-entra-id-app-registration>"
  }
}
```

## Authenticated trace deletion

Deletion is performed inside the Blazor server, not through the public DAB API. Immediately before accessing SQL, the service requires a signed-in user whose tenant claim matches the configured `AzureAd:TenantId`. **Every signed-in user in that tenant, including admitted guests, can delete any trace.** This is not an administrator-only or per-trace ownership policy.

Deletion is disabled until `TraceAdministration:SqlConnectionString` is configured. On App Service the setting name is `TraceAdministration__SqlConnectionString`. Keep its value in protected server configuration (or a Key Vault reference), never in source, browser fields, logs, or saved agent profiles. The connection validates the SQL server certificate and requires encryption.

Provision a dedicated database principal; do not reuse the SQL administrator, DAB, or importer credential. Prefer a managed identity where SQL Entra authentication is already configured. Alternatively, an operator can create a contained SQL user with a generated password and store that password securely. Grant only:

```sql
GRANT EXECUTE ON OBJECT::dbo.sp_DeleteTrace TO [TraceParserWebDeletion];
GRANT SELECT ON OBJECT::dbo.Traces TO [TraceParserWebDeletion];
```

The principal must not belong to `db_owner`, `db_datawriter`, or other broad roles. The procedure relies on the normal same-owner SQL ownership chain; do not grant table-delete permissions to compensate for a broken chain. No SQL schema or procedure replacement is required by this change.

The server repeats the existing procedure until a separate parameterized query confirms the trace is absent. This supports both the original procedure and incremental versions returning `HasMore`; one successful batch is not reported as a completed deletion. Errors and cancellation are surfaced, and the operation has a five-minute budget. A failed or timed-out operation can leave a partially deleted trace; refresh and retry. Do not delete traces while they are being imported.

Deploy the updated **read-only** `TraceParserMCP/dab-config.json` as part of this update. Merely hiding the Delete button does not remove direct API access. Existing deployments must remove the `DeleteTrace` entity and table-delete grants, not just update the web application. Anonymous analysis remains unchanged; protect sensitive traces with appropriate network and read-access controls.

`deploy.ps1` does not provision deletion credentials. Configure the dedicated principal and server setting separately, then restart the web app. If deletion is unavailable, retain the read-only DAB configuration rather than restoring public mutations.

### Deletion regression checks

The dependency-free console harness checks deletion authorization/completion, read-only DAB permissions, import-status query/error handling, visible deletion feedback, and non-overlapping status polls. It uses synthetic identities and fake stores/HTTP responses, with no database or network calls:

```powershell
dotnet run --project .\tests\TraceParserWeb.RegressionTests -c Release
```

## Import status and database maintenance

Status polling uses DAB's `$first` parameter, not OData's unsupported `$top`. The upload and trace-list pages share the same database-milestone checks. HTTP failures, timeouts and malformed responses are displayed as **status unavailable**, not as evidence that the Function is parsing or queued. Each page permits only one status poll at a time.

Trace-list labels describe data availability, not a live worker heartbeat. For example, an empty trace has no parsed session data; that alone does not prove an ETL job is running. SQL index maintenance can delay status queries and deletion. Deletion errors appear above the trace list so a timeout is not hidden below other records. Do not treat a timeout as successful deletion or repeatedly submit deletes while maintenance is blocking SQL.
