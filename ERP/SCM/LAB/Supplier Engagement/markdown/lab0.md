# Lab 0 of 9 — Prerequisites & Environment Validation

*⏱ ~25 min · Setup*

Before installing Supplier Engagement, confirm that your SCM environment, Dataverse integration, and virtual entity solutions all meet the requirements. A clean pre-flight avoids installation failures later. You will also set up the dedicated service account that all cloud flows and automation run under.

### Before you start
- [ ] System Administrator access to a D365 SCM environment.
- [ ] Access to Power Platform admin center (`admin.powerplatform.microsoft.com`).
- [ ] Access to Power Apps maker portal (`make.powerapps.com`).
- [ ] A dedicated Microsoft Entra ID service account is available (non-personal).

## Part A — Verify SCM Version

### Step 1 — Check the SCM build version
**Where:** Settings (gear icon) › About

In the **Version information** section, locate **Application version**. Confirm it is `10.0.48` with build `10.0.2645.52` or later.

> ✅ **Result:** Application version reads 10.0.48 (build 10.0.2645.52 or higher).

### Step 2 — Confirm the SCM environment is linked to Dataverse
**Where:** admin.powerplatform.microsoft.com › Manage › Environments › (your environment)

Supplier Engagement requires your Supply Chain Management environment to be connected to Dataverse. In the Power Platform admin center, open your environment and confirm it has a **Dataverse database** with an **Environment URL**. Learn more in the official [Power Platform integration with finance and operations apps](https://learn.microsoft.com/en-us/dynamics365/fin-ops-core/dev-itpro/power-platform/overview) documentation.

> **Note — Unified / merged environments:** If you are on a unified (merged finance and operations + Dataverse) environment, Dataverse is co-located and this prerequisite is met automatically — there is no separate "Power Platform integration" page to enable inside the SCM client.

> ✅ **Result:** The environment shows a Dataverse database and a resolvable environment URL.

## Part B — Verify Virtual Entity Solutions

### Step 3 — Confirm four required solutions are installed in Power Apps
Sign in to `make.powerapps.com`, select your environment → **Solutions → Managed** tab. Verify that all four solutions below are present:

| Required Solution | Purpose |
|---|---|
| `Dynamics 365 Company` | Legal entity support |
| `Dynamics Operations Virtual Entity Support` | Core virtual entity framework |
| `Microsoft Operations ERP Catalog` | Entity catalog |
| `Dynamics 365 ERP Virtual Entities` | Virtual entity definitions for SCM data |

If any are missing, install them via *Configure Dataverse virtual entities* on Microsoft Learn before continuing.

> ✅ **Result:** All four solutions appear in the Managed tab with status Installed.

### Step 4 — Verify Finance and Operations Virtual Entity app version
In the Power Platform admin center go to **Manage → Environments** → open your environment → **Resources → Dynamics 365 apps**. Find **Finance and Operations Virtual Entity** and confirm the version is `2.20.3385.8` or later. If outdated, select the app and click **Update**.

> ✅ **Result:** Finance and Operations Virtual Entity app shows version 2.20.3385.8 or higher.

## Part C — Service Account & Licensing

### Step 5 — Prepare the dedicated service account
Supplier Engagement requires a **dedicated Microsoft Entra ID service account** (not an app registration) for cloud flows, notifications, and background automation. Grant the account these roles:

| System | Required Role |
|---|---|
| Dataverse | `System Administrator` |
| Supply Chain Management | `System Administrator` |
| Microsoft Entra ID | `Power Platform Administrator` |

> **Note — Why these three roles?** Deployment and the ongoing automation span three different planes, so the identity needs admin on each:
> - **Power Platform Administrator (Entra)** — the "install & provision" role: installs the Supplier Engagement app and supplier portal, installs/updates the Finance and Operations Virtual Entity app, and provisions/reactivates the Power Pages site. These are environment- and tenant-scoped operations that a Dataverse admin alone can't perform.
> - **Dataverse System Administrator** — the "own the components & run the flows" role: imports the solutions, creates connection references, turns on the cloud flows and duplicate detection rules, and owns those flows at runtime (they execute under this identity).
> - **SCM System Administrator** — the "configure the ERP side" role: enables the feature, sets up workflows/batch jobs, security duties, and entity store refresh, generates the virtual entity metadata, and lets the SCM ↔ Dataverse data sync run under this identity.
>
> A single account holds all three because a flow in Dataverse pushes data into SCM through virtual entities and sends email — if the identity is missing any one role, you hit permission failures either during install or silently at runtime.

Use a shared mailbox such as `svc-suppliereng@yourtenant.onmicrosoft.com`. This account must have a valid mailbox — cloud flows that send email run under this identity.

> ⚠️ **Warning:** Do not use a personal mailbox as the service account. If the person leaves, all cloud flows stop. Use an IT-managed shared service account with a permanent mailbox.

> **Note — Addendum — MVP / single-tenant trial (alternate):** For a proof-of-concept or MVP where no dedicated service account is available, you can use your own licensed admin account as the flow owner instead. The dedicated account is a *production best practice*, not a technical requirement — what actually matters is that the identity you use meets all of the following:
> - **Native member of the target tenant** — use an account that lives in the same tenant as the SCM/Dataverse environment, not a guest (B2B) identity. If your personal account is a guest in this tenant, sign-in and flow ownership can behave unreliably; prefer a native member account, even a trial one.
> - **Has all three roles above** — Dataverse `System Administrator`, SCM `System Administrator`, and Entra `Power Platform Administrator`.
> - **Has a working mailbox in this tenant** — outbound onboarding/notification emails are sent as this identity, so the mailbox must be able to send.
> - **One identity per tenant** — because you are working across two tenants, keep a separate owner account in each. Do not try to share one flow-owner identity across both environments.
>
> **Trade-offs to accept for MVP:** flows, notifications, and background automation all run under *your* account, so emails appear to come from you, and if your account is disabled or loses a role the automation stops. That is acceptable for a demo/MVP — just plan to swap in a real dedicated service account before any production or shared use.

### Step 6 — Confirm licensing expectations
As of July 2026 the licensing model for Supplier Engagement is still under review for GA. For this preview:
- Your SCM environment needs a valid Dynamics 365 Supply Chain Management subscription.
- The supplier portal runs on Power Pages — a **30-day trial** is available during the preview.
- Dataverse capacity is consumed by global vendor and contact records.

> **Note — Preview terms:** These labs use a preview feature subject to supplemental terms of use. Do not configure in a production environment until the feature reaches general availability.

### Step 7 — Configure Microsoft Entra ID B2B for FSCM supplier users
Supplier Engagement invites every external supplier contact (Maria Santos, Klaus Weber, and any future supplier) into your tenant as a Microsoft Entra **B2B guest** — this is what actually lets them sign in to the portal. Configure the tenant and FSCM B2B invitation service *before* you rely on supplier invitations in Labs 5–6.

The Finance and Operations article [Export business-to-business (B2B) users to Microsoft Entra ID](https://learn.microsoft.com/en-us/dynamics365/fin-ops-core/dev-itpro/sysadmin/implement-b2b) still describes the right high-level FSCM pattern: create an Entra app registration, store its client details in FSCM, and let the vendor user workflow provision B2B guests. However, the article uses older Azure portal labels such as *Web app / API*, *Required permissions*, and *Keys*. Use the current Microsoft Entra admin center labels below.

**A. Allow guest invitations in Microsoft Entra**
**Where:** `entra.microsoft.com` › Identity › External Identities › External collaboration settings

- **Guest invite settings** — confirm "who can invite guests" is not set to "No one". Members and admins should be able to invite.
- **Collaboration restrictions** — confirm invitations are allowed for the domains your test suppliers use (e.g., `pacificcomponents.com`, `alps-sensors.de`, or your own personal test inbox's domain). If restricted to an allow-list, add those domains; if a deny-list, make sure they're not on it.

**B. Create the B2B invitation service app registration**
**Where:** `entra.microsoft.com` › Identity › Applications › App registrations

1. Select **New registration**.
2. Name the app registration, for example `FSCM B2B Invitation Service`.
3. Set **Supported account types** to **Accounts in this organizational directory only**.
4. Leave **Redirect URI** blank unless your tenant policy requires one. If required, choose **Web** and enter your FSCM environment URL.
5. Select **Register**, then copy the **Application (client) ID** and **Directory (tenant) ID**.
6. Open **API permissions** › **Add a permission** › **Microsoft Graph**. Add the permissions below, using the **Application permissions** and **Delegated permissions** tabs as shown. Then select **Grant admin consent** so every permission shows as granted for the tenant.

| Permission | Type | Why it is needed |
|---|---|---|
| `Directory.ReadWrite.All` | Application | Lets the service write directory objects created by the invitation flow. |
| `User.Invite.All` | Application | Lets the service invite guest users to the organization without an interactive user. |
| `User.ReadWrite.All` | Application | Lets the service create and update user profile details required by the workflow. |
| `Directory.ReadWrite.All` | Delegated | Matches the FSCM B2B invitation setup requirements for user-context operations. |
| `User.Invite.All` | Delegated | Allows guest invitation operations when the workflow runs in delegated context. |
| `User.Read` | Delegated | Allows sign-in and basic profile read for the configured app. |
| `User.ReadWrite.All` | Delegated | Allows user profile updates when the workflow runs in delegated context. |

7. Open **Certificates & secrets** › **Client secrets** › **New client secret**. Create a secret and copy the **Value** immediately; you cannot retrieve it later.

> **Security note:** The client secret is equivalent to a password for this provisioning app. Store it in your organization's approved secret store, set an expiration that matches your security policy, and rotate it before expiry.

**C. Configure FSCM to use the B2B invitation service**
**Where:** FSCM › System administration › Setup › Microsoft Entra ID › B2B Invitation Configuration

1. Open **B2B Invitation Configuration** and select **Edit**.
2. Set **Enabled** to **Yes**.
3. Confirm **Tenant ID** matches the Entra **Directory (tenant) ID**.
4. Enter the app registration's **Application (client) ID** in **Client ID**.
5. Enter the copied client secret **Value** in **Application Key**.
6. Save the configuration.

**D. Verify the vendor user workflow uses B2B provisioning**
**Where:** FSCM › System administration › Workflow › User workflows

Open **Vendor user request (new user or modify user)** and confirm the workflow includes the **Provision Microsoft Entra ID B2B user** task before the request completes. If it is missing, add it from **Automated tasks**. Lab 3 configures the approval behavior and exact placement for supplier portal user requests; this prerequisite makes sure the workflow can create the Entra B2B guest when the request is approved.

> **Note — Why this matters:** if guest invites are blocked at the tenant level, the portal's invitation email (Lab 5) and the Teams-invite workaround (Lab 6, Step 3) both silently fail to create a guest account — you only discover this later as a sign-in error. Checking it here avoids that troubleshooting path entirely.

> ✅ **Result:** External collaboration settings permit guest invitations for your test supplier domains, and FSCM is configured to provision approved supplier users as Microsoft Entra B2B guests.
