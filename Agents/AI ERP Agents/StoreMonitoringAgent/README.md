# Store Monitoring Agent

A comprehensive solution for monitoring Windows-based Point-of-Sale (POS) devices using Azure Arc, Azure Monitor Agent (AMA), and Microsoft Copilot Studio.

## Introduction

The **D365 Commerce Store Monitoring Agent** is a Microsoft Copilot Studio agent that provides a natural language interface for monitoring Windows-based Point-of-Sale (POS) devices in Dynamics 365 Commerce retail environments.

The solution connects POS devices to Azure via **Azure Arc** and **Azure Monitor Agent (AMA)**, collecting Windows event logs, performance counters, heartbeat signals, and offline database metrics into **Azure Log Analytics**. The Copilot Studio agent queries this data using **KQL (Kusto Query Language)** through an agent workflow with managed identity authentication.

### Capabilities

| Category                    | Description                                                               |
| --------------------------- | ------------------------------------------------------------------------- |
| **Device status**           | List online/offline POS devices, view offline history and event timelines |
| **Application errors**      | Errors for a single device or grouped counts across all devices           |
| **Hardware station errors** | Errors for a single device or counts/details across all devices           |
| **Retail server errors**    | Errors per device, grouped by request URL, counts by machine name         |
| **Performance**             | CPU % and available memory for a POS device                               |
| **Offline database**        | SQL offline database metrics and health                                   |
| **Reports**                 | Comprehensive health report for a single device or all devices            |
| **Utilities**               | Find machine names, change selected device, set/view query time range     |

### Key Design Points

- **Conversational + focused**: Strictly scoped to POS/Store Commerce diagnostics — declines off-topic questions
- **KQL-backed**: All queries run against Log Analytics via a `RunLogAnalyticsQuery` workflow
- **AI disclosure**: Always ends responses with a summary noting content is AI-generated
- **Autonomous monitoring**: Supports an alert-triggered mode for proactive, autonomous monitoring without user prompts

## Solution Components

### 1. Device Onboarding

- **Azure Arc Onboarding**: Connect Windows 10/11 and Server devices using portal-generated scripts or Server 2022 Arc Setup wizard
- **AzCM Agent**: Registers devices as Arc-enabled resources

### 2. Governance at Scale

- **Azure Policy**: Automatically deploys AMA and associates DCR to all Arc-enabled devices
- **Compliance**: Ensures new and existing devices stay compliant

### 3. Data Collection

- **Data Collection Rules (DCR)**: Define what data to collect and route to Log Analytics
  - **Windows Event Logs**: Application, System, and Security logs; custom XPath filters for Store Commerce-specific events
  - **Performance Counters**: CPU (`% Processor Time`) and memory (`Available Bytes`) sampled at a configurable interval
  - **Heartbeat**: Azure Arc agent heartbeat signals used to detect device online/offline status
  - **Custom Event Log entries**: Offline SQL database metrics written to the Windows Event Log by the `DatabaseMetricsService` (Event ID 3000)
  - **EventLog Sink Configuration**: The `EventLogSinkConfigService` monitors the Store Commerce `config.json` to ensure the `WebViewEventLogSink` is configured with `EventLevel` set to Informational, so that Store Commerce diagnostic events are written to the Windows Event Log for AMA collection

### 4. Query & Insights

- **Copilot Studio Agent**: Natural language interface for querying
- **Agent Flow**: Middleware for KQL execution with managed identity authentication
- **Log Analytics**: Stores and analyzes collected data

### 5. Networking

- **Outbound HTTPS only**: All device-to-Azure traffic uses port 443
- **No inbound ports required**: Secure by design for POS environments

## Quick Start

1. **Prerequisites**
   - Azure subscription
   - Log Analytics workspace
   - Azure Arc-enabled machines
   - Copilot Studio with Agents enabled

2. **Deployment Steps**
   - See [Quick start](docs/quick-start-portal.md)

3. **Import the Agent**
   - Import the Copilot Studio agent into your Power Platform environment using the solution zip file `StoreMonitoringAgent_1_0_0_14.zip` provided in the root of this repository. See [Step 7 in the Quick Start guide](docs/quick-start-portal.md#step-7-setup-copilot-studio-agent-5-minutes) for detailed instructions.

## Documentation

| Document                                                                              | Description                                                          |
| ------------------------------------------------------------------------------------- | -------------------------------------------------------------------- |
| [Quick Start Guide - Azure Portal](docs/quick-start-portal.md)                        | Step-by-step deployment guide using the Azure portal                 |
| [Architecture Documentation](docs/architecture.md)                                    | Solution architecture and component overview                         |
| [Device Onboarding Guide](docs/device-onboarding.md)                                  | Connect POS devices to Azure Arc and configure AMA                   |
| [Capturing Database Metrics to Log Analytics](docs/database-metrics-log-analytics.md) | Configure offline SQL database metrics collection                    |
| [Store Commerce App Update Procedure](docs/store-commerce-update.md)                  | Procedure for updating Store Commerce on monitored devices           |
| [Autonomous / Proactive Monitoring Setup](docs/autonomous-proactive-monitoring.md)    | Configure alert-triggered autonomous monitoring                      |
| [Alert-Triggered Agent](docs/alert-triggered-agent.md)                                | How the alert-triggered agent mode works                             |
| [Known Limitations](docs/known-limitations.md)                                        | Current known limitations and workarounds                            |
| [Periodic Maintenance Guide](docs/periodic-maintenance.md)                            | Periodic rotation and expiration checks for secrets and certificates |
