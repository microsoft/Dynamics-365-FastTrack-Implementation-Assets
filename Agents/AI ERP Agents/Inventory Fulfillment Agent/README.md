# Inventory Fulfilment Agent — Installation Playbook

> **Document:** Installation playbook
> **Audience:** Customer implementation teams, Power Platform admins, F&O admins, and solution owners
> **Status:** Deployment-ready working version
> **Last updated:** 06 May 2026

> [!WARNING]
> **Security note —** Do not store client secrets in this document.
> The IVS client secret must be entered directly into the relevant Power Platform environment variable. Do not paste, screenshot, email, or record the secret in this playbook or in implementation notes.

---

## 📑 Table of Contents

1. [Purpose](#-purpose)
2. [How to Use This Playbook](#-how-to-use-this-playbook)
3. [What Gets Installed](#-what-gets-installed)
4. [Setup Summary](#-setup-summary)
5. [Prerequisites](#-prerequisites)
6. [Required Environment Values](#-required-environment-values)
7. [Deploy IFA](#-deploy-ifa)
8. [Validate IFA](#-validate-ifa)
9. [Troubleshooting](#-troubleshooting)
10. [Microsoft References](#-microsoft-references)

---

## 🎯 Purpose

This playbook describes how to get the **Inventory Fulfilment Agent (IFA)** running in a customer Power Platform environment.

IFA is delivered as a managed Power Platform solution containing:

- Copilot Studio agent components
- Inventory Visibility Service (IVS) tools
- Dynamics 365 Finance and Operations (F&O) MCP actions
- Power Automate cloud flows

Environment-specific values are supplied after import through environment variables and connection references. The intended outcome is a **published, validated agent** that can run inventory, reservation, transfer order, and sales order workflows according to the scope enabled for the customer environment.

---

## 🧭 How to Use This Playbook

| Section | Use it for |
| --- | --- |
| [What Gets Installed](#-what-gets-installed) | Confirm the imported solution components and ownership boundaries. |
| [Setup Summary](#-setup-summary) | Understand the deployment sequence before starting. |
| [Prerequisites](#-prerequisites) | Confirm licensing, access, Power Platform, IVS, and F&O MCP readiness. |
| [Required Environment Values](#-required-environment-values) | Collect the values needed for variables, references, and validation. |
| [Deploy IFA](#-deploy-ifa) | Run the import and configuration steps with exit checks. |
| [Validate IFA](#-validate-ifa) | Test IVS, Copilot Studio, reservation, and F&O MCP behaviours. |
| [Troubleshooting](#-troubleshooting) | Map common symptoms to likely causes and corrective action. |
| [Microsoft References](#-microsoft-references) | Use official Microsoft documentation for supporting detail. |

---

## 📦 What Gets Installed

| Component area | Included items |
| --- | --- |
| **Copilot Studio agent** | Inventory Fulfilment Agent and child agents for order workflows. |
| **Agent actions** | IVS inventory actions and Dynamics 365 F&O MCP actions. |
| **Cloud flows** | IVS token, inventory, product search, reservation, and unreservation flows. |
| **Environment variables** | IVS tenant, app registration, endpoint, scope, and environment values. |
| **Connection references** | Dynamics 365 Finance and Operations connector reference. |
| **Knowledge** | Fulfilment proposal knowledge file, where included in the package. |

---

## 🚀 Setup Summary

1. Confirm Copilot Studio, Power Platform, IVS, and F&O MCP prerequisites.
2. Import the IFA Power Platform solution into the target environment.
3. Populate the IVS environment variables with customer-specific values.
4. Configure the Dynamics 365 F&O connection reference.
5. Turn on **Get IVS Access Token**, then turn on the dependent IVS flows.
6. Validate IVS, Copilot Studio, and F&O MCP calls with known customer data.
7. Publish the agent — or leave it explicitly ready for customer-controlled publishing.

---

## ✅ Prerequisites

Complete these checks before import. Treat any failed prerequisite as a deployment blocker unless the scope has been explicitly reduced.

### Licensing

| Area | Requirement |
| --- | --- |
| Copilot Studio | Environment has entitlement to create, configure, test, and publish the agent. |
| Power Platform & Power Automate | Installer can import solutions, configure flows, and use required connectors. |
| Dynamics 365 F&O | Users invoking F&O operations have appropriate licensing and security access. |
| MCP usage | Review current F&O MCP and Copilot Studio credit guidance where relevant. |

### Access

| System | Required access |
| --- | --- |
| Power Platform | Import solution, update environment variables, configure connection references, turn on flows, and publish customisations. |
| Copilot Studio | Open, test, configure, and publish the imported agent. |
| Power Automate | Turn on flows and inspect run history. |
| Microsoft Entra | Read app registration details and create or rotate the IVS credential if needed. |
| Dynamics 365 F&O | Configure or validate MCP access and run F&O operations used by the agent. |

### Power Platform Environment

| Requirement | Check |
| --- | --- |
| Target environment selected | Installer is in the correct Power Platform environment before import. |
| Dataverse enabled | Environment supports solutions, variables, references, flows, and Copilot Studio. |
| Copilot Studio available | Agent can be opened in Copilot Studio for the target environment. |
| Solution import allowed | Installer can import a Power Platform solution package. |

### Inventory Visibility Service

| Requirement | Check |
| --- | --- |
| Inventory Visibility installed | Confirm in Lifecycle Services or Power Platform admin centre. |
| Environment linking correct | Check F&O / Dataverse linking mismatch warnings where applicable. |
| IVS endpoint known | Base URL and IVS environment ID are available. |
| Entra app registration exists | Tenant ID and application client ID are available. |
| App credential valid | Client secret exists, is not expired, and can acquire a token. |
| IVS data exists | At least one known item / site / warehouse combination can be used for validation. |

### Finance and Operations MCP

| Requirement | Check |
| --- | --- |
| Product version | F&O version satisfies the current MCP prerequisite. The supplied guidance states **at least 10.0.47**. |
| Environment tier | Target environment is **Tier 2 or above**, or Unified Developer Environment. |
| MCP feature | Dynamics 365 ERP Model Context Protocol server feature is enabled. |
| Allowed MCP client | Copilot Studio is allowed as an MCP client in F&O. |
| Security access | Connection user has access to required data entities, forms, and actions. |

---

## 🔧 Required Environment Values

> [!IMPORTANT]
> **Before you start —** Collect these values before solution import where possible. Leave the IVS client secret out of written notes; enter it directly into the environment variable value field.

| Value | Used for | Notes |
| --- | --- | --- |
| Power Platform environment name | Confirm import target. | Example: `D365Commerce`. |
| Dataverse environment ID | Support and diagnostics. | Power Platform environment GUID. |
| F&O environment URL | F&O connector and MCP access. | Customer-specific F&O URL. |
| F&O product version | MCP readiness. | Must satisfy current MCP prerequisite. |
| F&O legal entity | IVS and order operations. | Example: `USRT`. |
| IVS base URL | IVS HTTP calls. | Environment-specific IVS endpoint. |
| IVS environment ID | IVS route and security token context. | Confirm expected IVS / F&O environment ID. |
| IVS tenant ID | Entra token request. | Tenant owning the IVS app registration. |
| IVS client ID | Entra token request. | Application client ID. |
| **IVS client secret** | Entra token request. | **Enter securely into the environment variable. Do not record in notes.** |
| IVS scope | Entra token request. | Example: `<resource-app-id>/.default`. |
| IVS security scope | IVS security token exchange. | Example: `https://inventoryservice.operations365.dynamics.com/.default`. |
| Test item ID | Validation. | Known item with IVS data. |
| Test site ID | Validation. | Required for ATP and reservation checks. |
| Test warehouse / location ID | Validation. | Maps to IVS `locationId`. |
| Test customer account | Sales order validation. | Required only if sales order flow is validated. |
| Transfer warehouses | Transfer order validation. | Source and destination warehouses must differ. |

---

## 🛠️ Deploy IFA

### Step 1 — Import the Solution

| # | Action |
| :-: | --- |
| 1 | Open the Power Apps maker portal. |
| 2 | Select the target Power Platform environment. |
| 3 | Open **Solutions**. |
| 4 | Select **Import solution**. |
| 5 | Select the IFA solution package. |
| 6 | Review the solution name, publisher, version, and package type. |
| 7 | Resolve dependency warnings. |
| 8 | Select or create required connections when prompted. |
| 9 | Enter required environment variable values if prompted. |
| 10 | Start the import and wait for completion. |

> ✅ **Exit check —** The Inventory Fulfilment Agent solution appears in the target environment.

---

### Step 2 — Configure IVS Environment Variables

| # | Action |
| :-: | --- |
| 1 | Open the imported Inventory Fulfilment Agent solution. |
| 2 | Select **Environment variables**. |
| 3 | Update the IVS variables with customer-specific values. |
| 4 | Resolve every environment variable warning. |
| 5 | Save changes. |
| 6 | Select **Publish all customisations**. |

> ✅ **Exit check —** The solution overview no longer reports missing required environment variable values.

#### Expected IVS Variables

| Display name | Typical logical name | Required value |
| --- | --- | --- |
| `IVS_BaseUrl` | `ftc_IVS_BaseUrl` or `new_IVS_BaseUrl` | IVS base endpoint URL. |
| `IVS_ClientId` | `ftc_IVS_ClientId` or `new_IVS_ClientId` | Entra application client ID. |
| `IVS_ClientSecret` | `ftc_IVS_ClientSecret` or `new_IVS_ClientSecret` | Entra app client secret. |
| `IVS_EnvironmentId` | `ftc_IVS_EnvironmentId` or `new_IVS_EnvironmentId` | IVS / F&O environment ID. |
| `IVS_Scope` | `ftc_IVS_Scope` or `new_IVS_Scope` | Entra token request scope. |
| `IVS_TenantId` | `ftc_IVS_TenantId` or `new_IVS_TenantId` | Microsoft Entra tenant ID. |
| `IVS_SecurityScope` | `new_IVS_SecurityScope`, if present | IVS security token exchange scope. |

---

### Step 3 — Configure the F&O Connection Reference

| # | Action |
| :-: | --- |
| 1 | In the solution, select **Connection references**. |
| 2 | Open the Dynamics 365 F&O connection reference. |
| 3 | Bind it to a valid Dynamics 365 F&O connection. |
| 4 | Confirm the connection points to the correct F&O environment. |
| 5 | Save the connection reference. |

> ✅ **Exit check —** The connection reference has a valid connection and no warning is shown.

#### Connection Reference

| Connection reference | Connector |
| --- | --- |
| `cr91d_agent9_4ET9z6.shared_dynamicsax.shared-dynamicsax-96e68f2b-5d16-41f7-919c-77b16415d9a9` | `/providers/Microsoft.PowerApps/apis/shared_dynamicsax` |

---

### Step 4 — Turn On Cloud Flows

Turn on **Get IVS Access Token** first. Then turn on the dependent IVS flows in order.

| Order | Flow | Check |
| :-: | --- | --- |
| 1 | Get IVS Access Token | Flow turns on and token validation succeeds. |
| 2 | IVS ATP Inventory Check v2 *(or IVS inventory check flow)* | Flow turns on with no configuration errors. |
| 3 | IVS Product Search | Flow turns on with no configuration errors. |
| 4 | IVS Onhand Reserve v2 | Flow turns on with no configuration errors. |
| 5 | IVS Onhand Unreserve v2 | Flow turns on with no configuration errors. |

> ✅ **Exit check —** All required flows are on, and **Get IVS Access Token** has a successful run history entry.

---

### Step 5 — Open the Agent in Copilot Studio

| # | Action |
| :-: | --- |
| 1 | Open Copilot Studio. |
| 2 | Select the target environment. |
| 3 | Open **Inventory Fulfilment Agent**. |
| 4 | Confirm the imported actions, child agents, topics, and knowledge are present. |
| 5 | Use test chat to confirm the agent can select IVS actions and F&O child agents. |

> ✅ **Exit check —** The agent opens in Copilot Studio and can invoke the expected tools in test chat.

---

### Step 6 — Publish the Agent

| # | Action |
| :-: | --- |
| 1 | Confirm IVS validation has passed. |
| 2 | Confirm F&O MCP validation has passed if transfer order or sales order workflows are in scope. |
| 3 | Publish the agent. |
| 4 | Configure channels if channel deployment is in scope. |

> ✅ **Exit check —** The agent is published or explicitly left ready for customer-controlled publishing.

---

## 🧪 Validate IFA

Use known customer data for validation. Run only the scenarios that are in scope.

| Area | Prompt pattern | Expected result |
| --- | --- | --- |
| **Product search** | *"Find product `<search term>` in `<legal entity>`."* | Agent returns matching products or asks one focused clarification question. |
| **On-hand inventory** | *"Check on-hand inventory for item `<item>` in site `<site>` warehouse `<warehouse>`."* | Agent calls IVS and reports current inventory. |
| **ATP** | *"Check ATP for item `<item>` in site `<site>` warehouse `<warehouse>` for the next 7 days."* | Agent calls IVS ATP and reports projected availability. |
| **Reserve** | *"Reserve `<quantity>` of item `<item>` at site `<site>` warehouse `<warehouse>`."* | Agent asks for confirmation before reservation and returns reservation ID on success. |
| **Unreserve** | *"Unreserve reservation `<reservationId>` for item `<item>` at site `<site>` warehouse `<warehouse>` quantity `<quantity>`."* | Agent asks for confirmation and reports unreservation result. |
| **Transfer order** | *"Create a transfer order in `<legal entity>` from `<from warehouse>` to `<to warehouse>` for `<quantity>` of item `<item>`."* | Agent routes to Transfer Order Agent and uses F&O MCP after confirmation. |
| **Sales order** | *"Create a sales order in `<legal entity>` for customer `<customer>` for `<quantity>` of item `<item>`."* | Agent routes to Sales Order Agent and uses F&O MCP after confirmation. |

---

## 🩺 Troubleshooting

| Symptom | Likely cause | Action |
| --- | --- | --- |
| `AADSTS7000222` in `Get_Access_Token` | Entra client secret is expired. | Create a new app credential, update `IVS_ClientSecret`, publish, and rerun **Get IVS Access Token**. |
| `401 invalid_client` in token flow | Wrong client secret, wrong client ID, wrong tenant, or expired credential. | Validate tenant ID, client ID, secret, and credential expiry in Entra. |
| `Get_Access_Token` succeeds but `Get_IVS_Token` fails | IVS security scope, environment ID, or service principal access is wrong. | Validate `IVS_SecurityScope`, `IVS_EnvironmentId`, IVS setup, and app permissions. |
| IVS flow reaches HTTP action but inventory call fails | Wrong IVS base URL / environment ID, IVS not installed, or item / dimension data missing. | Confirm endpoint values and test known IVS data. |
| Flow cannot be turned on | Missing connection, missing environment variable, invalid child flow reference, or insufficient permission. | Fix connection references and environment variables, then turn on **Get IVS Access Token** before dependent flows. |
| Agent selects IVS action but missing values reach the flow | Action input mapping or Copilot Studio tool binding is incomplete. | Inspect action inputs and ensure required flow trigger inputs are exposed to the agent. |
| F&O MCP calls fail with access denied | Connection user lacks F&O security permissions or MCP client is not allowed. | Validate F&O security roles and **Allowed MCP Clients** configuration. |
| Solution import fails | Missing dependency or insufficient import privilege. | Download import log, resolve dependency, and retry with sufficient Power Platform permissions. |

---

## 📚 Microsoft References

| Area | Reference |
| --- | --- |
| Copilot Studio licensing and access | <https://learn.microsoft.com/en-us/microsoft-copilot-studio/requirements-licensing-subscriptions> |
| Power Platform solution import | <https://learn.microsoft.com/en-us/power-apps/maker/data-platform/import-update-export-solutions> |
| Environment variables | <https://learn.microsoft.com/en-us/power-apps/maker/data-platform/environmentvariables> |
| Connection references | <https://learn.microsoft.com/en-us/power-apps/maker/data-platform/create-connection-reference> |
| Inventory Visibility setup | <https://learn.microsoft.com/en-us/dynamics365/supply-chain/inventory/inventory-visibility-setup> |
| Microsoft Entra app registration | <https://learn.microsoft.com/en-us/entra/identity-platform/quickstart-register-app> |
| Microsoft Entra app credentials | <https://learn.microsoft.com/en-us/entra/identity-platform/how-to-add-credentials> |
| Dynamics 365 F&O MCP | <https://learn.microsoft.com/en-us/dynamics365/fin-ops-core/dev-itpro/copilot/copilot-mcp> |
