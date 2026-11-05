# DAB_ParseEtl.ps1 - Headless import guide

Script banner version: 3.11.0. New trace provenance: `ps-import-v2`.
Requires Windows and PowerShell 7+ (`pwsh`), not Windows PowerShell 5.1.

## Choose the import path

[`DAB_ParseEtl.ps1`](../DAB_ParseEtl.ps1) imports a Dynamics 365 Finance & Operations ETL file into an existing AXTrace SQL schema without the web app, a running DAB server or a Copilot Studio agent.

Use this legacy direct writer only with an isolated database and exclusive import access. It uses shared `StageTraceLines` and `CopyTraceLinesFromStage`, creates a new trace on every run, and does not implement the Function importer's receipt-based retry/resume. Repeating a failed command can leave or add partial/duplicate data.

**For a receipt-managed web/Function database, use a new registered web upload instead.** The script refuses a database containing `dbo.TPImportReceipts`, including an empty receipt table, and refuses callers without database `VIEW DEFINITION`. Do not remove receipts, weaken metadata checks, or point this script at the shared web database to bypass the guard. See the [web importer protocol](../../TraceParserWeb/README.md).

## Prerequisites

| Requirement | Notes |
|---|---|
| Windows and PowerShell 7+ | Direct mode uses Windows `EventLogReader`. |
| Existing compatible AXTrace schema | This script does not create the database or install its full schema. Use a separately provisioned direct-import database. |
| Import tables and procedures | Includes `TraceImportSemaphores`, `StageTraceLines`, trace/session/thread and lookup tables, `QueryBindParameters`, `TopMethods`, `ReserveTraceLineIds` and `CopyTraceLinesFromStage`. DAB view scripts alone do not install them. |
| Reviewed SQL permissions | Requires database `VIEW DEFINITION`, reads/writes, procedure execution and authority for default-row `IDENTITY_INSERT` and the installed promotion procedure's operations. `db_datawriter` plus two `EXECUTE` grants alone is not a verified sufficient permission set. Review against the actual schema; do not grant broad roles to the shared web/Function identity for this script. |
| Exclusive import access | Coordinate all writers. The script's semaphore helper inserts a tracking row; it is not proof of cross-process exclusion. Do not run concurrent direct imports. |
| Source and storage headroom | Retain the original ETL; plan for staged/final rows, indexes, log and optional XML. No universal ETL-to-database ratio is established. |
| `tracerpt.exe` for XML mode | Windows tool used only with `-UseXml` when there is no cached `events.xml`. |

The SQL connection implementation uses `TrustServerCertificate=True`. SQL authentication also accepts a plain string password. Those are existing limitations, not a recommended secure deployment configuration. The examples below use local Windows authentication; review connection security separately before any remote use. Never place real passwords in saved commands, process arguments, shell history, transcripts or committed files.

## Parameters

| Parameter | Default | Behavior |
|---|---|---|
| `-EtlPath` | Required | Existing original `.etl` path. Keep it available even when reusing XML. |
| `-SqlServer` | `localhost\SQLEXPRESS` | Explicitly select the isolated SQL instance. |
| `-Database` | `AXTrace` | Explicitly select the separately provisioned direct-import database. |
| `-SqlUser` / `-SqlPassword` | Unset | Without a user, uses Windows authentication. SQL authentication requires both values; see the security limitation above. |
| `-SessionName` | ETL filename plus current time | Name assigned to the newly created trace. Not an idempotency key. |
| `-UseXml` | Off | Switches from direct ETL decoding to `tracerpt`/cached XML processing. |
| `-XmlCacheDir` | `<ETL-directory>\<ETL-basename>_parsed` | With `-UseXml`, reads or creates `events.xml` here. Setting this path alone does not enable XML mode. |
| `-BatchSize` | `50000` | Staging flush size. Not a whole-import transaction or memory/disk guarantee. |
| `-SkipXppMethods` | Off | Omits X++ Enter/Exit handling; changes analysis coverage. |
| `-SkipSqlStatements` | Off | Omits SQL statement handling; changes analysis coverage. |
| `-WhatIf` | Off | Stops before SQL connection/import, after input/mode preparation. Does not run the full parser or validate the database, permissions, promotion or row counts. |

## Local Windows-authentication example

Run from the `TraceParserMCP` folder. `AXTrace_Headless` below is a placeholder for a database you have already provisioned with the required schema; the command does not create it.

First review the command without importing:

```powershell
pwsh -File .\DAB_ParseEtl.ps1 `
  -EtlPath "C:\traces\sample.etl" `
  -SqlServer "localhost\SQLEXPRESS" `
  -Database "AXTrace_Headless" `
  -WhatIf
```

After checking the target, permissions, exclusive access and available storage, run:

```powershell
pwsh -File .\DAB_ParseEtl.ps1 `
  -EtlPath "C:\traces\sample.etl" `
  -SqlServer "localhost\SQLEXPRESS" `
  -Database "AXTrace_Headless" `
  -SessionName "Sample direct import"
```

The default decoder reads ETL directly. The script records an import semaphore row, creates the trace/session/thread hierarchy, stages rows, invokes `CopyTraceLinesFromStage`, handles bind parameters, performs post-processing and populates native `TopMethods`. It attempts semaphore release in `finally`. This does not certify exact desktop Trace Parser behavior or populate the Function's receipt/completion protocol.

New duration fields use nanoseconds under `ps-import-v2`, retaining 100 ns parser resolution. Use the [provenance-aware DAB readers](../README.md#duration-provenance-call-grain-and-pagination); do not infer historical/native units or rewrite old traces from column names. Desktop rendering/parity has not been certified for this version.

## XML fallback and cache reuse

Use explicit XML mode when direct decoding is unsuitable and you have validated the alternate path for the trace:

```powershell
pwsh -File .\DAB_ParseEtl.ps1 `
  -EtlPath "C:\traces\sample.etl" `
  -SqlServer "localhost\SQLEXPRESS" `
  -Database "AXTrace_Headless" `
  -UseXml -XmlCacheDir "C:\traces\sample_xml" `
  -SessionName "Sample XML import"
```

If `events.xml` already exists in that directory, the script reuses it without running `tracerpt`. Otherwise it converts the ETL there. Use a dedicated cache directory per source trace: the cache is selected by filename, not verified against the ETL's content hash. Keep the matching original ETL; do not substitute an unrelated existing file or pass `events.xml` as `-EtlPath`.

Run the same command with a different `-SessionName` only when you intentionally want another import. It creates another trace, not a replay-safe continuation. A fresh empty disposable database is preferable for comparing parser versions. XML conversion time and output size depend on the source; no fixed runtime estimate is guaranteed.

## Results and verification

Successful completion prints `Import Complete`, the new `TraceId`, elapsed time and parser counters, including mismatches and rows staged. The returned PowerShell object contains `TraceId`, `SessionName`, `RowsStaged`, `XppMethods`, `SqlStmts`, `Messages` and `Elapsed`. Console elapsed time excludes some initial preparation, so it is not a complete end-to-end timing.

Record the new trace ID and inspect expected sessions, methods, SQL and known-duration values through compatible readers. A success message alone does not prove provider completeness, zero dropped events, desktop parity or the absence of analytical defects. This script populates native `TopMethods`; it does not execute the Function's physical session-aggregation/completion workflow.

The Function's synthetic storage benchmark uses a different parser/import protocol and must not be quoted as this PowerShell script's performance or storage result.

## Failure and recovery

Stop on an error and retain the source, console output, new trace ID if known, and any staging data for investigation. Avoid logging credentials or sensitive SQL text. The script attempts to mark the trace description as failed, but this is not a durable receipt or rollback guarantee.

Do not blindly retry, truncate staging, delete partial traces, or run a blanket `UPDATE TraceImportSemaphores SET IsImporting=0`. Those actions can erase evidence or affect another writer. Confirm no importer is active, identify the affected trace/staging/semaphore record and agree a scoped recovery. For a disposable test database, an explicitly approved fresh database is an alternative to repairing partial data.

| Symptom | Next check |
|---|---|
| Direct import unsupported in a receipt-managed database or metadata hidden | Check the selected database and the caller's metadata visibility. Use registered web uploads for receipt-managed databases; never bypass the guard. |
| `EtlFolder` parameter not found | Use `-EtlPath`. |
| `??` operator unsupported | Use `pwsh` 7+, not `powershell` 5.1. |
| Cached XML ignored | Supply `-UseXml` as well as `-XmlCacheDir`. |
| `tracerpt` or event decoding error | Confirm source format, original ETL path and matching cache. Preserve the error; changing decoder does not establish equivalent output. |
| SQL connection/login/permission error | Check the explicit instance/database, authentication and schema-specific permissions. Do not broaden firewall access or grant shared application roles automatically. |
| Long import or apparent stalled progress | Inspect the owned operation and SQL activity before changing anything. Do not infer a safe retry or release a semaphore from elapsed time alone. |
