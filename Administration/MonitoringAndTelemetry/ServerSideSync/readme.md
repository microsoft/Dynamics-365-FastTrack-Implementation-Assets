# Server-Side Synchronization (SSS) Monitoring — ADX/AI Logs Dashboard

A ready-to-use Azure Data Explorer (ADX) dashboard over Dataverse Application Insights telemetry to monitor **Server-Side Synchronization (SSS)** health: incoming email, outgoing email and appointments/contacts/tasks (ACT) sync volumes, latency, failures, retries and per-mailbox behavior.

---

## Prerequisites

- [Dataverse Application Insights export](https://learn.microsoft.com/power-platform/admin/set-up-export-application-insights) enabled for the environment(s) using Server-Side Synchronization.
- Access to [Azure Data Explorer dashboards](https://dataexplorer.azure.com/dashboards) with read permissions on the Application Insights resource.

The dashboard reads the `traces` table, filtering on the SSS telemetry messages below (fields are read from `customDimensions`):

| Message | Sync type |
|---|---|
| `LogIncomingEmailItemStatForAppInsights` | Incoming email |
| `LogOutgoingEmailItemStatForAppInsights` | Outgoing email |
| `LogAppointmentContactTaskItemStatForAppInsights` | Appointments, contacts and tasks (ACT) |

The Cross-Metric page also uses `pageViews` and `dependencies` for form load and plug-in performance.

---

## Steps to import the sample dashboard

1. In [Azure Data Explorer dashboards](https://dataexplorer.azure.com/dashboards), select **New dashboard** > **Import dashboard from file** and choose `dashboard-ServerSideSync Monitoring.json`.
2. Name the dashboard and open the **Data sources** pane.
3. Edit the `DV` data source and replace `<SubscriptionId>` in the cluster URI with the subscription ID that contains your Application Insights resource:
   `https://ade.applicationinsights.io/subscriptions/<SubscriptionId>`
4. Select **Connect**, choose your Application Insights resource from the database list (replacing `<AppInsightsName>`) and save.
5. Use the **Time range** parameter (default: last 24 hours) to scope all tiles. Feel free to edit the queries to suit your needs.

---

## Dashboard pages

### 1. SSS Statistics
High-level overview of all sync types.

| Tile | Description |
|---|---|
| Incoming / Outgoing / ACT Scenarios | Distribution of items by scenario (e.g. track option, status). |
| Incoming / Outgoing / ACT Mailboxes | Mailboxes that synced items and their last activity. |
| Outgoing sync time P95 | 95th percentile outgoing email sync time. |
| CloudSSS Outgoing / ACT / Incoming Sync delays | Sync delays per sync type. Incoming only counts emails actually synced to D365. |
| CloudSSS Outgoing delayed messages | Column chart of delayed outgoing messages over time. |

### 2. Incoming Email
| Tile | Description |
|---|---|
| 1.1 Full Field Extraction | All parsed fields for incoming email telemetry. |
| 1.2 Summary by Track Option | Volume by track option (AutoTrack, ManualTrack, FolderBasedTrack, ...). |
| 1.3 Failure Analysis | Failed items and error details. |
| 1.4 Sync Latency | Time to sync from the remote mail server. |
| 1.5 Sync Latency Trend | Latency in 10-minute buckets. |
| 1.6 Volume by Hour | Hourly incoming volume. |
| 1.7 Attachment Analysis | Attachment counts and sizes. |

### 3. Outgoing Email
| Tile | Description |
|---|---|
| 2.1 Full Field Extraction | All parsed fields for outgoing email telemetry. |
| 2.2 Summary by Status | Volume by send status. |
| 2.3 Sync Latency (P95) | Outgoing latency percentiles. |
| 2.4 Sync Latency Trend | Latency in 10-minute buckets. |
| 2.5 Retry Analysis | Items requiring retries. |
| 2.6 Per-Mailbox Performance | Volume and latency per mailbox. |
| 2.7 Failure Details | Failed items and error details. |

### 4. ACT (Appointments, Contacts, Tasks)
| Tile | Description |
|---|---|
| 3.1 Full Field Extraction | All parsed fields for ACT telemetry. |
| 3.2 Summary by Entity Type | Volume by entity (appointment, contact, task). |
| 3.3 Sync Scenario Analysis | Volume by sync scenario. |
| 3.4 Sync Latency by Entity Type | Latency per entity type. |
| 3.5 Error Analysis | Errors and error codes. |
| 3.6 Sync Direction Analysis | CRM-initiated vs. remote-initiated sync. |

### 5. Cross-Metric
| Tile | Description |
|---|---|
| 4.1 Overall SSS Health Summary | Volume, failures and error rate across all sync types. |
| 4.2 Active Syncing Mailboxes Count | Distinct mailboxes actively syncing. |
| 4.3 Sync Volume Trend | Hourly volume for all sync types. |
| 4.4 Error Rate Trend | Hourly error rate for all sync types. |
| 4.5 Top Error Codes | Most frequent error codes across all sync types. |
| 4.6 Email Service Client Type Distribution | Volume by email service client type. |
| 4.7 Loopback Detection | Heartbeat/loopback mailbox activity. |
| 4.8 Page Views - Form Load Performance | Form load times (from `pageViews`). |
| 4.9 / 4.10 Plugin Performance / Failure Rate | Plug-in duration and failure rate (from `dependencies`). |

---

## Interpreting the dashboard

- Start with **SSS Statistics** and **4.1 Overall SSS Health Summary** to spot which sync type is degraded.
- Use the **latency trend** tiles to identify when delays started, then the **failure / error** tiles to find the cause.
- Use the **per-mailbox** tiles to determine whether an issue is isolated to specific mailboxes or affects the whole environment.
- Review **4.5 Top Error Codes** against the [Server-Side Synchronization troubleshooting guidance](https://learn.microsoft.com/power-platform/admin/troubleshooting-monitoring-server-side-synchronization).
