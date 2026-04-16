# Export & Import Trace Data to Azure SQL

## Overview

The `Export Local and Import to Azure SQL.ps1` script migrates individual D365 F&O trace datasets from a local SQL Server to Azure SQL. Unlike a full database export (SqlPackage/bacpac), this script transfers **a single trace** with all its related data, preserving referential integrity and identity values.

**When to use this script:**
- You import traces locally using the Trace Parser desktop tool (which requires Windows Authentication)
- You want to selectively push specific traces to Azure SQL for MCP access
- You want to add new traces without overwriting existing Azure data

**Why not just use SqlPackage?**
- SqlPackage exports/imports the **entire database**, replacing all data
- SqlPackage requires dropping Windows-authenticated users before export
- This script transfers only the data for a specific trace, leaving other traces intact

---

## Prerequisites

```powershell
# Install the SqlServer PowerShell module (one-time setup)
Install-Module -Name SqlServer -Scope CurrentUser -Force
```

The script will auto-install the module if missing, but manual installation avoids elevation prompts.

---

## How It Works

The script runs in three phases:

### Phase 1: Export

Extracts all data related to a single `TraceId` from the source database, respecting table dependencies:

```
1. Traces              → The trace record itself
2. Users               → Users referenced by sessions in this trace
3. UserSessions        → Sessions belonging to this trace
4. UserSessionProcessThreads → Threads within those sessions
5. MethodNames         → Method names referenced by trace lines
6. QueryStatements     → SQL statements referenced by trace lines
7. QueryTables         → Table names referenced by trace lines
8. TraceLines          → All trace line data (the bulk of the data)
```

Each table is exported to a numbered CSV file in the export directory.

### Phase 2: Import

Imports the CSV files into Azure SQL using `SqlBulkCopy` for performance. Tables are imported in dependency order so foreign key constraints are satisfied. `IDENTITY_INSERT` is enabled automatically for tables with identity columns to preserve the original IDs.

### Phase 3: Verification

Queries the destination database to confirm the trace, sessions, and trace lines were imported correctly.

---

## Usage

### Basic Usage: Local SQL Express to Azure SQL

The most common scenario - import traces locally with the Trace Parser tool, then push to Azure:

```powershell
& ".\Export Local and Import to Azure SQL.ps1" `
    -SourceServer "localhost\SQLEXPRESS" `
    -SourceDatabase "AxTrace" `
    -DestinationServer "sql-traceparser-202602100024.database.windows.net" `
    -DestinationDatabase "TraceParserDB" `
    -DestinationUsername "sqladmin" `
    -DestinationPassword "YourPassword!" `
    -TraceId 2 `
    -UseWindowsAuth
```

### SQL Authentication on Both Sides

```powershell
& ".\Export Local and Import to Azure SQL.ps1" `
    -SourceServer "localhost\SQLEXPRESS" `
    -SourceDatabase "AxTrace" `
    -SourceUsername "sa" `
    -SourcePassword "SourcePass!" `
    -DestinationServer "sql-traceparser-202602100024.database.windows.net" `
    -DestinationDatabase "TraceParserDB" `
    -DestinationUsername "sqladmin" `
    -DestinationPassword "DestPass!" `
    -TraceId 2
```

### Custom Export Path

```powershell
& ".\Export Local and Import to Azure SQL.ps1" `
    -SourceServer "localhost\SQLEXPRESS" `
    -SourceDatabase "AxTrace" `
    -DestinationServer "sql-traceparser-202602100024.database.windows.net" `
    -DestinationDatabase "TraceParserDB" `
    -DestinationUsername "sqladmin" `
    -DestinationPassword "YourPassword!" `
    -TraceId 5 `
    -ExportPath "C:\TraceBackups\Trace_5" `
    -UseWindowsAuth
```

---

## Parameters

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `SourceServer` | Yes | | Source SQL Server (e.g., `localhost\SQLEXPRESS`) |
| `SourceDatabase` | Yes | | Source database name (e.g., `AxTrace`) |
| `DestinationServer` | Yes | | Azure SQL server (e.g., `<name>.database.windows.net`) |
| `DestinationDatabase` | Yes | | Azure SQL database name (e.g., `TraceParserDB`) |
| `TraceId` | Yes | | The TraceId to export and import |
| `SourceUsername` | No | | SQL auth username for source (not needed with `-UseWindowsAuth`) |
| `SourcePassword` | No | | SQL auth password for source (not needed with `-UseWindowsAuth`) |
| `DestinationUsername` | No | | SQL auth username for Azure SQL |
| `DestinationPassword` | No | | SQL auth password for Azure SQL |
| `ExportPath` | No | `.\TraceExport_<TraceId>` | Directory for intermediate CSV files |
| `UseWindowsAuth` | No | `$false` | Use Windows Authentication for the source connection |

---

## Example Output

```
==================================================
D365 F&O Trace Export/Import Tool
==================================================
TraceId: 2
Export Path: .\TraceExport_2

[PHASE 1: EXPORT FROM SOURCE]
Source: localhost\SQLEXPRESS.AxTrace

Exporting 01_Traces...
  ✓ Exported 1 rows to .\TraceExport_2\01_Traces.csv
Exporting 02_Users...
  ✓ Exported 3 rows to .\TraceExport_2\02_Users.csv
Exporting 03_UserSessions...
  ✓ Exported 3 rows to .\TraceExport_2\03_UserSessions.csv
Exporting 04_UserSessionProcessThreads...
  ✓ Exported 12 rows to .\TraceExport_2\04_UserSessionProcessThreads.csv
Exporting 05_MethodNames...
  ✓ Exported 4521 rows to .\TraceExport_2\05_MethodNames.csv
Exporting 06_QueryStatements...
  ✓ Exported 892 rows to .\TraceExport_2\06_QueryStatements.csv
Exporting 07_QueryTables...
  ✓ Exported 156 rows to .\TraceExport_2\07_QueryTables.csv
Exporting 08_TraceLines...
  ✓ Exported 145230 rows to .\TraceExport_2\08_TraceLines.csv

Export Summary:
Total rows exported: 150818

[PHASE 2: IMPORT TO AZURE SQL]
Destination: sql-traceparser-202602100024.database.windows.net.TraceParserDB

Importing to Traces...
  ✓ Imported 1 rows to Traces
Importing to Users...
  ✓ Imported 3 rows to Users
...

[PHASE 3: VERIFICATION]
✓ Trace records: 1
✓ Sessions: 3
✓ Trace lines: 145230

✓ Migration completed successfully!
```

---

## Data Flow Diagram

```
┌─────────────────────────┐         ┌─────────────────────────┐
│   Local SQL Express     │         │      Azure SQL           │
│   (AxTrace database)    │         │  (TraceParserDB)         │
│                         │         │                          │
│  Trace Parser imports   │  CSV    │  DAB MCP server reads    │
│  ETL traces here using  │ ──────> │  from here and exposes   │
│  Windows Authentication │  files  │  via REST/GraphQL/MCP    │
└─────────────────────────┘         └─────────────────────────┘
        ▲                                      │
        │                                      ▼
   Trace Parser                        Copilot Studio
   Desktop Tool                     Claude Desktop / VS Code
```

---

## Typical Workflow

1. **Import trace locally** using the D365 Trace Parser desktop tool (Windows auth to local SQL Express)
2. **Find the TraceId** of the newly imported trace:
   ```sql
   SELECT TOP 5 TraceId, TraceName, ImportDate FROM Traces ORDER BY TraceId DESC
   ```
3. **Run this script** to push that trace to Azure SQL
4. **Query via MCP** using Copilot Studio, Claude Desktop, or any MCP client

---

## Troubleshooting

### "Cannot open server" / Connection timeout

- Verify Azure SQL firewall allows your IP: Azure Portal > SQL Server > Networking > Add client IP
- Verify the Azure SQL server name includes `.database.windows.net`

### "IDENTITY_INSERT is already ON"

- A previous import may have failed mid-way. Run this on the destination database:
  ```sql
  SET IDENTITY_INSERT Traces OFF
  SET IDENTITY_INSERT Users OFF
  SET IDENTITY_INSERT UserSessions OFF
  SET IDENTITY_INSERT UserSessionProcessThreads OFF
  ```

### "Violation of PRIMARY KEY constraint"

- The trace (or its related data) already exists in the destination. Delete the existing trace first:
  ```sql
  -- Delete in reverse dependency order
  DELETE tl FROM TraceLines tl
  INNER JOIN UserSessionProcessThreads pt ON tl.ThreadId = pt.ThreadId
  INNER JOIN UserSessions us ON pt.SessionId = us.SessionId
  WHERE us.TraceId = <TraceId>

  DELETE pt FROM UserSessionProcessThreads pt
  INNER JOIN UserSessions us ON pt.SessionId = us.SessionId
  WHERE us.TraceId = <TraceId>

  DELETE FROM UserSessions WHERE TraceId = <TraceId>
  DELETE FROM Traces WHERE TraceId = <TraceId>
  ```

### "SqlServer module not found"

```powershell
Install-Module -Name SqlServer -Scope CurrentUser -Force -AllowClobber
```

---

## Key Features

- **Single-trace granularity** - Export/import one trace at a time without affecting others
- **Dependency-aware ordering** - Tables are processed in the correct order for referential integrity
- **IDENTITY_INSERT handling** - Preserves original IDs across databases
- **SqlBulkCopy performance** - Uses bulk operations with 5000-row batches for large datasets
- **Verification step** - Validates the import was successful
- **Intermediate CSV files** - Export files are kept for debugging or re-import
- **Azure SQL compatible** - Handles encrypted connections, SQL authentication
