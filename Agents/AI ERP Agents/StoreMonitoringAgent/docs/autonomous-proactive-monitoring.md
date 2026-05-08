# Autonomous / Proactive Monitoring Setup

This guide explains how to configure the **Recurring Store Monitoring Agent** Agent Flow that automatically triggers the Copilot Studio Agent on a schedule and posts the monitoring report to a Microsoft Teams channel.

## Overview

The Store Monitoring solution includes a proactive monitoring flow that runs on a recurring schedule without any user interaction. This enables IT teams to receive daily health reports directly in a Teams channel, ensuring that issues with POS devices are surfaced even when no one is actively querying the agent.

```
┌────────────────────┐         ┌──────────────────────────┐         ┌─────────────────┐
│  Agent Flow        │  ──►    │  Copilot Studio Agent    │  ──►    │  Teams Channel   │
│  Recurrence Trigger│         │  "create a report for    │         │  (Daily Report)  │
│  (Daily @ 17:00)   │         │   all devices"           │         │                  │
└────────────────────┘         └──────────────────────────┘         └─────────────────┘
```

### How It Works

1. **Recurrence trigger** fires once per day (default: 17:00 UTC)
2. The flow invokes the Copilot Studio Agent using the **Microsoft Copilot Studio** connector with the prompt `"create a report for all devices"`
3. The agent processes the request across all its topics — gathering application errors, hardware station errors, retail server errors, device online/offline status, and database metrics
4. The agent's final response is posted to a designated **Microsoft Teams channel** as an HTML message via the **Teams** connector

## Prerequisites

- [ ] Store Monitoring Agent imported and published in Copilot Studio (see [Quick Start](quick-start-portal.md))
- [ ] Microsoft Teams with a target channel for receiving reports
- [ ] Connection references configured for:
  - **Microsoft Copilot Studio** (to execute the agent)
  - **Microsoft Teams** (to post messages)

## Setup Instructions

### Step 1: Import the Solution

If you haven't already imported the Store Monitoring Agent solution:

1. Go to [Power Apps Maker Portal](https://make.powerapps.com)
2. Select your environment
3. Click **Solutions** → **Import solution**
4. Upload the `StoreMonitoringAgent` solution `.zip` file
5. Click **Next** → **Import**

The solution includes both the agent and the recurring flow (`Recurring store monitoring agent all`).

### Step 2: Configure Connection References

After import, you must configure the connection references used by the flow:

1. In the **Solutions** list, open the **Store Monitoring Agent** solution
2. Click **Connection References** in the left navigation
3. Configure each connection:

| Connection Reference                       | Connector                | Purpose                             |
| ------------------------------------------ | ------------------------ | ----------------------------------- |
| `cr91d_sharedmicrosoftcopilotstudio_59cc8` | Microsoft Copilot Studio | Invokes the agent asynchronously    |
| `new_sharedteams_88fd9`                    | Microsoft Teams          | Posts the report to a Teams channel |

4. For each reference, click **Edit** → select or create a connection → **Save**

> 💡 **Tip:** The Teams connection must be authenticated with an account that has permission to post to the target channel.

### Step 3: Get Your Teams Channel IDs

The flow requires the **Group ID** (Team ID) and **Channel ID** of the Teams channel where reports will be posted.

**From Copilot Studio**

1. Edit the Agent Flow in Copilot Studio
2. Click on the **Post message in a chat or channel** action
3. Use the dropdown pickers for **Team** and **Channel** — the IDs will be populated automatically

### Step 4: Configure the Recurring Agent Flow

1. Go to [Copilot Studio](https://copilotstudio.microsoft.com)
2. Open your **Store Monitoring Agent**
3. In the left navigation, click **Flows**
4. Find the flow named **Recurring store monitoring agent all**
5. Click **Edit**

#### Update Teams Channel

5. Click the **Post message in a chat or channel** action
6. Set the following values:

| Property    | Value                                                |
| ----------- | ---------------------------------------------------- |
| **Post as** | Flow bot                                             |
| **Post in** | Channel                                              |
| **Team**    | Select your target team (or paste the Group ID)      |
| **Channel** | Select your target channel (or paste the Channel ID) |

#### Update Recurrence Schedule (Optional)

7. Click the **Recurrence** trigger at the top of the flow
8. Adjust the schedule as needed:

| Property       | Default Value          | Description                |
| -------------- | ---------------------- | -------------------------- |
| **Frequency**  | Day                    | How often the flow runs    |
| **Interval**   | 1                      | Every 1 day                |
| **Start Time** | `2026-02-09T17:00:00Z` | First execution time (UTC) |

> ⏰ **Schedule Examples:**
>
> | Scenario                 | Frequency | Interval | Start Time             |
> | ------------------------ | --------- | -------- | ---------------------- |
> | Daily at 5 PM UTC        | Day       | 1        | `2026-02-09T17:00:00Z` |
> | Every 12 hours           | Hour      | 12       | `2026-02-09T06:00:00Z` |
> | Every Monday at 9 AM UTC | Week      | 1        | `2026-02-09T09:00:00Z` |
> | Every 6 hours            | Hour      | 6        | `2026-02-09T00:00:00Z` |

9. Click **Save**

### Step 5: Turn On the Flow

1. Return to the flow details page
2. Ensure the flow status shows **On**
3. If it shows **Off**, click **Turn on** in the command bar
