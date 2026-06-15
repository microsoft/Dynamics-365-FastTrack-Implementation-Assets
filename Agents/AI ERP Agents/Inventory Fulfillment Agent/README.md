# Inventory Fulfillment Agent — Installation Playbook

> **Document:** Installation playbook
> **Audience:** Customer implementation teams, Power Platform admins, F&O admins, and solution owners
> **Status:** Deployment-ready working version
> **Last updated:** 15 June 2026

> **Before you start:** This guide assumes Inventory Visibility is being configured in a new environment. Save the Entra app registration values, IVS endpoint, environment ID, and default legal entity because they are required during solution import.

## Prerequisites

1. **Set up a Microsoft Entra app registration for Inventory Visibility.**
   Create the app registration and client secret used by Inventory Visibility. Save the Application/client ID, client secret value, and tenant ID. Use a separate app registration for each IVS environment.
   References: [Register an application](https://learn.microsoft.com/en-us/entra/identity-platform/quickstart-register-app) · [Add app credentials](https://learn.microsoft.com/en-us/entra/identity-platform/how-to-add-credentials)

2. **Install and set up Inventory Visibility.**
   Install the Dynamics 365 Inventory Visibility add-in and complete the Supply Chain Management setup. Confirm Inventory Visibility is installed, the integration is enabled, and inventory data is syncing.
   Reference: [Install and set up Inventory Visibility](https://learn.microsoft.com/en-us/dynamics365/supply-chain/inventory/inventory-visibility-setup)

3. **Set up Product Search for Inventory Visibility.**
   Product search must be installed and configured before the agent can search for products. Confirm the required product data has synced and the product search API can return results.
   Reference: [Set up product search for Inventory Visibility](https://learn.microsoft.com/en-us/dynamics365/supply-chain/inventory/inventory-visibility-product-search)

4. **Optional: set up ATP.**
   If users need Available-to-Promise responses, configure Inventory Visibility ATP. If ATP is not needed, disable the ATP tool after import and adjust the agent instructions.
   Reference: [Inventory Visibility on-hand change schedules and ATP](https://learn.microsoft.com/en-us/dynamics365/supply-chain/inventory/inventory-visibility-available-to-promise)

5. **Enable the Finance and Operations MCP (required for transfer orders and sales orders).**
   The transfer order and sales order child agents call Dynamics 365 F&O through the Model Context Protocol (MCP). Make sure the F&O MCP is enabled before testing these workflows.
   Reference: [Dynamics 365 F&O Model Context Protocol](https://learn.microsoft.com/en-us/dynamics365/fin-ops-core/dev-itpro/copilot/copilot-mcp)

## Download the Solution

Download the Inventory Fulfillment Agent solution ZIP from the FastTrack implementation assets repository.

[Inventory Fulfillment Agent on GitHub](https://github.com/microsoft/Dynamics-365-FastTrack-Implementation-Assets/tree/master/Agents/AI%20ERP%20Agents/Inventory%20Fulfillment%20Agent)

Download the solution `.zip` file. **Do not extract it before importing.**

## Import the Solution

1. Go to Power Apps at [make.powerapps.com](https://make.powerapps.com).
2. Select the target environment.
3. Go to **Solutions**.
4. Select **Import solution**.
5. Browse to the downloaded `.zip` file.
6. Select **Next**.
7. If prompted for a Dynamics 365 Finance and Operations connection, select or create the connection used by the order child agents.
8. Enter the environment variable values listed below.
9. Select **Import**.

Reference: [Import solutions in Power Platform](https://learn.microsoft.com/en-us/power-apps/maker/data-platform/import-update-export-solutions)

## Environment Variables

During import, enter the values for the target environment. The table below explains what each value is and where it normally comes from.

| Environment variable | What to enter | Where to get it |
| --- | --- | --- |
| IVS_TenantId | Microsoft Entra tenant ID used by the IVS app registration. | Microsoft Entra app registration or Azure tenant overview. |
| IVS Inventory Visibility Endpoint | Inventory Visibility endpoint, for example `https://inventoryservice.<region-stamp>.gateway.prod.island.powerapps.com`. | Inventory Visibility setup or endpoint details for the installed IVS add-in. |
| IVS Client ID | Application/client ID from the Entra app registration. | Microsoft Entra app registration overview. |
| IVS Client Secret | Client secret **value** from the app registration (not the secret ID). Enter directly into the variable; do not record elsewhere. | Microsoft Entra app registration secret created for IVS. |
| IVS_EnvironmentId | IVS/F&O environment GUID used by the Inventory Visibility API route. | Dynamics 365 / IVS environment details. |
| IVS Default Legal Entity | Default company/legal entity code, for example `usrt` or `usmf`. | Dynamics 365 Finance and Operations legal entity setup. |

## Turn On the Cloud Flows

Managed solutions may import cloud flows in a deactivated state. Turn them on in this order — the access-token flow **must** be on first because the others depend on it.

1. **Get IVS Access Token** — turn on first; confirm a successful run in the flow run history.
2. IVS ATP / Inventory Check
3. IVS Product Search
4. IVS Onhand Reserve
5. IVS Onhand Unreserve

> If the agent returns token or authentication errors during testing, this step (or the environment variables above) is the usual cause.

## Test the Agent

After import completes, turn on the flows, then open the agent in Copilot Studio and test the main capabilities.

> **Note:** These test steps assume the agent is being tested against **Contoso Demo data**. Substitute your own item, site, warehouse, and customer values when testing other environments.

- Search for product 81327
- Check stock for item 81327
- Check ATP for item 81327 at site central warehouse dc-central
- Reserve 2 of item 81327 at site central warehouse dc-central
- Create a transfer order for item 81327 from warehouse houston to warehouse dc-central quantity 1
- Create a sales order for customer US-001 for item 81327 quantity 2

## Publish the Agent

When validation has passed (and F&O MCP validation has passed if transfer/sales order workflows are in scope), publish the agent in Copilot Studio — or leave it explicitly ready for customer-controlled publishing. Configure channels if channel deployment is in scope.

## Capabilities

The agent supports the following business tasks:

- Product search
- On-hand inventory checks
- ATP checks
- Soft reservations
- Unreservation
- Transfer order creation
- Sales order creation

## Tools and Child Agents

IVS actions are implemented as tools. A tool is a specific callable action, such as checking inventory, searching products, reserving stock, or unreserving stock.

Transfer orders and sales orders are handled by child agents. A child agent is used for a more complex process that may require multiple steps, such as summarising the request, asking for confirmation, creating a header, and then creating lines.

## Customizing the Agent

You can modify the agent after import to match the capabilities you want to expose.

- If you do not use ATP, disable the ATP tool and remove ATP references from the instructions.
- If you do not want users to create reservations, disable the reserve and unreserve tools.
- If you only want inventory lookup, disable the transfer order and sales order child agents.
- Adjust the instructions to match your company terminology, warehouse naming, fulfilment rules, and support model.

## Troubleshooting

| Symptom | Likely cause | Action |
| --- | --- | --- |
| `AADSTS7000222` in Get IVS Access Token | Entra client secret is expired. | Create a new app credential, update the client secret variable, publish, and rerun Get IVS Access Token. |
| `401 invalid_client` in token flow | Wrong client secret, client ID, tenant, or expired credential. | Validate tenant ID, client ID, secret value, and credential expiry in Entra. |
| Access token succeeds but IVS token fails | Wrong environment ID, or service principal access. | Validate the environment ID, IVS setup, and app permissions. |
| IVS HTTP call reached but inventory call fails | Wrong endpoint URL / environment ID, IVS not installed, or item/dimension data missing. | Confirm endpoint values and test with known IVS data. |
| A flow cannot be turned on | Missing connection, missing environment variable, or insufficient permission. | Fix connection references and variables, then turn on Get IVS Access Token before the dependent flows. |
| F&O MCP calls fail with access denied | Connection user lacks F&O security permissions, or the MCP client is not allowed. | Validate F&O security roles and the Allowed MCP Clients configuration. |
| Solution import fails | Missing dependency or insufficient import privilege. | Download the import log, resolve the dependency, and retry with sufficient permissions. |

## Quick Setup Checklist

- [ ] Entra app registration created and client secret saved securely (not in notes).
- [ ] Inventory Visibility installed and configured.
- [ ] Product Search configured and synced.
- [ ] ATP configured if required.
- [ ] F&O MCP prerequisites met (if transfer/sales orders are in scope).
- [ ] Solution ZIP downloaded from GitHub.
- [ ] Finance and Operations connection selected during import.
- [ ] Environment variables entered for the target environment.
- [ ] Cloud flows turned on (Get IVS Access Token first).
- [ ] Agent tested in Copilot Studio.
- [ ] Agent published and ready for end-user consumption.

## Microsoft References

| Area | Reference |
| --- | --- |
| Copilot Studio licensing and access | https://learn.microsoft.com/en-us/microsoft-copilot-studio/requirements-licensing-subscriptions |
| Power Platform solution import | https://learn.microsoft.com/en-us/power-apps/maker/data-platform/import-update-export-solutions |
| Environment variables | https://learn.microsoft.com/en-us/power-apps/maker/data-platform/environmentvariables |
| Connection references | https://learn.microsoft.com/en-us/power-apps/maker/data-platform/create-connection-reference |
| Inventory Visibility setup | https://learn.microsoft.com/en-us/dynamics365/supply-chain/inventory/inventory-visibility-setup |
| Microsoft Entra app registration | https://learn.microsoft.com/en-us/entra/identity-platform/quickstart-register-app |
| Microsoft Entra app credentials | https://learn.microsoft.com/en-us/entra/identity-platform/how-to-add-credentials |
| Dynamics 365 F&O MCP | https://learn.microsoft.com/en-us/dynamics365/fin-ops-core/dev-itpro/copilot/copilot-mcp |
