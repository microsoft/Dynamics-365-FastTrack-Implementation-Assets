# Deployment and troubleshooting FAQ - 1.1.0.0

Date: 2026-11-24. For the Content Understanding and customer-matching release. Entries describe a symptom, what it
means and the safe action.

| Symptom/error | Meaning and safe action |
|---|---|
| Two customers tie and the order sits in Manual Review (`CustomerMatchAmbiguous`) | A reviewer can decide it: type ERP Customer Number and Company Code, fill Customer Override Reason, set Valid Customer to Yes and set the status to Valid (user guide, section 5). The order then validates and is created in the ERP. |
| One line stops for review but the customer is fine | Type the ERP Product Code on the line, set Manual Override to Yes with a reason, then set the order status to Valid (user guide, section 5). ERP checks at creation still apply. |
| ERP Customer Number and Company Code cannot be edited | They are editable only while Customer Match Status is Review Required, or after a reviewer decision until an ERP order exists. They are read only for system-matched orders and for orders already created. |
| The order stops with `ManualOverrideCustomerNotFound` | The ERP has no such customer in that company. Correct the customer number or the company and set the status again. |
| A line stops with `ManualOverrideIncomplete` | Manual Override is Yes but the ERP Product Code or the Override Reason is empty. |
| Turn on failed: `ConnectionAuthorizationFailed`, "cannot be used to activate this flow" | A connection reference is bound to a connection that the person turning the flow on does not own. Bind every reference to that person's connections (deployment guide, section 4.3), or have the connection's owner turn the flow on. |
| Turn on failed: BadGateway, "The remote name could not be resolved" for a `…operations.dynamics.com` host | The Finance and Operations host is wrong or is the placeholder from release 1.0.9.0. Set the environment variable `aipod_FinanceOperationsInstance` (section 5), or upgrade from 1.0.9.0. |
| Orders stop with `CustomerMatchConfigurationMissing` | `aipod_FinanceOperationsInstance` has no value. Set it to the F&O host name and re-run the order. |
| The HTTP with Microsoft Entra ID connection cannot be created (AADSTS65002) or no longer exists | Create it again with both URLs set to the plain target environment URL (no trailing slash), signed in as the person who turns the flows on, then rebind `aipod_sharedwebcontents_customermatch`. If the error persists with correct values, a tenant administrator must allow the connector's first-party app for Dataverse. |
| Notification emails became new orders | Fixed in 1.0.10.0: intake skips subjects containing `Sales Order Agent - `. On 1.0.9.0 use a reviewer address that is not the monitored mailbox. |
| CU connection says Connected, but `Analyze_content` returns 401 | Verify subscription state, matching resource endpoint/key and authentication mode. Recreate or rebind credentials only through approved connection administration. Connected is not an execution test. |
| `SubscriptionNotRegistered` or Azure subscription Disabled | The service owner must restore the subscription/provider/resource. Do not repeat document submissions. Provider registration alone does not repair a Disabled subscription. Recheck the actual analyzer and connector afterward. |
| `401 PermissionDenied` on CU defaults/analyzer | Check the target identity's data-plane role as well as management-plane permissions. Obtain approved access. |
| `DefaultsNotSet` | Prepare supported model deployments and CU defaults before analyzer creation; review the supplied deployment script's WhatIf output. |
| Analyzer identifier rejected | Use the shipped ID `sales_order_extraction_v2_0_7`. Identifiers accept letters, numbers, dot and underscore only. |
| Import Next disabled or connections cannot load | Create correct target connections and bind every reference. Verify the target environment, connector availability, consent and DLP. |
| Missing connection-reference dependency | Check target bindings against the actual logical name. Preserve the import log and stop a partial activation. |
| DLP blocks `shared_agentnode` with Dataverse | An admin must evaluate all applicable policies and put the required connectors in compatible approved groups. Include `shared_webcontents` for the customer resolver. Keep intake held during remediation. |
| The agent answers but VALIDATE stops with a product-lookup failure and the flow shows Succeeded | The agent model does not call the ERP tool. Set the model to Claude Sonnet or Auto, publish, and repeat the skill check (deployment guide, sections 6.1 and 6.2). |
| Setup > Matching rules is empty; orders stop with `CustomerMatchPolicyUnavailable` | The first policy was not created. Turn on the publish flow and run `Initialize-SalesOrderAgent.ps1` (deployment guide, section 7.2). |
| `Initialize-SalesOrderAgent.ps1` is "not digitally signed" and will not run | Windows marks a downloaded script as coming from the internet. Run `Unblock-File .\Initialize-SalesOrderAgent.ps1` in its folder, or `Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass` in that window only (the machine policy is unchanged). |
| "You do not have permission to access these records" after a role was assigned | The session still holds the previous security. Open the app in a new InPrivate window or sign out and in. If it persists, check the roles in the user's own business unit. |
| Matching stays held with a high score | Score alone is insufficient: company ambiguity, runner-up margin, candidate completeness, policy freshness and current proof all matter. Review the saved evidence; fuzzy suggestions do not authorize a write. |
| The same customer identity appears in multiple companies | Cross-company identities can be identical. The order is held for review rather than silently selecting a company. |
| ShipTo selected but address points absent | ShipTo matching needs an explicit source address and a valid ERP default delivery address. The operational Bill-to fallback is not ShipTo evidence. |
| A rule change was published and an order stopped with `CustomerMatchPolicyChanged` | The order was matched under the previous rules and is not yet in ERP. Re-run it; do not edit proofs. |
| A status flow run shows Cancelled and the order is unchanged | A guard stopped the run because the saved proof, the matching rules or the load state changed. Expected; re-run the order. |
| A line stops with `UnitOfMeasureMismatch` | The unit, after normalization, does not match the item's ERP sales unit. Add or correct the alias under Setup > Units of measure, or fix the item's unit in ERP. A unit that is not in the list is kept as printed. |
| An alias was saved but the order still shows the printed unit | The alias applies to orders loaded after it is published (a minute or two). Orders already loaded are not changed. Check that the row shows Published. |
| A unit alias row shows Rejected | A blank or duplicate alias, or the map would exceed 2,000 characters. Read the message on the row; the map in use did not change. |
| `LineCountMismatch` / `LineCountUnverifiable` | The extracted item count does not meet the independent row-count contract, or the contract cannot be established. Inspect the source and the persisted JSON. Never change the expected count or approve a short ERP order. |
| Same line count but incorrect quantity/item | Count verification does not validate every field. Hold and compare source, JSON and Dataverse values. |
| `PersistenceVerificationFailed` | Readback does not establish that the expected JSON persisted. Preserve evidence and stop downstream processing. |
| `StagingDocumentUnavailable` | Check Dataverse search, runtime identity permissions, organization/tool binding and the persisted source row. |
| `ValidateCustomerSkillUnavailable` | Imported skill records and publication do not prove execution availability. Verify the business agent, attached skills, target access and runtime invocation. Do not replay ERP SAVE while diagnosing. |
| `LineReadIncomplete` | The agent has not established a complete persisted line set. Check the count and all pages; do not waive the guard for large orders. |
| `LineBatchPersistenceFailure` | A line-result batch did not fully persist or read back. Inspect the affected lines and run evidence; do not release an incompletely validated order. |
| `InvalidValidationState` | The header state is not eligible for the requested operation. Inspect prior runs and the ERP outcome; do not force the status to New to bypass the guard. |
| ERP create times out or returns an uncertain outcome | Query ERP for the business/order key before retrying. An error or timeout can occur after a successful write. Retain the source/header and escalate for reconciliation. |
| Blank or long PO and duplicate risk | A blank PO skips the duplicate lookup; ERP can truncate long POs (20 characters observed). Concurrent arrivals and timeout-after-create can also produce duplicates. Reconcile before retrying. |
| Printed ship-to not used on the ERP order | The extracted operational address is stored; ERP uses its configured delivery address. |
| Requested delivery date is in the past | The date is withheld from ERP and the validation message says so; ERP uses its default date. Check the ERP readback and company time zone. |
| Small PDF does not reach document extraction | The default intake filter requires 4096 bytes and the small-PDF exception defaults to false. Do not pad documents. |
| XLSX is valid but not processed | File validity and the intake extension filter do not prove provider format support. Capture the actual runtime result for the original XLSX bytes; do not silently substitute PDF. |
| Dashboard totals tile is blank or shows a broken page | The tile must be a web resource component that points to `aipod_order_dashboard.html`. Edit the dashboard accordingly, publish, and reload with the cache cleared. |
| Dashboard totals differ for two users | Totals use saved records accessible to each user and are not a global audit. Check permissions, saved statuses and ERP-number criteria. |
| Order fields/status are editable | The original native form behavior is retained. Apply target permissions and never use status editing as an unverified retry mechanism. |

## Evidence and escalation

Record sanitized import, flow, agent and analyzer operation IDs, source/header GUIDs, solution version and hash, the
original document hash, the current status and the independent ERP readback. Preserve errors, and distinguish NOT RUN
from failed extraction and connector success from business success. Do not include secrets or signed download URLs in
tickets.
