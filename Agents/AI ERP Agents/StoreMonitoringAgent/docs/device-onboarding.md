# Device Onboarding Guide

This guide explains how to onboard new POS devices to the Store Monitoring solution after the initial deployment is complete.

## Overview

Once your Store Monitoring solution is deployed, adding new devices is straightforward. Devices automatically inherit:

- ✅ Azure Monitor Agent (AMA) deployment via Azure Policy
- ✅ Data Collection Rules (DCR) association
- ✅ Log Analytics workspace configuration
- ✅ Copilot Studio Agent access

## Prerequisites

Before onboarding new devices, ensure you have:

- [ ] Azure Arc infrastructure deployed (from initial setup)
- [ ] Service principal credentials (App ID, Tenant ID, Client Secret)
- [ ] Local administrator access on new POS devices
- [ ] Network connectivity from devices to Azure (HTTPS:443 outbound)

## Onboarding Methods

### Method 1: Reuse Existing Script (Fastest)

If you saved the Arc onboarding script from your initial deployment, you can reuse it for new devices.

**Steps:**

1. Locate the saved PowerShell script from initial deployment
2. On the **new POS device**, open **PowerShell as Administrator**
3. Paste and run the script:
   ```powershell
   # The script will look like this (don't copy this, use your generated one):
   # Invoke-WebRequest -Uri https://aka.ms/azcmagent-windows -OutFile AzureConnectedMachineAgent.msi
   # msiexec /i AzureConnectedMachineAgent.msi /qn /l*v install.log
   # azcmagent connect --service-principal-id "..." --service-principal-secret "..." ...
   ```
4. Wait for completion (typically 2-3 minutes)
5. Verify in Azure Portal → Azure Arc → Machines

**Advantages:**

- Fastest method for single or few devices
- No need to regenerate script
- Consistent configuration

### Method 2: Generate New Script via Portal

For new deployments or if you don't have the original script:

**Steps:**

1. Go to [Azure Portal](https://portal.azure.com)
2. Search for **Azure Arc**
3. Click **Machines** under **Infrastructure**
4. Click **+ Add/Create** → **Add a machine**
5. Select **Add a single server**
6. Configure the script:

   **Basics:**
   - **Subscription**: Your subscription
   - **Resource group**: `rg-store-monitoring`
   - **Region**: Same as your existing resources (e.g., East US)
   - **Operating system**: **Windows**

   **Connectivity:**
   - **Connectivity method**: Public endpoint (default)

   **Authentication:**
   - Select **Service principal** (recommended)
   - **Application (client) ID**: _(from `sp-arc-onboarding`)_
   - **Directory (tenant) ID**: _(your tenant ID)_
   - **Client secret**: _(from service principal)_

   **Tags (Optional but Recommended):**
   - `Location`: `Store-05`
   - `Environment`: `Production`
   - `Role`: `POS`
   - `DeviceType`: `Register` or `BackOffice`

7. Click **Generate script**
8. **Copy** the entire PowerShell script

9. On the **new POS device**:
   - Open **PowerShell as Administrator**
   - Paste the script
   - Press **Enter** to execute
   - Wait for completion

10. **Verify** the device appears:
    - Azure Portal → Azure Arc → Machines
    - Your new device should be listed with status "Connected"

## Bulk Onboarding

For onboarding multiple devices simultaneously:

### Option A: Shared Script Location

1. Save the Arc onboarding script to a network share:

   ```
   \\fileserver\deployment\arc-onboard.ps1
   ```

2. Create a deployment script that runs on each device:

   ```powershell
   # deploy-arc.ps1
   $scriptPath = "\\fileserver\deployment\arc-onboard.ps1"

   if (Test-Path $scriptPath) {
       Write-Host "Running Arc onboarding..."
       & $scriptPath
   } else {
       Write-Error "Script not found: $scriptPath"
   }
   ```

3. Deploy via:
   - **Group Policy**: Computer Configuration → Policies → Windows Settings → Scripts → Startup
   - **SCCM/ConfigMgr**: Create a package and deploy to device collections
   - **Intune**: Create a PowerShell script policy
   - **Remote execution**: Use `Invoke-Command` with PSRemoting

## Post-Onboarding Verification

After onboarding new devices, verify they're working correctly:

### 1. Check Azure Arc Status

**Via Azure Portal:**

1. Azure Portal → Azure Arc → Machines
2. Verify device is listed with status **Connected**
3. Check **Last heartbeat** is recent (< 5 minutes)

### 2. Verify Azure Monitor Agent Installation

**Wait 10-15 minutes** for Azure Policy to automatically deploy AMA.

**Via Azure Portal:**

1. Go to the Arc machine resource
2. Click **Extensions** in the left menu
3. Verify **AzureMonitorWindowsAgent** is installed and status is "Succeeded"

### 3. Verify Data Collection Rule Association

**Via Azure Portal:**

1. Monitor → Data Collection Rules
2. Click on `dcr-windows-events`
3. Click **Resources** in the left menu
4. Verify your new device is listed

**If not listed:**

Manually associate the DCR:

1. In the DCR, click **+ Add**
2. Select your new Arc machine
3. Click **Apply**

### 4. Check Data Flow to Log Analytics

Wait **5-10 minutes** after AMA installation for data to start flowing.

**Run KQL queries in Log Analytics:**

```kql
// Check if device is sending heartbeats
Heartbeat
| where Computer == "POS-STORE-05-01"
| where TimeGenerated > ago(1h)
| order by TimeGenerated desc
| take 10
```

```kql
// Check for application events
Event
| where Computer == "POS-STORE-05-01"
| where TimeGenerated > ago(1h)
| summarize EventCount = count() by EventLog
```

```kql
// Check for Store Commerce events
Event
| where Computer == "POS-STORE-05-01"
| where ProviderName == "Microsoft Dynamics - Store Commerce"
| where TimeGenerated > ago(24h)
| order by TimeGenerated desc
| take 20
```

```kql
// Check performance counters
Perf
| where Computer == "POS-STORE-05-01"
| where TimeGenerated > ago(1h)
| summarize count() by ObjectName, CounterName
```
