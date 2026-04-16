<p align="center">
  <img src="Images/trace-parser-logo.png" alt="Trace Parser Agent" width="120">
</p>

# Trace Parser Agent

> AI-powered performance trace analysis for D365 Finance & Operations, built with **Copilot Studio**, **Data API Builder**, and **Blazor Server**.

[![Made with Copilot Studio](https://img.shields.io/badge/Copilot%20Studio-Enabled-blue)](#) [![D365 F&O](https://img.shields.io/badge/D365-F%26O-success)](#) [![MCP](https://img.shields.io/badge/MCP-Protocol-purple)](#)

📖 [Microsoft Learn Documentation](https://learn.microsoft.com/en-us/dynamics365/guidance/agent-templates/trace-parser-agent) · 📝 [Request Access Form](https://forms.cloud.microsoft/r/ZCSSSMhg40)

---

## Overview

By using conversational AI, you can reduce performance troubleshooting in D365 F&O from 6–8 hours of manual trace analysis to approximately 5–10 minutes. Engineers and consultants can diagnose N+1 query patterns, slow SQL statements, blocking problems, and X++ exceptions by asking questions in plain English.

## Components

This agent consists of three components:

| Component | Description | Folder |
|-----------|-------------|--------|
| **Copilot Studio Agent** | The AI agent solution — import into Copilot Studio | [`Solutions/`](Solutions/) |
| **TraceParserMCP** | Data API Builder MCP server exposing trace data via REST, GraphQL, and MCP protocol | [`TraceParserMCP/`](TraceParserMCP/) |
| **TraceParserWeb** | Blazor Server web app + Azure Function for ETL trace upload and import | [`TraceParserWeb/`](TraceParserWeb/) |

## Architecture

The agent uses a **dual Model Context Protocol (MCP)** architecture:

- **TraceParser MCP (Data API Builder)** — Local SQL MCP Server exposing trace database views and stored procedures for deterministic, secure trace data access
- **Microsoft Learn MCP** — Public MCP Server providing real-time access to the full Microsoft documentation library for D365 performance optimization guidance and X++ code samples

### Deployment Topologies

| Topology | Description |
|----------|-------------|
| **Local developer** | Single machine with LocalDB/SQL Express — ideal for individual engineers |
| **Shared team server** | On-premises SQL Server with shared access for support teams |
| **Azure SQL + local DAB** | Cloud database with local API layer |
| **Full Azure** | Azure SQL Database + Azure App Service hosting DAB |
| **Enterprise auto-scale** | Azure Container Apps with auto-scaling for large teams |
| **Hybrid** | On-premises trace database with cloud-hosted AI orchestration |

## Quick Start

### 1. Set up the MCP Server

See [`TraceParserMCP/README.md`](TraceParserMCP/README.md) for full instructions.

```bash
# Install Data API Builder
dotnet tool restore

# Configure connection string
# Edit .env with your SQL Server details

# Start the server
dab start
```

### 2. Import the Copilot Studio Agent

See [`Solutions/readme.md`](Solutions/readme.md) for import instructions.

### 3. (Optional) Deploy TraceParserWeb

See [`TraceParserWeb/README.md`](TraceParserWeb/README.md) for the web-based ETL upload interface.

## Key Capabilities

- **N+1 query pattern detection** — Automatically identifies repetitive database call patterns
- **Slow SQL identification** — Finds SQL statements exceeding thresholds with index recommendations
- **SQL blocking/deadlock analysis** — Diagnoses contention issues
- **X++ exception diagnosis** — Pinpoints error sources in application code
- **Call tree analysis** — Identifies method execution bottlenecks
- **Keyword search** — Search across methods, SQL statements, messages, and table names
- **Microsoft Learn integration** — Every finding paired with current remediation guidance

## Prerequisites

- [.NET 8+ Runtime](https://dotnet.microsoft.com/download)
- SQL Server (LocalDB, SQL Express, or Azure SQL)
- Microsoft Copilot Studio access
- Copilot Studio Credits Capacity
- For TraceParserWeb: Azure subscription (optional, for cloud deployment)

## Supported Channels

- Chat (Copilot Studio)
- Microsoft Teams

## Disclaimer

> This repository contains **sample/reference code only**. It is provided as-is for educational and demonstration purposes. Microsoft does not operate this agent or any services built with it. Customers are responsible for deploying, operating, and managing this code in their own environments. This code is not production-ready and comes with no guarantees of availability, reliability, or support.
