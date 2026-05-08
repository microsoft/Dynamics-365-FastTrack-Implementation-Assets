# Capturing Database Metrics Service Events to Log Analytics

This guide shows how to configure Azure Monitor Agent to capture custom Windows Event Viewer logs from the `DatabaseMetricsService` event source and send them to Log Analytics workspace.

## Overview

The DatabaseMetricsService writes metrics reports to the Windows Event Viewer (Application log) with Event IDs:

- **1000**: Service started
- **1001**: Service stopped
- **2000**: Metrics collection started
- **2001**: Metrics collection completed
- **3000**: Metrics report (main data)
- **4000**: SQL error
- **4001**: General error

These events will be captured and stored in a custom table in Log Analytics.

## Prerequisites

- DatabaseMetricsService installed on POS devices (runs as Virtual Service Account `NT SERVICE\DatabaseMetricsService`)
- SQL permissions granted via `Grant-SqlPermissions.ps1` (see [Installer README](../installer/README.md))
- Azure Arc-enabled machines
- Azure Monitor Agent (AMA) deployed
- Log Analytics workspace created
- Existing Data Collection Rule (DCR)

## Configuration Steps

### Update Existing DCR via Azure Portal

#### Step 1: Navigate to Data Collection Rule

1. Go to [Azure Portal](https://portal.azure.com)
2. Search for **Monitor**
3. Click **Data Collection Rules** under Settings
4. Click on your existing DCR (e.g., `dcr-windows-events`)

#### Step 2: Add Custom Event Source

1. In the DCR, click **Data sources** in the left menu
2. Click **+ Add** to add a new data source
3. **Data source type**: Select **Windows Event Logs**
4. **Configure custom logs**:

   Under **Basic** tab, add a custom XPath query:

   ```xpath
   Application!*[System[Provider[@Name='DatabaseMetricsService']]]
   ```

   Or to filter specific Event IDs:

   ```xpath
   Application!*[System[Provider[@Name='DatabaseMetricsService'] and (EventID=3000 or EventID=4000 or EventID=4001)]]
   ```

5. Click **Next: Destination**

#### Step 3: Configure Destination

1. **Account or namespace**: Select your Log Analytics workspace (`law-store-monitoring`)
2. **Destination table**: The events will be stored in the `Event` table by default
3. Click **Add data source**
4. Click **Save**

## Modifying the Collection Recurrence

The DatabaseMetricsService collects metrics on a recurring interval controlled by the `CollectionIntervalMinutes` setting in `appsettings.json`. The default is **360 minutes (6 hours)**.

### Change the Collection Interval

1. On the POS device, open the configuration file:
   ```
   C:\Program Files\StoreMonitoring\DatabaseMetricsService\appsettings.json
   ```
2. Locate the `CollectionIntervalMinutes` property:
   ```json
   {
     "ConnectionStrings": {
       "DefaultConnection": "Server=localhost;Database=RetailOfflineDatabase;Integrated Security=True;Connection Timeout=30;Encrypt=Mandatory;TrustServerCertificate=True;"
     },
     "DatabaseName": "RetailOfflineDatabase",
     "ServerName": "localhost",
     "CollectionIntervalMinutes": 360
   }
   ```
3. Change `CollectionIntervalMinutes` to the desired value (in minutes):

   | Value  | Interval                |
   | ------ | ----------------------- |
   | `60`   | Every 1 hour            |
   | `120`  | Every 2 hours           |
   | `360`  | Every 6 hours (default) |
   | `720`  | Every 12 hours          |
   | `1440` | Once per day            |

4. Save the file
5. Restart the service for the change to take effect:
   ```powershell
   Restart-Service -Name "DatabaseMetricsService"
   ```

## Connection String Security

The default connection string uses `Encrypt=Mandatory;TrustServerCertificate=True;`. This configuration is intentional for the following reasons:

- **Encrypt=Mandatory** ensures all traffic between the service and SQL Server is encrypted via TLS, even though Microsoft.Data.SqlClient 5.x enables encryption by default. Making this explicit prevents regressions if the driver version changes.
- **TrustServerCertificate=True** is acceptable in this deployment because:
  - The connection is **localhost-only** — traffic never leaves the loopback adapter and is not exposed to network interception.
  - POS devices run **SQL Express with a self-signed certificate** that cannot be validated against a trusted CA.
  - Devices operate in **offline/disconnected environments** where provisioning and rotating CA-signed certificates is impractical.
  - **Windows Integrated Authentication** (no password in the connection string) provides identity verification independent of the TLS certificate.

> **Note:** If SQL Server is moved to a remote host or a network-accessible instance, `TrustServerCertificate` should be set to `False` and a CA-signed certificate should be configured on the SQL Server instance. See the [threat model](threat-model.md) for additional details.

````

## Verify Data Collection

### Step 1: Wait for Data

After configuring the DCR, wait 5-10 minutes for:

- DCR to propagate to devices
- AMA to start collecting events
- Data to flow to Log Analytics

### Step 2: Query Log Analytics

Run these KQL queries in Log Analytics workspace:

#### Check for DatabaseMetricsService Events

```kql
Event
| where Source == "DatabaseMetricsService"
| where TimeGenerated > ago(1h)
| project TimeGenerated, Computer, EventID, EventLevelName, RenderedDescription
| order by TimeGenerated desc
````

#### View Metrics Reports (Event ID 3000)

```kql
Event
| where Source == "DatabaseMetricsService"
| where EventID == 3000
| where TimeGenerated > ago(24h)
| project TimeGenerated, Computer, RenderedDescription
| order by TimeGenerated desc
```
