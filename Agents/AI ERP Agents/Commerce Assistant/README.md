# Commerce Assistant

A sample assistant for Dynamics 365 Commerce associates, combining Azure deployment resources and a Store Commerce POS chat extension in one package.

| Folder | Contents |
| --- | --- |
| [AzureResources](AzureResources/README.md) | API Management, Microsoft Foundry, Storage, Azure AI Search, assistant instructions, attachment policies, and post-deployment guides. |
| [Extensions](Extensions/README.md) | POS extension source, build script, and installation guide. |

## Get started

1. Use a nonproduction Commerce environment with Commerce MCP enabled, an activated POS device, a signed-in associate, and the required channel data. Review the [limitations](#limitations) before deploying.
2. Follow the [Azure deployment guide](AzureResources/README.md). Save the returned `apimGatewayUrl`.
3. Follow the [POS build and installation guide](Extensions/README.md), supplying that URL to the build script.
4. Verify chat, recommendations, cart suggestions, comparison, attachments, order flows, and sign-out/terminal-lock behavior against your own environment.

Azure deployment and POS extension installation are separate steps. Azure resources incur charges.

## Limitations

- Customer-order lookup simulates an outage by default. See the extension guide before enabling real lookups.
- Voice input requires browser support and microphone permission. Attachments and photo-based cart entry require compatible model capabilities and Commerce tools.
- Retain the included [Commerce SDK license](Extensions/LICENSE) and source notices when redistributing the sample.
- The package identity is `Contoso.PosExtensions`; do not install it beside another package using that identity.
