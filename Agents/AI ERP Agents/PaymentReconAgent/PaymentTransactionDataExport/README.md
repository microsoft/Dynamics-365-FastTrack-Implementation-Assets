# PAYMENT TRANSACTION DATA EXPORT — Deployment Instruction Guide

> **Version:** v1.0.0.0 | **Date:** 05/28/2026 | **Status:** Final | **Audience:** D365 F&O Developers / DevOps / Deployment Team

---

## Document Revision History

| Version | Date | Author | Description |
|---|---|---|---|
| v1.0.0.0 | 05/28/2026 | — | Initial release of the Payment Transaction Data Export model deployment guide |

---

## Table of Contents

1. [Overview](#1-overview)
2. [Prerequisites](#2-prerequisites)
3. [Deployment Package Contents](#3-deployment-package-contents)
4. [Import the AXPP Project](#4-import-the-axpp-project)
5. [Build and Synchronize](#5-build-and-synchronize)
6. [Deploy to Sandbox / Production via Deployable Package](#6-deploy-to-sandbox--production-via-deployable-package)
7. [Configure Payment Reconciliation Integration Parameters](#7-configure-payment-reconciliation-integration-parameters)
8. [Run and Validate the Export](#8-run-and-validate-the-export)
9. [Troubleshooting](#9-troubleshooting)
10. [Support](#10-support)

---

## 1. Overview

The **Payment Transaction Data Export** module is the Dynamics 365 Finance & Operations (Commerce) side of the **Payment Reconciliation Agent** solution. It is delivered as an `.axpp` (Application eXplorer Project Package) file and contains the metadata, data entity, and runtime parameter form (**Payment Reconciliation Integration Parameters**) required to export commerce payment transactions to an Azure Blob Storage container, where the Azure Data Factory pipelines (deployed via the main [PaymentReconAgent README](../README.md)) pick them up for reconciliation.

This guide covers:

1. Importing the `PaymentRecon_TransexportRecon.axpp` project into a Tier‑1 (Dev) environment.
2. Building, synchronizing, and creating a deployable package.
3. Deploying that package to Sandbox / Production via Lifecycle Services (LCS).
4. Configuring the **Payment Reconciliation Integration Parameters** form to connect F&O to the Azure Storage account provisioned in Step 5 of the main deployment guide.
5. Triggering and validating the export.

---

## 2. Prerequisites

### 2.1 Environments

- A **Tier‑1 (Cloud-hosted or local VHD) development environment** running a supported version of D365 Finance & Operations / Commerce.
- Target **Sandbox** and **Production** environments managed through Lifecycle Services (LCS).
- The **PaymentReconAgent** Azure resources (Storage Account, SQL DB, ADF) have already been provisioned per the [main PaymentRecon Agent README](../README.md).

### 2.2 Roles and Access

| Item | Required Access |
|---|---|
| Dev box | Administrator access to the VM and to Visual Studio with the D365 F&O developer tools installed. |
| LCS Project | **Project Owner** or **Environment Manager** to upload and apply deployable packages. |
| F&O User | **System Administrator** (or a custom role with access to **Retail and Commerce > Headquarters setup > Parameters > Payment Reconciliation Integration Parameters**). |
| Azure Storage | Access to the `commercefilestorage-in` container (or equivalent) created in Step 5 of the main guide, and the **Connection String** / **Access key**. |

### 2.3 Required Information

| Item | Description |
|---|---|
| Blob Storage Connection String | Connection string for the Azure Storage account that will receive the exported files (from Step 5 of the main guide). |
| Blob Storage Container Name | Container that will receive the exports (default: `commercefilestorage-in`). |
| Data Entity | `PRARetailPaymentReconEntity` (shipped in the AXPP). |
| Export Project Name | Recurring data-export project name used by the export framework.(Initially will be blank) |
| Last Exported Trans Date | Initial high-water mark for the first export run.(Initially will be blank) |

---

## 3. Deployment Package Contents

| File | Purpose |
|---|---|
| `PaymentRecon_TransexportRecon.axpp` | Visual Studio project package containing the model, the `PRARetailPaymentReconEntity` data entity, the **Payment Reconciliation Integration Parameters** form, and the export runtime classes. |

---

## 4. Import the AXPP Project

The `.axpp` file is a Visual Studio project archive that must be imported on a Tier‑1 developer environment.

1. Sign in to the **Tier‑1 dev box** as an administrator.
2. Open **Visual Studio** (Run as Administrator).
3. On the menu bar, choose **Dynamics 365 > Import Project**.
4. In the **Import Project** dialog:
   - **AXPP file path:** browse to `PaymentRecon_TransexportRecon.axpp`.
   - Select **Overwrite Existing Project** (only if re-importing).
   - Select **Current solution** or create a new solution named `PaymentReconTransExport`.
5. Click **OK** and wait for the import to complete.
6. In **Solution Explorer**, confirm the project `PaymentRecon_TransexportRecon` is loaded and contains the following key elements:
   - **Data Entity:** `PRARetailPaymentReconEntity`
   - **Form:** `PaymentReconIntegrationParameters`
   - **Table/EDT:** parameters table for the form
   - **Classes:** the export/runner classes used by the **Export** action on the form

---

## 5. Build and Synchronize

1. In **Solution Explorer**, right-click the imported project and select **Rebuild**.
2. Confirm the build completes with **0 errors**.
3. On the menu bar, choose **Dynamics 365 > Synchronize database**. Wait for the sync to complete successfully — this creates the parameters table and entity views in the dev environment.
4. Open the form **Payment Reconciliation Integration Parameters** from the F&O client menu (`Retail and Commerce > Headquarters setup > Parameters > Payment Reconciliation Integration Parameters`) to verify the metadata is present.

---

## 6. Deploy to Sandbox / Production via Deployable Package

For Sandbox and Production, deploy the model via a **deployable package** uploaded to **Lifecycle Services (LCS)**. AXPP imports are **not** supported in those environments.

### 6.1 Create the Deployable Package

1. In Visual Studio, choose **Dynamics 365 > Deploy > Create Deployment Package**.
2. Select the package(s) that contain the `PaymentRecon_TransexportRecon` model.
3. Specify an output folder (for example, `C:\Temp\PaymentReconExport_DP\`) and a package name.
4. Click **Create** and wait until the `.zip` deployable package is produced.

### 6.2 Upload to LCS

1. Open **Lifecycle Services** and navigate to the target LCS Project.
2. Open the **Asset Library** and select the **Software deployable package** asset type.
3. Click **Import** (or **Upload**) and upload the package created in Step 6.1.
4. Wait for validation to complete — the **Status** must be **Valid**.

### 6.3 Apply to Sandbox / Production

1. From the LCS project, open the target environment.
2. Click **Maintain > Apply updates**.
3. Select the deployable package you uploaded and click **Apply**.
4. Acknowledge the downtime warning and start the deployment.
5. Monitor progress until the environment status returns to **Deployed**.
6. Sign in to the target environment and confirm:
   - **Payment Reconciliation Integration Parameters** form opens without error.
   - Data entity `PRARetailPaymentReconEntity` is visible under **Data management > Data entities**.

> **TIP:** For Production, always apply and validate on Sandbox first, then request the move to Production through LCS.

---

## 7. Configure Payment Reconciliation Integration Parameters

After the model is deployed, configure the runtime parameters so that F&O can push payment transactions to the Azure Storage container that the ADF pipelines monitor.

Navigate to: **Retail and Commerce > Headquarters setup > Parameters > Payment Reconciliation Integration Parameters**.

The form is organized in three sections — **Setup**, **Configuration**, and **Payment Methods** — plus an **Export** action button.

### 7.1 Setup

| Field | Description | Example / Recommended Value |
|---|---|---|
| **Blob Storage Connection String** | A reference (name) to the Azure Blob Storage connection string stored in F&O's secure configuration store. The full connection string is the one you recorded in Step 5 of the [main guide](../README.md). | `CommPayTranExpConnStr` |
| **Blob Storage Container Name** | Reference to the destination container in the Storage Account. | `CommercePaymentTransContainer` (resolves to `commercefilestorage-in`) |
| **Poll Interval (seconds)** | Frequency at which the export job checks for new transactions to upload. | `10` |
| **Blob copy timeout (seconds)** | Maximum time the export job will wait for a single blob upload to complete before failing. | `600` |

> **NOTE:** The **Blob Storage Connection String** and **Blob Storage Container Name** drop-downs are populated from F&O Key vault configuration. These must be created **once** by an administrator under **System administration > Setup > Key vault parameters** (or equivalent secure-config form) before they appear in the drop-downs. The names you create there must match the values selected on this form.

### 7.2 Configuration

| Field | Description | Example / Recommended Value |
|---|---|---|
| **Entity** | The data entity that is exported on each run. Always select the entity shipped with the AXPP. | `PRARetailPaymentReconEntity` |
| **Export project name** | The name of the recurring data-export project that the framework creates on first run. Must be unique per environment. | `usrt-paymentexportdata-20260331` |
| **Source name** | The data source format. Only **CSV** is supported in v1. | `CSV` |
| **Last exported trans date** | High-water mark date. Transactions with a transaction date **strictly greater than** this value will be picked up on the next export. Set this to the date from which you want the first export to start. | `3/31/2026` |

> **IMPORTANT:** The **Last exported trans date** is updated automatically after each successful export. Manually adjust it only when you want to re-export historical data — be aware this can produce duplicate rows downstream.

### 7.3 Payment Methods

Toggle the payment methods that should be included in the export:

| Toggle | Description | Default |
|---|---|---|
| **Card** | Include card (credit/debit) payment lines in the export. | **Yes** |
| **Wallet** | Include digital wallet payment lines (Apple Pay, Google Pay, etc.). | **Yes** |

Disable a toggle to exclude that payment method from future export runs.

### 7.4 Save and Export

1. Click **Save** in the top-left of the form.
2. Click the **Export** action (under the **Setup** section header) to perform an immediate test export.
3. The form will display a status message (Infolog) indicating success or failure.

---

## 8. Run and Validate the Export

### 8.1 Verify the File in Azure Storage

1. Open the **Azure Portal > Storage account > Containers**.
2. Open the container configured in Step 7.1 (for example, `commercefilestorage-in`).
3. Confirm a new CSV file has been uploaded with a name pattern similar to `paymentexportdata-<timestamp>.csv`.
4. Download the file and confirm it contains rows for the date range and payment methods you selected.

### 8.2 Verify ADF Picks Up the File

1. Open **ADF Studio > Monitor > Pipeline runs**.
2. Confirm the **Payment Recon** ingestion pipeline triggers within the **Poll Interval** configured in Step 7.1.
3. Confirm the run completes with **Succeeded** status.

### 8.3 Verify Records in Azure SQL

Query the staging / reconciliation tables created in Step 4 of the [main guide](../README.md):

```sql
SELECT TOP 50 *
FROM dbo.CommerceTransactions
ORDER BY CreatedDateTime DESC;
```

Confirm rows matching the exported file are present.

### 8.4 Verify End-to-End in the Power App

Return to the **PaymentReconAgent-V4** Power App (see Section 9 of the [main guide](../README.md)) and confirm the new transactions appear and can be reconciled.

---

## 9. Troubleshooting

| Symptom | Likely Cause | Resolution |
|---|---|---|
| **Export** action fails with an authentication error. | Blob Storage Connection String reference is wrong or the underlying secret is invalid. | Rotate the storage key, update the secret in **Secret references**, and re-test. |
| File is uploaded but ADF never triggers. | ADF event trigger is bound to a different container, or the storage event subscription is missing. | Re-check Section 6 of the [main guide](../README.md) and confirm the container name matches. |
| `Last exported trans date` never advances. | Export job is failing silently after upload. | Open **System administration > Inquiries > Batch jobs** and review the job history for the export task. |
| Drop-down for **Blob Storage Connection String** is empty. | No secret references have been created in F&O. | Create the connection-string secret under **System administration > Setup > Secret references** and reopen the form. |
| Duplicate rows appear in SQL after export. | `Last exported trans date` was manually rolled back. | Reset the date to the last successful export and let ADF/agent run dedup logic. |
| Build fails after AXPP import. | Missing model references on the dev box. | Confirm the **ApplicationSuite** and **Retail** models are present and at a compatible version, then rebuild. |

---

## 10. Support

For deployment or runtime issues, contact the **Dynamics 365 Commerce Fasttrack P-Crew**.

| Contact Type | Details |
|---|---|
| Technical Support | Dynamics 365 Commerce Fasttrack P-Crew |
| Related Guide | [PaymentReconAgent — Deployment Instruction Guide](../README.md) |

---
