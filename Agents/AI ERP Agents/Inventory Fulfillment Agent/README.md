# Inventory Fulfillment Agent

Help an associate move from "Do we have it?" to a confirmed fulfillment action in Dynamics 365. This sample combines Microsoft Copilot Studio, Inventory Visibility, product search, and the Dynamics 365 ERP Model Context Protocol (MCP) connector.

**Find it. Promise it. Move it.**

The agent can resolve products, inspect inventory and available-to-promise (ATP), suggest fulfillment options, manage soft reservations, and assist with sales and transfer orders. Write operations require user confirmation and appropriate Dynamics 365 permissions.

> This is an implementation sample, not a turnkey production service. Validate licensing, regional/model availability, security, data, and business policy in your own non-production environment before deployment. Nothing runs locally.

## Start here: deploy v2

**For a new deployment, start with v2 when its required Copilot Studio experience and model are available in your target.** V2 uses the GitHub Copilot-based agent harness, sales/transfer skills, and the native Dynamics 365 ERP MCP connector.

**[Follow the v2 deployment guide](docs/install-v2.md)** — Prepare → Connect → Install → Configure → Verify → Publish.

The guide provides two starting points: verify an existing IVS/Product Search setup, or prepare a new environment first. It explains responsibilities, where to find configuration values, expected results, and when to stop.

> **Already using v1?** Keep your existing deployment. The unchanged [legacy package](Solutions/InventoryFulfillmentAgent_V1_1_0_0_7.zip) and [v1 guide](docs/legacy-v1-installation.md) remain available. V2 installs separately; it is **not an in-place v1 upgrade**.

## Download v2

| Asset | Purpose |
| --- | --- |
| [InventoryFulfillmentAgent_V2_2.0.0.1_unmanaged.zip](Solutions/InventoryFulfillmentAgent_V2_2.0.0.1_unmanaged.zip) | New solution; import the ZIP without extracting it |
| [SHA-256 checksum](Solutions/InventoryFulfillmentAgent_V2_2.0.0.1_unmanaged.zip.sha256) | Verify the exact download |
| [Blank v2 deployment settings](Solutions/deployment-settings.v2.example.json) | Seven environment variables and two target connection references |
| [Release notes](docs/release-notes.md) | Changes, known limitations, and package identity |

To download a ZIP from GitHub, open the file and choose **Download raw file**. Do not import the repository's **Code > Download ZIP** archive as a solution.

## Deployment at a glance

| Stage | Outcome |
| --- | --- |
| **1. Prepare** | Target supports the packaged harness/model; IVS, dual-write, Product Search, and ERP MCP prerequisites are ready |
| **2. Connect** | Two target connections and all seven settings are ready before import |
| **3. Install** | The checksum-verified unmanaged v2 ZIP imports successfully with dependencies intact |
| **4. Configure** | Five flows, four native workflow bindings, MCP, skills, and customer fulfillment policy are checked |
| **5. Verify** | Native Review and a safe Preview pass, followed by separately approved connected-service acceptance |
| **6. Publish** | An authorized owner publishes and tests the actual end-user channel |

Detailed steps, exact variable names, verification, and troubleshooting are in [Install v2](docs/install-v2.md).

## What has been tested?

Keep these evidence levels separate:

- **Package validation:** structural checks, native associations, configuration hygiene, and offline packaging.
- **Fresh installation (completed):** exact-package import into a second environment, native content/binding inspection, Review, and one no-tool draft Preview turn.
- **Functional acceptance (deployment-specific):** connected service calls, business-data conversations, approved transaction tests, evaluations, publication, and channel testing.

The exact **2.0.0.1** ZIP passed fresh-install structural verification and a no-tool Preview smoke test on **October 20, 2026**. That confirms installation and draft startup, not connected integration or production readiness.

The earlier configured-environment evaluation scored **115/116 evidence-led passes (99.1%)**; it is separate historical evidence. **Known limitation: an intermittent response can label another warehouse's stock as the requested store's stock (FUL-014). Verify location explicitly before acting.**

See the [release validation record](docs/validation.md) for the exact package tested, completed checks, and outstanding gates.

## Important implementation boundaries

- The included fulfillment knowledge is a **demo policy**: Central/Houston, nearby-store transfers first, vendor delivery only with vendor stock, then alternative sizes. Review it for your organization; it is not a universal sourcing policy or delivery SLA.
- Inventory data, synchronized catalogue data, ATP schedules, connections, credentials, evaluation runs, and channel installations are **not** included in the ZIP.
- The agent can change business data. A successful import is not authorization to run order or reservation examples.
- The IVS client-secret variable uses **String** storage, not an Azure Key Vault secret reference. Protect it, restrict makers, retain secure flow inputs/outputs, and rotate credentials appropriately.
- Do not shorten instructions, switch models, or disable authentication merely to make an unsupported target accept the sample.

## Existing v1 deployments

| | Current implementation | Retained legacy implementation |
| --- | --- | --- |
| Version / unmanaged solution | **2.0.0.1**, `InventoryFulfillmentAgent_V2` | **1.0.0.7**, `InventoryFulfillmentAgent_V1` |
| Order assistance | Sales/transfer skills | Sales/transfer child agents |
| Guidance | [Deploy v2](docs/install-v2.md) | [Historical v1 guide](docs/legacy-v1-installation.md) |

Keep working v1 deployments and their backups until a separately configured v2 installation passes your acceptance and cutover plan. Conversations, settings, credentials, channels, and evaluations are not migrated by importing v2. See [version differences and cutover](docs/version-comparison.md).

The packaged display name has no "v2" suffix; internal versioned identities are intentional and must remain unchanged. Use distinguishable channel/display names during side-by-side evaluation.

## Documentation

- [Installation and configuration](docs/install-v2.md)
- [Version differences, coexistence, and cutover](docs/version-comparison.md)
- [Release notes and known issues](docs/release-notes.md)
- [Validation scope and acceptance checklist](docs/validation.md)
- [Legacy v1 installation](docs/legacy-v1-installation.md)
- [Solution inventory](Solutions/README.md)

This sample is provided under the repository's [license](../../../LICENSE) and [security policy](../../../SECURITY.md). It is provided as-is; assess and support your deployment through your normal implementation and operations processes. Never attach secrets, raw tenant exports, or customer conversations to public issues.
