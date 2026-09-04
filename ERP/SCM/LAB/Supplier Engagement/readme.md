# Supplier Engagement lab for Dynamics 365 Supply Chain Management

This lab walks through the preview Supplier Engagement experience in Dynamics 365 Supply Chain Management. It is designed for implementation teams, solution architects, and functional consultants who need to understand how global vendor onboarding, supplier portal access, supplier lifecycle management, RFQ collaboration, purchase order collaboration, and supplier invoice collaboration fit together.

The lab uses a fictional electronics manufacturer, Technova Industries, and follows three supplier onboarding patterns:

| Supplier | Scenario | Creation path |
|---|---|---|
| Pacific Components Ltd. | New supplier self-registration | Supplier portal |
| Alps Sensors GmbH | Internally invited supplier | Supplier Engagement app |
| Acme Office Supplies | Existing vendor migration | Supply Chain Management |

## Start here

Open [index.html](index.html) for the full browser-based guide.

The editable source modules are also included under [markdown](markdown):

| Module | Article |
|---|---|
| Scenario | [Personas, lab values, and preview disclaimer](markdown/story.md) |
| Concept | [Global vendor model and lifecycle overview](markdown/concept.md) |
| Lab 0 | [Prerequisites and environment validation](markdown/lab0.md) |
| Lab 1 | [Supplier portal setup and site access](markdown/lab1.md) |
| Lab 2 | [Dataverse configuration and duplicate detection](markdown/lab2.md) |
| Lab 3 | [SCM feature, security, and workflow setup](markdown/lab3.md) |
| Lab 4 | [Supplier Engagement reference data](markdown/lab4.md) |
| Lab 5 | [Supplier self-registration and onboarding](markdown/lab5.md) |
| Lab 6 | [Internal invitation and vendor lifecycle](markdown/lab6.md) |
| Lab 7 | [Existing vendor migration](markdown/lab7.md) |
| Lab 8 | [RFQ collaboration through the supplier portal](markdown/lab8.md) |
| Lab 9 | [Purchase order collaboration, invoice collaboration, and optional consignment](markdown/lab9.md) |

## Prerequisites

Before running the lab, prepare the following:

- Dynamics 365 Supply Chain Management version 10.0.48 build 10.0.2645.52 or later.
- A Supply Chain Management environment linked to Dataverse.
- Required finance and operations virtual entity solutions installed and current.
- System Administrator access in Supply Chain Management and Dataverse.
- A Power Platform administrator or equivalent tenant-level setup access.
- A dedicated service account for cloud flows and supplier portal automation, or a suitable admin account for a non-production proof of concept.
- Microsoft Entra ID B2B invitation configuration for Finance and Operations apps.
- A configured vendor user request workflow that includes the automated `Provision Microsoft Entra ID B2B user` task.
- A Power Pages supplier portal configured for public access, or private site access granted to the redeemed supplier B2B guest for trial or developer environments.

## Important preview note

Supplier Engagement is a preview feature in Dynamics 365 Supply Chain Management 10.0.48. Preview features are not intended for production use and are subject to supplemental terms of use. Validate all configuration in a sandbox or demo environment before using the guidance in customer-facing work.

## B2B and supplier portal guidance

The lab documents the recommended B2B setup pattern for Finance and Operations apps:

- Configure a Microsoft Entra app registration with the required Microsoft Graph permissions.
- Grant tenant admin consent.
- Add the app registration and client secret in **System administration > Setup > Microsoft Entra ID > B2B Invitation Configuration**.
- Add the automated `Provision Microsoft Entra ID B2B user` task to the approved new-user path in the vendor user request workflow.

For normal external supplier testing, the supplier portal should be publicly accessible. If a trial, developer, or non-production Power Pages site cannot be made public, keep the site private and grant site access to the supplier's redeemed Entra B2B guest. This allows the supplier to reach the portal while preserving the Supplier Engagement permission checks performed by the app.

## Optional steps

Some steps in the lab are marked optional because they are useful for a richer demo but are not required for the core Supplier Engagement flow. Examples include portal branding updates, image updates, help cards, risk reporting setup, second legal entity release, and consignment collaboration.

## Assets

Screenshots and supporting files are stored in [assets](assets). The workflow setup screenshot is included to show where the Entra B2B provisioning automated task belongs in the approved new-user workflow path.

## References

- [Supplier Engagement overview](https://learn.microsoft.com/dynamics365/supply-chain/supplier-engagement/supplier-engagement-overview)
- [Global vendor management overview](https://learn.microsoft.com/dynamics365/supply-chain/supplier-engagement/supplier-engagement-global-vendors-overview)
- [Manage local vendors](https://learn.microsoft.com/dynamics365/supply-chain/supplier-engagement/supplier-engagement-manage-local-vendors)
- [Power Platform integration with finance and operations apps](https://learn.microsoft.com/dynamics365/fin-ops-core/dev-itpro/power-platform/overview)