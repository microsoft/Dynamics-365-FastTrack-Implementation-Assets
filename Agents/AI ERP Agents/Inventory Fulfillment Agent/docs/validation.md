# Validation and acceptance

## Exact release candidate

| Property | Value |
| --- | --- |
| Solution | `InventoryFulfillmentAgent_V2` |
| Version/type | `2.0.0.1`, unmanaged |
| ZIP | [InventoryFulfillmentAgent_V2_2.0.0.1_unmanaged.zip](../Solutions/InventoryFulfillmentAgent_V2_2.0.0.1_unmanaged.zip) |
| SHA-256 | `b1aaeb388a1127c49b4f64fbe1c71b2eb9f59136bd6cc2b1354802118ab23d04` |
| Main instruction SHA-256 | `044aa228d9d0d666c79844cd88edcabfc951cf12a3cdfa5fc36e7ec60baf0e8c` |
| Packaging | Power Platform CLI 2.9.3; 41 ZIP entries |

## Fresh-install record

**Blocked before IFA import; not a deployment sign-off.** The exact ZIP above has not yet passed a fresh-install test. Do not propose this candidate for release approval until that gate is completed.

On October 20, 2026, prerequisite installation in the separate sandbox produced these results:

- Dual-write Core completed successfully through its supported application installer, including managed `msdyn_DualWriteCore` and `DualWriteCoreAnchor` version `1.0.26098.0`.
- The native map component importer (`msdyn_dualwriteentitymap`, component type 500) was verified before Product Search installation.
- Dual-write Application Core subsequently completed successfully, including managed `msdyn_DualWriteAppCoreMaps` and its anchor at version `2.4.0.337`. Finance and Operations Platform Tools was also confirmed installed.
- Earlier Core/Application Core attempts failed because Dataverse reported a concurrent `EntityCustomization`. Waiting for competing operations to finish and using controlled supported retries allowed those two application installations to succeed; no internal locks were cleared or dependency checks bypassed.
- The first Inventory Visibility attempt, submitted through the required admin-center custom wizard using a dedicated test application registration, failed on the same concurrent `EntityCustomization` error. After visible customization activity settled, one controlled retry progressed past that dependency.
- The retry installed managed `msdyn_ProductSearchCore`, `msdyn_ProductSearchPermissions`, and `msdyn_ProductSearchAnchor` at version `1.1.3403.2`. All **six managed Product Search maps** were verified against the installed Core solution.
- The latest observed Inventory Visibility application state was still **Installing**, not successful installation. IFA import remains on hold rather than competing with that first-party operation. No integration maps or data synchronization were enabled.
- IFA itself was **not imported**, so target-side flow/tool bindings, agent diagnostics, and service-side compilation remain unverified. No agent publication or business transactions were performed.

Wait for the in-progress first-party installation to reach a terminal state, review its result, and resolve any remaining platform failure through the supported administration/support process. Do not submit a duplicate installation, skip dependency checks, or treat successful prerequisite solution imports alone as IFA deployment acceptance.

The test scope is a new IFA installation in a separate sandbox after first-party prerequisite installation. It does not require linking or synchronizing F&O/IVS, creating business transactions, or exposing a new published agent.

Raw environment IDs, connection details, logs, and bot payloads are retained privately, not included in this public record.

## Offline checks completed

- Ten repository tests and structured source validation.
- PAC packing and exact packed-content comparison.
- Eleven runtime components, five flows, four native workflow associations.
- Seven environment variables, two unbound connection references, and no exported current values.
- No populated workflow-level IVS fallback values.
- Preserved main/sales/transfer instruction fingerprints, Microsoft authentication, model configuration, and immutable tool slots.
- No empty conversation starters; automatic publication on import/create is disabled.

These checks do not execute Power Platform services.

## Native source diagnostics

The Copilot Studio language server (version 1.8.22) checked all 12 authoring YAML documents on October 20, 2026: **zero errors and zero warnings**, with diagnostics received for every document. An isolated negative control with an intentionally invalid bot identity produced the expected error, confirming that the diagnostic check was active.

This validates the local authoring view, not the imported target's connections, service-side compilation, Preview, or publication.

## Supporting configured-environment evidence

The earlier configured-environment cycle covered 103 MCS conversations plus 13 component-contract cases:

| Scope | Evidence-led result |
| --- | --- |
| Core read-only | 14/14 |
| Product routing | 14/14 |
| Inventory, ATP, fulfillment | 17/18 |
| Confirmation/scope safety | 19/19 |
| Transactional sandbox | 10/10 |
| Adversarial/regression | 13/13 |
| Component contracts | 13/13 |
| Long conversation | 5/5 |
| Order lifecycle sandbox | 10/10 |
| **Total** | **115/116 (99.1%)** |

FUL-014 was accepted as a known defect. The native General quality score (86/103) is advisory; refusals and fixture-specific no-data responses were reviewed against expected behavior and correlated evidence.

That cycle used the draft harness, followed by authorized publication. It was not a fresh-import test of this ZIP, and predates the removal of exported flow-level fallback values. Its raw evidence is not distributed here.

## Customer acceptance checklist

Treat each line as a separate gate:

- [ ] Target supports the packaged harness/model; licenses and DLP permit the intended tools.
- [ ] Dependencies installed in order; all six managed Product Search maps present.
- [ ] Import completed successfully for the exact checksum; import warnings reviewed.
- [ ] All five flows and eleven runtime components present.
- [ ] All four native workflow bindings and the native MCP connection binding resolve.
- [ ] Seven variables have correct target values; both references use valid target connections.
- [ ] Copilot Studio validation has no unexplained blocking errors; knowledge and skills load.
- [ ] Main/sales/transfer instruction fingerprints match the reviewed release.
- [ ] Product Search data identities, names, and attributes verified for the intended companies.
- [ ] Inventory and ATP tested separately with known fixtures; populated ATP requires actual schedule data.
- [ ] Explicit and default company handling verified; location claims checked for FUL-014.
- [ ] Reservation/order tests authorized, disposable, and reconciled/cleaned up.
- [ ] Publication explicitly approved and server status/timestamp verified.
- [ ] A conversation passes in each intended published channel with the real end-user identity.
- [ ] Business-policy, security, support, monitoring, and rollback owners accept the deployment.

Do not convert a structural pass or an HTTP 200 into a claim that live integrations, write safety, or customer-specific business acceptance have passed.
