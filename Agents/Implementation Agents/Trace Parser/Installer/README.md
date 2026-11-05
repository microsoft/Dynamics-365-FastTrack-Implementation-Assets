# Trace Parser Desktop App

> Official Microsoft desktop application for capturing and viewing D365 Finance & Operations performance trace files (`.etl`).

## What This Is

The **Trace Parser** is Microsoft's native desktop tool for:

- Recording ETW performance traces in D365 F&O environments
- Browsing trace events in a tree / call-stack viewer
- Exporting trace data to a SQL Server `AxTrace` database — the same schema the AI agent components in this folder read from

It is the **upstream data source** for the rest of this repository — the AI agent analyzes traces that have been captured and imported via this tool.

## File

| Field | Value |
|---|---|
| File | `TraceParser.zip` (contains `TraceParser.msi`) |
| Product | Microsoft Dynamics 365 Unified Operations - Trace Parser |
| Version | 7.0.7690.33 |
| Publisher | Microsoft Corporation (digitally signed) |
| Install scope | Machine-wide (`ALLUSERS=1`) |
| Size | 4.13 MB (zip) · 4.65 MB (extracted MSI) |

## Installation

1. Download `TraceParser.zip` from this folder.
2. Extract the archive — you'll get `TraceParser.msi`.
3. Right-click `TraceParser.msi` → **Install** (or double-click).
4. Accept the UAC prompt — the installer requires administrator privileges (machine-wide install).
5. Follow the installer wizard to complete the setup.

After installation, launch **Microsoft Dynamics 365 Unified Operations - Trace Parser** from the Start menu.

## Verifying Authenticity

Before installing, you can verify the MSI's Microsoft digital signature:

```powershell
Get-AuthenticodeSignature -FilePath TraceParser.msi
```

Expected output:

- **Status:** `Valid`
- **Signer:** `CN=Microsoft Corporation, O=Microsoft Corporation, L=Redmond, S=Washington, C=US`
- **Issuer:** `CN=Microsoft Code Signing PCA 2011, O=Microsoft Corporation, …`

## Usage with the AI Agent

This desktop tool produces the `.etl` trace files and the `AxTrace` SQL database schema that the rest of this repository uses:

1. **Capture** an ETW trace using the desktop Trace Parser while reproducing a performance issue in D365 F&O.
2. **Import** the trace into your `AxTrace` SQL database — either via the desktop tool's own import dialog, or via the [`TraceParserMCP`](../TraceParserMCP/) PowerShell script (`DAB_ParseEtl.ps1`), or via the [`TraceParserWeb`](../TraceParserWeb/) Blazor upload UI.
3. **Analyze** the imported trace conversationally using the [Copilot Studio agent](../Solutions/).

## Source

This installer is included for FastTrack customer discoverability — the same MSI Microsoft provides through official internal channels. It is bundled here so customers can pick up the Trace Parser desktop tool alongside the AI agent components in this repository.

## Disclaimer

The Trace Parser desktop tool is a Microsoft product distributed under its own End User License Agreement, displayed during MSI installation. The remaining components in the parent folder (Copilot Studio agent, MCP server, web upload UI) are **sample / reference code** as described in the [parent README](../README.md).
