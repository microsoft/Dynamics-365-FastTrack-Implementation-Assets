# Copilot Studio Solutions

## Solution Files

| File | Description |
|------|-------------|
| `TraceParser_1_0_0_4.zip` | Copilot Studio agent solution — the Trace Parser AI agent that connects to the MCP server for conversational trace analysis |
| `TPA - Solution Files V1.zip` | Supporting solution files for the Trace Parser agent |

## Import Instructions

1. Go to [make.powerapps.com](https://make.powerapps.com) → **Solutions** → **Import**
   - Or open [Copilot Studio](https://copilotstudio.microsoft.com) → **Import Agent**
2. Select `TraceParser_1_0_0_4.zip`
3. Follow the wizard to create/sign in to required connections
4. Click **Import** and wait for completion
5. After import, open the agent in Copilot Studio and configure the MCP server connection to your deployed DAB instance

> **Note:** The agent requires a running TraceParserMCP (Data API Builder) server instance. See the [Local Setup Guide](../TraceParserMCP/docs/Trace%20Parser%20Agent%20-%20Local%20Setup%20Guide.md) for complete setup instructions.

### Prerequisites

- Microsoft Copilot Studio access
- Copilot Studio Credits Capacity
- A deployed TraceParserMCP instance (local DAB or Azure App Service)
- SQL Server database with trace data imported
