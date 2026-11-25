# Deploy the Commerce assistant resources to Azure

Use PowerShell with Azure CLI installed and an Azure account permitted to create resources and assign roles. You need `Owner`, or both `Contributor` and `Role Based Access Control Administrator`, at the deployment scope, plus resource-group creation permissions if creating a group. Confirm regional model availability and quota before deploying.

Choose a model/version that supports text watermarking, and verify that watermarking is enabled after deployment.

```powershell
.\deploy.ps1 -Tenant "<tenant-id>"
```

Enter the four values when prompted:

- `apimPublisherEmail`: API Management publisher email
- `retailServerBaseUrl`: Retail Server URL without a trailing slash
- `commerceChannelId`: Commerce channel record ID
- `posOrigin`: Cloud POS origin containing only the scheme and host

Save the final output. Use `apimGatewayUrl` as the assistant endpoint in POS.

A deployment creates billable Azure resources. If a connection is interrupted, check the deployment status in Azure before rerunning with the same values.

Continue with the [POS extension build and deployment](../Extensions/README.md) using the returned `apimGatewayUrl`. See the [post-deployment guides](docs/README.md) for assistant, model, authentication, and knowledge-source configuration.
