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

**Fresh-install structural verification passed on October 20, 2026.** The exact ZIP above was imported into a separate sandbox and checked against its actual target content. This is not full integration, evaluation, publication, or production sign-off.

### Imported target verification

| Check | Actual result |
| --- | --- |
| Solution | Unmanaged `InventoryFulfillmentAgent_V2`, `2.0.0.1` |
| Runtime components | All 11 present; schema names, types, content, and attachment-parent associations verified |
| Workflows | All 5 present; definitions and connection-reference metadata matched the exact ZIP |
| Native workflow registrations | All 4 resolve to the correct imported flows, independently of YAML `workflowId` values |
| Native MCP registration | Present and bound to the verified target F&O connection |
| Agent configuration | Full configuration matched the ZIP, including Microsoft authentication, harness/model, instructions, and publication defaults |
| Skill/policy attachments | All 3 downloaded from the target and matched byte-for-byte by SHA-256 |
| Target configuration | Both references bound to the verified target connections; all 7 current variables present |
| Native Copilot Studio Review | No blocking errors; one warning: **No evaluation run** on the newly imported agent |
| Native Preview | One capability-summary turn passed, explicitly requesting no tools or data changes |
| Publication | Agent remained unpublished |

All five flows were **active after import**, despite `PublishWorkflows:false`. Read-only Power Automate history confirmed **zero runs across all five imported flows** after the Preview smoke test. Import options must not be treated as a guarantee that flows remain inactive.

### Scope and remaining limits

The test establishes a fresh IFA installation and native draft startup after first-party prerequisite installation. The target's IFA settings referenced an existing IVS service under the permitted shared-service test arrangement. The dedicated app was used only for the target's separate IVS prerequisite installation; the existing IVS service was not re-registered or changed.

No connected IVS/F&O tool calls, catalogue synchronization, populated ATP checks, order/reservation transactions, new evaluations, publication, or published-channel tests were performed. No integration maps or data synchronization were enabled. Skills and knowledge components/attachment bytes were verified and displayed in the editor; this does not certify external knowledge ingestion or business behavior.

Native Review and one Preview turn are not exhaustive service-side compilation or execution coverage for every skill/tool path. The new target's missing-evaluation warning is expected: runtime evaluation cases are not included in this ZIP. Customer-specific functional and publication acceptance remains required.

Raw environment IDs, connection details, logs, and bot payloads are retained privately, not included in this public record.

### Prerequisite setup and troubleshooting lesson

The sandbox started without the native dual-write map importer. Setup completed in the supported order before the IFA import:

| Prerequisite | Verified installed result |
| --- | --- |
| Dual-write Core | `msdyn_DualWriteCore` / `DualWriteCoreAnchor` `1.0.26098.0`; native `msdyn_dualwriteentitymap` importer (component type 500) present |
| Dual-write Application Core | `msdyn_DualWriteAppCoreMaps` and anchor `2.4.0.337` |
| Finance and Operations Platform Tools | Installed before IVS setup |
| IVS / Product Search | IVS anchor `1.3.3432.1`; Product Search Core, Permissions, and Anchor `1.1.3403.2`; all six managed maps verified |

Earlier first-party installer attempts failed because Dataverse reported a concurrent `EntityCustomization`. Waiting for competing work to finish and using controlled supported retries resolved this. IVS required its custom admin-center wizard; the generic application-package API does not support that wizard. Its retry succeeded and the enclosing prerequisite applications reported **Installed** before IFA import.

The exact IFA ZIP was then submitted once, with dependency checks enabled. Its durable operation completed at **13:44:57 UTC on October 20, 2026**; the import job reached 100% with no warning/failure log entries. No internal lock was cleared, first-party solution deleted, or dependency check skipped. See [installation troubleshooting](install-v2.md#troubleshooting).

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

This validates the local authoring view. The imported target's native Review and Preview checks are separate evidence recorded above; no imported-authoring-clone language-server pass is claimed.

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

Treat each line as a separate gate for **each customer deployment**; the completed sample sandbox checks above do not complete these gates for another target:

- [ ] Target supports the packaged harness/model; licenses and DLP permit the intended tools.
- [ ] Target connector exposes all six packaged MCP tool names, including `data_find_entities_sql`; Product Search's minimum F&O version alone is not sufficient.
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
