# Commerce Assistant POS extension

This sample provides the Commerce Assistant POS extension and its supporting CRT endpoints. It does not include a custom Commerce MCP implementation.

## Prerequisites

- Windows and Visual Studio with MSBuild and the .NET development tools required by the [Store Commerce extension SDK](https://learn.microsoft.com/dynamics365/commerce/dev-itpro/pos-extension/pos-extension-overview), including .NET Framework 4.7.2 targeting support for the installers.
- Node.js and npm on `PATH`.
- Access to Commerce SDK NuGet packages matching the target Commerce release. This sample targets the **9.61** SDK family in `repo.props`.
- An activated POS device and a signed-in associate, with channel/product/customer/order data appropriate to the scenario.
- The [Azure resources](../AzureResources/README.md), configured for your environment, and an external Commerce MCP service exposing the tools used by the assistant.

## Build

The Commerce SDK's packaging tasks use legacy Windows path limits. Extract or copy `Commerce Assistant` to a short path such as `C:\CommerceAssistant` before building; a long repository path can compile successfully but fail while packaging. A short directory junction to this `Extensions` directory is another option.

Run from the `Extensions` directory at that short path. Supply the `apimGatewayUrl` returned by Azure deployment, without `/chat` or `/attachments`:

```powershell
.\Build-ExtensionArtifacts.ps1 `
    -ApimEndpoint "https://your-apim.azure-api.net/commerce-assistant" `
    -CommerceSdkPackagesVersion "<exact-sdk-version-for-your-release>"
```

The script builds the React panel, generates Commerce proxies and POS SDK development files, and uses Visual Studio MSBuild to restore and build the CSU package and Windows Store Commerce installer. No separate npm build commands are required. Supply `-MSBuildPath` if automatic discovery cannot find your installation. `-BuildNumber` defaults to `1.0`; the package version combines the source's major version with that build number.

Package restore requires access to the configured NuGet and npm feeds. If a corporate network blocks a feed or causes TLS errors, configure an approved reachable mirror through NuGet or MSBuild's `RestoreSources` setting before running the script; do not disable certificate validation.

`ContosoApimEndpoint` is packaged as CRT setting `ext.Contoso.ApimEndpoint`. The POS client reads it through `GetApimEndpoint` and appends its operation paths. Do not put keys, credentials, query strings, or fragments in this URL. Build CSU and Windows packages using the same endpoint, SDK version, and package version.

## Generated artifacts and installation

The build script reports the SDK output directories:

| Project | Output and use |
| --- | --- |
| `ScaleUnit\Contoso.PosExtensions.ScaleUnit.csproj` | CSU deployment ZIP containing the POS web extension and supporting CRT assembly. Deploy through the supported extension-management process for your environment. |
| `StoreCommerce.Installer\Contoso.PosExtensions.StoreCommerce.Installer.csproj` | Windows Store Commerce extension installer and companion configuration. In-app Store Commerce requires this in addition to the CSU package. |
| `ScaleUnit.Installer\Contoso.PosExtensions.ScaleUnit.Installer.csproj` | Optional self-hosted CSU installer project, retained for environments using that deployment path. |

For Commerce environments managed through Power Platform admin center, upload the generated CSU ZIP through your approved Commerce extension-asset process, then apply that exact asset to the target CSU. Do not upload a source ZIP or the Windows installer archive as the CSU asset.

For Windows Store Commerce, keep the generated installer and companion files together and follow the SDK installation procedure (including elevation where required). Cloud POS does not require the Windows installer. Reopen POS and sign in after deploying the matching POS/CRT components.

No prebuilt ZIP from another release is included or represented as a build of this source.

## How it works

The header icon opens the React/Fluent UI panel. Logon, logoff, and terminal-lock triggers manage its lifecycle. The agent receives POS context and returns assistant text plus named POS actions; POS validates actions and resolves product data through Commerce APIs.

| Source | Purpose |
| --- | --- |
| `Pos\Create\SideChatPanel` | React UI, agent contracts, attachments, voice input, citations, product cards, and comparison. |
| `Pos\Extend\Agent` | Gateway requests, supported actions, cart/product/customer/order helpers. |
| `Pos\Extend\Triggers` | Panel lifecycle, cart updates, and automatic suggestions. |
| `Pos\Create\Views` | Product comparison/results, customer-order lookup, counter-order entry, and the assistant menu. |
| `CommerceRuntime` | APIM configuration lookup, customer-order delivery endpoint, and POS package registration. |

The gateway must provide `POST /chat` and `POST /attachments` beneath the configured base URL. Chat uses a JSON-serialized request envelope in `message` and a Responses API-style reply containing the serialized assistant envelope. See `Pos\Create\SideChatPanel\agentContracts.ts` and `Pos\Extend\Agent\posActionCatalogue.ts` for the precise contracts and action schemas.

APIM must validate the associate's Commerce token and the device token where applicable. Allow the actual POS origin, preflight requests, and `Authorization`, `DeviceToken`, and `Content-Type` headers. The [Azure policies](../AzureResources/README.md) implement the gateway side; review their settings against your authentication and deployment requirements.

## Validate in your environment

1. Sign in, open the chat icon, and send a normal question. Verify authentication, the APIM endpoint, and a response from the configured model.
2. Search your channel's products; verify cards, filters, variant selection, comparison, and Add to sale.
3. Add a product and verify cart suggestions. Exercise shipping/customer-order actions with valid Commerce data.
4. Open the assistant menu and test **Customer order lookup** and **Counter order**. Photo entry needs attachments, an image-capable model, and cart tools; verify partial failures do not cause duplicate additions.
5. Test attachments, a new conversation, sign-out, and terminal lock. Verify no conversation is inherited by another operator.

Customer-order lookup intentionally simulates an outage. Set `SIMULATE_OUTAGE_BY_DEFAULT` in `Pos\Extend\Agent\CustomerOrderLookup.ts` to `false` and rebuild for real lookups. The unrelated forced product-sale error trigger is not registered in this package.

The persistent panel and device-token integration use unsupported host internals. Validate compatibility with the actual POS version. External MCP extensions, performance improvements, and tool discovery are not installed or validated merely by building this extension.
