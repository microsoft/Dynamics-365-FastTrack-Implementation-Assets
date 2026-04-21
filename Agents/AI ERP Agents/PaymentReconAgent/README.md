# PAYMENT RECON AGENT — Deployment Instruction Guide

> **Version:** v4.1.0.0.15 | **Date:** 03/24/2026 | **Status:** Final | **Audience:** DevOps / Deployment Team

---

## Document Revision History

| Version | Date | Author | Description |
|---|---|---|---|
| v4.1.0.0.13 | 03/01/2026 | — | Initial release of deployment guide |
| v4.1.0.0.15 | 03/24/2026 | — | Updated with latest version |

---

## Table of Contents

1. [Overview](#1-overview)
2. [Prerequisites](#2-prerequisites)
3. [Deployment Package Contents](#3-deployment-package-contents)
4. [Database Setup](#4-database-setup)
5. [Azure Storage Account](#5-azure-storage-account)
6. [Azure Data Factory (ADF)](#6-azure-data-factory-adf)
7. [Update Linked Service Configuration](#7-update-linked-service-configuration)
8. [Deploy PaymentRecon Agent Application](#8-deploy-paymentrecon-agent-application)
9. [Validate and Publish](#9-validate-and-publish)
10. [Support](#10-support)

---

## 1. Overview

The Payment Recon Agent (version 4.1.0.0.14) is an automated reconciliation solution that operates on Microsoft Azure. It is designed to handle payment and commerce files, reconcile transactions according to predefined rules, and output results into specific storage containers. Azure Data Factory (ADF) is used for orchestration, Azure SQL Database provides data persistence, and Azure Blob Storage manages file ingestion and output.

The deployment process follows these major steps:

1. Provision and initialize the Azure SQL Database.
2. Configure firewall rules for the Azure SQL Database to allow connectivity.
3. Create and set up the Azure Storage Account with necessary Blob containers.
4. Deploy and configure Azure Data Factory pipelines using an ARM template.
5. Update credentials for Linked Services in ADF Studio.
6. Deploy the PaymentRecon Agent application package.
7. Validate and publish all ADF resources.
8. Carry out post-deployment verification.

---

## 2. Prerequisites

Before starting the deployment, verify that all prerequisite conditions are satisfied.

### 2.1 Azure Permissions

- Ensure you have **Contributor** or **Owner** access for the relevant Azure Subscription or Resource Group.
- Ability to create and configure Azure SQL Database, Storage Accounts, and Azure Data Factory resources is required.
- Access to the Azure Portal is necessary.

### 2.2 Tools and Software

- Access to the Azure Portal using a modern browser.
- Access to Azure Data Factory Studio.
- SQL client tools such as **Azure Data Studio** or **SQL Server Management Studio**.
- The deployment package folder must be accessible.

### 2.3 Information Required

| Item | Description |
|---|---|
| Azure Subscription ID | Target subscription for all resources. |
| Resource Group | Existing or new resource group name. |
| Azure SQL Server | Server name, database name, admin username, and password. |
| Storage Account Name | Desired name and Azure region. |
| ADF Instance Name | Azure Data Factory instance name. |
| Storage Account Key | Retrieved after creating the Storage Account in Step 5. |
| Client IP | IP address or range for Azure SQL Database firewall configuration. |

---

## 3. Deployment Package Contents

The deployment package includes the following files:

| File Name | Purpose |
|---|---|
| `01_schema.sql` | Creates all database tables and schema objects; seeds policy data (must be executed **twice** — see Step 4). |
| `02_indexes.sql` | Creates performance indexes on core database tables. |
| `03_seed_rules.sql` | Seeds reconciliation rules required at runtime. |
| `arm-storage-v4.json` | ARM template for provisioning the Azure Storage Account and Blob containers. |
| `arm-datafactory-v4.json` | ARM template for provisioning and configuring Azure Data Factory pipelines. |
| `PaymentReconAgentV4_1_0_0_15.zip` | Application package for deployment to the host environment. |

---

## 4. Database Setup

This step involves provisioning the Azure SQL Database schema, setting up indexes, seeding initial policy and reconciliation rule data, and configuring firewall access for the Payment Recon Agent.

### 4.1 Prerequisites

- An empty Azure SQL Database must be provisioned in the target Resource Group.
- Connection details must be available: server name, database name, admin username, and password.

### 4.2 Run Database Scripts

1. Connect to the Azure SQL Database using Azure Data Studio or SQL Server Management Studio with admin credentials.
2. Execute `01_schema.sql` to create all necessary tables and schema objects.
3. Run `02_indexes.sql` to create performance indexes on the core tables.
4. Run `03_seed_rules.sql` to seed reconciliation rules required by the agent.
5. Verify the schema by querying the database to ensure all expected tables are present and populated.

> **NOTE:** `PaymentReconV4DbScripts.sql` must be executed **twice**. The first run creates schemas and tables; the second seeds and initializes policy data.

### 4.3 Configure Azure SQL Firewall Rules  (Optional)

Azure SQL Database blocks all inbound connections by default, including those from Azure Data Factory. Firewall rules must be configured before ADF Linked Service connections or SQL client tools can connect.

1. Navigate to your **Azure SQL logical server** in the Azure Portal (not the database).
2. Choose **Security > Networking** from the left menu.
3. Under **Firewall rules**, add your client IPv4 address to permit the machine running the deployment.
4. To allow Azure Data Factory (using the Azure Integration Runtime) to connect, enable **"Allow Azure services and resources to access this server"** in the Exceptions section.
5. Click **Save** to apply the firewall rules.

---

## 5. Azure Storage Account

This step covers deploying the Azure Storage Account and creating Blob containers for file ingestion and output.

### 5.1 Deploy ARM Template

1. Sign in to the **Azure Portal**.
2. Search for **"Deploy a custom template"** and select it.
3. Click **"Build your own template in the editor."**
4. Upload `arm-storage-v4.json` from the deployment package.
5. Update the Storage Account name in the template.
6. Save the template and update the parameters below.
7. Click **Review + create**, then **Create**. Wait for completion before continuing.

| Parameter | Action / Value |
|---|---|
| Subscription | Select target Azure subscription. |
| Resource Group | Select or create the target resource group. |
| Region | Choose the appropriate Azure region. |
| Storage Account Name | Unique, lowercase name (3–24 characters, letters and numbers only). |

### 5.2 Verify Storage Containers

After deployment, confirm these four Blob containers were created:

| Container | Purpose |
|---|---|
| `commercefilestorage-in` | Incoming commerce files |
| `commercefilestorage-out` | Processed commerce output files |
| `paymentfilestorage-in` | Incoming payment files |
| `paymentfilestorage-out` | Processed payment output files |

To confirm: navigate to **Storage accounts** → open the new account → select **Containers** in the left menu.

> **NOTE:** Record the **Storage Account Access Key /Connection string** — it is needed for Steps 6 and 7. Retrieve it via **Storage Account > Security + networking > Access keys**.

---

## 6. Azure Data Factory (ADF)

This step involves creating the Azure Data Factory instance and importing pipeline definitions via the provided ARM template.

### 6.1 Create the Azure Data Factory Instance

1. Search for **Data factories** in the Azure Portal and select it.
2. Click **Create**.
3. Enter Subscription, Resource Group, Region, and a unique ADF Name.
4. Click **Review + create**, then **Create**.
5. After deployment, go to the resource and launch **ADF Studio**.

### 6.2 Import Pipelines via ARM Template

1. In the **Azure Portal**, search for **"Deploy a custom template"** and select it.
2. Click **"Build your own template in the editor."**
3. Upload `arm-datafactory-v4.json` from the deployment package.
4. Ensure **Subscription**, **Resource Group**, and **ADF Name** match those from Step 6.1.
5. Ensure the correct details are updated on  the Factory name,connection String(from Storage account), SQL connection - Database name , user name,password
6. Update the parameters below, then click **Review + create**.
7. Wait for completion and confirm the success notification.

| Parameter | Value / Action |
|---|---|
| SQL Server Name | Fully qualified Azure SQL Server hostname. |
| SQL Database Name | The database name from Step 4. |
| SQL Admin Username | SQL administrator username. |
| SQL Admin Password | SQL administrator password. |
| Storage Account Name | Storage Account name from Step 5. |
| Storage Account Key | Storage Account access key from Step 5. |

---

## 7. Update Linked Service Configuration

After deploying the ARM template, update Linked Services in ADF Studio -> 'Manage' to confirm connectivity with the SQL database and Storage Account.

### 7.1 Storage Account Linked Service

1. In ADF Studio, go to **Manage > Linked services**.
2. Find the **Storage Account Linked Service** and click **Edit**.
3. Click **Test connection** — confirm a "Successful" result.
4. If there are errors -  Update **Storage account name** and **Account key**.
5. Click **Save**.

### 7.2 Azure SQL Database Linked Service

1. Locate the **Azure SQL Database Linked Service** and click **Edit**.
2. Click **Test connection** — confirm a "Successful" result.
3. If there are errors - Update **Server name**, **Database name**, **Username**, and **Password**.
4. Click **Save**.

> **BEST PRACTICE:** Microsoft recommends **Managed Identity** authentication for ADF-to-SQL and ADF-to-Storage connections. To use it, grant the ADF instance `db_datareader` and `db_datawriter` roles on the SQL Database, and `Storage Blob Data Contributor` on the Storage Account.

### 7.3 Verify Integration Runtime

- Go to **Manage > Integration runtimes** and confirm all runtimes show **Running** status.
- The Azure Integration Runtime is provisioned automatically and requires no setup.

> **IMPORTANT:** Do not proceed if any Linked Service connection test fails. Verify Azure SQL firewall rules (Section 4.3) if a failure occurs.

---

## 8. Deploy PaymentRecon Agent Application

This step covers importing the PaymentRecon Agent solution (`PaymentReconAgentV4_1_0_0_15.zip`) into the target Power Platform environment.

### 8.1 Preparation

- Ensure the target environment (Dynamics sandbox / Production) is available and accessible.
- Confirm the environment can reach the Azure SQL Database and Storage Account configured in previous steps.

### 8.2 Import the Solution

1. Go to [https://make.powerapps.com](https://make.powerapps.com) and select the correct environment.
2. Navigate to **Solutions > Import solution**.
3. Select `PaymentReconAgentV4_1_0_0_15.zip` and follow the import prompts.

The solution contains the following components:

| Component | Description |
|---|---|
| Agent: Payment Recon V5 | Reconciliation engine |
| Agent: Payment Recon V5 – Admin | Admin agent to manage payment recon rules |
| Cloud Flow: PaymentReconIntegration_V4 | Integration flow between ADF and the agent |
| Power App: PaymentReconAgent-V4 | UI for payment reconciliation |

### 8.3 Agent: Payment Recon V5

- Verify the SQL connection — ensure it is connected to the correct database.

### 8.4 Agent: Payment Recon V5 – Admin

- Deploy this agent to **Microsoft 365 / Teams** channels to make it interactive.

### 8.5 Cloud Flow: PaymentReconIntegration_V4

- Ensure the Cloud Flow is connected to the correct ADF pipelines and the newly deployed Agent.

### 8.6 Power App: PaymentReconAgent-V4

- Verify the connections in the Power App.

---

## 9. Validate and Publish

Carry out end-to-end validation to confirm the full deployment is working correctly before going live.

### 9.1 Upload Sample Files

1. Open the **PaymentReconAgent-V4** Power App.
2. Upload the sample commerce file (`Sample_Commerce Transactions.csv`) using the app's file upload interface.
3. Upload the sample payments file (`Sample_payments_accounting_report.csv`).

### 9.2 Trigger Reconciliation

1. Initiate a reconciliation run from within the Power App.
2. Confirm the **PaymentReconIntegration_V4** Cloud Flow is triggered — verify it shows a successful run in **Power Automate > My Flows > Run history**.
3. Confirm the ADF pipeline is triggered — open **ADF Studio > Monitor > Pipeline runs** and verify the run completes successfully.

### 9.3 Verify Agent Activity

1. Open the **Payment Recon V5** agent and confirm it processes the reconciliation request without errors.
2. Check the agent conversation log for any rule execution failures or warnings.

### 9.4 Confirm Reconciliation Results

1. Return to the **PaymentReconAgent-V4** Power App.
2. Verify reconciliation results are displayed correctly — matched, unmatched, and exception records should be visible.
3. Query the Azure SQL Database to confirm records are written to the expected tables (`ReconciliationExecution`, history tables).

### 9.5 Publish ADF Resources

1. In **ADF Studio**, click **Publish all** to publish any pending changes.
2. Confirm the publish completes without errors.

---

## 10. Support

For deployment issues or technical inquiries, contact the **Dynamics 365 Commerce Fasttrack P-Crew**.

| Contact Type | Details |
|---|---|
| Technical Support | Dynamics 365 Commerce Fasttrack P-Crew |

---

