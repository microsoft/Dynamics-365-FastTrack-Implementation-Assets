# Inventory Fulfillment Agent

Help an associate move from "Do we have it?" to a confirmed fulfillment action in Dynamics 365. This sample combines Microsoft Copilot Studio, Inventory Visibility, product search, and the Dynamics 365 ERP Model Context Protocol (MCP) connector.

**Find it. Promise it. Move it.**

The agent can resolve products, inspect inventory and available-to-promise (ATP), suggest fulfillment options, manage soft reservations, and assist with sales and transfer orders. Write operations require user confirmation and appropriate Dynamics 365 permissions.

> This is an implementation sample, not a turnkey production service. Validate licensing, regional/model availability, security, data, and business policy in your own non-production environment before deployment. Nothing runs locally.

> **V2 validation status:** the exact ZIP passed a fresh import into a separate sandbox, native binding/content verification, Copilot Studio Review with no blocking errors, and a no-tool Preview smoke test on October 20, 2026. This is not connected integration, evaluation, publication, or production certification. See the [validation record](docs/validation.md). The legacy ZIP is unchanged.

## Choose a version

Both versions remain available. They are **different solution identities**, not two ZIPs that update the same installation.

| | New implementation | Legacy implementation |
| --- | --- | --- |
| Version | **2.0.0.1**, unmanaged | **1.0.0.7**, unmanaged |
| Solution unique name | `InventoryFulfillmentAgent_V2` | `InventoryFulfillmentAgent_V1` |
| Orchestration | GitHub Copilot-based Copilot Studio harness, `CLICopilotRecognizer`, `Sonnet5` model configuration | Generative orchestration, topics, actions, and order child agents |
| Order assistance | Sales and transfer skills using the ERP MCP connector | Sales and transfer child agents using ERP MCP |
| Deployment | Separate installation; requires the new harness/model to be supported in the target | Existing v1 solution and legacy instructions retained |
| Start here | [Install v2](docs/install-v2.md) | [Legacy installation guide](docs/legacy-v1-installation.md) |

The user-facing agent name does not contain "v2". The version suffix in internal identities is intentional and must not be removed.

**Do not import v2 as an in-place upgrade to v1.** The two can coexist, but each needs its own configuration, connection bindings, sharing, channel installation, and acceptance tests. See [version differences and migration](docs/version-comparison.md).

## Download

| Asset | Purpose |
| --- | --- |
| [InventoryFulfillmentAgent_V2_2.0.0.1_unmanaged.zip](Solutions/InventoryFulfillmentAgent_V2_2.0.0.1_unmanaged.zip) | New solution; import the ZIP without extracting it |
| [SHA-256 checksum](Solutions/InventoryFulfillmentAgent_V2_2.0.0.1_unmanaged.zip.sha256) | Verify the exact download |
| [Blank v2 deployment settings](Solutions/deployment-settings.v2.example.json) | Seven environment variables and two target connection references |
| [InventoryFulfillmentAgent_V1_1_0_0_7.zip](Solutions/InventoryFulfillmentAgent_V1_1_0_0_7.zip) | Unchanged legacy solution |
| [Release notes](docs/release-notes.md) | Changes, known limitations, and package identity |

To download a ZIP from GitHub, open the file and choose **Download raw file**. Do not import the repository's **Code > Download ZIP** archive as a solution.

## Deployment at a glance

1. Confirm target licenses, Dataverse security roles, connector/DLP policies, and support for the packaged agent harness and model. Do not assume standard Copilot Studio agent compatibility.
2. Install **Dual-write core**, then **Dual-write Application Core**. Verify completion before installing IVS/Product Search Core. The map importer must exist before Product Search Core imports.
3. Install/configure Inventory Visibility using Microsoft's supported installer. Verify all six managed Product Search maps; for live product search, apply them and complete company setup and initial synchronization.
4. Import the v2 ZIP with values and connections for the intended target. Use a protected settings file outside Git.
5. Verify all five flows, four native workflow registrations, the MCP binding, skills, knowledge, and agent validation. Do not infer correct bindings from tool names alone.
6. Test read-only operations before allowing any reservation or order changes. Test mutations only with approved disposable fixtures and cleanup.
7. Publish after acceptance, then test the intended Teams or Microsoft 365 Copilot channel with the actual user identity.

Detailed steps, exact variable names, verification, and troubleshooting are in [Install v2](docs/install-v2.md).

## What has been tested?

Keep these evidence levels separate:

- **Package validation:** structural checks, native associations, configuration hygiene, and offline packaging.
- **Fresh installation (completed):** exact-package import into a second environment, native content/binding inspection, Review, and one no-tool draft Preview turn.
- **Functional acceptance (deployment-specific):** connected service calls, business-data conversations, approved transaction tests, evaluations, publication, and channel testing.

The prior configured-environment evaluation scored **115/116 evidence-led passes (99.1%)**, with **FUL-014** accepted as a known intermittent location-labeling defect. This does not certify every customer environment or a fresh package import. Native Copilot Studio General quality scores are advisory, not the evidence-led assessment.

See the [release validation record](docs/validation.md) for the exact package tested, completed checks, and outstanding gates.

## Important implementation boundaries

- The included fulfillment knowledge is a **demo policy**: Central/Houston, nearby-store transfers first, vendor delivery only with vendor stock, then alternative sizes. Review it for your organization; it is not a universal sourcing policy or delivery SLA.
- Inventory data, synchronized catalogue data, ATP schedules, connections, credentials, evaluation runs, and channel installations are **not** included in the ZIP.
- The agent can change business data. A successful import is not authorization to run order or reservation examples.
- The IVS client-secret variable uses **String** storage, not an Azure Key Vault secret reference. Protect it, restrict makers, retain secure flow inputs/outputs, and rotate credentials appropriately.
- Do not shorten instructions, switch models, or disable authentication merely to make an unsupported target accept the sample.

## Documentation

- [Installation and configuration](docs/install-v2.md)
- [Version differences, coexistence, and cutover](docs/version-comparison.md)
- [Release notes and known issues](docs/release-notes.md)
- [Validation scope and acceptance checklist](docs/validation.md)
- [Legacy v1 installation](docs/legacy-v1-installation.md)
- [Solution inventory](Solutions/README.md)

This sample is provided under the repository's [license](../../../LICENSE) and [security policy](../../../SECURITY.md). It is provided as-is; assess and support your deployment through your normal implementation and operations processes. Never attach secrets, raw tenant exports, or customer conversations to public issues.
