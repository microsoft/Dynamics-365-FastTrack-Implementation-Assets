# Payment Recon Agent — Deployment Guide

> **Version:** v4.1.0.0.16 &nbsp;|&nbsp; **Status:** Final &nbsp;|&nbsp; **Audience:** DevOps / Deployment Team
>
> Step-by-step deployment guide for the Payment Recon Agent. For a solution **overview**, see
> **[../README.md](../README.md)**. Follow **Steps 1–5** to deploy; reference detail (variants, resource
> details, connection references, manual/portal deployment, troubleshooting, package contents) is in
> the **Appendices**.

---

## Contents

- **[Deployment Steps 1–5](#deployment-steps)** ← start here
- **[Cleanup / Uninstall](#cleanup--uninstall)**
- [Appendix A — Deployment variants (Key Vault vs Direct)](#appendix-a--deployment-variants)
- [Appendix B — What gets deployed & resource naming](#appendix-b--what-gets-deployed--resource-naming)
- [Appendix C — Connection references (enterprise naming + how to bind)](#appendix-c--connection-references)
- [Appendix D — Verify the Copilot Studio agents use the right SQL](#appendix-d--verify-the-copilot-studio-agents-use-the-right-sql)
- [Appendix E — Manual / portal deployment (no installer)](#appendix-e--manual--portal-deployment-no-installer)
- [Appendix F — Troubleshooting](#appendix-f--troubleshooting)
- [Appendix G — Deployment package contents](#appendix-g--deployment-package-contents)
- [Appendix H — Deployment review checklist](#appendix-h--deployment-review-checklist)
- [Appendix I — Support & revision history](#appendix-i--support--revision-history)

---

## Before you start

| You need | Notes |
|---|---|
| Windows machine, PowerShell 5.1+ or 7+ | Required modules auto-install |
| Azure account with **Contributor** on a Resource Group | Subscription-level rights only needed if the RG must be created |
| A **5–10 character prefix** (letters/digits, lowercase) | All Azure resource names are derived from it |
| SQL admin **username + password** | You choose them; prompted at runtime, never written to disk |
| Target **Power Platform environment URL** | e.g. `https://<org>.crm.dynamics.com` |
| **Code apps enabled** on the target Power Platform environment | Required for the Reconcile **code app**. A Power Platform / environment admin must turn on the **Power Apps code apps** feature (Power Platform admin center → your environment → **Settings** → **Product** → **Features**). See [Enable code apps on a Power Platform environment](https://learn.microsoft.com/en-us/power-apps/developer/code-apps/overview#enable-code-apps-on-a-power-platform-environment). |

> Prefer the automated installer below. For a fully manual portal deployment, see **Appendix E**.

---

## Deployment Steps

### Step 1 — Run the installer
Run **`Install-PaymentRecon.cmd`** (double-click) or **`Install-PaymentRecon.ps1`** from PowerShell.
This version deploys the **Direct** variant automatically (secrets embedded in ADF linked services) —
there is no variant prompt. The **Key Vault** variant is planned for a later version; see **Appendix A**
for the difference and the reference scripts that remain in the package.

### Step 2 — Provision Azure
1. Sign in to **Azure** when prompted (the installer asks even if you are already signed in).
2. Select **subscription** and **region**.
3. Enter your **5–10 character prefix**.
4. Answer the prompts: **create Azure SQL?** and **run SQL scripts?** (choose **yes** for a fresh deployment).

The installer deploys **Storage + Data Factory** (and optionally **SQL** + schema), then writes
`PaymentReconSolutionV5.deployment-settings.json` with the real Azure values.
See **Appendix B** for what gets created.

### Step 3 — Import the Power Platform solution
1. Sign in to **Power Platform** when prompted (Browser, Device code, or Browser-with-fallback).
2. Enter the target **environment URL**.

The installer imports the solution (**pass 1**). It automatically repoints SQL to your deployed
server/database, stamps Cloud Flow environment variables, and applies **enterprise display names**
to the connection references (prefix `Payment Recon - …`).

### Step 4 — Create connections & bind references (one-time per environment)
After pass 1, create the connections and bind them to the connection references. **Recommended:** do
this from **Solutions → Payment Recon Agent V4 → Connection references** (opening a reference lets you
**+ New connection**, which auto-binds it).

Create these **4** connections:

| Connection | Enter |
|---|---|
| **SQL Server** | server `<prefix>-sqlsrv.database.windows.net`, your DB, SQL or Entra auth — use the **same** connection for all **3** SQL references |
| **Azure Blob Storage** | storage account name + access key (or Entra) |
| **Azure Data Factory** | sign in with an account that can access the data factory |
| **Microsoft Copilot Studio** | sign in (OAuth) |

> **Optional / preview:** *Microsoft Outlook Mail MCP* — only needed for the admin agent's email
> tool. Create it from inside Copilot Studio (see **Appendix C/D**); skip if not required.

At the installer's `Press Enter to run pass 2 now, or type SKIP to finish` prompt: press **Enter**
to auto-map the connections you just created, or type **SKIP** to finish (you can map later by
re-running `Deploy-PowerPlatform.ps1`). Full detail in **Appendix C**.

**Turn on the Cloud Flow.** After the connection references are bound, switch the integration flow on
— imported flows can arrive **Off** until their connections exist:
**Solutions → Payment Recon Agent V4 →** open **PaymentReconIntegration_V4 → Turn on**
(or **Power Automate → Solutions →** the same flow **→ Turn on**).
Confirm its connections (SQL, ADF, Blob, Copilot Studio) show as connected.
The installer/import rewrite now also injects the missing code-app Logic flows connection reference
(`paymentreconintegration_v5`) into the deployment zip, so Reconcile does not fail with
"Connection reference not found" on fresh installs.

### Step 5 — Validate
1. In **ADF Studio → Manage → Linked services**, open each linked service and click **Test connection** (expect *Successful*).
2. Open the **PaymentReconAgent-V4** Power App and upload the two sample files from the **`Samples`**
   folder (`Sample_Commerce Transactions.csv` and `Sample_payments_accounting_report.csv`).
3. Trigger a reconciliation; confirm the **PaymentReconIntegration_V4** flow and the ADF pipeline run successfully.
4. Confirm results appear in the app and rows are written to SQL (`ReconciliationExecution`, history tables).
5. (Optional) Confirm the agents query the correct SQL — see **Appendix D**.

✅ **Deployment complete.**

---

## Cleanup / Uninstall

Removing the solution is done in two places — **Azure** and **Power Platform**.

### 1. Azure — delete the resource group
Deleting the resource group removes **all** Azure resources at once (Storage, Data Factory, SQL
Server/Database, and Key Vault if used).

- **Portal:** **Resource groups** → select the RG you deployed into (e.g. `<prefix>-paymentrecon-rg`,
  also shown in `PaymentReconSolutionV5.deployment-settings.json` → `ResourceGroupName`) → **Delete resource group**.
- **CLI:**
  ```powershell
  az group delete --name "<your-resource-group>" --yes --no-wait
  ```

### 2. Power Platform — delete the solution and connections
1. **make.powerapps.com** → select the environment → **Solutions**.
2. Delete the solution **`PaymentReconSolutionV5`** (from package `PaymentReconSolutionV5.zip`).
   This removes its objects — the **Payment Recon V5** and **Payment Recon V5 – Admin** agents,
   the **Reconciliation** agent, the Power App, the **PaymentReconIntegration_V4** Cloud Flow,
   and all **connection references**.
3. Go to **Connections** and delete the connections you created (SQL Server, Azure Blob Storage,
   Azure Data Factory, Microsoft Copilot Studio, and the optional Outlook Mail MCP).

> **Order tip:** delete the **solution first**, then the **connections** (a connection that is still
> referenced cannot be deleted). Deleting the solution does **not** delete Azure data — that is removed
> only when the resource group / SQL database is deleted in step 1.

---

# Appendices

## Appendix A — Deployment variants

| | **Key Vault** | **Direct** |
|---|---|---|
| Recommended for | Production / enterprise | Quick PoC / lab |
| Where secrets live | Azure Key Vault | Inside ADF linked services (SecureString) |
| ADF reads SQL password | Managed Identity → Key Vault | Embedded in the linked service |
| ADF reads Storage key | Managed Identity → Key Vault | Embedded in the linked service |
| Extra Azure resource | 1 Key Vault | none |
| Permissions required | Contributor on RG | Contributor on RG |
| AAD / tenant admin needed | **No** | **No** |
| Rotating a secret later | Update Key Vault only | Re-run ARM / edit linked service |

Both variants deploy the same Storage Account, Data Factory, and (optionally) Azure SQL.

**What is stored in Key Vault** (Key Vault variant only): `SqlAdminPassword` and `StorageAccountKey`.
ADF's system-assigned Managed Identity is granted **Key Vault Secrets User**, scoped to the vault only.

---

## Appendix B — What gets deployed & resource naming

Single Resource Group, single region:

| Component | Notes |
|---|---|
| Storage Account | Standard_RAGRS, TLS 1.2, with the 4 required blob containers |
| Azure Data Factory | Pipelines, datasets, and linked services from the ARM template |
| Azure Key Vault | **Key Vault variant only** — holds 2 secrets |
| Azure SQL Server + Database | Only when you answer "yes" to "create SQL" |
| SQL schema + rules | Only when you answer "yes" to "run SQL scripts" |

Resource names are derived from your prefix, for example with prefix `contosopay`:

```
contosopay-paymentrecon-rg   (resource group)
contosopaystorage            (storage account)
contosopay-adf               (data factory)
contosopay-kv                (key vault — KV variant only)
contosopay-sqlsrv            (SQL server, if created)
contosopay-sqldb             (SQL database, if created)
```

The four blob containers: `commercefilestorage-in`, `commercefilestorage-out`,
`paymentfilestorage-in`, `paymentfilestorage-out`.

---

## Appendix C — Connection references

The solution ships with **7 connection references**. Each has two names:
- **Name** (logical/schema name, e.g. `cap_sharedsql_36c34127c7`) — **immutable**. Deployment
  automation and every solution component bind to this. **Never change it.**
- **Display name** — cosmetic only. The deployment **auto-applies** an enterprise prefix
  (default `Payment Recon - …`).

### C.1 The 7 references

| Find this **Name** (logical) | Type | **Display name** (auto-applied) | Settings field for the GUID |
|---|---|---|---|
| `cap_sharedsql_36c34127c7` | SQL Server | **Payment Recon - Azure SQL Database (Power App)** | `SqlConnectionId` |
| `copilots_header_fe637.shared_sql.9ea221cbf55…` | SQL Server | **Payment Recon - Azure SQL Database (Agent - Reconciliation)** | `SqlConnectionId` |
| `cre7a_agentR61Db3.shared_sql.shared-sql-bf74b048-…` | SQL Server | **Payment Recon - Azure SQL Database (Agent - Rule Admin)** | `SqlConnectionId` |
| `cap_sharedazureblob_36c34fa51a` | Azure Blob Storage | **Payment Recon - Azure Blob Storage** | `BlobConnectionId` |
| `new_sharedazuredatafactory_98752` | Azure Data Factory | **Payment Recon - Azure Data Factory** | `AzureDataFactoryConnectionId` |
| `new_sharedmicrosoftcopilotstudio_dea00` | Microsoft Copilot Studio | **Payment Recon - Microsoft Copilot Studio** | `MicrosoftCopilotStudioConnectionId` |
| `cre7a_agentR61Db3.shared_a365mcpservers.shared-a365mcpserver-afbe760a-…` | A365 MCP (Outlook Mail) | **Payment Recon - Microsoft Outlook Mail MCP** | `A365McpServersConnectionId` |

> There are **three SQL references** (Power App + two agents). **Point all three at the SAME Azure SQL connection.**

### C.2 Create / bind the connection for each reference
1. **make.powerapps.com** → select environment → **Solutions → Payment Recon Agent V4 → Connection references**.
2. Click a reference's **Display name** to open it.
3. Under **Connection**, pick an existing one or **+ New connection** (SQL / Blob / ADF / Copilot Studio — see Step 4 inputs).
4. **Save**. Repeat for all references; each **Status** should change from `Off` to a bound connection.

### C.3 Microsoft Outlook Mail MCP (optional, preview)
The `…shared_a365mcpservers…` reference feeds **one** tool on the admin agent — **Microsoft Outlook
Mail MCP** — used to read/send Outlook email. It is an experimental Microsoft "Frontier" preview, so:
- It often is **not** in the standard *New connection* catalog.
- Create it from **copilotstudio.microsoft.com → Payment Recon V5 – Admin → Tools →
  Microsoft Outlook Mail MCP**, which prompts you to authorize a connection.
- If it isn't offered, your tenant doesn't have the preview enabled — safe to skip; core reconciliation is unaffected.

### C.4 Rename display names (normally automatic)
Display names are already prefixed when you deploy with `Deploy-PowerPlatform.ps1`. Act only if you
imported the **raw** template, or want a **different** prefix:
- **Rename one manually:** open the reference → edit **Display name** → **Save** (leave **Name** untouched).
- **Different enterprise prefix at deploy time:**
  ```powershell
  .\Update-SolutionSqlBinding.ps1 `
    -SolutionZip .\PaymentReconSolutionV5.zip `
    -SqlServerFqdn "<prefix>-sqlsrv" -SqlDatabaseName "<db>" `
    -ConnectionReferenceDisplayPrefix "Contoso PayRecon"
  ```
  (`-SkipConnectionReferenceRename` keeps the original auto-generated names.)

### C.5 Capture GUIDs for clean reruns (optional)
**make.powerapps.com → Connections →** open each connection → copy the GUID from the URL
(`…/connections/<GUID>/…`) → paste into the `Connections` block of
`PaymentReconSolutionV5.deployment-settings.json` using the right-hand column above. Re-running
`Deploy-PowerPlatform.ps1` then maps everything automatically with no manual clicking.

---

## Appendix D — Verify the Copilot Studio agents use the right SQL

The agents run SQL through the **"Execute a SQL query (V2)"** tool. The connector is correct out of
the box (`shared_sql`), **but the Server/Database the tool queries come from the solution zip**, not
the connection. They are repointed to your deployment **only when you import the
`…-deploy-<timestamp>.zip` produced by `Deploy-PowerPlatform.ps1`**. If you import the raw template,
the agents still contain placeholder tokens (`<Reconserver>`, `<ReconDatabase>`) and SQL calls fail.

**To verify:**
1. **copilotstudio.microsoft.com** → select environment.
2. Open **Payment Recon V5** and **Payment Recon V5 – Admin**.
3. Open each **Execute a SQL query (V2)** tool and confirm:
   - **Server** = `<prefix>-sqlsrv.database.windows.net`
   - **Database** = `<db>`
   - **Connection** = your active SQL Server connection.
4. If you still see the unresolved `<Reconserver>` / `<ReconDatabase>` placeholder
   tokens (i.e. the binding rewrite did not run), re-run:
   ```powershell
   .\Deploy-PowerPlatform.ps1 `
     -EnvironmentUrl "https://<org>.crm.dynamics.com" `
     -SettingsFile .\PaymentReconSolutionV5.deployment-settings.json
   ```

---

## Appendix E — Manual / portal deployment (no installer)

Use this only if you cannot run `Install-PaymentRecon`. Otherwise the installer (Steps 1–5) does all
of this for you.

### E.1 Database setup
1. Provision an empty Azure SQL Database in the target Resource Group.
2. Connect with Azure Data Studio / SSMS (admin credentials) and run, in order:
   - `01_schema.sql` — **run twice** (1st creates schema/tables; 2nd seeds/initializes policy data)
   - `02_indexes.sql` — performance indexes
   - `03_seed_rules.sql` — reconciliation rules
3. Verify expected tables exist and are populated.

**SQL firewall:** Azure SQL → logical **server** → **Security → Networking** → add your client IP, and
enable **"Allow Azure services and resources to access this server"** so ADF can connect → **Save**.

### E.2 Storage account (ARM)
1. Azure Portal → **Deploy a custom template** → **Build your own template** → upload `arm-storage-v4.json`.
2. Set a unique lowercase storage account name (3–24 chars), subscription, RG, region → **Review + create**.
3. Confirm the 4 containers exist (see Appendix B). Record the **Access key / connection string**.

### E.3 Azure Data Factory (ARM)
1. Create the Data Factory instance (Portal → **Data factories → Create**), or deploy via template.
2. **Deploy a custom template** → upload `arm-datafactory-v4-keyvault.json` **or**
   `arm-datafactory-v4-direct.json` (match your variant).
3. Provide: SQL Server FQDN, SQL DB name, SQL admin user/password, Storage account name + key → **Review + create**.

### E.4 Linked services
In **ADF Studio → Manage → Linked services**, edit each, **Test connection** (expect *Successful*),
fix server/db/credentials if needed, **Save**. Confirm **Integration runtimes** show **Running**.
*Best practice:* prefer **Managed Identity** (grant ADF `db_datareader`/`db_datawriter` on SQL and
`Storage Blob Data Contributor` on Storage). Do not proceed if any test fails — recheck the firewall (E.1).

### E.5 Import the solution
Use the script so SQL binding, env-variable values, and connection references are handled correctly:
```powershell
.\Deploy-PowerPlatform.ps1 `
  -EnvironmentUrl "https://<org>.crm.dynamics.com" `
  -SettingsFile .\PaymentReconSolutionV5.deployment-settings.json
```
Add `-SignInMode DeviceCode` to force device-code sign-in. Then complete **Step 4** (connections) and
**Step 5** (validate). Importing the raw zip from make.powerapps.com requires manual SQL/connection fixes afterward.

**Solution components:** Agent *Payment Recon V5* (reconciliation engine), Agent *Payment Recon V5 –
Admin* (rule management; deploy to Teams/M365 to make it interactive), Cloud Flow
*PaymentReconIntegration_V4* (ADF ↔ agent), Power App *PaymentReconAgent-V4* (UI).

---

## Appendix F — Troubleshooting

| Issue | Action |
|---|---|
| "Execution policy" error | Use the `.cmd` launcher (sets `-ExecutionPolicy Bypass`) |
| Storage name not available | Pick a different prefix and re-run |
| SQL connection fails | Script retries 3× and re-prompts for the password; check firewall + credentials (Appendix E.1) |
| Key Vault role assignment fails | Verify your account has Contributor on the Resource Group |
| `Az` module errors | Pre-flight installer fixes most cases; else `Install-Module Az -Scope CurrentUser -Force` |
| SQL script execution fails | Re-run the "run SQL scripts" option, or run the 3 scripts manually (run `01_schema.sql` **twice**) |
| Agent queries wrong/old SQL server | You imported the raw template — re-run `Deploy-PowerPlatform.ps1` (Appendix D) |
| Connection reference shows `Off` | Create/bind its connection (Appendix C); for the 3 SQL refs use the same SQL connection |
| Outlook Mail MCP connection missing | Preview connector — create it from Copilot Studio, or skip (Appendix C.3) |
| Window closes too fast | Both `.cmd` and `.ps1` keep the console open; run from an open PowerShell window if needed |

---

## Appendix G — Deployment package contents

The package is organized into three parts:

```
README.md            overview & entry point (package root)
Deployment\          everything needed to deploy
Samples\             sample CSV files for validation
```

The **`Deployment\`** folder contains:

| File | Purpose |
|---|---|
| `Install-PaymentRecon.ps1` | Primary installer (Azure + Power Platform) |
| `Install-PaymentRecon.cmd` | Double-click launcher for the installer |
| `Deploy-PowerPlatform.ps1` | Standalone/retry Power Platform importer (SQL binding, env vars, connection mapping, enterprise rename) |
| `Update-SolutionSqlBinding.ps1` | Rewrites SQL binding + env-variable values and applies enterprise connection-reference display names |
| `New-PaymentRecon-Package.ps1` | Builds a clean, timestamped deployment ZIP |
| `Deploy-PaymentRecon-KeyVault.ps1` | Key Vault deployment variant |
| `Deploy-PaymentRecon-Direct.ps1` | Direct deployment variant |
| `arm-storage-v4.json` | Storage Account + blob containers ARM template |
| `arm-datafactory-v4-keyvault.json` | Data Factory ARM template (Key Vault-backed) |
| `arm-datafactory-v4-direct.json` | Data Factory ARM template (SecureString) |
| `01_schema.sql` / `02_indexes.sql` / `03_seed_rules.sql` | Database schema, indexes, rules |
| `PaymentReconSolutionV5.zip` | Power Platform solution package (Power App + all Copilot Studio agents) |
| `PaymentReconSolutionV5.deployment-settings.template.json` | Template for deployment settings (scripts generate the real `…deployment-settings.json`) |
| `DEPLOYMENT.md` | This deployment guide |

Alongside the `Deployment\` folder:

| Location | Purpose |
|---|---|
| `README.md` (package root) | Solution overview & entry point |
| `Samples\Sample_Commerce Transactions.csv`, `Samples\Sample_payments_accounting_report.csv` | Sample files for validation |

---

## Appendix H — Deployment review checklist

1. **Parameterization complete** — SQL, Storage, ADF, environment values, and solution settings are deployment-driven (no hardcoded post-install edits).
2. **Credential safety** — SQL admin username/password are prompted at runtime and never persisted to disk.
3. **Single guided installer flow** — `Install-PaymentRecon.cmd` / `.ps1` is the primary entry point with minimal prompts.
4. **Resilient Power Platform sign-in** — browser first, automatic device-code fallback.
5. **Connection-reference mapping at import time** — SQL, Blob, ADF, Copilot Studio, and Outlook Mail MCP can be mapped from deployment settings; display names are auto-prefixed `Payment Recon - …`.
6. **First-run bootstrap in same terminal** — pass 1 import, guided connector setup, then optional pass 2.
7. **Clean redeploy path** — reruns complete with minimal/no manual clicking when IDs are in settings.
8. **Blob integration cleanliness** — Blob wiring handled through mapping/settings.
9. **Package traceability** — distribution ZIP generated with a unique timestamped filename per build.
10. **Operator simplicity** — end-to-end deployment is understandable for non-technical operators.

> **Accepted platform constraint:** first-time creation/consent for some connector instances is a
> one-time manual action per environment. Import automation maps existing connection IDs but does not
> auto-create every connector instance.

---

## Appendix I — Support & revision history

**Support:** Dynamics 365 Commerce Fasttrack P-Crew.

| Version | Date | Description |
|---|---|---|
| v4.1.0.0.13 | 03/01/2026 | Initial release of deployment guide |
| v4.1.0.0.15 | 03/24/2026 | Updated to latest solution version |
| v4.1.0.0.16 | 04/24/2026 | Power Platform solution package updated to v4.1.0.0.16 |
| v4.1.0.0.16 | 06/18/2026 | Merged into a single deployment guide; added Cleanup/Uninstall; enterprise connection-reference naming |
