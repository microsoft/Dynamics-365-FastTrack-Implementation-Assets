# Alert-Triggered Agent

> ⚠️ **Status: In Progress (v2)**

This guide covers how to set up Azure Monitor alert rules for **Hardware Station Errors** and **Device Offline Detection**, and route them through the **Copilot Studio Store Monitoring Agent** for AI-enriched analysis before posting to a Microsoft Teams channel.

Instead of forwarding raw alert data, this approach triggers the Copilot Studio agent to **investigate the issue**, correlate with other data, and post an **AI-generated summary with recommendations** to Teams.

## Architecture Overview

```
KQL Query matches condition
        ↓
Azure Monitor Alert Rule fires
        ↓
Action Group triggers Webhook
        ↓
Copilot Studio Agent Flow receives webhook (HTTP trigger)
        ↓
Flow parses alert → builds contextual prompt
        ↓
Copilot Studio Agent investigates
  (queries Log Analytics, correlates data, generates summary)
        ↓
Posts AI-enriched report to Teams Channel
```

## Why Use the Agent for Alerts?

| Capability        | Agent-Enhanced Alert                                 |
| ----------------- | ---------------------------------------------------- |
| **Detection**     | Azure Monitor (real-time)                            |
| **Intelligence**  | AI analysis + context                                |
| **Teams message** | Rich AI summary with recommendations                 |
| **Correlation**   | Cross-references errors, offline status, performance |
| **Actionability** | Agent provides next steps                            |

## Prerequisites

- Azure subscription with a Log Analytics workspace
- Azure Arc-connected store devices sending heartbeat and event data
- Microsoft Copilot Studio
- Microsoft Teams channel for receiving alerts
- **Store Monitoring Agent** imported and published in Copilot Studio (see [Quick Start](quick-start-portal.md))
- **RunLogAnalyticsQuery** flow configured as an agent skill (see [Autonomous Proactive Monitoring](autonomous-proactive-monitoring.md))

---

## Step 1 — Create the Agent Flow in Copilot Studio

Agent Flows are created directly inside Copilot Studio and run in the context of your agent.

### 1.1 Create a New Agent Flow

1. Go to [copilotstudio.microsoft.com](https://copilotstudio.microsoft.com)
2. Open your **Store Monitoring Agent**
3. In the left navigation, click **Flows**
4. Click **+ Add a flow** → **Create new flow**
5. Name it: `Alert Triggered Agent`
6. For the trigger, select **When an HTTP request is received**

### 1.2 Configure the HTTP Trigger

Click on the trigger step and paste the following **Request Body JSON Schema**:

```json
{
  "type": "object",
  "properties": {
    "schemaId": { "type": "string" },
    "data": {
      "type": "object",
      "properties": {
        "essentials": {
          "type": "object",
          "properties": {
            "alertId": { "type": "string" },
            "alertRule": { "type": "string" },
            "severity": { "type": "string" },
            "signalType": { "type": "string" },
            "monitorCondition": { "type": "string" },
            "monitoringService": { "type": "string" },
            "alertTargetIDs": {
              "type": "array",
              "items": { "type": "string" }
            },
            "firedDateTime": { "type": "string" },
            "description": { "type": "string" }
          }
        },
        "alertContext": { "type": "object" }
      }
    }
  }
}
```

**Save** the flow — this generates the **HTTP POST URL**. Copy it for use in the Action Group.

### 1.3 Add a Condition to Build the Agent Prompt

Add a **Condition** step in the agent flow to generate the right prompt based on which alert fired:

1. Click **+ New step** → search **Condition**
2. Set the condition:
   - `triggerBody()?['data']?['essentials']?['alertRule']` **contains** `Hardware Station`

**If yes** (Hardware Station Errors):

1. Add a **Compose** action
2. Set **Inputs** to:

```
A hardware station error (EventID 40450) was detected at @{triggerBody()?['data']?['essentials']?['firedDateTime']}. Investigate hardware station errors across all devices in the last 15 minutes. Include error counts per device, error details, and recommendations to resolve the issues.
```

**If no** (Device Offline):

1. Add a **Compose** action
2. Set **Inputs** to:

```
A store device has been detected as offline for more than 5 minutes at @{triggerBody()?['data']?['essentials']?['firedDateTime']}. Check which devices are currently offline, how long they have been offline, and check for any related application or hardware station errors on those devices.
```

### 1.4 Execute the Copilot Studio Agent

After each branch of the condition, add the agent execution step:

1. Click **+ New step** → search **Microsoft Copilot Studio**
2. Select **Execute Agent and wait** (`ExecuteCopilotAsyncV2`)
3. Configure:
   - **Copilot**: `cr91d_storeMonitoringAgent`
   - **Message**: Select the **Output** from the Compose step (dynamic content)

The agent will use its existing topics (Hardware Station Errors, Application Errors, etc.) to query Log Analytics, correlate data across multiple signals, and generate a comprehensive summary.

### 1.5 Post the Agent Response to Teams

After the **Execute Agent and wait** step:

1. Click **+ New step** → search **Microsoft Teams**
2. Select **Post message in a chat or channel**
3. Configure:
   - **Post as**: Flow bot
   - **Post in**: Channel
   - **Team**: Select your team
   - **Channel**: Select your alert channel
   - **Message**:

```html
<h3>🚨 Store Monitoring Alert</h3>
<b>Alert Rule:</b> @{triggerBody()?['data']?['essentials']?['alertRule']}<br />
<b>Severity:</b> @{triggerBody()?['data']?['essentials']?['severity']}<br />
<b>Fired at:</b>
@{triggerBody()?['data']?['essentials']?['firedDateTime']}<br />
<hr />
<h4>🤖 Agent Investigation Report</h4>
@{outputs('Execute_Agent_and_wait')?['body/lastResponse']}
```

4. **Save** the agent flow

### Complete Agent Flow Summary

```
┌──────────────────────────────────────────┐
│  Copilot Studio Agent Flow               │
├──────────────────────────────────────────┤
│                                          │
│  ┌────────────────────────────────────┐  │
│  │  When an HTTP request is received  │  │
│  │  (Webhook from Azure Monitor)      │  │
│  └──────────────┬─────────────────────┘  │
│                 ↓                         │
│  ┌────────────────────────────────────┐  │
│  │  Condition: alertRule contains     │  │
│  │  "Hardware Station"?               │  │
│  └──────┬──────────────────┬──────────┘  │
│         ↓ Yes              ↓ No          │
│  ┌──────────────┐   ┌────────────────┐   │
│  │ Compose:     │   │ Compose:       │   │
│  │ HW error     │   │ Device offline │   │
│  │ prompt       │   │ prompt         │   │
│  └──────┬───────┘   └───────┬────────┘   │
│         ↓                   ↓            │
│  ┌────────────────────────────────────┐  │
│  │  Execute Agent and wait            │  │
│  │  (Agent investigates via topics)   │  │
│  └──────────────┬─────────────────────┘  │
│                 ↓                         │
│  ┌────────────────────────────────────┐  │
│  │  Post message in Teams channel     │  │
│  │  (Alert header + Agent response)   │  │
│  └────────────────────────────────────┘  │
│                                          │
└──────────────────────────────────────────┘
```

---

## Step 2 — Create the Action Group

1. Go to **Azure portal** → **Monitor** → **Action groups** → **+ Create**
2. **Basics**:
   - **Resource group**: Your resource group
   - **Action group name**: `StoreMonitoring-Teams`
   - **Display name**: `SM-Teams`
3. Go to **Actions** tab:
   - **Action type**: Webhook
   - **Name**: `CopilotStudio-AgentFlow`
   - **URI**: Paste the **HTTP POST URL** from the Copilot Studio agent flow (Step 1.2)
   - ✅ Enable **Common alert schema**
4. Click **Review + create** → **Create**

---

## Step 3 — Create Alert Rules

### Alert Rule 1: Hardware Station Errors

Detects hardware station errors (EventID 40450) on store devices.

#### KQL Query

```kusto
Event
| where TimeGenerated > ago(5m)
| where EventLog == "Application"
| where EventLevelName in ("Error", "Critical")
| where EventID == 40450
| extend DeviceName = Computer, ErrorMessage = RenderedDescription
| project TimeGenerated, DeviceName, EventID, Source, ErrorMessage
```

#### Setup in Azure Portal

1. **Log Analytics workspace** → **Logs** → paste the query → click **+ New alert rule**
2. **Condition**:
   - **Measure**: Table rows
   - **Aggregation type**: Count
   - **Aggregation granularity**: 5 minutes
   - **Operator**: Greater than
   - **Threshold value**: 0
   - **Frequency of evaluation**: 5 minutes
3. **Actions** → Select `StoreMonitoring-Teams` action group
4. **Details**:
   - **Alert rule name**: `Store Monitoring - Hardware Station Errors`
   - **Severity**: Sev 1 - Error
   - **Description**: `Hardware station error (EventID 40450) detected on a store device`
   - ✅ Enable **common alert schema**
5. Click **Review + create** → **Create**

---

### Alert Rule 2: Device Offline Detection

Detects when an Arc-connected device has not sent a heartbeat for more than 5 minutes.

#### KQL Query

```kusto
let HeartbeatThreshold = 5m;
Heartbeat
| where ResourceProvider == "Microsoft.HybridCompute"
| summarize LastHeartbeat = max(TimeGenerated) by Computer, OSType
| where now() - LastHeartbeat > HeartbeatThreshold
| extend
    MinutesSinceLastHeartbeat = datetime_diff('minute', now(), LastHeartbeat),
    Status = "Offline"
| project
    Computer,
    Status,
    LastHeartbeat,
    MinutesSinceLastHeartbeat,
    OSType
```

#### Setup in Azure Portal

1. **Log Analytics workspace** → **Logs** → paste the query → click **+ New alert rule**
2. **Condition**:
   - **Measure**: Table rows
   - **Aggregation type**: Count
   - **Aggregation granularity**: 5 minutes
   - **Operator**: Greater than
   - **Threshold value**: 0
   - **Frequency of evaluation**: 5 minutes
3. **Actions** → Select `StoreMonitoring-Teams` action group
4. **Details**:
   - **Alert rule name**: `Store Monitoring - Device Offline`
   - **Severity**: Sev 2 - Warning
   - **Description**: `An Arc-connected store device has been offline for more than 5 minutes`
   - ✅ Enable **common alert schema**
5. Click **Review + create** → **Create**

---

## Step 4 — Testing

### Test the Action Group

1. In the Azure portal, go to **Monitor** → **Action groups**
2. Select `StoreMonitoring-Teams`
3. Click **Test** from the top toolbar
4. Select **Sample type**: Log search alert
5. Check **Webhook** and click **Test**
6. Verify the agent processes the alert and the AI-generated report appears in your Teams channel

### Test the Agent Flow Manually

1. In Copilot Studio, open the **Store Monitoring Agent** → **Flows** → `Alert Triggered Agent`
2. Click **Test** → **Manually** → **Test**
3. Send a sample payload using a tool like Postman or curl:

```json
{
  "schemaId": "azureMonitorCommonAlertSchema",
  "data": {
    "essentials": {
      "alertId": "/subscriptions/xxx/providers/Microsoft.AlertsManagement/alerts/test-001",
      "alertRule": "Store Monitoring - Hardware Station Errors",
      "severity": "Sev1",
      "signalType": "Log",
      "monitorCondition": "Fired",
      "monitoringService": "Log Alerts V2",
      "alertTargetIDs": [
        "/subscriptions/xxx/resourcegroups/rg-store-monitoring/providers/microsoft.operationalinsights/workspaces/law-store-monitoring"
      ],
      "firedDateTime": "2026-02-11T14:30:00.000Z",
      "description": "Hardware station error (EventID 40450) detected on a store device"
    },
    "alertContext": {}
  }
}
```

4. Verify the agent is triggered, investigates the issue, and posts the report to Teams

### Expected Teams Message

The Teams message will include:

- **Alert header**: Rule name, severity, and timestamp
- **Agent investigation report**: AI-generated summary including:
  - Which devices are affected
  - Error details and counts
  - Correlated issues (e.g., device also showing offline)
  - Recommendations for resolution

---

## Alert Rules Summary

| Alert Rule              | Triggers When           | Severity        | Frequency   |
| ----------------------- | ----------------------- | --------------- | ----------- |
| Hardware Station Errors | EventID 40450 detected  | Sev 1 (Error)   | Every 5 min |
| Device Offline          | No heartbeat for >5 min | Sev 2 (Warning) | Every 5 min |

---

## Combined Monitoring Strategy

This alert-triggered agent works alongside the existing daily proactive monitoring flow:

| Flow                                                                          | Purpose                                      | Trigger                                    | Teams Output              |
| ----------------------------------------------------------------------------- | -------------------------------------------- | ------------------------------------------ | ------------------------- |
| **Alert-Triggered Agent** (this guide)                                        | Real-time issue detection + AI investigation | On-demand (when Azure Monitor alerts fire) | AI investigation report   |
| **Daily Recurring Agent** ([setup guide](autonomous-proactive-monitoring.md)) | Daily health summary for the team            | Scheduled (daily at 17:00 UTC)             | Full device health report |

Together these provide:

- **Real-time alerting** — immediate notification when hardware errors occur or devices go offline
- **AI-powered investigation** — the agent automatically correlates data and provides actionable insights
- **Daily health visibility** — proactive reporting even when no alerts fire

---

## Adding More Alert Rules

To add new alert types (e.g., Application Errors, Retail Server Errors):

1. Create a new **alert rule** in the Log Analytics workspace with the appropriate KQL query
2. Attach the same `StoreMonitoring-Teams` **action group**
3. Update the **Condition** step in the agent flow to handle the new alert type with a contextual prompt
4. The agent will use its existing topics to investigate — no additional changes needed in Copilot Studio

### Example Prompts for Additional Alert Types

| Alert Rule           | Agent Prompt                                                                                                                                                                              |
| -------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Application Errors   | `"Application errors were detected at {firedDateTime}. Investigate application errors across all devices in the last 15 minutes. Include error sources, event IDs, and recommendations."` |
| Retail Server Errors | `"Retail server errors were detected at {firedDateTime}. Investigate retail server errors in the last 15 minutes, including error URLs and affected devices."`                            |
| Database Metrics     | `"Database performance issues were detected at {firedDateTime}. Check database metrics for the last 15 minutes and identify any bottlenecks."`                                            |

---

## Related Resources

- [hardware-station-errors.kql](../kql-queries/hardware-station-errors.kql) — Full hardware station error query
- [hardware-station-errors-count.kql](../kql-queries/hardware-station-errors-count.kql) — Error counts by device
- [arc-offline-history.kql](../kql-queries/arc-offline-history.kql) — Offline history and timeline
- [autonomous-proactive-monitoring.md](autonomous-proactive-monitoring.md) — Daily scheduled agent monitoring
- [quick-start-portal.md](quick-start-portal.md) — Copilot Studio agent setup
