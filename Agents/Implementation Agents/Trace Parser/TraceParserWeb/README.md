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

### Agent destination protection

Environment IDs are validated on the server before profiles are saved or clients are used. Accepted identifiers are a hyphenated GUID or `Default-<GUID>` (case-insensitive, with surrounding whitespace trimmed); saved identifiers are canonicalized. URLs, encoded escapes and arbitrary environment names are rejected with form feedback. Valid legacy profiles still work; invalid legacy entries remain visible for correction or deletion but cannot connect.

Startup configuration and runtime agent switching use the same validation. Switching retains the server's cloud and app registration, never browser-supplied authentication settings. The default cloud is `Prod`. The named hosted clouds from **Microsoft.Agents.CopilotStudio.Client 1.3.176** are supported; `Local`, `Other`, `Unknown`, undefined cloud values and any `CustomPowerPlatformCloud` are rejected. `UseExperimentalEndpoint=true` is explicitly unsupported. These restrictions fail closed at startup rather than acquiring a token for an unverified endpoint.

The authenticated HTTP handler independently checks **every request before token acquisition or attachment**, including requests that already have Authorization and SDK response-derived activity/stream URLs. Only HTTPS on port 443, without userinfo or fragments, is allowed. Hosts must have the exact SDK environment-ID DNS-label shape under the **configured cloud's** Power Platform API domain; a matching substring or arbitrary subdomain is not enough. A server `DirectConnectUrl` must satisfy this same policy (specify `Cloud` for a non-commercial URL). A trusted direct-only configuration can omit EnvironmentId/SchemaName; identifiers supplied alongside it are still validated. Switching clears the default direct URL so it does not override the selected agent.

Automatic HTTP redirects are disabled and all 3xx responses are rejected, even redirects to another trusted host. Transport-level redirects would otherwise bypass the authenticated handler. No arbitrary redirect or experimental island endpoint is followed. If the service begins requiring redirects or another hostname family, update and test this explicit policy before enabling that behavior; do not broaden it to suffix/substring matching or an allow-all override.

**Deployment:** publish/restart only the Blazor web application for this fix; no database, importer, DAB, token-scope, consent or tenant changes are required. Review the server's CopilotStudio cloud/direct/experimental settings before rollout, because unsupported configurations now fail startup. Normal commercial GUID/Default-GUID agent switching is preserved. Offline regression coverage checks the actual pinned SDK's generated URLs and synthetic returned endpoints; it is not a live service compatibility test or a claim of complete application security coverage.

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

The principal must not belong to `db_owner`, `db_datawriter`, or other broad roles. The procedure relies on the normal same-owner SQL ownership chain; do not grant table-delete permissions to compensate for a broken chain.

The server repeats the procedure until a separate parameterized query confirms the trace is absent. It supports the original no-result procedure, incremental versions returning only `HasMore`, and the bounded procedure below. One successful batch (or `HasMore=0`) is not proof of completion. The page displays confirmed batches, actual rows deleted when supplied by SQL, and the last completed phase; it never invents a percentage or a legacy row count. The initial/in-flight message remains visible while SQL is working.

Deletion retains its **five-minute overall budget and 120-second SQL command timeout**. Cancel stops further batches and cancels the current SQL request; leaving the page also cancels its deletion. Previously committed batches stay deleted. Caller cancellation and overall timeout have distinct partial-deletion messages, including SqlClient cancellation errors when the operation token really was cancelled. Other SQL errors remain errors, not successful cancellation. Refresh before retrying a partial deletion. **Do not delete a trace being imported, submit concurrent imports for it, or infer importer inactivity from missing statistics.** This change does not coordinate with or stop importers.

### Bounded deletion procedure migration (fresh and existing installs)

The canonical install/update script is [`sql/sp_DeleteTrace.sql`](sql/sp_DeleteTrace.sql). It updates **only `dbo.sp_DeleteTrace`** with `CREATE OR ALTER`; existing EXECUTE grants survive. Run this same script for a fresh compatible database after installing its base schema/physical aggregates, and for an existing database. It is not bundled into the historical solution ZIP, view scripts, importer, or resource deployment. Do not replace a database, re-run `Create Views.sql`, change indexes, or repack an unrelated solution to install it.

**Prerequisites / fail closed:** inspect the current definition, columns, keys, ownership, triggers, FK graph and caller inventory; save the deployed procedure definition and grants as rollback evidence. Required objects are dbo **physical tables** `Traces`, `UserSessions`, `UserSessionProcessThreads`, `TraceLines`, `QueryBindParameters`, `XppParameters`, `TopMethods`, `StageTraceLines`, `SessionMetrics`, `TopMethodsBySession`, `MethodAotLayers`, and `TraceInformations`. The migration checks the exact deletion column types, unique identifiers, dbo ownership, absence of enabled table triggers, and supported non-cascading inbound FKs (including disabled FKs). `Traces.TraceId`, `TraceLines.TraceLineId`, `UserSessionProcessThreads.UserSessionProcessThreadId` and `TopMethods.Id` need enabled, unfiltered single-column unique keys. `UserSessions` instead needs the exact unique key **`(SessionId, TraceId)`**, not standalone `SessionId` uniqueness. The supported thread-to-session FK is exactly **`(SessionId, TraceId) -> UserSessions(SessionId, TraceId)`** in that order; reordered, shortened, extended and other composite FK shapes are rejected as complete constraints, not accepted by matching their columns independently. Both TopMethods endpoint FKs and both additional root-child FKs are allowlisted. Additional inbound FK edges/column mappings, or missing/renamed/mistyped deletion columns, still fail closed.

`XppParameters.TraceLineId` must be `bigint`; this child is drained even when its FK is disabled. Unexpected/missing objects, views in place of physical aggregates, temporal/memory-optimized/graph/ledger/FileTable/remote-archive tables, enabled triggers or unsupported FK edges abort **before** the procedure is changed. Feature metadata checks require modern Azure SQL or SQL Server 2022+; unavailable metadata on older engines is a migration failure, not a reason to bypass the guards. Disabled **nonessential nonclustered indexes** do not prevent installation/deletion and are never rebuilt or enabled by this script. Review incompatible schemas separately; do not bypass checks or manufacture replacement aggregates/views. Schemas without declared FKs still require the owner's review of logical relationships. Existing orphan rows whose trace/thread association was already removed cannot be safely attributed to this deletion.

Use a deployment-owner SQL session with permission to inspect metadata and alter the procedure; the runtime principal does not perform migration. With an already-approved authentication mechanism, for example:

```powershell
# Run from TraceParserWeb. Entra authentication shown; no password in source/arguments.
sqlcmd -S "<approved-server>" -d "<approved-database>" -G -b -i ".\sql\sp_DeleteTrace.sql"
```

The script is a **single SQL batch**, without `GO`, so failed prerequisites prevent installation even in clients that otherwise continue after batch errors. It changes no tables, indexes, views, permissions, SQL settings or tiers.

Contract: `@TraceId int` is retained; optional `@BatchSize int = 2000` accepts 1–10000. Each call deletes **at most that many persisted rows in total**, returns one row `(HasMore int, Phase nvarchar(40), RowsDeleted int)`, and commits just that batch. TopMethods is checked/drained first in bounded candidates touching the requested trace at **either** endpoint. Both endpoints must resolve to threads in that same trace. A cross-trace or missing endpoint raises **51013**, rolls back that candidate batch and leaves the ambiguous row untouched; previous safe batches may already be committed. This requires owner review/data correction, not automatic retries or choosing an endpoint as the owner. Normal methods can begin and end in different threads of the same trace.

Then parameter fan-out is independently bounded before its TraceLines are removed. Staging, each aggregate table, threads, sessions, MethodAotLayers and TraceInformations are drained in bounded phases before the single root row. Session/aggregate/root-child deletes always use `TraceId`, preserving repeated SessionIds in other traces; shared method-name dimensions are not deleted. A root update lock serializes callers for the same trace during each batch. `XACT_ABORT` and transaction rollback protect interrupted batches; production connections are disposed on failure, rolling back any transaction left by an attention. Calls inside a caller-owned transaction are rejected so a caller cannot accidentally turn all batches into one giant transaction. No index hints or rebuilds are used. Bounded rows do not guarantee fixed runtime, cheap scans, or absence of blocking/lock escalation: nonclustered-index and bookmark locks also count, and even `ROWLOCK` would not guarantee prevention. The existing command and operation timeouts still apply. See [Microsoft's lock-escalation guidance](https://learn.microsoft.com/en-us/troubleshoot/sql/database-engine/performance/resolve-blocking-problems-caused-lock-escalation).

**Deployment order:** (1) first establish an owner-verified quiet SQL window with no active import/index maintenance, then capture/review fresh metadata, permissions and rollback definition; if metadata access times out or maintenance resumes, hold deployment rather than interrupting the importer; (2) deploy the web application first, which remains compatible with existing procedures (legacy progress has no row counts); (3) apply this procedure-only migration; (4) verify grants/definition and perform an owner-approved synthetic smoke test before any real deletion. The already-deployed looping web client also supports the new procedure if SQL must be updated first. Other callers that previously assumed one procedure invocation deletes everything must be updated to loop and confirm root absence; callers that strictly deserialize a one-column result must accept the two added columns. Do not restore anonymous DAB deletion.

**Rollback:** stop new deletion requests, let/cancel the current bounded call finish, and restore the captured *deployed* definition using `ALTER`/`CREATE OR ALTER` (not DROP), preserving grants. Do not substitute the old Git procedure for the captured deployed version. The new web supports the restored no-result/HasMore-only contract. A captured older procedure may omit MethodAotLayers/TraceInformations or consider only BeginUspId; restoring it also restores those deletion limitations, so rollback is not permission to retry affected traces. Prefer retaining the prior authenticated looping web and the bounded procedure over restoring a large-batch performance problem. Neither procedure nor web rollback resurrects committed rows; recovery of deleted data requires a separately approved data-restoration plan.

Installations upgrading from unauthenticated deletion must also deploy the **read-only** `TraceParserMCP/dab-config.json`. Merely hiding the Delete button does not remove direct API access: remove the `DeleteTrace` entity and table-delete grants, not just update the web application. Already read-only deployments need no DAB change for the bounded-procedure migration. Anonymous analysis remains unchanged; protect sensitive traces with appropriate network and read-access controls.

`deploy.ps1` does not provision deletion credentials. Configure the dedicated principal and server setting separately, then restart the web app. If deletion is unavailable, retain the read-only DAB configuration rather than restoring public mutations.

### Deletion regression checks

The dependency-free console harness checks deletion authorization/completion, read-only DAB permissions, import-status query/error handling, visible deletion feedback, non-overlapping status polls, agent identifier/profile validation, startup/runtime configuration, authenticated destination checks, redirect policy, and SDK-generated/response-derived URLs. It uses synthetic identities/tokens and fake stores/HTTP responses, with no database or network calls:

```powershell
dotnet run --project .\tests\TraceParserWeb.RegressionTests -c Release
```

The same harness optionally runs **real, synthetic SQL integration**, without any live SQL connection strings:

```powershell
# On a host with runtime 8/10 but no 9, allow this net9.0 harness to use runtime 10:
$env:DOTNET_ROLL_FORWARD = "Major"
dotnet run --project .\tests\TraceParserWeb.RegressionTests -c Release -- --sql-integration
```

This integration mode is hard-guarded to the already-provisioned `(localdb)\TPImporterTests_c100bb02` instance and a newly generated `TPBoundedDelete_c100bb02_<guid>` database. It never uses/changes `MSSQLLocalDB`; it creates and removes only its own database in `finally`. The fixture uses the captured twelve deletion tables' relevant column/key shapes, the actual composite session key/FK and both TopMethods endpoint FKs, with stricter enabled parameter/staging/aggregate FKs. It includes 250,001 synthetic TraceLines, parameter fan-out, multi-batch stages/aggregates/parents/root children, repeated SessionIds across traces, shared method-name data, two representative disabled nonclustered indexes, and a preserved unrelated trace. Tests cover both cross-trace endpoint directions, missing endpoints under disabled FKs, explicit correction/retry, rejection of unknown inbound edges/columns and malformed composite constraints, actual versus reported batch row limits, restricted EXECUTE + root SELECT ownership chaining, partial cancellation/retry, interrupted mutation rollback, legacy procedure contracts, actual SQL errors, fail-closed migration, and grant preservation. SQL timings, phase totals, TLS result and cleanup state are emitted as JSON; **LocalDB timings do not predict Azure SQL S4 performance**. Only the test fixture may trust a local self-signed certificate; production TLS remains enforced and is tested separately. Offline tests use actual SqlClient exception types plus service/dispatcher-rendered UI checks.

## Import status and database maintenance

Status polling uses DAB's `$first` parameter, not OData's unsupported `$top`. The upload and trace-list pages share the same database-milestone checks. HTTP failures, timeouts and malformed responses are displayed as **status unavailable**, not as evidence that the Function is parsing or queued. Each page permits only one status poll at a time.

Trace-list labels describe data availability, not a live worker heartbeat. For example, an empty trace has no parsed session data; that alone does not prove an ETL job is running. SQL index maintenance can delay status queries and deletion. Deletion errors appear above the trace list so a timeout is not hidden below other records. Do not treat a timeout as successful deletion or repeatedly submit deletes while maintenance is blocking SQL.
