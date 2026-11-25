# Find the deployed Azure resources

Use this procedure to locate the deployment, endpoints, instructions, and knowledge resources.

## Find the deployment outputs

1. Sign in to the [Azure portal](https://portal.azure.com/).
2. Open the resource group used during deployment.
3. Select **Deployments**.
4. Open `commerce-assistant-infrastructure`.
5. Select **Outputs**.

Record these values:

| Output | Use |
| --- | --- |
| `apimGatewayUrl` | Commerce assistant chat endpoint used by POS |
| `apimAttachmentUrl` | Attachment upload endpoint |
| `assistantBlobUrl` | Location of `assistant-instructions.txt` |
| `foundryProjectEndpoint` | Microsoft Foundry project endpoint |
| `searchServiceEndpoint` | Azure AI Search endpoint used by Foundry IQ |
| `foundryIqKnowledgeSourceName` | File knowledge source, normally `commerce-documents` |
| `foundryIqKnowledgeBaseName` | Knowledge base, normally `commerce-knowledge` |

## Identify each resource

Resource names are derived from the Retail Server environment ID. If a globally unique name was unavailable, deployment adds a short suffix.

| Resource | Typical name | Purpose |
| --- | --- | --- |
| API Management | `<environment-id>-apim` | Secures and routes POS requests |
| Microsoft Foundry | `<environment-id>-foundry` | Hosts the project and model deployments |
| Foundry project | `<environment-id>-assistant` | Contains connected resources and knowledge |
| Azure AI Search | `<environment-id>-search` | Stores and retrieves Foundry IQ knowledge |
| Storage account | `<environment-id>stg` | Stores assistant instructions |

## Common destinations

- Update instructions: storage account > **Containers** > `assistant-config`.
- Add documents: Microsoft Foundry > project > **Build** > **Knowledge** > `commerce-knowledge` > `commerce-documents`.
- Review API configuration: API Management > **APIs** > `commerce-assistant`.

## Microsoft guidance

- [View Azure Resource Manager deployment history](https://learn.microsoft.com/azure/azure-resource-manager/templates/deployment-history)
- [Manage resources in the Azure portal](https://learn.microsoft.com/azure/azure-resource-manager/management/manage-resources-portal)

[Back to guide index](README.md)
