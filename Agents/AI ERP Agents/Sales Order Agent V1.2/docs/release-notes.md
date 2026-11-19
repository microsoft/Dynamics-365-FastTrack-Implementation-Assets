# Release notes - 1.0.9.0

Date: 2026-11-03. Solution `SalesOrderAgentProcessingTemplateV12`, version 1.0.9.0, managed.

## What is new

* **Configurable customer matching.** The customer resolver scores candidates with a Published rule set instead of fixed
  values. Administrators edit points, threshold, margin, address basis (Bill-To or Ship-To), the optional fallback
  address and the name-cleaning switches under **Setup > Matching rules**. Rules take effect for the next order. Safety
  floors cannot be lowered: threshold at least 60, margin at least 10, name-contains length at least 5, and no single
  group can reach the threshold alone. The standard values are name exact 40, name contains 20, email 15, street 10,
  ZIP 20, city 10 and state 5, threshold 70 and margin 15. Each order's **Customer Match** tab shows the score
  breakdown and the reason for a hold. See [Customer Matching Rules](./customer-matching-rules.md).
* **Unit-of-measure aliases.** The loader normalizes the printed unit (EA, EACH, PCS, Pc, E and others) before the
  order line is written. The starter list of 66 aliases is maintained under **Setup > Units of measure**; saving a row
  publishes it. The extraction JSON keeps the unit as printed.
* **Guarded release.** The agent validates an order only from the status New and creates an ERP order only when no ERP
  number exists yet. A run that stops because the saved proof, the matching rules or the load state changed is recorded
  as Cancelled and leaves the order unchanged for re-run.
* **Agent model.** The agent ships configured for Claude Sonnet. Auto is the alternative; see the deployment guide,
  section 6.2.
* **Dashboards.** The totals tile on both order dashboards loads from the solution, so the dashboards work in any
  environment.
* **First-time setup script.** `PowerPlatform\Initialize-SalesOrderAgent.ps1` creates the first Published matching
  policy, adds the starter unit aliases and assigns the reader field security. See the deployment guide, section 7.2.
* **New roles and screens.** The *Sales Order Matching Administrator* role and the Setup area (Matching rules, Draft
  rules, Rule history, Unit aliases, Try a printed unit).

## Package

| Item | Notes |
| --- | --- |
| `PowerPlatform/SalesOrderAgentProcessingTemplateV12_1_0_9_0_managed.zip` | Install in test and production environments. |
| `PowerPlatform/Initialize-SalesOrderAgent.ps1` | One-time data setup after import. |
| `azure-content-understanding/` | Analyzer v2.0.7 and the deployment and test scripts. |
| `docs/` | Deployment guide, Customer Matching Rules, FAQ, architecture, DLP and security requirements. |

The package contains no environment-variable current values, mailbox addresses, connection identifiers, keys or
environment host names. The resolver's `FinanceOperationsInstance` parameter ships as
`your-environment.operations.dynamics.com` and `ReleaseHeaders` ships as false.

## Installing or upgrading

* **New environment:** follow the deployment guide, Parts A to F.
* **Upgrade from 1.0.8.5:** follow the deployment guide, section 11.1. After the import re-check the resolver's
  `FinanceOperationsInstance`, all connection bindings, the agent model (section 6.2) and the first-time setup
  (section 7.2), because the new tables hold no data until it runs.

See the [deployment guide](./deployment-guide.md).
