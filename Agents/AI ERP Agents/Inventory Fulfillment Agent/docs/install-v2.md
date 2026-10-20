# Install and configure v2

Applies to **InventoryFulfillmentAgent_V2 2.0.0.1 (unmanaged)**. For legacy deployments, use the [v1 guide](legacy-v1-installation.md). This is deployable Power Platform/Copilot Studio source, not a local application.

## 1. Confirm the target

Record the intended tenant, Power Platform environment, Dataverse URL, F&O URL, IVS environment, agent owner, and deployment scope in your private deployment record.

- Obtain the required Copilot Studio licensing/capacity and the target's supported GitHub Copilot-based agent harness (`CLICopilotRecognizer`) and `Sonnet5` model availability. This package is not a standard-harness agent template. If the target does not support its elements/model, stop; do not silently convert it or shorten instructions.
- Use a supported Dynamics 365 Supply Chain Management environment; Product Search documents version 10.0.36 or later.
- Ensure the importing account has the necessary Dataverse solution and agent privileges (normally System Administrator for installation). Tenant Global Administrator and Dataverse System Administrator are separate.
- Review connector DLP policies, HTTP actions, Dataverse, F&O, ERP MCP access, maker access, agent sharing, and end-user access. They are not interchangeable permissions.
- Use a non-production target and back up existing components before upgrades. V2 installs separately from v1.

## 2. Install first-party prerequisites in order

**Do not import Product Search Core before the dual-write map importer is installed.**

| Order | Prerequisite | Verify before proceeding |
| --- | --- | --- |
| 1 | Dual-write core (`DualWriteCoreAnchor`) | Install completes; `msdyn_DualWriteCore` exists and map component type 500 (`msdyn_dualwriteentitymap`) is registered |
| 2 | Dual-write Application Core (`msdyn_DualWriteAppCoreAnchor`) | Install completes, including `msdyn_DualWriteAppCoreMaps` |
| 3 | Inventory Visibility, including Product Search Core | Use the supported Microsoft installer; `msdyn_ProductSearchCore` exists and contains six managed Product Search maps |
| 4 | IFA v2 | Import the reviewed IFA ZIP only after its dependencies are present |

Use **Power Platform admin center > Dynamics 365 apps** and Microsoft's current setup instructions. Do not start several solution installations concurrently or treat an accepted request as a completed installation.

Before installing Inventory Visibility, also verify that **Dynamics 365 Finance and Operations Platform Tools** is installed. Inventory Visibility uses a **custom setup wizard in the admin center**; the generic application-package install API does not support it. Prepare a dedicated application registration and supply its application ID and tenant ID in that wizard. Do not reuse another environment's IVS registration, even for a structural installation test.

If an installation fails because another import or entity customization is running, retain the failed operation details and let the competing operation finish before a controlled retry. Check the enclosing application's installation result as well as its underlying solution imports; a successful solution import alone is not application-installation sign-off. Do not clear internal locks or cancel unrelated deployments.

A same-version app reinstall can log `SkipSameVersion` and leave a previously incomplete Product Search import untouched. If maps are missing, diagnose installed component ownership and dependency order; do not reset a healthy dual-write link or delete Microsoft solutions blindly.

For a structural import test, prerequisite schemas can be installed without enabling maps or populating data. That does **not** make Product Search or IVS operational.

### For a connected deployment

1. Create a dedicated IVS application registration and configure it using the [IVS installation guide](https://learn.microsoft.com/en-us/dynamics365/supply-chain/inventory/inventory-visibility-setup). Do not re-register another environment's IVS service with a shared app as a shortcut.
2. Configure the correct F&O-to-Dataverse dual-write link and company setup, privileges, owner teams, and integration users.
3. Refresh the F&O entity list and wait for the batch to finish.
4. In dual-write, apply **Dynamics 365 Product Search Core**. It supplies these six maps:
   - Released products V2
   - Released product variants
   - Inventory batch attributes V2
   - Product attribute definitions
   - Product attribute values
   - Product translations
5. Run required company/reference prerequisites, then initial sync for the six Product Search maps with **Finance and Operations apps** as master. Review per-company errors and actual row identities, not just a Running state.
6. Configure inventory synchronization, required IVS measures/formulas, reservations, and ATP if used. Verify the IVS service and product-search projection with known fixtures.
7. Enable ERP MCP for the intended F&O connector and user. Use Microsoft's supported connector route; do not allowlist unrelated CLI clients as a workaround.

Current references: [dual-write prerequisites](https://learn.microsoft.com/en-us/dynamics365/fin-ops-core/dev-itpro/data-entities/dual-write/requirements-and-prerequisites), [separated Application Core package](https://learn.microsoft.com/en-us/dynamics365/fin-ops-core/dev-itpro/data-entities/dual-write/separated-solutions), [Product Search setup](https://learn.microsoft.com/en-us/dynamics365/supply-chain/inventory/inventory-visibility-product-search), [ERP MCP](https://learn.microsoft.com/en-us/dynamics365/fin-ops-core/dev-itpro/copilot/copilot-mcp).

## 3. Download and verify the package

Download [the v2 ZIP](../Solutions/InventoryFulfillmentAgent_V2_2.0.0.1_unmanaged.zip) and [its checksum](../Solutions/InventoryFulfillmentAgent_V2_2.0.0.1_unmanaged.zip.sha256).

```powershell
Get-FileHash -LiteralPath .\InventoryFulfillmentAgent_V2_2.0.0.1_unmanaged.zip -Algorithm SHA256
```

Compare against the sidecar. Import the ZIP unchanged; do not extract it or import GitHub's repository download ZIP. See [release validation](validation.md) for the tested identity.

## 4. Prepare the target settings

Copy [deployment-settings.v2.example.json](../Solutions/deployment-settings.v2.example.json) to an owner-restricted location **outside Git**. All seven values and both connection IDs in the example are intentionally blank.

| Schema name | Target value |
| --- | --- |
| `ftc_IFAV2_IVS_BaseUrl` | Actual IVS service endpoint; no trailing API route or source-environment endpoint |
| `ftc_IFAV2_IVS_ClientId` | IVS application/client ID |
| `ftc_IFAV2_IVS_ClientSecret` | Client-secret **value**, not secret ID |
| `ftc_IFAV2_IVS_DefaultLegalEntity` | Intended default F&O company; obtain it from the target owner, not the sample |
| `ftc_IFAV2_IVS_EnvironmentId` | IVS resource environment ID used in IVS API routes; not automatically the new agent-host environment ID |
| `ftc_IFAV2_IVS_Scope` | Normally `0cdb527f-a8d1-4bf8-9436-b352c68682b2/.default`; verify against current IVS guidance |
| `ftc_IFAV2_IVS_TenantId` | Tenant for the IVS app/service identity |

The agent uses the explicit company when supplied, otherwise the configured IVS default obtained through its tools. An unavailable tool/default is a setup problem, not permission to fall back to the ERP user's current company.

The secret variable is a **String**, not a Key Vault reference. Protect the settings file and environment-variable access. Never log it or put it in a command line, pull request, or issue.

### Connection references

Keep the example's long logical names unchanged. Select connections that actually exist in the target:

| Connector | Used by | Configuration |
| --- | --- | --- |
| Microsoft Dataverse (`shared_commondataserviceforapps`) | Product resolver's attribute lookup | Bind to the intended target Dataverse connection; the synchronized Product Search tables must exist there |
| Finance and Operations (`shared_dynamicsax`) | Native Dynamics 365 ERP MCP tool | Bind to the intended F&O endpoint and authorized user; retain the packaged invoker/run-as contract |

A connection ID from another Power Platform environment cannot simply be reused. Reusing an existing IVS endpoint for a read-only test also does **not** provide the new Dataverse environment with its catalogue tables/data, projection configuration, F&O connection, or per-user consent. Record that test boundary explicitly.

## 5. Import

### Power Apps

1. Open [Power Apps](https://make.powerapps.com/), select the verified target, and choose **Solutions > Import solution**.
2. Select the v2 ZIP. Review dependencies; do not skip failed dependency checks.
3. Bind both connection references and enter the target environment values.
4. Complete import and retain the import job/log privately.

### Optional Power Platform CLI

Use the current `pac solution import help` and verify the authenticated account and target first.

```powershell
pac org who --environment <target-dataverse-url>
pac solution import --environment <target-dataverse-url> `
  --path .\InventoryFulfillmentAgent_V2_2.0.0.1_unmanaged.zip `
  --settings-file <protected-target-settings-path> `
  --activate-plugins false
```

`--activate-plugins false` is not a reliable guarantee that request-triggered cloud flows remain inactive. Check all five actual states after import. Automatic agent publication is disabled in the package.

## 6. Inspect the imported runtime

Expected contents:

- One agent: schema `ftc_inventoryfulfilmentagentv2_9kWGCB`, Microsoft authentication.
- Eleven runtime bot components: two order skills, two skill metadata files, four workflow tools, one ERP MCP tool, one fulfillment-policy file, and one documentation knowledge source.
- Five solution-owned flows:
  1. **IFA - Get IVS Access Token**
  2. **IFA - Exact Item Inventory Check** (inventory and ATP)
  3. **IFA - Product Search and Resolver**
  4. **IFA - Onhand Reserve**
  5. **IFA - Onhand Unreserve**
- Four native tool-to-workflow registrations. The token helper is internal and is not a fifth exposed agent tool.
- One native MCP-to-connection-reference association.
- Seven environment-variable definitions and two connection references.

Open the agent in Copilot Studio and inspect validation errors, tools, skills, knowledge, authentication, and model. A workflow GUID in tool YAML is not enough: its native association must exist and point to the imported flow.

Once configuration is complete, activate the token-helper flow first, then dependent flows. Verify connections and flow validation before invoking them. There are no separate v2 inventory and ATP flows; they share the exact-item tool.

## 7. Accept and publish deliberately

Follow the [acceptance checklist](validation.md). Start with scoped read-only requests; confirm the actual product, company, site, warehouse, and returned quantities. "No rows" is not proof of no physical stock.

Reservation and order tests require explicit approval, disposable fixtures, and before/after reconciliation. Do not execute the legacy sample mutation prompts as a casual installation check.

Review the demo fulfillment knowledge before deployment: it assumes Central/Houston and orders alternatives by demo policy. Customer lead times and fulfillment rules must be configured and tested, not inferred from demo stock.

Publish only after acceptance. Confirm the server's published timestamp and successful status, then test the actual Teams or Microsoft 365 Copilot channel as the intended user. HTTP 200, Preview, and a published timestamp establish different things.

## Troubleshooting

| Symptom | What to check |
| --- | --- |
| `prvReadbot` or other Dataverse privilege missing | Assign the appropriate target Dataverse role through approved administration; tenant admin membership alone is not enough |
| Import requires `cc_attribute` | Product Search Core must be installed before IFA |
| Apply solution is empty/missing Product Search | Verify core importer and Application Core installed first, then all six managed Product Search maps; a connection reset does not install missing maps |
| Tools show missing flow or connection | Check native workflow/MCP associations, target IDs, connection owner/consent, and actual flow state |
| Unknown bot element/model | Verify the target supports this harness/model; do not silently rewrite the sample |
| Token or IVS authentication failure | Verify all seven values, credential expiry, IVS registration and token exchange, and secure flow run diagnostics |
| Product lookup returns no rows | Verify company-aware catalogue sync, derived name/attribute projection, and item/variant/attribute constraints; do not invent a match |
| ATP returns no dates | Verify source schedules and ATP configuration; enabled ATP alone does not prove time-phased data exists |
| Publish fails on null Teams command title | Remove malformed empty conversation starters; do not reduce instruction bodies as a speculative fix |
| Location label looks inconsistent | Stop before a write and resolve the company/site/warehouse explicitly; see known defect FUL-014 |

Do not attach signed URLs, tokens, credentials, raw conversation evidence, or private tenant exports to a public support request.
