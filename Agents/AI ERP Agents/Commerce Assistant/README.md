# Commerce Assistant

A sample assistant for Dynamics 365 Commerce associates, combining Azure deployment resources and a Store Commerce POS chat extension in one package.

| Folder | Contents |
| --- | --- |
| [AzureResources](AzureResources/README.md) | API Management, Microsoft Foundry, Storage, Azure AI Search, assistant instructions, attachment policies, and post-deployment guides. |
| [Extensions](Extensions/README.md) | POS chat UI, product recommendation and comparison views, customer-order and counter-order flows, supporting CRT endpoints, and CSU/Store Commerce packaging projects. |

## Get started

1. Use a nonproduction Commerce environment with an activated POS device, a signed-in associate, and the required channel data. Review the [limitations](#limitations) before deploying.
2. Follow the [Azure deployment guide](AzureResources/README.md). Save the returned `apimGatewayUrl`.
3. Follow the [POS build and installation guide](Extensions/README.md), supplying that URL as `ContosoApimEndpoint`. Build the POS and CRT components together for the target Commerce release.
4. Verify chat, recommendations, cart suggestions, comparison, attachments, order flows, and sign-out/terminal-lock behavior against your own environment.

Azure deployment and Commerce extension deployment are separate operations. This repository does not deploy to an environment automatically. Azure resources incur charges.

## Scope and dependencies

The Azure resources and POS extension source are supplied together. The POS build produces the CSU deployment package and Windows Store Commerce extension installer; a source archive or React JavaScript bundle is **not** an installable Commerce extension.

**No custom Commerce MCP implementation is included.** The target environment must provide its own supported Commerce MCP service and tools. Assistant instructions may refer to extension tools such as `extension_search_products_with_variants`; deploy those separately or adapt the instructions to the tools your environment actually exposes. Their availability and performance are external dependencies, not capabilities installed by this sample.

Configure authentication, allowed POS origins, model capabilities, assistant instructions, and knowledge sources for your own environment. The POS client does not send an APIM subscription key. For Windows Store Commerce, review whether the gateway must also allow `https://local.storecommerce.dynamics.com`.

## Limitations

- This is a sample, not a production-readiness or latency guarantee. Validate the complete Azure, Commerce, and POS path before adoption.
- The persistent chat panel attaches to `document.body`, and device-token acquisition uses host internals. These are not supported POS extension contracts.
- Customer-order lookup simulates an outage by default. See the extension guide before enabling real lookups.
- Voice input requires browser support and microphone permission. Attachments and photo-based cart entry require compatible model capabilities and Commerce tools.
- Retain the included [Commerce SDK license](Extensions/LICENSE) and source notices. Publication approval and target-release compatibility must be established before redistributing generated packages.

## Source snapshots

The Azure files originate from `Commerce-ConceptValidations`, commit `d0c34172ad0838d62340872427a0de1cf0bc9d28`, under `MCP/APIM/commerce-assistant-azure-resources`.

The POS implementation originates from `Commerce-Samples-InStore` PR 350, commit `2f595cdad495d3c6223789b4ad05f7fd46cce8b9`. Only the POS assistant functionality and its required CRT/build support were extracted. The PR's MCP folder, MCP tests, unrelated POS samples, and forced product-sale error demo are excluded.

Packaging adaptations are limited to the standalone build-property import, assistant-only menu/manifest registrations, removal of MCP build references, customer-facing documentation, and artifact/build hygiene. The npm lockfile uses public registry URLs with the original versions and integrity hashes; npm restoration uses `npm ci`. The original package identity `Contoso.PosExtensions` is retained across the manifest and CRT registration trigger; do not install it beside another package using that identity.

Maintainer-only Azure deployment notes and development-environment screenshots are intentionally omitted from the customer package.
