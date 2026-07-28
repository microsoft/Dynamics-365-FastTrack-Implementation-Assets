# Payment Recon Agent

Automated payment reconciliation for **Microsoft Dynamics 365 Commerce**, running on **Microsoft Azure**
and **Microsoft Power Platform**. It ingests commerce and payment‑processor (PSP) files, matches
transactions using rule‑based policies, archives matched records, and surfaces results in a Power App and
Copilot Studio agents.

> **Deploying?** Go straight to **[Deployment/DEPLOYMENT.md](Deployment/DEPLOYMENT.md)** and follow Steps 1–5,
> or run **`Deployment/Install-PaymentRecon.cmd`**.

---

## What it does

- Ingests commerce + PSP CSV files into **Azure SQL** via **Azure Data Factory**.
- Reconciles transactions with configurable rules (settled → Policy‑1, refunds → Policy‑2).
- Archives matched records to history; leaves unmatched rows for the next run.
- Lets users upload files and review matched / unmatched / exception results in the Power App.
- Ships Copilot Studio agents for the reconciliation engine and rule administration.

---

## Architecture

```
Power Platform (UI + orchestration)
  ├─ Power App    file upload + results dashboard
  ├─ Agent        Payment Recon — reconciliation engine
  ├─ Agent        Payment Recon — Admin (manage reconciliation rules)
  └─ Cloud Flow   triggers Azure Data Factory + invokes the agent

Azure (data layer)
  ├─ Azure Data Factory    CSV ingestion (Blob → SQL staging)
  ├─ Azure Blob Storage    4 containers (commerce/payment, in/out)
  └─ Azure SQL Database    staging, active, history tables + reconciliation rules
```

**Data flow:** Upload → Ingest (ADF) → Preprocess → Reconcile → Archive → Report.

---

## Folder contents

```
README.md                      this overview
INSTALL.md                     quick-start install notes
Deployment\                    everything needed to deploy — run Install-PaymentRecon.cmd here
Samples\                       sample CSV files for validation
```

> The **`PaymentTransactionDataExport\`** project (Dynamics 365 F&O `.axpp`) lives at the repository
> root, alongside this `PaymentReconAgent\` folder.

---

## Deploy

Full instructions are in **[Deployment/DEPLOYMENT.md](Deployment/DEPLOYMENT.md)**. At a glance you'll need:

- A Windows machine with PowerShell 5.1+ / 7+.
- An Azure account with **Contributor** on a resource group.
- A 5–10 character prefix, SQL admin credentials, and the target Power Platform environment URL.
- **Code apps enabled** on the target Power Platform environment (needed for the Reconcile code app). A
  Power Platform / environment admin turns on the **Power Apps code apps** feature in the Power Platform
  admin center → *Settings → Product → Features*. See
  [Enable code apps on a Power Platform environment](https://learn.microsoft.com/en-us/power-apps/developer/code-apps/overview#enable-code-apps-on-a-power-platform-environment).

Then, in the **`Deployment`** folder, run **`Install-PaymentRecon.cmd`** (or `Install-PaymentRecon.ps1`)
and follow **Steps 1–5**.

### Smart installer (install **or** update)

`Deployment\Deploy-PaymentRecon-Smart.ps1` inspects a resource group and chooses **Fresh** (create
everything) or **Redeploy** (incremental ARM upgrade, base schema preserved). Default is a **read‑only
plan**; pass `-Execute` to apply.

---

## Data export (Dynamics 365 F&O)

`PaymentTransactionDataExport\` (at the repository root) contains a Dynamics 365 Finance & Operations
project (`.axpp`) used to export payment transactions for reconciliation. See its
**[README](../PaymentTransactionDataExport/README.md)** for import and usage details.

---

## Support

Dynamics 365 Commerce FastTrack.
