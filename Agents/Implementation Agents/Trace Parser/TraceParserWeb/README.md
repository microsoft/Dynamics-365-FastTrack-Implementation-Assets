# TraceParserWeb

Blazor Server web app + Azure Function for uploading and importing D365 ETL traces.

## Durable background deletion (local implementation; disabled by default)

The existing net8 isolated Premium Function app now has `DeleteTraceJobs`, a monitored
one-minute timer. SQL is the durable queue; no new Azure resource, storage queue,
Durable Functions or Durable Task Scheduler is used. The sole new production package
is `Microsoft.Azure.Functions.Worker.Extensions.Timer` 4.3.1, the isolated-worker
binding corresponding to the existing Worker/Storage binding pattern.

**Activation is NOT part of local validation.** `DurableDeletion__WebEnabled` defaults
to `false`; absent/false `DurableDeletion__WorkerEnabled` performs no SQL work. The
Function requires `DurableDeletion__WorkerSqlConnectionString`; the web requires
`DurableDeletion__WebSqlConnectionString`. Neither falls back to importer credentials.
Connection strings belong in approved secret configuration, not this repository.
The worker needs a **separate EXECUTE-only identity**, never the importer's dbo access.
See `sql\durable-deletion-permissions.sql` for the narrow provisioning template.
Existing legacy deletion grants need not be widened: old callers are refused while
any non-completed durable job reserves the trace, even when cancelled/blocked/failed.
With the web feature disabled, the existing bounded interactive deletion remains.

**Contract and identity.** `sql\durable-deletion.sql` creates an empty job queue,
request-key aliases, and a generated `Traces.DeletionIdentity` incarnation column
(existing roots receive metadata only, not jobs). Existing traces are never adopted
or queued automatically. Jobs retain immutable root/import IDs and authenticated
requester tenant/object IDs, not uploader ownership. Existing tenant-wide eligibility
is preserved, while lists/status/cancel/resume are requester-only. A duplicate from
another requester returns no job details. Every accepted request key continues to
resolve to the same job after completion, root removal, refresh or restart.
HTTP mutations are authorized, tenant/object checked, antiforgery validated and
`no-store`; request-body identity fields are ignored. Blazor interactive callbacks
also check the current authenticated circuit identity through the same service.
No DAB mutation or HTTP worker endpoint is added.

**Atomicity and pacing.** The compatible optional job/token/expected-sequence
parameters on `sp_DeleteTrace` keep its old call signature and three result columns.
It still owns each transaction and rejects an outer transaction. Under the trace
application lock, it checks import eligibility and immutable identity, holds the
fenced job row through commit, deletes one bounded batch, tombstones the import
receipt *after data*, and commits sequence/counters/terminal status together.
Replaying the immediately preceding sequence returns its stored response without
deleting again. Completion requires a successful root-absence query; neither
`HasMore=0`, a SQL exception nor a hidden catalog object means completion.
New counters represent only rows committed by that job, excluding prior cleanup.
The deployed receipt lock-order and target-thread seek/index guards are retained.
Blob contents and shared lookup tables are never deleted.

A filtered unique SQL index permits only **one leased job database-wide**, independent
of process/Function scale. Claim/control/status never acquire trace/data/receipt locks
after taking job locks. A batch retains its job ownership lock through commit, so
expired takeover cannot pass an uncommitted batch. Leases last 90 SQL-server seconds;
the client renews before each step and never estimates expiry from its own clock.
Each invocation runs at most four 2,000-row batches (SQL accepts 1–10,000), paced one
second apart, with a 45-second slice budget, 30-second SQL command timeout, 10-second
connection timeout and at most five seconds for reconciliation/release. Released
work yields for five seconds. Deadlock, busy, throttling, timeout and selected network
errors use bounded exponential backoff (5–320 seconds plus 0–4 seconds jitter), then
fail after nine consecutive failed attempts; lease-loss recovery is bounded too.
Unknown commit outcomes inspect persisted state before releasing; if SQL is still
unavailable, ownership expires rather than fabricating progress or retrying a batch.
Import eligibility changes become `Blocked` and require explicit resume. Permanent
schema, fingerprint, permission and cross-trace endpoint errors stop as `Failed`.
Eligibility, identity and endpoint holds commit under the owning job lock before
SQL reports their error, so losing the worker cannot auto-resume a rejected trace.
Other catchable server errors persist their classified stop/backoff before returning;
the worker separately reconciles client-side timeouts and transport uncertainty.

**User experience.** Enabled deletion enqueues and returns; a separate job panel
polls every three seconds even if trace/statistics loading fails. It displays
Queued/Running/RetryScheduled/CancelRequested/Cancelled/Blocked/Failed/Completed,
committed rows/batches and last phase, never a guessed percentage. Refresh/reconnect
reads SQL jobs including completed jobs whose roots are gone. Closing/disposal stops
only polling. Cancellation does not undo commits: an already committing batch may
finish, then future batches stop. Explicit resume preserves history and obtains a
fresh fenced lease. Stale/offline reads retain last confirmed values with an error.

**Separately approved rollout sequence:** inventory/quiesce incompatible writers;
back up definitions/permissions and verify existing importer/storage/seek guards;
apply additive `durable-deletion.sql`, then `sp_DeleteTrace.sql` (its exact definition
and importer/durable fingerprints update atomically); verify jobs remain empty and
fingerprints match; provision/audit the two narrow identities; deploy compatible
web/Function binaries with both features disabled. Only after fresh live gates and
explicit approval enable the worker and web. No `tp_*` names or module-count checks
are relaxed. Do not use the broad `deploy.ps1` provisioning script for this rollout.
Rollback means disable new enqueues/worker, drain or expire the current slice and
retain all jobs, aliases, root tokens and counters. **Never downgrade deletion SQL
while non-completed jobs exist.** Cancelling is not deleting the job or reversing data.

**Liveness is separate from `/health`.** The timer uses the Function app's existing
`AzureWebJobsStorage` host storage for schedule monitoring/host coordination, not a
new work queue. Validate host storage access, timer listener startup, Premium host
availability, function-enabled settings, schedule telemetry and advancing SQL job
timestamps independently. Web health alone cannot establish worker availability.
No automatic host-level retry loop is configured; the next scheduled tick and SQL
due time control recovery. Local tests do not certify Azure timer/storage liveness,
Azure SQL capacity, or real-browser acceptance.

Local console validation (no new test framework; synthetic owned databases only):
`dotnet run --project tests\TraceParserWeb.RegressionTests -- --durable-deletion --sql-integration --batch-selection`,
`dotnet run --project tests\TraceParserFunction.ProtocolTests -- --lock-order`,
and the existing web import protocol harness. LocalDB is exclusively
`(localdb)\TPImporterTests_c100bb02`; each run creates/removes uniquely named databases.
Set `NUGET_PACKAGES=C:\.tools\.nuget\packages` and `DOTNET_ROLL_FORWARD=Major` where
SDK10 is installed without runtime9. The SQL suite uses real restricted principals,
RCSI off/on, actual transactions, replay/rollback/cancel races and schema/permission
failures. Manual-clock worker and render/HTTP tests are not real-browser acceptance.

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
    ├── SqlImporter.cs              Dimensions and isolated staging
    └── SafeImport.cs               Durable import protocol and bounded promotion
```

## How It Works

1. User navigates to `/upload`, enters a session name, selects an `.etl` file
2. The authenticated, configured-tenant service registers a fresh upload before issuing a HTTPS **create-only** SAS. Its internal path is `etl-uploads/_imports/{registration-guid}/{fileName}`; the displayed filename/session name are unchanged.
3. The BlobTrigger enforces the existing **1 GiB (1,073,741,824-byte)** limit from actual blob properties before download, pins that registered source's ETag, conditionally downloads exactly those bytes, and records their SHA-256. Re-uploading/overwriting the same logical filename gets a fresh registration/path; the old internal blob cannot be overwritten with its create-only SAS.
4. Rows/binds are staged by import, then promoted in short transactions with **all TraceLines indexes enabled**. No shared-stage truncation, remap, index disable/rebuild or global statistics update is issued.
5. The web reads authenticated SQL receipt status, not a trace-name match or the presence of one aggregate row. Completion commits both physical aggregate tables and the terminal receipt atomically.

## Retry-safe importer protocol and controlled cutover

`sql/safe-importer.sql` adds only `TPImportReceipts`, `TPImportLines`, `TPImportBinds`, `TPImportThreads` and narrowly scoped `tp_*` procedures. It preserves the deployed base tables and physical aggregation procedure/views. Do not replace the whole schema, reinstall public view scripts, use `deploy.ps1`, change tiers/resources/runtime, repair indexes or migrate historical partial traces as part of this change.

**Identity and retries.** A preregistered, full case-sensitive source path plus pinned ETag identifies one import. [Put Blob's service-SAS permission contract](https://learn.microsoft.com/en-us/rest/api/storageservices/put-blob#authorization) permits creation with `c` but requires `w` to overwrite, so the browser needs no additional conditional-request header/CORS change. Missing registrations and unexpected replacements are explicit held errors (51104/51105), not successful imports or evidence that a blob is new. The Function rethrows for normal host retry/poison handling and does not alter the blob or legacy SQL data. Existing historical uploads require separate owner review; no timestamp/truncated-name heuristic adopts them. Completed/deleted receipts are retained permanently. A repeated delivery cannot recreate a deleted trace.

**Existing size policy, server-enforced.** The UI, server-upload stream and Function share `Shared\ImportFilePolicy.cs`; SQL admission mirrors its unchanged 1 GiB maximum. The Function supplies actual `BlobProperties.ContentLength` to `tp_BeginImport`, not a browser-provided claim. An oversized registered version commits `RejectedOversize` and its ETag, then reports error 51127 **before creating a trace, downloading or parsing**. The Function acknowledges that rejected delivery without logging import completion or repeating expensive work; authenticated status/UI explicitly show rejection and stop processing polls. Repeated delivery cannot revive the receipt, even with a smaller claimed length. Upload a smaller file through a fresh registration. The original blob, receipt and any existing partial data are retained; nothing is automatically deleted or adopted, and a held partial trace remains deletion-blocked.

The migration transactionally extends the existing receipt phase check without changing rows; `tp_BeginImport` now requires `@ContentLength`. Deploy the matching SQL/Function pair in the order below; do not substitute a default length in the real BlobTrigger path. A create-only SAS cannot impose a byte quota on Azure Blob Storage itself, so an oversized uploaded blob may remain there for explicit review. The cap does **not** certify available Azure temporary disk, storage/account limits, high-cardinality memory usage or the two-hour execution budget. Those remain separate live deployment/performance gates.

Before `Ready`, retries reparse the same bytes and verify row/bind fingerprints against retained staging. Sequence identity is independent of emission order, so held SELECTs and early bind batches remain associated. Existing staged TraceLineIds never change; unused reserved gaps are allowed. The additive allocator shares the legacy allocator's application lock/control row but propagates errors and rejects absent, nonsingleton or stale controls—**never initialize/reseed them automatically**. Trace-owned sessions, threads and mappings publish with `Ready` in one transaction. SessionIds remain globally allocated despite the deployed composite session key; readiness/completion refuse cross-trace collisions involving the new trace without altering historical duplicates. Inventory every writer before activation: uncoordinated legacy writers cannot run concurrently with protocol imports; the application lock cannot fence a writer that ignores it.

After `Ready`, line promotion resumes from a durable TraceLineId checkpoint. Once all lines exist, a separate `Binding` phase resumes from the `(statement sequence, parameter index)` cursor. Each transaction inserts at most 1,000 lines **or** binds by default and commits its matching checkpoint atomically; bind fan-out cannot turn one line batch into an unbounded transaction. Uncertain acknowledgements are resolved from the receipt on the next attempt. Lines can be visible before all their binds arrive, but the receipt stays explicitly nonterminal and deletion remains blocked. Staging flushes are 10,000 rows; promotion accepts 1–4,000 rows per call. Completion verifies both totals and atomically populates the existing physical aggregates and terminal receipt. Only after durable `Complete` may bounded cleanup remove this import's new staging/mapping rows. Failed staging and all receipts/tombstones remain. Cleanup failure does not revert completion or restart import.

**Ownership and deletion.** Importers acquire database-scoped session lock `TraceParser:Importer:v1`, then `TraceParser:Trace:{TraceId}`, before touching existing trace-owned data. A new trace/receipt pair is first created atomically; any deletion in that short interval sees a nonterminal receipt and is rejected. Every deletion batch acquires the same trace lock with transaction ownership, never the global importer lock. Under that lock, eligibility is a locking read-committed receipt read, not a retained update/range lock; this also works with database RCSI enabled. Trace data is mutated **before** updating the captured completed receipt by ImportId, matching promotion, binding and completion's data-before-checkpoint order. Legacy traces without receipts and already-deleted receipts need no receipt update. Active **and between-attempt retryable** imports cannot be deleted. A successful first deletion batch atomically changes a completed receipt to `Deleted`; that tombstone prevents import while partial deletion remains visible/resumable as `Deleting`. Only absence of the trace root proves deletion finished. All configured-tenant users retain the same authorization; no trace-owner restriction is introduced. Legacy writers do not honor these locks and must be absent at cutover.

The Function uses nonpooled SQL connections with transparent reconnect disabled. Loss of session ownership fails closed; it never silently continues on a replacement session. The parser's bounded channel cancels and joins its SQL consumer on producer failure before the connection/locks can be released. The host timeout remains two hours; a 110-minute invocation budget leaves shutdown margin. Replay before `Ready` must fit this budget: if representative large-file validation fails, **hold release**, not increase the timeout or drop retry guarantees.

### Ordered migrations, permissions and rollback

Ownership contention waits inside the invocation's 110-minute budget instead of rapidly consuming BlobTrigger retries. Waiting consumes that same budget; an arbitrary backlog is not guaranteed to drain before the host's finite delivery/poison limit. Monitor pending receipts and poison deliveries, and explicitly retry a held delivery only after checking its receipt. A retry never authorizes adoption of an unregistered legacy blob.

1. Establish an owner-verified quiet window with no legacy import/rebuild activity; this release does not cancel it. Review fresh metadata and capture deployed definitions/grants. Every TraceLines index must already be enabled. A disabled index blocks importer activation; nothing here enables/rebuilds it.
2. Apply `sql/safe-importer.sql` with a client that **stops on the first batch error**, then reapply `sql/sp_DeleteTrace.sql`. Do not start the new Function between those steps. The second script retains all twelve-table/composite-FK/51013 guards and installs receipt coordination atomically with a definition fingerprint. New imports fail with 51122 if coordination is absent or the deletion procedure is subsequently replaced. The fingerprint checker is a fixed metadata-only `EXECUTE AS OWNER` module; callers need no general metadata permissions.
3. Deliberately grant the existing web principal only the two added operations below, in addition to its existing deletion EXECUTE and root SELECT. No DAB entity, source path, receipt table or table-write permission is exposed:

   ```sql
   GRANT EXECUTE ON OBJECT::dbo.tp_RegisterUpload TO [TraceParserWebDeletion];
   GRANT EXECUTE ON OBJECT::dbo.tp_GetImportStatus TO [TraceParserWebDeletion];
   ```

   The Function identity needs EXECUTE on `tp_BeginImport`, `tp_SetImportContentHash`, `tp_ReserveTraceLineIds`, `tp_StageImportBatch`, `tp_MapImportThread`, `tp_MarkImportReady`, `tp_PromoteImportBatch`, `tp_CompleteImport`, `tp_CleanupCompletedImport`, `tp_RecordImportFailure`, and `tp_AssertImportOwner`; SELECT on `TPImportLines`/`TPImportBinds` creates empty connection-local bulk-copy prototypes. Its existing narrow dimension permissions remain necessary: SELECT/INSERT on `MethodNames`, `QueryStatements`, `QueryTables`, `Messages`, `Users`, `Customers`, `UserSessions`, `UserSessionProcessThreads`; column SELECT on `Traces.TraceId` and column UPDATE on `Traces.TimeStampBegin`/`TimeStampEnd`. The restricted lifecycle test uses exactly these permissions, not broad roles.

   `SET IDENTITY_INSERT` requires table ownership or ALTER permission; ownership chaining alone does not supply that authority. Therefore the migration deliberately creates **`TPImportPromotionExecutor WITHOUT LOGIN`**, grants **only `ALTER ON dbo.TraceLines`** to it, and makes the fixed `tp_PromoteImportBatch` module execute as that principal. The module accepts only the import identifier and bounded batch size, uses no dynamic SQL, and retains the same session/public-principal application-lock and activation checks. Context automatically reverts on success or error. This avoids database-owner execution, certificate/private-key passwords, and new runtime credentials. Runtime identities receive **no ALTER, CONTROL, ownership, IMPERSONATE, db_owner, db_datawriter, schema-wide rights, or new durable-table mutation rights**. Internal bind/metadata helper procedures need no separate caller grants through the existing same-owner module chain.

   Run the migration as the reviewed deployment owner with database VIEW DEFINITION and authority to create the no-login user, grant the single object permission and define the module's execution context. Full definition visibility is checked before principal validation, never inferred from empty metadata. Reapplication preserves runtime grants and rejects a pre-existing executor with a login, role membership, object/schema/principal ownership, another module using its context, or permissions beyond this one object ALTER grant (and optional CONNECT). It also rejects **every explicit inbound permission ON the executor principal**, regardless of grantee or grant/deny state, before granting target ALTER: this includes IMPERSONATE, CONTROL, ALTER and grant-option delegation. Checking only permissions granted TO the executor would miss this authority bypass. Unexpected permissions cause a clear error; the migration never silently revokes them. Do not repurpose this principal or grant application users permission to impersonate it. No application grants, credential rotation, external resources or master-key changes are performed by these scripts. Retain this user and its permission with the compatible procedure during rollback; do not substitute an ordinary-caller promotion module or broaden runtime permissions to mask failure.
4. Validate the complete package and coordinated SQL protocol in isolation. In the verified quiet window, deploy/verify the **new Function first, then the new web application**; never enable new registrations while an old importer binary can consume them. Mixed old/new importer operation is unsupported. Old-web/direct uploads during cutover are unregistered and will be held by the new Function, not silently adopted. The new web reuses protected `TraceAdministration__SqlConnectionString`; SQL TLS validation stays mandatory. The old `/api/upload/sas` GET is removed. Optional HTTP clients use authenticated, tenant-checked `POST /api/imports` with a valid anti-forgery token, and `GET /api/imports/{id}` for status. Blazor calls the same checked service directly and provides a bookmarkable authenticated receipt-status link.
5. Verify ordinary upload, duplicate/retry, authoritative status and eligible deletion with approved synthetic data before releasing normal traffic. Keep legacy backlog review separate; do not infer an empty queue from a quiet sample.

**Rollback is not a schema drop or old-importer redeployment.** Stop admitting new protocol uploads through the approved operational process, establish a quiet window, and retain every receipt, tombstone and staged row. Do not run old importer binaries against queued protocol uploads: they ignore this protocol and can duplicate data. Restoring an old deletion definition changes its fingerprint and intentionally blocks new imports. Restore only a reviewed compatible application/procedure pair; any committed deletion remains deleted. Do not automate cleanup/adoption of historical partial data.

### Isolated importer validation and limits

For an already-installed compatible importer, the deletion lock-order correction is SQL-only: in a verified quiet window, apply only `sql/sp_DeleteTrace.sql`. Its guarded transaction replaces the procedure and fingerprint together, preserving grants, receipts and staging. Do not rerun the full importer migration or redeploy binaries for this correction. Restoring the older receipt-before-data deletion procedure reintroduces its deadlock risk and is not an operational recovery strategy.

Deletion batch selection seeks the requested trace's threads, then seeks their lines using a forced ordered loop join. This prevents a row-goal scan of unrelated traces without increasing the five-minute service budget. Installation requires enabled, unfiltered rowstore indexes with leading keys `UserSessionProcessThreads(TraceId)` and `TraceLines(UserSessionProcessThreadId)`; index names are immaterial. Existing compatible indexes suffice; missing/disabled access paths fail installation with 51007, without creating or repairing indexes. Runtime index removal can cause a seek-plan error and requires owner review, not a silent scan fallback. Selection work includes seeking empty target threads after partial deletion; it is bounded by target-thread count plus the requested batch, not by unrelated trace rows. All write bounds, eligibility, lock order and receipt behavior are unchanged.

The existing regression executable accepts `--batch-selection` for an isolated multi-trace scale test on the dedicated LocalDB instance. It reuses the protocol schema (six TraceLines indexes), deletes a skewed 2,580,000-line/337-thread target through the restricted SQL caller and actual five-minute service, preserves 4,000,000 unrelated lines, and checks sparse, empty-thread, partial-deletion and batch-size variants. It asserts seek plans and bounded logical reads, including after unrelated growth. Missing/filtered/wrong-leading/disabled indexes fail closed; differently named valid indexes work. The old unhinted query and a separately labeled forced production scan/hash shape are measured independently: a good natural LocalDB plan is not a reproduction of the Azure regression. Local timings do not predict Azure SQL S4 end-to-end deletion duration.

The console projects `tests/TraceParserFunction.ProtocolTests` (`net8.0-windows`) and `tests/TraceParserWeb.ImportProtocolTests` (`net9.0`) reuse existing dependencies without a new test framework. The SQL harness accepts no connection override, uses only the already-provisioned `(localdb)\TPImporterTests_c100bb02`, and creates/drops its own `TPImporterProtocol_<guid>` database. Run the compiled DLL where long Windows paths prevent `dotnet run` from launching its apphost:

```powershell
dotnet build .\tests\TraceParserFunction.ProtocolTests --no-restore
dotnet .\tests\TraceParserFunction.ProtocolTests\bin\Debug\net8.0-windows\TraceParserFunction.ProtocolTests.dll --large
dotnet build .\tests\TraceParserWeb.ImportProtocolTests --no-restore
dotnet .\tests\TraceParserWeb.ImportProtocolTests\bin\Debug\net9.0\TraceParserWeb.ImportProtocolTests.dll
```

`--large` adds two 250,000-row imports, a prepopulated indexed target, independent read-progress checks and bounded-batch assertions. Fault tests exercise real SQL transactions, producer/consumer cancellation, replay, uncertain acknowledgements, legacy holds, allocation failures, physical aggregate atomicity, coordinated deletion/tombstones, disabled-index refusal and restricted grants.

Every protocol run also tests unrelated deletion against line promotion, bind promotion and completion, for both absent legacy receipts and completed receipts, with RCSI off and on. `--lock-order` runs only this matrix and installation guards. Test-only table-X pressure and observed SQL lock barriers reproduce the receipt/data inversion without timing-based sleeps or production table-lock hints. Actual procedures run under restricted callers; checkpoints, tombstones, deletion row bounds and the unrelated import are checked.

With separately approved **session-local synthetic fixtures**, append `--etl-fixture '<approved-fixture-directory>\synthetic-small.etl'`, `synthetic-large.etl`, or `synthetic-near-limit.etl`. The adjacent `fixture-catalog.json` supplies expected counts; the near-limit fixture also requires its catalog SHA-256 to match. No fixture binary, generator, or private ETL header metadata is included in this repository or approved for redistribution. Never substitute customer ETL. The harness copies only the existing production manifests to its output and compiles the unchanged real `EtlParser`, `StageBatchWriter`/channel, and `SqlImporter`; it does **not** substitute a capture sink.

The real-ETL mode uses exactly the documented restricted Function grants. It retains the first committed parser batch across an injected pre-Ready failure, reparses with fresh parser/importer instances, checks stable IDs and fingerprints, out-of-order/held SELECTs and bind association, then discards a committed promotion result and resumes from another connection. It verifies physical aggregates, durable completion, cleanup, terminal replay, unrelated trace checksums/counts and enabled indexes. Combining `--large --etl-fixture ...` prepopulates the target with 500,000 additional lines before the real ETL path. JSON output separates interrupted parsing, successful replay parsing, promotion/aggregation/cleanup and total test time (including injected failure and assertions).

These fixtures cover 10 events/8 rows/1 bind and 300,000 events/240,000 rows/30,000 binds, including a real 200,000-row parser batch boundary. They are **not** representative maximum-size imports, broad provider/native-ETW compatibility certification, Azure performance estimates, or BlobTrigger/network/host-timeout tests. TraceEvent 3.1.13 was observed to fault in a finalizer after constructing a reader for a four-byte invalid file; preflight rejects such truncated headers, but broader malformed-file behavior is not certified. Existing tick-valued parser fields remain unchanged; no historical duration-unit conversion is included.

The near-limit fixture additionally covers **1,060,765,696 bytes (98.79% of the existing cap), four million events, 3.2 million rows and 400,000 binds**. SQL aggregate/checksum assertions avoid capturing the full dataset in memory; only the first retained batch's identity/fingerprint projection is copied to a connection-local SQL table. A read-only one-second watchdog checks this disposable database, process memory and system/disk headroom. It cancels only the test operation before 8 GiB allocated SQL data (below Express's 10 GiB limit), 16 GiB combined data/log, 2 GiB managed memory, 3 GiB process private/working memory, 4 GiB available physical memory, or 16 GiB free database-drive space; initial free-memory/disk requirements are 8/32 GiB. Cancellation uses the real consumer-join path and fixture cleanup, never instance/process termination, configuration changes or resource provisioning.

The validated near-limit LocalDB run completed the ETL/failure/replay/promotion/aggregation/cleanup section in **486.10 seconds**, and the whole harness including prepopulation in **572.82 seconds**. One-second sampled peaks were 862,979,768 managed bytes, 951,398,400 working-set bytes, 3,430,940,672 allocated SQL data bytes and 1,015,021,568 log bytes. These are sampled observations, not guaranteed peaks or Azure capacity predictions. Repeated low-cardinality synthetic events do not certify high-cardinality dimensions, other providers, blob transfer, live free disk or the Azure host's two-hour budget. The production 110-minute budget and two-hour timeout are unchanged.

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

Deletion is performed inside the Blazor server, not through the public DAB API. Immediately before accessing SQL, the service requires a signed-in user whose tenant claim matches the configured `AzureAd:TenantId`. **Every signed-in user in that tenant, including admitted guests, can delete any eligible trace.** This is not an administrator-only or per-trace ownership policy. Protocol imports are eligible only after durable completion; partial deletions remain eligible for resumption.

Deletion is disabled until `TraceAdministration:SqlConnectionString` is configured. On App Service the setting name is `TraceAdministration__SqlConnectionString`. Keep its value in protected server configuration (or a Key Vault reference), never in source, browser fields, logs, or saved agent profiles. The connection validates the SQL server certificate and requires encryption.

Provision a dedicated database principal; do not reuse the SQL administrator, DAB, or importer credential. Prefer a managed identity where SQL Entra authentication is already configured. Alternatively, an operator can create a contained SQL user with a generated password and store that password securely. Grant only:

```sql
GRANT EXECUTE ON OBJECT::dbo.sp_DeleteTrace TO [TraceParserWebDeletion];
GRANT SELECT ON OBJECT::dbo.Traces TO [TraceParserWebDeletion];
```

The principal must not belong to `db_owner`, `db_datawriter`, or other broad roles. The procedure relies on the normal same-owner SQL ownership chain; do not grant table-delete permissions to compensate for a broken chain.

The server repeats the procedure until a separate parameterized query confirms the trace is absent. It supports the original no-result procedure, incremental versions returning only `HasMore`, and the bounded procedure below. One successful batch (or `HasMore=0`) is not proof of completion. The page displays confirmed batches, actual rows deleted when supplied by SQL, and the last completed phase; it never invents a percentage or a legacy row count. The initial/in-flight message remains visible while SQL is working.

Deletion retains its **five-minute overall budget and 120-second SQL command timeout**. Cancel stops further batches and cancels the current SQL request; leaving the page also cancels its deletion. Previously committed batches stay deleted. Caller cancellation and overall timeout have distinct partial-deletion messages, including SqlClient cancellation errors when the operation token really was cancelled. Other SQL errors remain errors, not successful cancellation. Refresh before retrying a partial deletion. The coordinated protocol above blocks active/retryable imports in SQL; it does not stop importers. Legacy importers remain outside that protocol and must not run during deletion/cutover.

### Bounded deletion procedure migration (fresh and existing installs)

The canonical install/update script is [`sql/sp_DeleteTrace.sql`](sql/sp_DeleteTrace.sql). It updates `dbo.sp_DeleteTrace` with `CREATE OR ALTER` and its coordination fingerprint in one installation transaction; existing EXECUTE grants survive. Without protocol tables it remains a standalone bounded deletion upgrade. When `TPImportReceipts` exists it installs mandatory receipt guards/tombstoning. Run this same script for a fresh compatible database after installing its base schema/physical aggregates, and for an existing database. It is not bundled into the historical solution ZIP, view scripts, importer, or resource deployment. Do not replace a database, re-run `Create Views.sql`, change indexes, or repack an unrelated solution to install it.

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

**Standalone deletion-only deployment order:** (1) first establish an owner-verified quiet SQL window with no active import/index maintenance, then capture/review fresh metadata, permissions and rollback definition; if metadata access times out or maintenance resumes, hold deployment rather than interrupting the importer; (2) deploy the authenticated looping web client; (3) apply the procedure migration; (4) verify grants/definition and perform an owner-approved synthetic smoke test before any real deletion. **For the retry-safe importer/web release, the ordered protocol migration section above supersedes this standalone order.** Other callers that previously assumed one procedure invocation deletes everything must be updated to loop and confirm root absence; callers that strictly deserialize a one-column result must accept the two added columns. Do not restore anonymous DAB deletion.

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

Production protocol status comes from authenticated receipt procedures, not DAB milestone inference. Missing receipts are explicitly legacy/untracked; unlocked nonterminal receipts report interruption/retry rather than claiming a live parser. A terminal tombstone plus a surviving root reports incomplete deletion. Compatibility milestone helpers retain DAB's `$first` syntax, but new uploads do not use trace-name matching. Status failures are **unavailable**, not evidence that the Function is parsing or queued. Each page permits only one poll at a time.

Trace-list labels describe data availability, not a live worker heartbeat. For example, an empty trace has no parsed session data; that alone does not prove an ETL job is running. SQL index maintenance can delay status queries and deletion. Deletion errors appear above the trace list so a timeout is not hidden below other records. Do not treat a timeout as successful deletion or repeatedly submit deletes while maintenance is blocking SQL.
