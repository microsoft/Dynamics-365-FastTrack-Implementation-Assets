# Add documents to Foundry IQ

Use this procedure to make product guides, policies, and other customer documents available to the Commerce assistant.

> The deployed file knowledge source and its portal management experience are preview features.

## Before you start

Ask the Azure resource owner for access to the deployed Foundry project and Azure AI Search service. Document upload requires **Foundry User**, **Search Service Contributor**, and **Search Index Data Contributor** access.

## Open the knowledge source

1. Sign in to [Microsoft Foundry](https://ai.azure.com/). Make sure **New Foundry** is on.
2. Open the project whose name ends in `-assistant`.
3. Select **Build** > **Knowledge**.
4. Open the `commerce-knowledge` knowledge base.
5. Open the `commerce-documents` knowledge source.
6. Use the file upload action to select and upload documents.
7. Wait until processing completes before testing.

![Microsoft Foundry Build and Knowledge navigation](https://learn.microsoft.com/fabric/onelake/media/onelake-foundry-knowledge/select-knowledge.png)

> Foundry IQ portal features are in preview. Button names can change slightly.

## Choose suitable files

The deployed file knowledge source uses minimal extraction and supports common business documents:

- PDF
- Word, PowerPoint, and Excel
- Text, Markdown, HTML, and CSV
- JSON

On the deployed Basic search tier, each file can be up to 50 MB. A file knowledge source can contain up to 200 files with the current preview API.

Do not use image-only files with this deployment. Minimal extraction does not process image content. Convert scanned or image-only content to a searchable PDF or text document first.

## Verify

1. Confirm the file is listed as processed in `commerce-documents`.
2. In POS, ask a question that can be answered only from the new document.
3. Confirm the answer reflects the document content.

No Azure resource or POS redeployment is required when documents change.

## Microsoft guidance

- [What is Foundry IQ?](https://learn.microsoft.com/azure/foundry/agents/concepts/what-is-foundry-iq)
- [Create and manage a file knowledge source](https://learn.microsoft.com/azure/search/agentic-knowledge-source-how-to-file)
- [Foundry IQ frequently asked questions](https://learn.microsoft.com/azure/foundry/agents/concepts/foundry-iq-faq)

[Back to guide index](README.md)
