# Change the Commerce assistant model

Use this procedure to switch the model used by POS.

The replacement must be deployed in the same Foundry resource and support the Responses API, tool calling, image input, and PDF file input. Confirm regional availability, quota, context size, and output-token limits before making the change.

This starter kit is configured for OpenAI-format models. Customers can update the APIM policy to support partner/community models or models that use a different endpoint format.

## Before you start

- Get permission to manage Foundry model deployments and APIM named values.
- Record the current deployment name and `foundry-max-output-tokens` value.
- Keep the current model deployment for rollback.
- Test the change in a nonproduction environment first.

## 1. Deploy and test the model in Foundry

1. Sign in to [Microsoft Foundry](https://ai.azure.com/) and open the project whose name ends in `-assistant`.
2. Select **Discover** > **Models**, choose a compatible model, and review its model card.
3. Select **Deploy** > **Custom settings**.
4. Enter a unique deployment name, choose the deployment type and capacity, and select **Deploy**.
5. Wait for the deployment status to show **Succeeded**.
6. Select **Build** > **Models**, open the deployment, and test it in the playground.

Write down the deployment name exactly. APIM uses this name, not the model family name.

## 2. Point APIM to the deployment

1. In the [Azure portal](https://portal.azure.com/), open the deployment resource group.
2. Open the API Management service whose name ends in `-apim`.
3. Select **APIs** > **Named values**.
4. Open `foundry-model-deployment`.
5. Replace its value with the new Foundry deployment name and select **Save**.
6. If the new model supports fewer output tokens, also lower `foundry-max-output-tokens`.

Do not edit the API policy XML. The policy already reads these named values at runtime.

Keep the named value's name and type unchanged. Replace only its value with the new Foundry deployment name.

## 3. Validate in POS

Test each behavior before removing the old deployment:

- A normal assistant question
- A Commerce action that calls a Commerce MCP tool
- A question answered from Foundry IQ
- An image attachment and a PDF attachment
- A follow-up question in the same conversation

Check APIM and Foundry metrics for authentication errors, unsupported features, `429` throttling, and token-limit errors.

## 4. Make the change durable

A future `deploy.ps1` run restores template defaults unless a parameters file supplies overrides. To preserve a custom model, ask the deployment owner to add or update these entries under `parameters` in `azuredeploy.parameters.json` and pass that file with `-ParametersFile` on subsequent deployments. Interactive mode only prompts for the four environment values, not model settings. The numeric values below are examples; choose values supported by the model and available quota.

```json
"modelDeploymentName": { "value": "<deployment-name>" },
"modelName": { "value": "<model-name>" },
"modelVersion": { "value": "<model-version>" },
"modelSkuName": { "value": "<deployment-type>" },
"modelCapacity": { "value": 100 },
"modelMaxOutputTokens": { "value": 25000 }
```

Running `deploy.ps1` after updating these values is the preferred repeatable method because it keeps Foundry and APIM configuration aligned.

## Roll back

1. Restore the previous `foundry-model-deployment` value in APIM.
2. Restore `foundry-max-output-tokens` if it changed.
3. Test in POS.
4. Restore the previous values in `azuredeploy.parameters.json`.

Changing to a different Foundry account or project also requires endpoint and managed-identity permission changes. Use the deployment package rather than this quick-switch procedure.

## Microsoft guidance

- [Deploy and manage Foundry models](https://learn.microsoft.com/azure/foundry/foundry-models/how-to/deploy-foundry-models)
- [Responses API supported models and file input](https://learn.microsoft.com/azure/foundry/openai/how-to/responses)
- [Use named values in Azure API Management](https://learn.microsoft.com/azure/api-management/api-management-howto-properties)

[Back to guide index](README.md)
