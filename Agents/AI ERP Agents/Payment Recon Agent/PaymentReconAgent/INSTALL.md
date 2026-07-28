# Payment Recon — Install Guide

A short guide to install Payment Recon on a customer tenant. Full details are in **DEPLOYMENT.md**.

## 1. Before you start (one-time)

You need:

- A **Windows** machine with **PowerShell** (5.1 or 7).
- **Power Platform CLI (`pac`)** installed → https://aka.ms/PowerAppsCLI
- An **Azure subscription** where you are **Owner/Contributor**.
- A **Power Platform environment URL** (looks like `https://org.crm.dynamics.com`).
- A **SQL admin username + password** you will choose during install.
- **Code apps enabled** on your Power Platform environment — required for the Reconcile **code app**. A
  Power Platform / environment admin turns on the **Power Apps code apps** feature (Power Platform admin
  center → your environment → **Settings** → **Product** → **Features**). See
  [Enable code apps on a Power Platform environment](https://learn.microsoft.com/en-us/power-apps/developer/code-apps/overview#enable-code-apps-on-a-power-platform-environment).

> The Azure PowerShell modules install automatically the first time — no action needed.

## 2. Install

1. **Unzip** the package.
2. Open the `Deployment` folder and **double-click `Install-PaymentRecon.cmd`**.
3. Choose **[1] First-time install**.
4. **Sign in to Azure** in the browser window that opens.
5. Answer the prompts:
   - Customer prefix (5–10 lowercase letters/numbers)
   - Azure region
   - SQL admin username + password
6. When asked, paste your **Power Platform environment URL**.
7. **Sign in to Power Platform** (browser, or device code if asked).

That's it — the installer builds the Azure resources, then imports the solution. It finishes with **"deployment complete"**.

## 3. After install (turn it on)

Open **Power Platform** → your environment → **Solutions** → *Payment Recon* and:

- Make sure each **connection reference** is connected (SQL, Azure Blob, Data Factory, Copilot Studio).
- For the code app Reconcile button, the installer now auto-adds the Logic flows connection reference
  (`paymentreconintegration_v5`) during solution import; no manual code-app rebind is needed on new installs.
- **Turn on** the cloud flows (`PaymentReconIntegration_V4` / `_V5`).

## 4. To update later

Run `Install-PaymentRecon.cmd` again and choose **[2] Update**. It keeps what exists (your SQL data is preserved) and only adds what's missing.

## Trouble?

- **"pac not found"** → install the Power Platform CLI (step 1) and rerun.
- **Azure sign-in / permission errors** → make sure your account is Owner/Contributor on the subscription.
- **Flow fails in the app** → check the flow's **Run history** in Power Automate for the real error, and confirm the connections above are connected.

Need the long version? See **DEPLOYMENT.md**.
