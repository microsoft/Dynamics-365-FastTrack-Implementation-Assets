# Add another knowledge source

Use this procedure when the assistant needs knowledge from a source other than manually uploaded files, such as Azure Blob Storage, SharePoint, OneLake, or public web content.

## Before you start

- Confirm that the source is supported in your Azure region.
- Confirm preview status, permissions, networking, and expected cost.
- Get approval from the owner of the source data.
- Ask the Azure resource owner for **Foundry User** access. Sources backed by Azure AI Search also require **Search Service Contributor** and **Search Index Data Contributor** access.

## Add the source

1. Sign in to [Microsoft Foundry](https://ai.azure.com/) and open the project whose name ends in `-assistant`.
2. Select **Build** > **Knowledge**.
3. Open the existing `commerce-knowledge` knowledge base.
4. Select the option to add a knowledge source.
5. Choose the source type and complete the portal prompts.
6. Make sure the new source is included in `commerce-knowledge`.
7. Save the knowledge base and wait for any indexing or synchronization to finish.

Keep the existing knowledge base name. The Commerce assistant is configured to call `commerce-knowledge`; creating a separate knowledge base does not connect it to the assistant automatically.

## If Foundry asks for a connection

1. Select **Manage** > **Project details** > **Connected resources**.
2. Select **Add connection**.
3. Choose the service, select the resource, and use Microsoft Entra ID authentication when supported.
4. Return to **Build** > **Knowledge** and add the source again.

Adding a connection only makes the resource available to the project. You must still add it as a source in `commerce-knowledge`.

## Verify

1. Confirm the source shows a healthy or ready state.
2. Ask a question that can be answered only from that source.
3. Confirm the answer is grounded in the expected content.

## Microsoft guidance

- [Foundry IQ supported concepts and workflow](https://learn.microsoft.com/azure/foundry/agents/concepts/what-is-foundry-iq)
- [Knowledge source overview](https://learn.microsoft.com/azure/search/agentic-knowledge-source-overview)
- [Add a connection to a Foundry project](https://learn.microsoft.com/azure/foundry/how-to/connections-add)
- [Foundry role-based access control](https://learn.microsoft.com/azure/foundry/concepts/rbac-foundry)

[Back to guide index](README.md)
