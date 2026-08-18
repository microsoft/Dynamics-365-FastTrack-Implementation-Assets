# Store Monitoring Agent

A comprehensive solution for monitoring Windows-based Point-of-Sale (POS) devices using Azure Arc, Azure Monitor Agent (AMA), and Microsoft Copilot Studio.

## Introduction

The **D365 Commerce Store Monitoring Agent** is a Microsoft Copilot Studio agent that provides a natural language interface for monitoring Windows-based Point-of-Sale (POS) devices in Dynamics 365 Commerce retail environments.

The solution connects POS devices to Azure via **Azure Arc** and **Azure Monitor Agent (AMA)**, collecting Windows event logs, performance counters, heartbeat signals, and offline database metrics into **Azure Log Analytics**. The Copilot Studio agent queries this data using **KQL (Kusto Query Language)** through an agent workflow with managed identity authentication.

### Capabilities

| Category                         | Description                                                                                                                         |
| -------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------- |
| **Device availability**          | List online and offline devices, inspect status history and timelines, calculate uptime and downtime, and identify flapping devices |
| **Application diagnostics**      | Analyze Store Commerce errors by device or Event ID, parse diagnostic context, view trends, and explain known RetailLogger events   |
| **Hardware station diagnostics** | Review hardware station errors, counts, details, and trends for individual devices or the full estate                               |
| **Retail Server diagnostics**    | Analyze errors by device or request URL, request duration, slow-request evidence, and performance trends                            |
| **Performance and telemetry**    | Review CPU, available memory, performance pressure, telemetry freshness, and Store Commerce event-log sink health                   |
| **Offline database health**      | Inspect SQL offline database size, table and index metrics, health details, and trends                                              |
| **Operational diagnostics**      | Review completed POS operations, login failures, and card-payment failures                                                          |
| **Fleet analysis and reports**   | Rank unhealthy devices, compare devices, detect anomalies and regressions, and generate single-device or estate-wide reports        |
| **Alerts**                       | Investigate device-offline, database-size, and Retail Server performance alerts and deliver findings for operator review            |
| **Conversation utilities**       | Discover and select devices, configure preset or custom query time ranges, and explain missing or stale data                        |

### Key Design Points

- **Conversational + focused**: Strictly scoped to POS/Store Commerce diagnostics — declines off-topic questions
- **KQL-backed**: All queries run against Log Analytics via a `RunLogAnalyticsQuery` workflow
- **AI disclosure**: Always ends responses with a summary noting content is AI-generated
- **Alert investigation**: Supports alert-driven diagnostic investigation and notification for operator review
- **No automatic mitigation**: The solution does not automatically run remediation or device-changing actions

## Solution Components

### 1. Device Onboarding

- **Azure Arc Onboarding**: Connect Windows 10/11 and Server devices using portal-generated scripts.
- **AzCM Agent**: Registers devices as Arc-enabled resources
- **Azure Monitor Agent (AMA)**: Collects configured telemetry from each Arc-enabled POS device

### 2. Governance at Scale

- **Azure Policy**: Automatically deploys AMA and associates DCR to all Arc-enabled devices
- **Compliance**: Ensures new and existing devices stay compliant

### 3. Data Collection

- **Data Collection Rules (DCR)**: Define what data to collect and route to Log Analytics
  - **Windows Event Logs**: Application logs with custom XPath filters for Store Commerce-specific events
  - **Performance Counters**: CPU (`% Processor Time`) and memory (`Available Bytes`) sampled at a configurable interval
  - **Heartbeat**: Azure Arc agent heartbeat signals used to detect device online/offline status
  - **Custom Event Log entries**: Offline SQL database metrics written to the Windows Event Log by the `DatabaseMetricsService` (Event ID 3000)
  - **EventLog Sink Configuration**: The `EventLogSinkConfigService` monitors the Store Commerce `config.json` to ensure the `WebViewEventLogSink` is configured with `EventLevel` set to Informational, so that Store Commerce diagnostic events are written to the Windows Event Log for AMA collection

### 4. Query & Insights

- **Copilot Studio Agent**: Natural language interface with monitoring, diagnostics, comparison, anomaly detection, triage, and reporting topics
- **RunLogAnalyticsQuery Agent Flow**: Executes KQL against Log Analytics using the configured Azure Monitor Logs connection
- **KQL Query Library**: Reusable queries for device availability, errors, performance, database health, telemetry freshness, trends, and reports
- **Log Analytics Workspace**: Stores collected events, performance counters, and heartbeat data and provides the KQL query engine

### 5. Optional Alerting

- **Azure Monitor Scheduled Query Alerts**: Evaluate Log Analytics telemetry for conditions such as device availability, database growth, and Retail Server performance
- **Alert Investigation Topics**: Gather diagnostic evidence and summarize likely causes for operator review
- **Notifications**: Deliver alert context and investigation findings to configured operational channels
- **Operator-Controlled Response**: Alerts do not initiate automatic mitigation or device-changing actions

### 6. Device-Side Services and Installers

- **DatabaseMetricsService**: Collects Store Commerce offline SQL database metrics and writes Event ID 3000 records for AMA ingestion
- **EventLogSinkConfigService**: Monitors Store Commerce `config.json` and keeps informational event-log telemetry enabled
- **MSI Installer Projects**: WiX-based installers and deployment scripts for both Windows services

### 7. Networking

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
   - Import the Copilot Studio agent into your Power Platform environment using the solution zip file `StoreMonitoringAgent_1_0_0_26.zip` provided in the root of this repository. See [Step 7 in the Quick Start guide](docs/quick-start-portal.md#step-7-setup-copilot-studio-agent-5-minutes) for detailed instructions.

## Documentation

| Document                                                                              | Description                                                          |
| ------------------------------------------------------------------------------------- | -------------------------------------------------------------------- |
| [Quick Start Guide - Azure Portal](docs/quick-start-portal.md)                        | Step-by-step deployment guide using the Azure portal                 |
| [Architecture Documentation](docs/architecture.md)                                    | Solution architecture and component overview                         |
| [Device Onboarding Guide](docs/device-onboarding.md)                                  | Connect POS devices to Azure Arc and configure AMA                   |
| [Capturing Database Metrics to Log Analytics](docs/database-metrics-log-analytics.md) | Configure offline SQL database metrics collection                    |
| [Store Commerce App Update Procedure](docs/store-commerce-update.md)                  | Procedure for updating Store Commerce on monitored devices           |
| [Model Support](docs/model-support.md)                                                | Supported generative AI models for the Copilot Studio agent          |
| [Alert-Triggered Agent](docs/alert-triggered-agent.md)                                | Alert-triggered investigation pattern using Azure Monitor and Teams  |
| [Autonomous / Proactive Monitoring Setup](docs/autonomous-proactive-monitoring.md)    | Configure the Recurring Store Monitoring Agent Flow                  |
| [Known Limitations](docs/known-limitations.md)                                        | Current known limitations and workarounds                            |
| [Periodic Maintenance Guide](docs/periodic-maintenance.md)                            | Periodic rotation and expiration checks for secrets and certificates |
