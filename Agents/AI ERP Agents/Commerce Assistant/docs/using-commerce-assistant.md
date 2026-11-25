# Configure and use Commerce Assistant

Complete [Azure setup](../AzureResources/README.md) and
[POS installation](../Extensions/README.md) first.

## Prepare your store guidance

The supplied assistant instructions are deployed with the Azure resources. To tailor
the experience, [update the instructions](../AzureResources/docs/update-assistant-instructions.md)
with your store's guidance. To answer questions about products or policies,
[add the relevant documents](../AzureResources/docs/add-knowledge-documents.md).

Use products, customers, and delivery options available in your own Commerce channel.

## Open chat

1. Open POS and sign in as an associate.
2. Select the **Copilot icon** in the POS header to open the chat panel.
3. Enter a request, for example, **"Find a jacket for rainy weather."**
4. Review the response and product cards. Choose any required size, color, or other variant before selecting **Add to sale**.
5. Select **New chat** when you want to start another conversation.

Use your own product terms in the examples below.

| Task | Example request | What to check |
| --- | --- | --- |
| Find products | "Find a jacket for rainy weather." | The results match products sold in the current channel. |
| Refine a search | "Show me similar options in blue." | The selected product and variant match the customer's request. |
| Compare options | "Compare these jackets." | Review the displayed differences before selecting a product. |
| Get cart suggestions | "What goes well with the items in this cart?" | Review suggestions and add only the items the customer wants. |
| Prepare shipping | "Help me ship this cart to the customer." | Verify the customer, address, delivery option, and quantities. |
| Ask about a policy | "What is our return policy?" | Add your policy documents first and review any linked sources. |

## Enter a counter order

Open the samples menu in the POS header, then select **Copilot > Counter order**.

### Paste an item list

1. Select **Bulk add items** > **Paste item list**.
2. Paste one item ID and quantity per line. For example:

   ```text
   ITEMSKU-001 x2
   ITEMSKU-002 x3
   ```

3. Replace the example IDs with items sold in your channel. Correct any reported errors and review the products and quantities.
4. Select **Add to cart**, then check the cart before proceeding to payment.

### Add from a photo

1. Select **Bulk add items** > **Add from photo**.
2. Choose a clear photo of the customer's item list and follow the prompts.
3. Check the cart when processing finishes. If only some items were added or the request was interrupted, check existing quantities before trying again.

Photo entry requires an image-capable model and access to your Commerce cart.

## Customer-order lookup

Open the samples menu and select **Copilot > Customer order lookup**.

The sample starts in demonstration mode, which simulates a lookup failure so you can
try error assistance. For real lookups, set `SIMULATE_OUTAGE_BY_DEFAULT` to `false` in
[`CustomerOrderLookup.ts`](../Extensions/Pos/Extend/Agent/CustomerOrderLookup.ts),
then [rebuild and redeploy](../Extensions/README.md#build) the extension.

## Check the experience before rollout

1. Find a product, select its variant, add it to the sale, and verify its quantity and price.
2. Try a comparison, a cart suggestion, and a counter-order item list.
3. Test shipping and customer-order tasks with valid test customers and addresses.
4. If using documents or attachments, verify a policy answer and a file or photo request.
5. Start a new chat, sign out, and lock the terminal. Confirm another associate does not inherit the conversation.

Voice input requires browser support and microphone permission.

## Troubleshooting

| Symptom | What to do |
| --- | --- |
| Chat icon is missing | Confirm the POS package reached the correct CSU, then reopen POS and sign in. Windows Store Commerce also needs its matching extension installer. |
| Chat fails to connect | Confirm the build used the `apimGatewayUrl` from your deployment. Check authentication and that the gateway allows the POS origin; Windows Store Commerce also uses `https://local.storecommerce.dynamics.com`. |
| Product search returns no usable results | Confirm the products are available in the active channel and Commerce MCP is enabled and reachable. |
| A policy answer is missing | Confirm the document is available to the assistant using the [document guide](../AzureResources/docs/add-knowledge-documents.md). |
| A photo or file request fails | Check the file format and size, model support, and the deployed attachment endpoint. |

[Back to Commerce Assistant](../README.md)
