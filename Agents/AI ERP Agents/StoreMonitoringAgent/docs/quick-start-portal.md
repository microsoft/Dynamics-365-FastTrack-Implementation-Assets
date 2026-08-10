# Quick Start Guide - Azure Portal

A streamlined guide for deploying the Store Monitoring solution using the Azure Portal.

## 📋 Prerequisites Checklist

- [ ] Azure subscription with Owner/Contributor role
- [ ] Access to POS devices (local admin)
- [ ] Copilot Studio with Agents enabled

## Quick Setup

### Step 1: Create Resources (5 minutes)

**Resource Group:**

1. Portal → Resource groups → Create
2. Name: `rg-store-monitoring`
3. Region: `East US`

**Log Analytics Workspace:**

1. Search "Log Analytics" → Create
2. Name: `law-store-monitoring`
3. **📝 Save Workspace ID and Primary Key**

**Service Principal:**

1. Azure AD → App registrations → New
2. Name: `sp-arc-onboarding`
3. Create client secret:
   - Certificates & secrets → New client secret
   - Description: `Arc onboarding`
   - Expires: 24 months
   - **📝 Save: App ID, Tenant ID, Secret Value**

**Assign Roles:**

These roles allow the service principal to register devices and deploy monitoring agents:

- **Azure Connected Machine Onboarding**: Allows devices to register with Azure Arc
- **Monitoring Contributor**: Allows deploying Azure Monitor Agent (AMA) extension to devices

Steps:

1. Go to Resource Group → `rg-store-monitoring`
2. Click **Access control (IAM)** in left menu
3. Click **+ Add** → **Add role assignment**
4. Search and select **Azure Connected Machine Onboarding**
5. Click **Next**
6. Click **+ Select members**
7. Search for `sp-arc-onboarding`
8. Select it → **Select**
9. Click **Review + assign** (twice)
10. Repeat steps 3-9 for **Monitoring Contributor** role

### Step 2: Onboard Devices (10 minutes)

**Generate Script:**

1. Search for **Azure Arc** in the portal
2. Click **Azure Arc** service
3. In the left menu under **Infrastructure**, click **Machines**
4. Click **+ Add/Create** → **Add a machine**
5. Select **Onboard existing machine** (or **Add a single server**)
6. Fill in:
   - Resource group: `rg-store-monitoring`
   - Region: Same as resource group
   - Operating system: **Windows**
   - **Connectivity method**: Public endpoint (default)
   - **Authentication**:
     - **Service principal** (recommended for bulk/automated deployment)
       - Enter the App ID, Tenant ID, and Client Secret from Step 1
       - This allows unattended authentication - no user login required
     - _Alternative: "Interactive" for single device testing (requires manual Azure login on device)_
   - **Authenticate machines automatically**: Leave unchecked (service principal handles authentication)
7. Optionally add tags (Location, Environment, Role)
8. Click **Generate script** (or **Download and run script**)
9. **Copy** the entire PowerShell script

**On Each POS Device:**

```powershell
# Run as Administrator
# Paste the generated script
```

**Verify:**

- Azure Arc → Machines → See your devices

### Step 3: Configure Data Collection (10 minutes)

**Create DCE:**

1. Monitor → Data Collection Endpoints → Create
2. Name: `dce-store-monitoring`

**Create DCR:**

1. Search for **Monitor** in the portal
2. Under **Settings**, click **Data Collection Rules**
3. Click **+ Create**
4. **Basics** tab:
   - Rule name: `dcr-windows-events`
   - Subscription: Your subscription
   - Resource group: `rg-store-monitoring`
   - Region: Same as resource group
   - Platform Type: **Windows**
   - Data Collection Endpoint: Select `dce-store-monitoring`
   - Click **Next: Resources**
5. **Resources** tab:
   - Click **+ Add resources**
   - Expand your subscription → resource group
   - Check **Enable Data Collection Endpoints**
   - Select your Arc-enabled machines (POS devices)
   - Click **Apply**
   - Click **Next: Data sources**
6. **Data sources** tab - Add Windows Event Logs:
   - Click **+ Add data source**
   - Data source type: **Windows Event Logs**
   - **Custom** tab (for filtering specific providers):
     - Click **Custom**
     - Add XPath query:
       ```xpath
       Application!*[System[Provider[@Name='Microsoft Dynamics - Store Commerce'] and (Level=1 or Level=2 or Level=3)]]
       ```
       _(This filters Critical (Level=1), Error (Level=2), and Warning (Level=3) from Store Commerce)_
     - Add additional XPath queries:
       ```xpath
       Application!*[System[Provider[@Name='Microsoft Dynamics - Store Commerce'] and EventID=40253]]
       ```
       _(Store Commerce Event ID 40253 — used for targeted Store Commerce diagnostics)_
       ```xpath
       Application!*[System[Provider[@Name='Microsoft Dynamics - Store Commerce'] and EventID=40102]]
       ```
       _(Store Commerce Event ID 40102 — used for Retail Server performance diagnostics)_
       ```xpath
       Application!*[System[Provider[@Name='DatabaseMetricsService'] and (EventID=3000)]]
       ```
       _(Database Metrics Service — used by DatabaseMetrics topic)_
       ```xpath
       Application!*[System[Provider[@Name='EventLogSinkConfigService']]]
       ```
       _(EventLog Sink Config Service — used for config monitoring)_
   - Click **Next: Destination**
   - Destination type: **Azure Monitor Logs**
   - Subscription: Your subscription
   - Account or namespace: Select `law-store-monitoring`
   - Click **Add data source**
7. **Data sources** tab - Add Performance Counters:
   - Click **+ Add data source** (again)
   - Data source type: **Performance Counters**
   - Sample rate: **86400 seconds** _(once per day - use 60 for once per minute, 300 for 5 minutes)_
   - Click **Add** next to each counter:
     - `\Processor(_Total)\% Processor Time`
     - `\Memory\Available Bytes`
   - Click **Next: Destination**
   - Destination type: **Azure Monitor Logs**
   - Select `law-store-monitoring`
   - Click **Add data source**
8. Click **Review + create**
9. Click **Create**

### Step 4: Enable Auto-Deployment (3 minutes)

**Assign Policy:**

This policy automatically deploys AMA to all Arc-enabled devices and links them to your DCR.

1. Search for **Policy** in the portal
2. Click **Assignments** in the left menu
3. Click **Assign policy** at the top
4. **Basics** tab:
   - Click **...** button next to **Policy definition**
   - Search: `Configure Windows Arc-enabled machines to run Azure Monitor Agent`
   - Select it and click **Select**
   - **Scope**: Click **...** button
     - Select your subscription
     - Select resource group: `rg-store-monitoring`
     - Click **Select**
   - **Assignment name**: Auto-generated (or customize)
   - **Policy enforcement**: Enabled
   - Click **Next**
5. **Parameters** tab:
   - Leave **Effect** at "DeployIfNotExists"
   - Click **Next**

   **After policy is created, you'll manually associate the DCR with your Arc machines:**

   **Option A - Via Azure Portal (Easiest):**
   1. Go to **Monitor** → **Data Collection Rules**
   2. Click on `dcr-windows-events`
   3. Click **Resources** in the left menu
   4. Click **+ Add**
   5. Expand your subscription → resource group `rg-store-monitoring`
   6. Check the boxes next to all your Arc-enabled machines
   7. Click **Apply**

   _This associates all selected Arc machines with the DCR in one step._

6. **Remediation** tab:

- Check ✅ **Create a remediation task** (deploys the policy action to Arc-enabled devices that already exist in the selected scope)
- Click **Next**

7. **Managed Identity** tab:
   - **Permissions**: Select **System assigned managed identity**
   - **Managed Identity Location**: Same region as resource group (e.g., East US)
   - Click **Next**

8. **Review + create** tab:
   - Review settings
   - Click **Create**

9. **Assign role to managed identity** (required):
   - After policy is created, go to your **Resource Group**
   - Click **Access control (IAM)**
   - Click **+ Add** → **Add role assignment**
   - Select **Monitoring Contributor**
   - Click **Next**
   - Click **+ Select members**
   - Search for your policy assignment name
   - Select the managed identity → **Select**
   - Click **Review + assign** (twice)

**Wait for policy to apply** (10-15 minutes):

- Go to **Policy** → **Compliance**
- Find your assignment
- Check compliance status (will show "Non-compliant" initially, then "Compliant" after remediation)

### Step 5: Install Database Metrics Service (5 minutes per device)

The Database Metrics Service is a Windows service that collects SQL Server database metrics (size, table sizes, index sizes) and writes them to the Windows Event Log, where AMA picks them up and sends them to Log Analytics.

**Option 1: Using the MSI Installer (Recommended)**

1. Build the installer (if not already built):
   ```powershell
   cd installer\scripts
   .\build-installer.ps1
   ```
2. Copy the generated `.msi` file to each POS device
3. Run the installer on each device:
   ```cmd
   msiexec /i DatabaseMetricsService.Installer.msi
   ```
4. Follow the wizard:
   - Accept the license agreement
   - Choose the installation directory (default: `C:\Program Files\StoreMonitoring\DatabaseMetricsService`)
   - Enter the **SQL Server instance** (e.g., `localhost`, `.\SQLEXPRESS`)
   - Enter the **Database name** (e.g., `RetailOfflineDatabase`)
5. The installer will create and start the Windows service (runs as Virtual Service Account `NT SERVICE\DatabaseMetricsService`)

6. **Grant SQL permissions** (required post-install step):
   ```powershell
   .\Grant-SqlPermissions.ps1 -SqlServer "localhost" -DatabaseName "RetailOfflineDatabase"
   ```
   This creates the SQL login for the service account and grants `VIEW SERVER STATE`, `VIEW ANY DATABASE`, `VIEW DATABASE STATE`, and `VIEW DEFINITION`.
   The script is located in the installer `scripts\` folder.

**Option 2: Silent Installation**

```cmd
msiexec /i DatabaseMetricsService.Installer.msi /quiet ^
    SQL_SERVER=localhost ^
    DATABASE_NAME=RetailOfflineDatabase ^
    INSTALLFOLDER="C:\Program Files\StoreMonitoring\DatabaseMetricsService"
```

**Verify:**

- Open **Services** (`services.msc`) → Look for **Database Metrics Service** (should be Running)
- Open **Event Viewer** → **Application** log → Look for events from source `DatabaseMetricsService`

> **Important:** After silent installation, you must still run `Grant-SqlPermissions.ps1` to configure SQL access for the service.

> 📖 For full build instructions, troubleshooting, and uninstall steps, see the [Installer README](../installer/README.md).

### Step 6: Install EventLog Sink Config Service (5 minutes per device)

The EventLog Sink Config Service is a Windows service that monitors the Store Commerce `config.json` and ensures the `WebViewEventLogSink` is configured with the correct `EventLevel` (Informational). This is required so that Store Commerce diagnostic events are written to the Windows Event Log, where AMA picks them up and sends them to Log Analytics.

**Option 1: Using the MSI Installer (Recommended)**

1. Build the installer (if not already built):
   ```powershell
   cd installer-eventlogsink\scripts
   .\build-installer.ps1
   ```
2. Copy the generated `.msi` file to each POS device
3. Run the installer on each device:
   ```cmd
   msiexec /i EventLogSinkConfigService.Installer.msi
   ```
4. Follow the wizard:
   - Accept the license agreement
   - Choose the installation directory (default: `C:\Program Files\StoreMonitoring\EventLogSinkConfigService`)
5. The installer will create and start the Windows service

**Option 2: Silent Installation**

```cmd
msiexec /i EventLogSinkConfigService.Installer.msi /qn
```

**Post-Install Configuration (optional):**

The service uses default settings that work for standard Store Commerce installations. To customize:

```powershell
cd "C:\Program Files\StoreMonitoring\EventLogSinkConfigService"
.\Configure-Service.ps1 -ConfigFilePath "C:\path\to\config.json" -CollectionIntervalMinutes 720
```

Default settings in `appsettings.json`:

- **ConfigFilePath**: `C:\Program Files\Microsoft Dynamics 365\10.0\Store Commerce\Microsoft\contentFiles\Pos\config.json`
- **CollectionIntervalMinutes**: `1440` (24 hours)

**Verify:**

- Open **Services** (`services.msc`) → Look for **EventLog Sink Config Service** (should be Running)
- Open **Event Viewer** → **Application** log → Look for events from source `EventLogSinkConfigService`

> 📖 For full build instructions, troubleshooting, and uninstall steps, see the [EventLog Sink Config Installer README](../installer-eventlogsink/README.md).

### Step 7: Setup Copilot Studio Agent (5 minutes)

**Import Power Platform Solution:**

1. Go to [Power Platform Admin Center](https://admin.powerplatform.microsoft.com)
2. Select your environment
3. Go to [Copilot Studio](https://copilotstudio.microsoft.com)
4. Click **Solutions** in the left menu
5. Click **Import solution**
6. Browse to the `StoreMonitoringAgent_1_0_0_25.zip` file provided in the root of this repository.
7. On the **Connections** page, map the **Azure Monitor Logs** connection reference to an existing connection or create one. Sign in with an account that has permission to query the Log Analytics workspace.
8. If prompted for the optional `SMAAlertObjectId` environment variable, keep the imported value or enter a temporary GUID. This value is not a secret and is only used by the optional alert-triggered flows. Replace it with the correct object ID when completing [Step 8](#step-8-optional---enable-autonomous-alert-capabilities).
9. Click **Next** → **Import** and wait for the import to complete.

**Configure the Log Analytics cloud flow:**

1. Open the imported solution, select **Cloud flows**, and open **RunLogAnalyticsQuery**.
2. Select **Edit**, expand **Run query and list results**, and configure these fields for the workspace created in Step 1:

| Field          | Value                                                                 |
| -------------- | --------------------------------------------------------------------- |
| Subscription   | Azure subscription containing the Log Analytics workspace             |
| Resource group | Resource group containing the workspace                               |
| Resource type  | `Log Analytics Workspace`                                             |
| Resource name  | Log Analytics workspace resource name, such as `law-store-monitoring` |

> **Note:** **Resource name** is the workspace name, not the Workspace ID saved in Step 1. The `query` and `timespan` inputs are supplied by the agent at runtime and do not require post-import values.

3. Confirm that **Run query and list results** uses the imported **Azure Monitor Logs** connection reference.
4. Click **Save**, run the flow checker, and turn on the flow if it is disabled.
5. Return to Copilot Studio, open **Store Monitor Agent**, and use the test pane to submit a monitoring prompt. Confirm that the agent returns data, then check the **RunLogAnalyticsQuery** run history and verify that **Run query and list results** succeeded.
6. Click **Publish** to activate the agent.

> 💡 **Tip:** To capture Database Metrics Service events in Log Analytics, add a custom XPath filter to your DCR. See [Database Metrics Log Analytics Guide](database-metrics-log-analytics.md) for instructions.

### Step 8: Optional - Enable Autonomous Alert Capabilities

After the agent, Log Analytics workspace, and data collection are working, you can add autonomous alert-triggered investigations. This optional setup uses Azure Monitor scheduled query alerts to trigger the Store Monitoring Agent, generate an investigation summary, and post the result to Teams.

Use the alert documentation for the full setup:

- [Alert-Triggered Agent](alert-triggered-agent.md) - architecture, supported alert types, Agent Flow actions, prompt routing, Teams notification setup, deployment scripts, parameters, and validation checklist

## 🔧 Common Issues

### No Devices in Arc

- Check firewall allows HTTPS:443 outbound
- Verify service principal permissions
- Re-run onboarding script

### No Data in Log Analytics

- Wait 15 minutes after setup
- Check Policy compliance
- Verify AMA extension installed (Arc → Machines → Extensions)

### Agent Not Returning Results

- Check the **Azure Monitor Logs** connection reference in the imported solution
- Verify the subscription, resource group, and workspace resource name in **RunLogAnalyticsQuery**
- Test KQL query manually in Log Analytics portal
- Ensure Agent has proper permissions to query workspace
