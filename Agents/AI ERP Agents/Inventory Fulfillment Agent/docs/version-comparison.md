# Legacy v1 and the new v2 implementation

## What changes

| Area | Legacy 1.0.0.7 | New 2.0.0.1 |
| --- | --- | --- |
| Solution | `InventoryFulfillmentAgent_V1` | `InventoryFulfillmentAgent_V2` |
| Agent schema | `cr91d_agent9_4ET9z6` | `ftc_inventoryfulfilmentagentv2_9kWGCB` |
| Orchestration | Generative recognizer, topics/actions, two order child agents | `CLICopilotRecognizer`, `Sonnet5`, two order skills, one ERP MCP tool |
| IVS integration | Five flows; inventory/ATP and product-search actions | Five isolated flows; exact-item inventory/ATP, product resolver, reserve, unreserve, and token helper |
| Bot-component records | 24 in the legacy ZIP, including its GPT metadata component | 11, including skills, tools, and knowledge; main configuration is in the bot record |
| Environment variables | Legacy schema names | Seven `ftc_IFAV2_IVS_*` definitions; values are not migrated automatically |
| Connections | Legacy references | Separate Dataverse and F&O logical references; bind them in the target |
| Evaluation definitions | Not a promise of included test certification | Excluded from the runtime ZIP; import/manage test cases separately |
| Publication | Customer-controlled | Automatic create/import publication disabled; explicit customer-controlled publication |

Counts describe these exact package versions, not a requirement to customize the legacy implementation to match v2.

## Changes in the new implementation

- Separates product resolution from exact inventory checks and preserves native workflow registrations, not just YAML workflow IDs.
- Keeps identity colours in product names and size syntax from becoming unintended search/stock filters. Explicit attribute and variant constraints remain meaningful; do not remove real customer constraints to force a match.
- Uses an explicitly requested company, otherwise the configured **IVS Default Legal Entity** returned by IVS tools for order proposals; it does not rely on the ERP connection user's current company.
- Includes confirmation, scope, refusal, replay, and order-lifecycle guidance in the main instructions and skills.
- Removes the empty conversation starter that previously blocked Teams manifest validation.
- Uses portable environment-variable definitions and blank flow-level environment fallbacks rather than exported source-environment defaults.

V2 is not simply a renamed v1. Both the orchestration and internal identities differ. The model/harness and target feature availability must be checked before choosing v2.

## Side-by-side installation

1. Keep the existing v1 solution and its backups. Record its connections, published version, users, channels, and external consumers.
2. Install v2 as a **new** solution in non-production first. Do not rename either solution's unique name or replace component IDs to make them look like an upgrade.
3. Set the seven v2 variables and bind the two v2 connection references. Do not copy v1 configuration by display name.
4. Review the included demonstration fulfillment policy against your business rules.
5. Use distinguishable names during evaluation and channel onboarding, even though the packaged user-facing display name has no version suffix.
6. Complete read-only, permission, confirmation, transactional, and published-channel acceptance with approved fixtures.
7. Agree a deliberate cutover. Prevent simultaneous agents from processing the same order/reservation request.
8. Keep v1 available for rollback until acceptance is signed off. Unpublishing or removing v2 does not reverse business transactions it already performed.

## No automatic migration

The ZIP does not migrate conversations, channels, user consent, sharing, connector credentials, environment values, evaluation cases/results, catalogue/inventory data, or orders. Re-establish each in the chosen target and retain audit evidence privately.

Do not uninstall a working legacy deployment merely because v2 imported successfully. Package import, agent publication, live connection health, and business acceptance are distinct gates.
