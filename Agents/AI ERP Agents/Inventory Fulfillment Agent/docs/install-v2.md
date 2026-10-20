# Install and configure v2

Applies to **InventoryFulfillmentAgent_V2 2.0.0.1 (unmanaged)**. For legacy deployments, use the [v1 guide](legacy-v1-installation.md). This is deployable Power Platform/Copilot Studio source, not a local application.

## Choose your starting point

| Your situation | Route |
| --- | --- |
| IVS and Product Search already work for the intended F&O/Dataverse pair | Complete stage 1's readiness checks. Keep the existing IVS registration and service; do not reinstall or re-register them. Continue at stage 2 when the checks pass. |
| A new environment or incomplete IVS/Product Search setup | Complete the first-party setup in stage 1, including its connected-data checks, before continuing. |
| You only need an isolated package-import test | Install prerequisite schemas in order, then inspect the imported runtime and run the no-tool Preview check. Do not call it operational or production-ready without connected acceptance. |

**Journey:** [Prepare](#1-prepare-your-environment) → [Connect](#2-connect-and-collect-configuration) → [Install](#3-install-the-verified-package) → [Configure](#4-configure-the-imported-runtime) → [Verify](#5-verify-safely) → [Publish](#6-publish-and-hand-over).

The stages below describe actions for an authorized implementation team. Creating identities/connections, starting synchronization, importing, testing writes, and publishing need approval for the intended target; following this guide is not that approval.

## 1. Prepare your environment

**Owner:** Power Platform administrator, with Entra and F&O administrators. **Where:** the target tenant's admin center, Copilot Studio, and F&O.

### Agree responsibilities

| Role | Prepare and verify |
| --- | --- |
| Power Platform administrator | Target environment/Dataverse URL, licenses/capacity, solution privileges, DLP, and first-party app installations |
| Entra administrator / IVS identity owner | Dedicated IVS registration for a new service, approved permissions, protected credential, and rotation owner |
| F&O administrator | Correct environment link, intended companies, dual-write prerequisites/sync, IVS integration, and ERP MCP availability/user permissions |
| Agent owner / business tester | Connection ownership, model/harness eligibility, customer fulfillment policy, test fixtures, publication and support ownership |

One person can cover multiple roles, but ownership must be explicit. Global Administrator does not automatically supply Dataverse or F&O permissions.

### Confirm target and compatibility

Record the intended tenant, Power Platform environment, Dataverse URL, F&O URL, IVS environment, agent owner, and deployment scope in your private deployment record.

- In [Copilot Studio](https://copilotstudio.microsoft.com/), select the intended environment and confirm that the **GitHub Copilot-based agent experience** is available to the importing account. Confirm that its model selector supports the packaged **`Sonnet5`** model (display labels can vary). If these controls are unavailable or access is unclear, stop and have the tenant/feature owner confirm eligibility before import. A standard generative-orchestration agent is not proof of compatibility with `CLICopilotRecognizer`.
- Use a supported Dynamics 365 Supply Chain Management environment. Product Search requires 10.0.36 or later, but that is **not the overall minimum for IFA**: ERP MCP must also expose the tools listed below.
- Ensure the importing account has the necessary Dataverse solution and agent privileges (normally System Administrator for installation). Tenant Global Administrator and Dataverse System Administrator are separate.
- Review connector DLP policies, HTTP actions, Dataverse, F&O, ERP MCP access, maker access, agent sharing, and end-user access. They are not interchangeable permissions.
- Use a non-production target and back up existing components before upgrades. V2 installs separately from v1.

### Install first-party prerequisites for a new setup

**Do not import Product Search Core before the dual-write map importer is installed.**

| Order | Prerequisite | Verify before proceeding |
| --- | --- | --- |
| 1 | Dual-write core (`DualWriteCoreAnchor`) | Install completes; `msdyn_DualWriteCore` exists and map component type 500 (`msdyn_dualwriteentitymap`) is registered |
| 2 | Dual-write Application Core (`msdyn_DualWriteAppCoreAnchor`) | Install completes, including `msdyn_DualWriteAppCoreMaps` |
| 3 | Dynamics 365 Finance and Operations Platform Tools | Application status is **Installed** before the IVS wizard |
| 4 | Inventory Visibility, including Product Search Core | Application status is **Installed**; `msdyn_ProductSearchCore` exists and contains six managed Product Search maps |

In [Power Platform admin center](https://admin.powerplatform.microsoft.com/), open the **target environment > Resources > Dynamics 365 apps** (navigation labels can vary). Use **Install app** for each prerequisite and wait for its **Installed** status before proceeding. In [Power Apps](https://make.powerapps.com/), select the same environment and open **Solutions** to inspect the named managed solutions.

Before step 4, have the Entra owner create **one dedicated registration for this new IVS service** and securely retain its application ID, tenant ID, and client-secret value according to [Microsoft's IVS setup guide](https://learn.microsoft.com/en-us/dynamics365/supply-chain/inventory/inventory-visibility-setup). Do not reuse another environment's IVS registration, even for a structural installation test. Existing working services keep their registration.

For **Dynamics 365 Inventory Visibility**, select **Install app > Next** to open the custom wizard. Enter **application id of service** and **tenant id of service**, review the terms, and submit once. The generic application-package install API does not support this custom wizard. Refresh the application status until it reaches **Installed**; do not submit another installation while it is running.

**Check the map importer and map inventory:** in the managed Product Search Core solution, inspect the dual-write map objects; the expected six are listed below. If the maker UI does not expose these objects, have the administrator inspect native `msdyn_dualwriteentitymap` records and their managed solution ownership. The native map importer is component type **500**, registered for that entity by Dual-write Core. A list of similarly named YAML tools or an **Apply solution** entry alone is not proof the maps imported.

An import/customization conflict is a stop condition: keep the operation details, let competing work finish, then use a controlled supported retry. Do not clear internal locks or delete first-party solutions. See [troubleshooting](#troubleshooting).

### Make the connected services ready

For an existing setup, verify these outcomes without resetting healthy integrations. For a new connected deployment, the F&O administrator follows Microsoft's current setup instructions:

1. Configure the correct F&O-to-Dataverse dual-write link and company setup, privileges, owner teams, and integration users.
2. In F&O, open **System administration > Workspaces > Data management > Framework parameters > Entity settings > Refresh entity list**. Wait for the batch to complete.
3. Return to **Data management > Dual-write > Apply solution** and apply **Dynamics 365 Product Search Core**. Verify these six managed maps (display labels can vary by package):
   - Released products V2
   - Released product variants
   - Inventory batch attributes V2
   - Product attribute definitions
   - Product attribute values
   - Product translations
4. With synchronization approved, complete company/reference prerequisites. Select the six maps, choose **Run**, enable **Initial sync**, and set **Master for initial sync** to **Finance and Operations apps**. Review per-company errors and actual row identities, not just a Running state.
5. Configure inventory synchronization, required IVS measures/formulas, reservations, and ATP if used. Confirm a known product can be found and its inventory can be read in IVS before involving the agent. ATP needs schedule data; empty dates do not prove populated ATP works.
6. Enable ERP MCP for the intended F&O environment and user. The packaged allowlist requires **all six** tools: `data_find_entity_type`, `data_get_entity_metadata`, `data_find_entities_sql`, `data_create_entities`, `data_update_entities`, and `data_delete_entities`. Check the intended connector's discovered tools against this list. An older static server or one exposing only `data_find_entities` is not equivalent. Follow the current ERP MCP client/security guidance; do not allowlist unrelated CLI clients or silently replace the packaged tool names.

Current references: [dual-write prerequisites](https://learn.microsoft.com/en-us/dynamics365/fin-ops-core/dev-itpro/data-entities/dual-write/requirements-and-prerequisites), [separated Application Core package](https://learn.microsoft.com/en-us/dynamics365/fin-ops-core/dev-itpro/data-entities/dual-write/separated-solutions), [Product Search setup](https://learn.microsoft.com/en-us/dynamics365/supply-chain/inventory/inventory-visibility-product-search), [ERP MCP](https://learn.microsoft.com/en-us/dynamics365/fin-ops-core/dev-itpro/copilot/copilot-mcp).

**Expected result:** correct target, supported harness/model and MCP tools, completed prerequisite apps, six managed maps, and working connected fixtures for an operational deployment.

- [ ] Preparation gate: prerequisites and intended test scope are confirmed; unsupported features or incomplete dependencies are resolved.

## 2. Connect and collect configuration

**Owner:** agent owner, assisted by Power Platform/F&O administrators. **Where:** Power Apps in the intended target environment and the IVS owner's protected configuration record.

### Create or select the two target connections

1. In [Power Apps](https://make.powerapps.com/), select the same target environment. Open **Connections** (under **More** if not pinned), then **New connection**, or inspect existing connections.
2. Select **Microsoft Dataverse**, sign in with the approved account, and verify that it can access the target's Product Search data.
3. Select **Fin & Ops Apps (Dynamics 365)**, provide the intended F&O instance when prompted, and authenticate with the approved F&O user. Do not select a different F&O environment simply because a cached connection works.
4. Confirm both connections show **Connected** and belong to the intended owner. During import, select these connections for their matching references. For CLI deployment, obtain each connection's ID from its connection details/URL, not its display name, connector ID, or an ID from another environment.

| Connector | Used by | Target check |
| --- | --- | --- |
| Microsoft Dataverse (`shared_commondataserviceforapps`) | Product resolver's attribute lookup | The intended Dataverse environment contains the synchronized Product Search tables/data |
| Fin & Ops Apps (`shared_dynamicsax`) | Native Dynamics 365 ERP MCP tool | The intended F&O instance and user expose the six required MCP tools |

Connection-owner consent is not end-user consent. Keep the packaged invoker/run-as contract; verify the intended users' access separately before channel rollout.

### Collect all seven values before import

Copy [deployment-settings.v2.example.json](../Solutions/deployment-settings.v2.example.json) to an owner-restricted location **outside Git**. All seven values and both connection IDs in the example are intentionally blank.

| Schema name | What to enter | Where to find or confirm it |
| --- | --- | --- |
| `ftc_IFAV2_IVS_BaseUrl` | IVS service endpoint, without an API route | Target Inventory Visibility app's endpoint/configuration details; see [find your service endpoint](https://learn.microsoft.com/en-us/dynamics365/supply-chain/inventory/inventory-visibility-power-platform#endpoint). Do not construct a region/stamp hostname. |
| `ftc_IFAV2_IVS_ClientId` | IVS application/client ID | Entra **App registrations > intended IVS app > Overview > Application (client) ID** |
| `ftc_IFAV2_IVS_ClientSecret` | Client-secret **value**, not secret ID | Approved credential store or the Entra app's **Certificates & secrets** at creation; an existing secret value cannot be retrieved later. Coordinate any replacement with the IVS owner. |
| `ftc_IFAV2_IVS_DefaultLegalEntity` | Intended default F&O company | F&O administrator's agreed legal entity; verify it against synchronized product/inventory fixtures |
| `ftc_IFAV2_IVS_EnvironmentId` | IVS resource environment GUID used in the service's API routes | IVS setup/integration record for that service, confirmed by its owner against a working read-only request; do not substitute a Dataverse organization ID or assume it is the new agent-host environment ID |
| `ftc_IFAV2_IVS_Scope` | Normally `0cdb527f-a8d1-4bf8-9436-b352c68682b2/.default` | Current [IVS API authentication guidance](https://learn.microsoft.com/en-us/dynamics365/supply-chain/inventory/inventory-visibility-api#authentication); confirm for the intended service/cloud |
| `ftc_IFAV2_IVS_TenantId` | Tenant for the IVS app/service identity | Entra **App registrations > intended IVS app > Overview > Directory (tenant) ID** |

The agent uses the explicit company when supplied, otherwise the configured IVS default obtained through its tools. An unavailable tool/default is a setup problem, not permission to fall back to the ERP user's current company.

The secret variable is a **String**, not a Key Vault reference. Protect the settings file and environment-variable access. Never log it or put it in a command line, pull request, or issue.

Keep the template's long logical reference names unchanged. Populate its seven `Value` fields and two `ConnectionId` fields only in the protected copy. Leave `LogicalName`, `SchemaName`, and `ConnectorId` unchanged.

A connection ID from another Power Platform environment cannot simply be reused. Reusing an existing IVS endpoint for a read-only test also does **not** provide the new Dataverse environment with its catalogue tables/data, projection configuration, F&O connection, or per-user consent. Record that test boundary explicitly.

**Expected result:** two connected target connections, seven values with confirmed provenance, and no secrets in Git or shared notes. Stop if a value, credential owner, or target is ambiguous.

- [ ] Connection gate: both connections and all seven settings are ready for the intended target.

## 3. Install the verified package

**Owner:** authorized solution importer. **Where:** Power Apps in the target environment, or an explicitly targeted PAC session.

Download [the v2 ZIP](../Solutions/InventoryFulfillmentAgent_V2_2.0.0.1_unmanaged.zip) and [its checksum](../Solutions/InventoryFulfillmentAgent_V2_2.0.0.1_unmanaged.zip.sha256). Open each GitHub file and choose **Download raw file**. Do not import GitHub's repository download ZIP.

```powershell
Get-FileHash -LiteralPath .\InventoryFulfillmentAgent_V2_2.0.0.1_unmanaged.zip -Algorithm SHA256
```

Compare against the sidecar. A mismatch is a stop condition. Import the ZIP unchanged, without extracting it. This unmanaged solution is a separate v2 installation, not an in-place v1 upgrade; see [version comparison](version-comparison.md).

### Power Apps

1. Open [Power Apps](https://make.powerapps.com/), select the verified target, and choose **Solutions > Import solution**.
2. Select the v2 ZIP. Review dependencies; do not skip failed dependency checks.
3. Bind both connection references and enter the target environment values.
4. Complete import. Wait for the terminal result, download/review its import log, and retain it privately. Do not submit a duplicate import while the first is still running.
5. Confirm the solution **Inventory Fulfillment Agent**, unique name `InventoryFulfillmentAgent_V2`, version **2.0.0.1**, appears under **Solutions**. The agent itself uses **Inventory Fulfilment Agent** as its display name. Review warnings rather than treating progress or HTTP acceptance alone as success.

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

**Expected result:** successful exact-package import, reviewed log, correct solution identity/version, and no automatic agent publication. Stop on missing dependencies or unexpected overwrite prompts.

- [ ] Installation gate: the verified v2 package imported successfully and its log was reviewed.

## 4. Configure the imported runtime

**Owner:** agent owner and Power Platform administrator. **Where:** imported solution objects in Power Apps/Power Automate and the imported agent in Copilot Studio.

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

1. Open the imported solution's **Connection references** and **Environment variables**. Confirm both bindings and all seven current values. Do not capture the secret in a screenshot.
2. Open each of the five flows in Power Automate. Check connection references/validation and actual state. If inactive, enable the token helper first, then dependent flows, after configuration is approved. Do not run reserve/unreserve flows as a setup check.
3. In Copilot Studio, select the target environment and open **Inventory Fulfilment Agent**. Confirm the packaged model and Microsoft authentication. Check the two skills, four workflow tools, ERP MCP tool, fulfillment file, and documentation knowledge source are present.
4. Open each workflow tool and verify its associated flow resolves to the corresponding imported flow. Open ERP MCP and confirm the target F&O reference resolves. A `workflowId` in YAML alone is not proof of its native association. If a native link is missing or cannot be verified, have the administrator inspect `botcomponent_workflow` / `botcomponent_connectionreference`; do not remove/re-add tools blindly.
5. Review both skills' metadata and instruction content and the fulfillment policy. Replace demo-specific business policy through a reviewed customization: the supplied policy assumes Central/Houston and a particular sourcing order, not your organization's delivery SLA. Check knowledge readiness separately; an attachment being present does not prove external ingestion.

There are no separate v2 inventory and ATP flows; both use **IFA - Exact Item Inventory Check**. Keep logical names, component identities, immutable input/output slots, invoker authentication, model, and the full reviewed instructions intact.

**Expected result:** complete runtime inventory, resolved native bindings, valid target settings, deliberate flow states, and reviewed customer policy. Stop on missing links, unknown elements, or unexplained instruction/attachment differences.

- [ ] Configuration gate: runtime, connections, flow states, skills, and fulfillment policy have been reviewed.

## 5. Verify safely

**Owner:** agent owner and business tester. **Where:** Copilot Studio **Review** and **Preview**, with approved fixture evidence from IVS/F&O.

### Draft-startup check

1. Open **Review**. Resolve blocking errors before proceeding. **No evaluation run** can be the only warning on a new installation because the runtime ZIP does not include evaluation cases/results. Record it; do not represent it as evaluation acceptance.
2. Open **Preview** and send this no-tool prompt:

```text
In two short sentences, explain what you can help with. Do not call any tools, look up data, or create or change anything.
```

3. Expect a capability summary and the AI disclaimer, with no inventory/order data or tool requests. Inspect the trace/run history if tools are unexpectedly called. The agent should remain unpublished.

This is the smoke test completed in the [fresh-install record](validation.md); it does not prove service connectivity.

### Connected-service acceptance

Choose real, owner-approved fixtures. Substitute actual values for the placeholders below; do not use the demo company's data by assumption.

| Test | Example request | Evidence required |
| --- | --- | --- |
| Identity only | `Find <known product phrase> in company <company>. Do not check stock.` | Correct product identity/company; product resolver used, no inventory call |
| On-hand | `Check on-hand for item <item> in company <company>, site <site>, warehouse <warehouse>.` | Exact location and quantities match a fresh IVS read |
| ATP, if in scope | `Check ATP for item <item> in company <company>, site <site>, warehouse <warehouse>, quantity <quantity>.` | Known dated schedules and per-location promise results, not just empty dates |
| Default company | Repeat an approved read without company | Reported effective company matches the configured IVS default |
| Permission boundary | Approved read as intended user | Correct identity, company scope, connector consent, and refusal where access is absent |

**Known limitation (FUL-014):** another warehouse's stock can intermittently be described as the requested store's stock. Compare the returned company/site/warehouse explicitly and stop before any write if the location is inconsistent. "No rows" is not proof of no physical stock.

Reservation/order tests and evaluations that invoke writes require explicit approval, disposable fixtures, before/after reconciliation, and cleanup. Do not execute the legacy mutation examples as a casual installation check. Import/manage evaluation definitions separately; the ZIP does not migrate them.

**Expected result:** clean native Review, safe draft startup, and evidence for the connected capabilities you intend to expose. A structural-only test stops here with integrations clearly marked unverified.

- [ ] Verification gate: the approved test scope passed, limitations were recorded, and any mutating fixtures were reconciled.

## 6. Publish and hand over

**Owner:** authorized agent publisher and service owner. **Where:** Copilot Studio and the intended Teams/Microsoft 365 Copilot channel.

1. Complete the [customer acceptance checklist](validation.md#customer-acceptance-checklist), review the known location limitation, and obtain publication approval for the exact target.
2. Select **Publish** only after acceptance. Wait for a successful server publication result and verify the target's published timestamp/state; an accepted request is not completion.
3. Configure the intended channels, sharing, and end-user consent. Run an approved read-only conversation in the actual channel as the real intended user. Preview is not channel acceptance.
4. Record support/monitoring owners, credential rotation, approved business policy, and recovery/cutover steps. Keep v1 available until any v2 cutover is accepted. Removing an unmanaged solution or unpublishing an agent does not reverse its business transactions.

**Expected result:** approved publication, verified channel behavior, and explicit operational ownership. Stop if users lack the intended permissions or channel behavior differs from Preview.

- [ ] Publication gate: authorized publication and real-user channel acceptance are recorded; handover owners are assigned.

## Troubleshooting

| Symptom | What to check |
| --- | --- |
| `prvReadbot` or other Dataverse privilege missing | Assign the appropriate target Dataverse role through approved administration; tenant admin membership alone is not enough |
| Import requires `cc_attribute` | Product Search Core must be installed before IFA |
| First-party installer reports another import / `EntityCustomization` | Retain the failed operation, wait for competing customization to finish, then retry through the supported installer; never clear locks or cancel unrelated deployments |
| Apply solution is empty/missing Product Search | Verify core importer and Application Core installed first, then all six managed Product Search maps; a connection reset does not install missing maps |
| Reinstall logs `SkipSameVersion` but maps are missing | Diagnose managed ownership/dependency order with the administrator or Microsoft Support; same-version success is not proof missing objects were repaired |
| Tools show missing flow or connection | Check native workflow/MCP associations, target IDs, connection owner/consent, and actual flow state |
| Unknown bot element/model or missing SQL MCP tool | Verify harness/model and all six packaged MCP tool names in the target; do not silently rewrite the sample |
| Token or IVS authentication failure | Verify all seven values, credential expiry, IVS registration and token exchange, and secure flow run diagnostics |
| Product lookup returns no rows | Verify company-aware catalogue sync, derived name/attribute projection, and item/variant/attribute constraints; do not invent a match |
| ATP returns no dates | Verify source schedules and ATP configuration; enabled ATP alone does not prove time-phased data exists |
| Publish fails on null Teams command title | Remove malformed empty conversation starters; do not reduce instruction bodies as a speculative fix |
| Location label looks inconsistent | Stop before a write and resolve the company/site/warehouse explicitly; see known defect FUL-014 |

Do not attach signed URLs, tokens, credentials, raw conversation evidence, or private tenant exports to a public support request.
