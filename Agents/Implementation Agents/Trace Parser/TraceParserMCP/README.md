# TraceParserMCP

A sample MCP (Model Context Protocol) server for analyzing Dynamics 365 Finance & Operations performance trace data. Built on [Azure Data API Builder](https://learn.microsoft.com/en-us/azure/data-api-builder/), it exposes trace data from a SQL Server database via REST, GraphQL, and MCP endpoints.

> **Disclaimer:** This repository is **sample/reference code only**. It is provided as-is for educational and demonstration purposes. Microsoft does not operate this server or any agents built with it. Customers are responsible for deploying, operating, and managing this code in their own environments. This code is not production-ready and comes with no guarantees of availability, reliability, or support.

> **This repository is sample/reference code only.** It is provided as a template to demonstrate how to build an MCP server for D365 F&O trace analysis using Azure Data API Builder. See [Scope & Intent](#scope--intent) and [Responsible AI](#responsible-ai-considerations) below.

## Scope & Intent

- This repository contains **sample/reference/template code only**
- Microsoft does not operate, host, or manage this agent, service, or runtime
- Customers are responsible for deploying and running the solution in their own tenant
- No promises of production readiness, SLAs, or ongoing support are provided
- This is not an official Microsoft product or service

## Responsible AI Considerations

### AI Scope

This project provides a **data access layer** (MCP server) that enables AI assistants to read and query D365 F&O performance trace data. It does **not** include or ship any AI model, LLM, or inference engine. The AI capabilities come from the MCP client that connects to this server (e.g., Microsoft Copilot Studio, Claude Desktop, VS Code with GitHub Copilot).

### LLM Configuration

The Large Language Model (LLM) used with this MCP server is **entirely customer-configured**. Customers choose:
- Which MCP client and AI model to use
- How to configure prompts and agent behavior
- What level of access and permissions to grant
- Whether and how to validate AI-generated analysis

### Intended Use

- **Sample patterns** for building MCP servers with Azure Data API Builder
- Reference architecture for exposing SQL Server data via MCP protocol
- Template for D365 F&O performance trace analysis workflows
- Educational resource for understanding MCP integration with Copilot Studio

### Not-Intended Use

- Not intended as a production-ready, turnkey solution without customer review and customization
- Not intended for automated decision-making without human oversight
- Not intended for processing sensitive or personal data without appropriate access controls
- Not intended to replace professional performance engineering judgment

### Known Limitations

- **Data accuracy depends on source traces.** The MCP server returns data as-is from the database. Analysis quality depends on the completeness and correctness of imported trace data.
- **No built-in authentication.** The default configuration uses anonymous read access. Customers must implement appropriate authentication and network security for their deployment.
- **AI analysis is non-deterministic.** Different AI models and prompts will produce different analysis results for the same trace data. Results should be verified by qualified engineers.
- **Read-only access.** The MCP server provides read and execute permissions only. It cannot modify trace data.
- **View-based analysis thresholds are fixed.** Analytical views (e.g., N+1 pattern detection at >100 DB calls, slow SQL at >5 seconds) use hardcoded thresholds that may not suit all scenarios.

### Disclaimers

- AI-generated trace analysis is provided for **informational purposes only** and should not be treated as definitive performance diagnostics
- This project makes **no claims of safety, accuracy, or completeness** of AI-generated outputs
- Users are responsible for validating any analysis or recommendations produced by AI models connected to this MCP server
- Microsoft is not responsible for any decisions made based on AI-generated analysis from this tool

---

## Prerequisites

- [.NET 8+ Runtime](https://dotnet.microsoft.com/download)
- SQL Server (local or Azure SQL)
- The `AxTrace` database populated with trace data

For Azure deployment, you also need:
- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli) (`az`)
- An active Azure subscription

## Local Development

1. **Restore the .NET tool:**

   ```bash
   dotnet tool restore
   ```

2. **Configure the connection string:**

   Edit the `.env` file to match your SQL Server instance:

   ```
   AZURE_SQL_CONNECTION_STRING=Server=localhost\SQLEXPRESS;Database=AxTrace;Trusted_Connection=True;TrustServerCertificate=True;Encrypt=Optional
   ```

3. **Start the server:**

   ```bash
   dab start
   ```

The server will be available at:

| Protocol | Endpoint                      |
|----------|-------------------------------|
| REST     | `http://localhost:5000/api`    |
| GraphQL  | `http://localhost:5000/graphql`|
| MCP      | `http://localhost:5000/mcp`   |

## Azure Deployment

The included `deploy-to-azure.ps1` script provisions all Azure resources and deploys the DAB MCP server as a container-based App Service.

### What It Creates

| Resource | Details |
|----------|---------|
| Resource Group | `rg-traceparser-prod` |
| Azure SQL Server + Database | `TraceParserDB` (S1 tier) |
| App Service Plan | Linux B1 |
| App Service | Container running the official DAB Docker image |

### How to Deploy

1. **Update the script parameters** (password, region, etc.):

   ```powershell
   .\deploy-to-azure.ps1 -SqlPassword "YourSecurePassword!" -Location "westus2"
   ```

2. **Import your local database** to Azure SQL using SqlPackage:

   ```bash
   sqlpackage /Action:Export /SourceServerName:localhost\SQLEXPRESS /SourceDatabaseName:AxTrace /TargetFile:AxTrace.bacpac /SourceTrustServerCertificate:True /SourceEncryptConnection:Optional
   sqlpackage /Action:Import /TargetServerName:<your-server>.database.windows.net /TargetDatabaseName:TraceParserDB /SourceFile:AxTrace.bacpac /TargetUser:sqladmin /TargetPassword:"YourPassword"
   ```

   > **Note:** Windows-authenticated SQL users must be dropped before export, as Azure SQL doesn't support Windows auth. Run `DROP USER [DOMAIN\username]` in the AxTrace database before exporting, and recreate after.

   > **If you get "Data cannot be imported into target because it contains one or more user objects":** The target database is not empty. Drop and recreate it before importing:
   > ```
   > az sql db delete --name TraceParserDB --server <your-server> --resource-group rg-traceparser-prod --yes
   > az sql db create --name TraceParserDB --server <your-server> --resource-group rg-traceparser-prod --service-objective S1
   > ```

### Architecture

- Uses the official DAB Docker image: `mcr.microsoft.com/azure-databases/data-api-builder:1.7.83-rc`
- The `dab-config.json` is deployed via zip to `/home/site/wwwroot/`
- DAB reads the config via startup command: `--ConfigFileName /home/site/wwwroot/dab-config.json`
- Connection string is set via the `AZURE_SQL_CONNECTION_STRING` app setting
- DAB listens on port 5000 (configured via `WEBSITES_PORT=5000`)

After deployment, endpoints are available at:

| Protocol | Endpoint |
|----------|----------|
| REST     | `https://<app-name>.azurewebsites.net/api` |
| GraphQL  | `https://<app-name>.azurewebsites.net/graphql` |
| MCP      | `https://<app-name>.azurewebsites.net/mcp` |

## Connecting to an MCP Client

To use this server with an MCP-compatible client (e.g., Claude Desktop, VS Code with GitHub Copilot, Microsoft Copilot Studio), add it as an SSE transport:

**Local:**
```json
{
  "mcpServers": {
    "TraceParserMCP": {
      "url": "http://localhost:5000/mcp"
    }
  }
}
```

**Azure:**
```json
{
  "mcpServers": {
    "TraceParserMCP": {
      "url": "https://<app-name>.azurewebsites.net/mcp"
    }
  }
}
```

## Exposed Entities

All entities are read-only and accessible via REST, GraphQL, and MCP.

### Core Tables

| Entity | Description |
|--------|-------------|
| **Traces** | Imported ETL trace files, each containing multiple user sessions |
| **UserSessions** | Individual user sessions within a trace |
| **Users** | User lookup table (UserId to UserName) |
| **UserSessionProcessThreads** | Process threads within sessions, linked to TraceLines |
| **TraceLines** | Main trace data with call tree structure and timing (nanoseconds) |
| **MethodNames** | Method name lookup (join via `MethodHash`) |
| **QueryStatements** | SQL statement text lookup (join via `QueryStatementHash`) |
| **QueryTables** | Table name lookup (join via `QueryTableHash`) |
| **TopMethods** | Pre-aggregated top methods by performance |

### Analytical Views

| Entity | Description |
|--------|-------------|
| **SessionSummary** | Denormalized session view with user and trace info |
| **SessionMetrics** | Sessions with aggregated metrics (times in milliseconds) |
| **TraceLineDetails** | TraceLines with resolved method names and SQL text (times in milliseconds) |
| **NPlusOnePatterns** | N+1 query pattern candidates (>100 DB calls, <5ms avg) |
| **SlowSqlStatements** | SQL statements exceeding 5 seconds, with full text |
| **TopMethodsBySession** | Method performance aggregated per session |

### Stored Procedures

| Entity | Description |
|--------|-------------|
| **SearchTracesByKeyword** | Search traces by keyword with optional scope (`ALL`, `SQL`, `METHOD`, `MESSAGE`, `TABLE`) |
| **SearchSqlStatements** | Search SQL statements by keyword |
| **SearchMethods** | Search method names by keyword |
| **SearchMessages** | Search messages by keyword |

## Querying Data

### REST

```
GET http://localhost:5000/api/SessionSummary
GET http://localhost:5000/api/TraceLineDetails?$filter=UserSessionId eq 1
GET http://localhost:5000/api/SlowSqlStatements?$orderby=ExclusiveDurationMs desc
```

### GraphQL

```graphql
{
  sessionMetrics(filter: { totalDurationMs: { gt: 1000 } }) {
    items {
      userSessionId
      totalDurationMs
      sqlCallCount
    }
  }
}
```

### MCP

MCP clients can use the `read-records`, `describe-entities`, and `execute-entity` tools to query all exposed entities and run stored procedures.

## Key Concepts

- **Time units differ between tables and views.** Raw tables (`TraceLines`) store durations in **nanoseconds**. Analytical views (`TraceLineDetails`, `SessionMetrics`, etc.) convert to **milliseconds**.
- **Hash-based lookups.** `TraceLines` references method names, SQL statements, and table names via hash columns (`MethodHash`, `QueryStatementHash`, `QueryTableHash`). Use the corresponding lookup tables or the `TraceLineDetails` view which resolves them automatically.
- **Session-centric organization.** Data is organized around user sessions. Start with `SessionSummary` or `SessionMetrics` to discover sessions, then drill into `TraceLineDetails` for specifics.

## Project Structure

```
TraceParserMCP/
  .config/dotnet-tools.json                   # Data API Builder tool definition (v1.7.83-rc)
  .env                                        # Database connection string (AZURE_SQL_CONNECTION_STRING)
  dab-config.json                             # Data API Builder configuration (entities, permissions, endpoints)
  Create Views.sql                            # SQL script to create 6 analytical views
  Create Keyword Search SPs.sql               # SQL script to create 4 keyword search stored procedures
  deploy-to-azure.ps1                         # Azure deployment script (provisions all resources)
  Export Local and Import to Azure SQL.ps1    # Per-trace data migration script
```

## Configuration

All server behavior is defined declaratively in `dab-config.json`. Key settings:

- **Connection string:** Read from `AZURE_SQL_CONNECTION_STRING` environment variable (`.env` locally, App Settings on Azure)
- **MCP permissions:** Read and execute only (create, update, delete disabled)
- **Authentication:** Anonymous read access (customers should configure authentication for their deployment)
- **Host mode:** Production
- **GraphQL introspection:** Enabled
- **REST request body:** Strict validation

## Third-Party Dependencies

This project uses the following third-party components:

| Component | License | Usage |
|-----------|---------|-------|
| [Azure Data API Builder](https://github.com/Azure/data-api-builder) | MIT | MCP/REST/GraphQL server engine |

No other third-party libraries or packages are included. The solution is entirely configuration-driven (`dab-config.json`).

## License

This project is licensed under the [MIT License](LICENSE).
