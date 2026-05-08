# Store Commerce App Update Procedure

This guide covers the steps to follow when applying an update to the Dynamics 365 Store Commerce application on a POS device that is part of the Store Monitoring solution.

## Why This Matters

The Store Commerce installer may overwrite the `config.json` file located at:

```
C:\Program Files\Microsoft Dynamics 365\10.0\Store Commerce\Microsoft\contentFiles\Pos\config.json
```

This file contains the `Diagnostics.Sinks.WebViewEventLogSink` configuration that enables Store Commerce events to flow to the Windows Event Log — which is required for Azure Monitor Agent (AMA) to collect and forward events to Log Analytics.

If the update resets or removes the EventLog sink configuration, monitoring data will stop flowing until the configuration is restored.

## Update Steps

### 1. Apply the Store Commerce Update

Install the Store Commerce update as directed by your organization's update process. This may involve running the Store Commerce installer or applying a servicing update from Lifecycle Services (LCS).

### 2. Restart the EventLogSinkConfigService

After the update completes, restart the **EventLogSinkConfigService** so it immediately validates and repairs the `config.json` if the update overwrote the EventLog sink settings.

#### Using Windows Services (recommended)

1. Press **Win + R**, type `services.msc`, and press **Enter**
2. In the Services window, scroll down and locate **EventLogSinkConfigService**
3. Right-click the service and select **Restart**
4. Wait for the service status to return to **Running**

#### Using the configure script (alternative)

```powershell
& "$env:ProgramFiles\StoreMonitoring\EventLogSinkConfigService\Configure-Service.ps1"
```

> **Note:** The EventLogSinkConfigService runs on a 24-hour interval by default. Without a manual restart, it could take up to a full day before it detects and fixes a missing or incorrect EventLog sink configuration.

### 3. Verify the Configuration Was Restored

Check the Windows Event Log for confirmation that the service validated (and, if needed, repaired) the configuration:

1. Open **Event Viewer** (`eventvwr.msc`)
2. Navigate to **Windows Logs > Application**
3. Filter by Source: **EventLogSinkConfigService**
4. Look for one of the following events:
   - **Event ID 3000 (ConfigValid)** — The EventLog sink is correctly configured. No action was needed.
   - **Event ID 3002 (ConfigUpdated)** — The EventLog sink was missing or incorrect and has been repaired.
   - **Event ID 3001 (ConfigInvalid)** — A problem was detected. Review the event details for specifics.

### 4. Confirm Monitoring Data Is Flowing

After the configuration is verified, confirm that event data is reaching Log Analytics:

1. Open the **Azure Portal** → **Log Analytics workspace**
2. Run a quick KQL query to check for recent events from the device:
   ```kql
   Event
   | where Computer == "<device-name>"
   | where TimeGenerated > ago(1h)
   | take 10
   ```
3. If no results appear after 10–15 minutes, check that the Azure Monitor Agent is running on the device:
   ```powershell
   Get-Service -Name "AzureMonitorAgent"
   ```

## Troubleshooting

| Symptom                                  | Possible Cause                                     | Resolution                                                                                                               |
| ---------------------------------------- | -------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------ |
| EventLogSinkConfigService fails to start | Service not installed or was removed by the update | Reinstall the service using the MSI installer (see [installer-eventlogsink README](../installer-eventlogsink/README.md)) |
| Event ID 3001 (ConfigInvalid) persists   | `config.json` structure changed in the new version | Check the `config.json` for the expected `Diagnostics.Sinks.WebViewEventLogSink` section and update manually if needed   |
| No events in Log Analytics               | AMA not running or DCR misconfigured               | Verify AMA service status and check Azure Policy compliance for the device                                               |
