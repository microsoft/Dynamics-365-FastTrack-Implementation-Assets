# Changelog

## 1.1.0.0 - 2026-11-24

Enhancement release: reviewer overrides.

### Added
* A reviewer can decide the customer and company of an order in Manual Review (Customer Match Status Review Required): ERP Customer Number, Company Code, **Customer Override Reason**, Valid Customer = Yes, status Valid. The decision is saved as evidence schema 5 (who, when, why), the agent confirms the customer in the ERP (`ManualOverrideCustomerNotFound`), validates every line and creates the order. Correctable until an ERP order exists. The system result is kept in **Original Match Evidence**.
* A reviewer can decide a line: ERP Product Code, **Manual Override** = Yes, **Override Reason**; then the order status Valid. All lines are validated again; the ERP checks at creation still apply (`ManualOverrideIncomplete` when the code or reason is missing).
* A Valid status with lines that are not valid now starts the product validation again instead of stopping.
* New columns: order Customer Override Reason, Original Match Evidence; line Manual Override, Override Reason.
* The release switch is now the environment variable `aipod_ReleaseHeaders` (text, ships `false`; only `true` releases). It replaces the resolver flow parameter `ReleaseHeaders`, which no portal screen could change.

### Changed
* ERP Customer Number and Company Code are editable on the order form only while Customer Match Status is Review Required, or after a reviewer decision until an ERP order exists.
* The status flow, the update-status flow, the three business skills and the order form script accept proof schema 5. Schemas 3 and 4 are unchanged.
* The Customer Match tab shows a notice and the system result for a reviewer decision.

## 1.0.10.0 - 2026-11-23

Bugfix release.

### Fixed
* The Finance and Operations host is now the environment variable `aipod_FinanceOperationsInstance` (ships empty) instead of a resolver-flow parameter with a placeholder host. Turning the resolver flow on with the placeholder failed with a BadGateway error, and the designer offers no way to edit that parameter. While the variable is empty, customer matching stops with `CustomerMatchConfigurationMissing`.
* The agent's own notification emails are no longer read as orders: both intake flows skip emails whose subject contains `Sales Order Agent - `.

### Removed
* The environment variable `aipod_CustomerMatchAddressBasis`. Bill-To or Ship-To matching is chosen only by the **Address basis** of the Published matching policy. The variable was read only for orders that still carried a proof from before 1.0.9.0; such an order that is not yet in ERP stops for review and is re-run under the Published rules.

### Changed
* Every component in the managed solution is now customizable. Before, the alternate key `aipod_policykeyversion`, two connection references and the two ERP and Dataverse tool components of the agent were locked. The build now fails if any component is locked.

### Documentation

### Notes
* Required analyzer: `sales_order_extraction_v2_0_7`.
* Upgrading from 1.0.9.0: set `aipod_FinanceOperationsInstance` after the import, before turning the resolver flow on (deployment guide, section 11.1).
* The solution now ships as managed only. Its components are customizable.

## 1.0.9.0 - 2026-11-03

First published release of the Sales Order Agent processing template (V1.2).

### Added
* Configurable customer matching: points, threshold, margin, address basis, optional fallback address and name switches, edited under **Setup > Matching rules**, with safety floors that cannot be lowered and a logged decision (score, margin, reason, rule version) for every order.
* Unit-of-measure aliases: the printed unit is normalized from an editable list under **Setup > Units of measure** (66 starter aliases).
* Guarded release: an order is validated only from status New, an ERP order is created only when no ERP number exists, and a run that stops on a guard is recorded as Cancelled.
* First-time setup script `Initialize-SalesOrderAgent.ps1`.
* Order overview dashboards that load their totals tile from the solution itself.
* Analyzer v2.0.7 with deployment and contract-test scripts.

### Notes
* Required analyzer: `sales_order_extraction_v2_0_7`.
* Agent model: Claude Sonnet (shipped) or Auto.
* The release switch `ReleaseHeaders` ships off.

### Known issue (fixed in 1.0.10.0)
* If the reviewer address (`aipod_ReviewerEmailAddress`) is the same mailbox the intake flow monitors, and notification emails land in the monitored folder, the notification can be read as a new order and produce another notification. Use a reviewer address that is not the monitored mailbox, or monitor a dedicated folder. A skip rule for notification emails is planned for the next release.
