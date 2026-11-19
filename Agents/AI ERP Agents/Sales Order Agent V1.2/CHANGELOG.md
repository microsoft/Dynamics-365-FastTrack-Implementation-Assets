# Changelog

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

### Known issue
* If the reviewer address (`aipod_ReviewerEmailAddress`) is the same mailbox the intake flow monitors, and notification emails land in the monitored folder, the notification can be read as a new order and produce another notification. Use a reviewer address that is not the monitored mailbox, or monitor a dedicated folder. A skip rule for notification emails is planned for the next release.
