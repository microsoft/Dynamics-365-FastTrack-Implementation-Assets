# DAB_ParseEtl.ps1 — User Guide

> **Version:** 3.9.0
> **Requires:** PowerShell 7+ (`pwsh`)

---

## Overview

`DAB_ParseEtl.ps1` imports a D365 ETL trace file (`.etl`) into the **AXTrace** SQL database so it can be viewed in **Microsoft Dynamics 365 Trace Parser.exe**.

The script mirrors the exact import protocol used by Trace Parser:
1. Runs `tracerpt.exe` to convert the `.etl` to XML (skipped if a cached XML already exists)
2. Streams XML events and builds the session/thread hierarchy in SQL
3. Stages trace lines in batches, then promotes them with `CopyTraceLinesFromStage`
4. Runs post-processing (hash propagation, recursion detection, TopMethods aggregation)

---

## Prerequisites

| Requirement | Notes |
|---|---|
| PowerShell 7+ | Run as `pwsh`, not `powershell` (needed for `??` operator) |
| `tracerpt.exe` | Ships with Windows, already in PATH |
| AXTrace SQL database | Local or Azure SQL — must have the AXTrace schema |
| SQL permissions | `db_datawriter` + `EXECUTE` on `ReserveTraceLineIds` and `CopyTraceLinesFromStage` |

---

## Parameters

| Parameter | Type | Default | Description |
|---|---|---|---|
| `-EtlPath` | string | *(required)* | Full path to the `.etl` trace file **or** a dummy path when reusing cached XML |
| `-SqlServer` | string | `localhost\SQLEXPRESS` | SQL Server host. For Azure SQL use `myserver.database.windows.net` |
| `-Database` | string | `AXTrace` | Database name |
| `-SqlUser` | string | *(blank)* | SQL login username. Leave blank to use Windows/Integrated auth |
| `-SqlPassword` | string | *(blank)* | SQL login password. Leave blank to use Windows/Integrated auth |
| `-SessionName` | string | *(auto from ETL filename)* | Label shown in Trace Parser's session dropdown |
| `-XmlCacheDir` | string | *(same folder as ETL)* | Directory where `events.xml` is cached. If `events.xml` already exists here, `tracerpt.exe` is skipped |
| `-BatchSize` | int | `500` | Rows per staging batch. Increase (e.g. `1000`) for faster imports on fast machines |
| `-SkipXppMethods` | switch | off | Skip X++ Enter/Exit events (rarely needed) |
| `-SkipSqlStatements` | switch | off | Skip SQL statement events (rarely needed) |
| `-WhatIf` | switch | off | Parse-only dry run — no data written to SQL |

---

## Common Scenarios

### 1. Local SQL Express — Windows auth (most common)

```powershell
pwsh -File DAB_ParseEtl.ps1 `
  -EtlPath "C:\traces\price_sim_perf_slow.etl" `
  -SqlServer "localhost\SQLEXPRESS" `
  -Database "AXTrace"
```

### 2. Azure SQL — SQL authentication

```powershell
pwsh -File DAB_ParseEtl.ps1 `
  -EtlPath "C:\traces\price_sim_perf_slow.etl" `
  -SqlServer "myserver.database.windows.net" `
  -Database "TraceParserDB" `
  -SqlUser "sqladmin" `
  -SqlPassword "P@ssw0rd"
```

### 3. Give the trace a custom name in Trace Parser

```powershell
pwsh -File DAB_ParseEtl.ps1 `
  -EtlPath "C:\traces\price_sim_perf_slow.etl" `
  -SessionName "PriceSim slow — 2026-02-25"
```

### 4. Reuse cached XML (re-import without re-running tracerpt)

> Use this when re-importing the same trace with a new script version.
> Pass any existing file path as `-EtlPath` — only `-XmlCacheDir` matters here.

```powershell
pwsh -File DAB_ParseEtl.ps1 `
  -EtlPath "C:\traces\price_sim_perf_slow.etl" `
  -XmlCacheDir "C:\TraceParserMCP\XmlCache" `
  -SessionName "v3.9.0 re-import"
```

The script detects `C:\TraceParserMCP\XmlCache\events.xml` and skips `tracerpt.exe`.

### 5. Dry run (no SQL writes)

```powershell
pwsh -File DAB_ParseEtl.ps1 `
  -EtlPath "C:\traces\price_sim_perf_slow.etl" `
  -WhatIf
```

### 6. Larger batch size for faster import

```powershell
pwsh -File DAB_ParseEtl.ps1 `
  -EtlPath "C:\traces\price_sim_perf_slow.etl" `
  -BatchSize 1000
```

---

## XmlCacheDir — Why Use It

`tracerpt.exe` takes 1–2 minutes for large ETL files. If you need to re-import the same trace (e.g. after fixing a bug), you can avoid re-running tracerpt by pointing `-XmlCacheDir` to a directory that already contains `events.xml`.

**First import** — generates and caches the XML:
```powershell
pwsh -File DAB_ParseEtl.ps1 -EtlPath "C:\traces\file.etl" -XmlCacheDir "C:\cache"
```

**Subsequent imports** — reuses the cache:
```powershell
pwsh -File DAB_ParseEtl.ps1 -EtlPath "C:\traces\file.etl" -XmlCacheDir "C:\cache" -SessionName "v2"
```

> **Note:** Do not delete `events.xml` from the cache directory between re-imports.
> The cache is specific to the ETL file — if you switch to a different ETL, use a different cache directory.

---

## Output

When the import succeeds, the script prints a summary:

```
=== Import Complete ===
Elapsed:     00:02:15
TraceId:     69
X++ Enter:   27650
SQL Stmts:   668
Bind Params: 1973
Row Fetches: 315
Messages:    30650
Rows Staged: 61256
```

The **TraceId** is the numeric ID assigned to this trace in the database. Each import creates a new `Traces` row with a unique `TraceId`. Open **Trace Parser.exe**, connect to the same SQL database, and select the session by name from the dropdown.

---

## Troubleshooting

| Error | Likely cause | Fix |
|---|---|---|
| `tracerpt.exe exited -2147023504` | Passed `events.xml` path as `-EtlPath` directly | Pass the original `.etl` path; use `-XmlCacheDir` to point to the XML directory |
| `A parameter cannot be found that matches 'EtlFolder'` | Wrong parameter name | Use `-EtlPath` (not `-EtlFolder`) |
| `Cannot connect to SQL Server` | Wrong server name or firewall | Verify `-SqlServer`; for Azure SQL add your IP to the firewall |
| `Login failed for user '...'` | Wrong credentials | Check `-SqlUser` / `-SqlPassword` |
| `The ?? operator is not supported` | Running under `powershell` (v5) | Use `pwsh` (PowerShell 7) |
| Import hangs at "Pre-scanning..." | Very large ETL | Normal — large traces take 2–4 min to scan |
| `Semaphore already held` | Previous import crashed mid-run | Run `UPDATE TraceImportSemaphores SET IsImporting=0 WHERE IsImporting=1` in SQL, then retry |
