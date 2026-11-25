# Commerce Assistant POS extension

Build and install the Commerce Assistant chat experience for Cloud POS or Windows Store Commerce.

## Prerequisites

- Windows and Visual Studio with MSBuild and the .NET development tools required by the [Store Commerce extension SDK](https://learn.microsoft.com/dynamics365/commerce/dev-itpro/pos-extension/pos-extension-overview), including .NET Framework 4.7.2 targeting support for the installers.
- Node.js and npm on `PATH`.
- Access to Commerce SDK NuGet packages matching the target Commerce release. This sample targets Commerce SDK **9.61**.
- An activated POS device and a signed-in associate, with channel/product/customer/order data appropriate to the scenario.
- The [Azure resources](../AzureResources/README.md) deployed for your environment, with Commerce MCP enabled and accessible to the assistant.

## Build

Run the build from the `Extensions` directory. If you encounter Windows path-length errors, copy the complete `Commerce Assistant` folder to a short path such as `C:\CommerceAssistant` and retry.

Supply the `apimGatewayUrl` returned by Azure deployment, without `/chat` or `/attachments`:

```powershell
.\Build-ExtensionArtifacts.ps1 `
    -ApimEndpoint "https://your-apim.azure-api.net/commerce-assistant" `
    -CommerceSdkPackagesVersion "<exact-sdk-version-for-your-release>"
```

The script restores dependencies and builds the CSU deployment ZIP and Windows Store Commerce installer. No separate build commands are required. Supply `-MSBuildPath` if automatic discovery cannot find your installation. `-BuildNumber` defaults to `1.0`; the package version combines the sample's major version with that build number.

Package restore requires access to the configured NuGet and npm feeds. If a corporate network blocks a feed or causes TLS errors, configure an approved reachable mirror through NuGet or MSBuild's `RestoreSources` setting before running the script; do not disable certificate validation.

Do not put keys, credentials, query strings, or fragments in the endpoint URL. Use the same endpoint, SDK version, and package version for CSU and Windows packages.

## Generated artifacts and installation

The package identity is `Contoso.PosExtensions`. Do not install it beside another package using that identity.

The build script reports the generated files:

| Output | Use |
| --- | --- |
| `ScaleUnit\bin\Release\netstandard2.0\CloudScaleUnitExtensionPackage.zip` | Deploy to the CSU for Cloud POS and Windows Store Commerce. |
| `StoreCommerce.Installer\bin\Release\net472\Contoso.PosExtensions.StoreCommerce.Installer.exe` | Install on Windows Store Commerce devices in addition to the CSU package. |

For Commerce environments managed through Power Platform admin center, upload the generated CSU ZIP through your approved Commerce extension-asset process, then apply that exact asset to the target CSU. Do not upload a source ZIP or the Windows installer archive as the CSU asset.

For Windows Store Commerce, keep the generated installer and companion files together and follow the SDK installation procedure (including elevation where required). Cloud POS does not require the Windows installer. Reopen POS and sign in after deployment.

Configure authentication and allowed POS origins using the [Azure deployment guide](../AzureResources/README.md). For Windows Store Commerce, also allow `https://local.storecommerce.dynamics.com` in the gateway's CORS settings.

## Next step

Follow [Configure and use Commerce Assistant](../docs/using-commerce-assistant.md)
to try product search, cart suggestions, counter orders, and customer-order lookup.
