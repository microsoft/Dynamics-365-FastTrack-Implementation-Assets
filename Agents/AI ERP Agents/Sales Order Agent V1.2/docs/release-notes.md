# Release notes - 1.1.0.0

Date: 2026-11-24. Solution `SalesOrderAgentProcessingTemplateV12`, version 1.1.0.0, managed.

## What is new

* **A reviewer can decide the customer.** When two customers tie (or no customer is accepted), the order waits in Manual
  Review. The reviewer types the ERP customer number and the company code on the order, fills the new **Customer Override
  Reason**, sets Valid Customer to Yes and sets the status to Valid. The agent saves the decision as evidence (who, when,
  why), checks in the ERP that the customer exists in that company, validates every line and creates the order. A wrong
  decision can be corrected until an ERP order exists. The system's own result is kept in **Original Match Evidence**
  and in the Customer Match tab.
* **A reviewer can decide a line.** If the customer is accepted but a line stops for review, the reviewer types the ERP
  product code on the line, sets **Manual Override** to Yes with an **Override Reason**, and sets the order status to
  Valid. Every line is validated again; the overridden line is accepted without an ERP item lookup. The ERP checks at
  creation (unit of measure, Site and Warehouse, read-back) still apply.
* **New columns and screens.** Customer Override Reason and Original Match Evidence on the order, Manual Override and
  Override Reason on the line; the order form and the line form show them. ERP Customer Number and Company Code are
  editable only while the order waits for a customer decision.
* **Every component is customizable**, and the build fails when one is locked.
* **The release switch is an environment variable.** `aipod_ReleaseHeaders` replaces the resolver flow parameter
  `ReleaseHeaders`, which the portal does not show and so could not be changed there. It ships `false` (accepted matches
  are held, `CustomerMatchReleaseDisabled`); set its Current Value to `true` to release them. Only the text `true`
  releases; an empty or misspelled value holds the orders.
* **Changed components:** the status flow (`WhenStatusChanges`), the resolver flow, `Update Processing Status to Valid`, the three business
  skills (validate-customer, validate-product, create-sales-order) and the order form script. Saved proof schemas 3 and 4
  behave as before; schema 5 marks a reviewer decision.

## Upgrading from 1.0.10.0

Import the managed solution as an upgrade and publish the agent if your release plan requires it. No setting is
required: the new variable `aipod_ReleaseHeaders` ships `false`, as the old parameter did. If you changed the resolver's
`ReleaseHeaders` parameter in your own customization layer, remove that customization first so the managed definition
applies, then set the variable instead. See the deployment guide, sections 9.12 and 11.1.

---

# Release notes - 1.0.10.0

Date: 2026-11-23. Solution `SalesOrderAgentProcessingTemplateV12`, version 1.0.10.0, managed.

## What is fixed

* **The Finance and Operations host is an environment variable.** It was a flow parameter of the resolver flow with the
  placeholder `your-environment.operations.dynamics.com`. The designer has no place to edit that parameter, and turning the
  flow on with the placeholder failed with a BadGateway error ("remote name could not be resolved"). The host is now
  `aipod_FinanceOperationsInstance`, set like the mailbox settings at import or later under Environment variables. It ships
  empty, and while it is empty customer matching stops with `CustomerMatchConfigurationMissing`.
* **The agent's own notification emails are no longer read as orders.** Both intake flows have a new step that skips emails
  whose subject contains `Sales Order Agent - `. Before this, if the reviewer address was the monitored mailbox and the
  notification landed in the monitored folder, it could be processed as a new order and produce another notification.
* **Every component is customizable.** The alternate key `aipod_policykeyversion`, two connection references and the two
  ERP and Dataverse tool components of the agent were locked in 1.0.9.0. None is locked now.
* **Documentation.** The connection reference table and the `ConnectionAuthorizationFailed` guidance (deployment guide
  section 4.3), the connection edit form, and new troubleshooting rows (including the setup script reported as "not
  digitally signed", and "You do not have permission to access these records" after a role change).

## Removed

* **The environment variable `aipod_CustomerMatchAddressBasis`.** Bill-To or Ship-To matching is chosen only by the
  **Address basis** of the Published matching policy (Setup > Matching rules). The variable was read only for orders that
  still carried a proof from before 1.0.9.0. Such an order that is not yet in ERP stops for review and is re-run under the
  Published rules.

## Upgrading from 1.0.9.0

Import the managed solution as an upgrade. After the import, set `aipod_FinanceOperationsInstance` to your F&O host name
before turning the resolver flow on. See the deployment guide, section 11.1.

---

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
| `PowerPlatform/SalesOrderAgentProcessingTemplateV12_1_0_9_0_unmanaged.zip` | Development only. Do not install both in one environment. |
| `PowerPlatform/Initialize-SalesOrderAgent.ps1` | One-time data setup after import. |
| `azure-content-understanding/` | Analyzer v2.0.7 and the deployment and test scripts. |
| `documentation/` | Deployment guide, Customer Matching Rules, FAQ, architecture, DLP and security requirements. |

The package contains no environment-variable current values, mailbox addresses, connection identifiers, keys or
environment host names. The resolver's `FinanceOperationsInstance` parameter ships as
`your-environment.operations.dynamics.com` and `ReleaseHeaders` ships as false.

## Installing or upgrading

* **New environment:** follow the deployment guide, Parts A to F.
* **Upgrade from 1.0.8.5:** follow the deployment guide, section 11.1. After the import re-check the resolver's
  `FinanceOperationsInstance`, all connection bindings, the agent model (section 6.2) and the first-time setup
  (section 7.2), because the new tables hold no data until it runs.

See the [deployment guide](./deployment-guide.md).
