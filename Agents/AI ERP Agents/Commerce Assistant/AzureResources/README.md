# Deploy the Commerce assistant resources to Azure

Use PowerShell with Azure CLI installed and an Azure account permitted to create resources and assign roles. You need `Owner`, or both `Contributor` and `Role Based Access Control Administrator`, at the deployment scope, plus resource-group creation permissions if creating a group. Confirm regional model availability and quota before deploying.

The template requests always-on text watermarking for the assistant model deployment. Before deploying, confirm that the selected model/version and ARM API version support this setting. Existing deployments are not changed until the updated template is applied; `deployModel: false` skips the model update. Verify the deployment setting and generated-text provenance after deployment.

```powershell
.\deploy.ps1 -Tenant "<tenant-id>"
```

Enter the four values when prompted:

- `apimPublisherEmail`: API Management publisher email
- `retailServerBaseUrl`: Retail Server URL without a trailing slash
- `commerceChannelId`: Commerce channel record ID
- `posOrigin`: Cloud POS origin containing only the scheme and host

Save the final output. Use `apimGatewayUrl` as the assistant endpoint in POS.

The deployment uses Azure CLI's active subscription. Select the intended subscription before running the script:

```powershell
az account set --subscription "<subscription-id>"
```

For repeatable deployments, replace the placeholders in `azuredeploy.parameters.json` and pass it explicitly:

```powershell
.\deploy.ps1 -Tenant "<tenant-id>" -ParametersFile .\azuredeploy.parameters.json
```

Without `-ParametersFile`, only the four prompted values are supplied; the template defaults apply to other settings. Keep model and customer-authentication overrides in the parameters file for subsequent deployments. Do not commit credentials or environment-specific parameter files.

The script signs in if needed, deploys resources and role assignments, provisions Foundry IQ, and uploads the assistant instructions. A deployment creates billable Azure resources. If a connection is interrupted, check the deployment status in Azure before rerunning with the same values.

Continue with the [POS extension build and deployment](../Extensions/README.md) using the returned `apimGatewayUrl`. See the [post-deployment guides](docs/README.md) for assistant, model, authentication, and knowledge-source configuration.
