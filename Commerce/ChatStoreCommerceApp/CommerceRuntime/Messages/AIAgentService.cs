/**
 * SAMPLE CODE NOTICE
 * 
 * THIS SAMPLE CODE IS MADE AVAILABLE AS IS.  MICROSOFT MAKES NO WARRANTIES, WHETHER EXPRESS OR IMPLIED,
 * OF FITNESS FOR A PARTICULAR PURPOSE, OF ACCURACY OR COMPLETENESS OF RESPONSES, OF RESULTS, OR CONDITIONS OF MERCHANTABILITY.
 * THE ENTIRE RISK OF THE USE OR THE RESULTS FROM THE USE OF THIS SAMPLE CODE REMAINS WITH THE USER.
 * NO TECHNICAL SUPPORT IS PROVIDED.  YOU MAY NOT DISTRIBUTE THIS CODE UNLESS YOU HAVE A LICENSE AGREEMENT WITH MICROSOFT THAT ALLOWS YOU TO DO SO.
 */

namespace Contoso.CommerceRuntime.Services
{
  using System;
  using System.Collections.Generic;
  using System.Linq;
  using System.Threading.Tasks;
  using Microsoft.Dynamics.Commerce.Runtime;
  using Microsoft.Dynamics.Commerce.Runtime.Messages;
  using Microsoft.Dynamics.Commerce.Runtime.DataModel;
  using Contoso.CommerceRuntime.Messages;
  using Microsoft.Dynamics.Commerce.Runtime.Services.Messages;
  using Microsoft.SemanticKernel.ChatCompletion;
  using OpenAI.Assistants;
  using Microsoft.Dynamics.Commerce.Runtime.DataServices.Messages;


  /// <summary>
  /// A service that handles AI agent requests related to adaptive card template.
  /// This service implements the IRequestHandlerAsync interface to process requests asynchronously.
  /// </summary>
  public class AIAgentService : IRequestHandlerAsync
  {
    private const string AIMODELNAME = "AIModelName";
    private const string AIENDPOINT = "AIEndpoint";
    private const string AIAPPLICATIONKEY = "AIApplicationKey";
    private const string AIDEPLOYMENTNAME = "AIDeploymentName";
    private const string AIAPIVERSION = "AIApiVersion";

    /// <summary>
    /// Gets the collection of supported request types by this handler.
    /// </summary>
    public IEnumerable<Type> SupportedRequestTypes
    {
      get
      {
        return new[]
        {
                    typeof(GetChatRequest)
                };
      }
    }

    /// <summary>
    /// Entry point to service.
    /// </summary>
    /// <param name="request">The request to execute.</param>
    /// <returns>Result of executing request, or null object for void operations.</returns>
    public Task<Response> Execute(Request request)
    {
      ThrowIf.Null(request, nameof(request));

      switch (request)
      {
        case GetChatRequest getChatRequest:
          return this.GetChatResponse(request as GetChatRequest);
        default:
          throw new NotSupportedException($"Request '{request.GetType()}' is not supported.");
      }
    }

    private async Task<Response> GetChatResponse(GetChatRequest request)
    {
      ThrowIf.Null(request, "request");
      GetChatResponse response = new GetChatResponse();

      GetUserDefinedSecretStringValueServiceRequest keyVaultRequest = new GetUserDefinedSecretStringValueServiceRequest(AIMODELNAME);
      GetUserDefinedSecretStringValueServiceResponse keyVaultResponse = await request.RequestContext.ExecuteAsync<GetUserDefinedSecretStringValueServiceResponse>(keyVaultRequest).ConfigureAwait(false);
      string aiModelName = keyVaultResponse.SecretStringValue;

      keyVaultRequest = new GetUserDefinedSecretStringValueServiceRequest(AIENDPOINT);
      keyVaultResponse = await request.RequestContext.ExecuteAsync<GetUserDefinedSecretStringValueServiceResponse>(keyVaultRequest).ConfigureAwait(false);
      string aiEndPoint = keyVaultResponse.SecretStringValue;

      keyVaultRequest = new GetUserDefinedSecretStringValueServiceRequest(AIAPPLICATIONKEY);
      keyVaultResponse = await request.RequestContext.ExecuteAsync<GetUserDefinedSecretStringValueServiceResponse>(keyVaultRequest).ConfigureAwait(false);
      string aiAppKey = keyVaultResponse.SecretStringValue;

      keyVaultRequest = new GetUserDefinedSecretStringValueServiceRequest(AIDEPLOYMENTNAME);
      keyVaultResponse = await request.RequestContext.ExecuteAsync<GetUserDefinedSecretStringValueServiceResponse>(keyVaultRequest).ConfigureAwait(false);
      string aiDeploymentName = keyVaultResponse.SecretStringValue;

      keyVaultRequest = new GetUserDefinedSecretStringValueServiceRequest(AIAPIVERSION);
      keyVaultResponse = await request.RequestContext.ExecuteAsync<GetUserDefinedSecretStringValueServiceResponse>(keyVaultRequest).ConfigureAwait(false);
      string aiApiVersion = keyVaultResponse.SecretStringValue;

      if (!AIClientKernel.Instance.IsInitialized)
      {
        AIClientKernel.Instance.Initialize(aiModelName, aiEndPoint, aiAppKey, aiDeploymentName, aiApiVersion);
      }

      var aiResponseGenerator = new AIResponseGenerator(AIClientKernel.Instance);

      var messages = new[]
      {
              new AIMessage(
                  AuthorRole.System,
                  @"You are a retail store assistant designed to provide helpful and engaging responses to user queries.
                  You can read data and other provided data to assist users in a friendly and efficient manner.
                  Your responses should be clear, concise, and tailored to the user's needs.
                  The response should be in valid markdown format.
                  Respond only in valid Markdown format — no explanations or plain text.
                  Use bullet points (`-`) or numbered lists (`1.`, `2.`) for lists when appropriate.
                  Use proper line breaks and spacing for readability.
                  Correct obvious typos and formatting errors in the input.
                  Format currency with dollar sign `$` or appropriate symbol.
                  Do not include any extra commentary or non-markdown content.
                  Your responses should be informative, friendly, and tailored to the user's needs.
                  Use natural language and maintain a conversational tone.
                  Focus on providing clear and concise information, while also being engaging and personable.
                  If you don't know the answer to a question, it's okay to say so, 
                  but try to provide a helpful alternative or suggest where the user might find more information."
              ),
          };

      if (!String.IsNullOrEmpty(request.CartId))
      {
        var cartSearchCriteria = new CartSearchCriteria(request.CartId);
        var getCartServiceRequest = new GetCartServiceRequest(cartSearchCriteria, QueryResultSettings.SingleRecord);
        var cartResponse = await request.RequestContext.ExecuteAsync<GetCartServiceResponse>(getCartServiceRequest).ConfigureAwait(false);
        var cart = cartResponse.Carts.SingleOrDefault();
        if (cart != null && cart.Id != String.Empty)
        {
          messages = messages.Append(new AIMessage(AuthorRole.System, $"Here is cart data to be used for the template: {System.Text.Json.JsonSerializer.Serialize(cart)}")).ToArray();
        }
      }

      if (!String.IsNullOrEmpty(request.Data))
      {
        messages = messages.Append(new AIMessage(AuthorRole.System, $"Here is some data to be used for the template: {request.Data}")).ToArray();
      }

      if (!string.IsNullOrEmpty(request.UserPrompt))
      {
        messages = messages.Append(new AIMessage(AuthorRole.User, request.UserPrompt)).ToArray();
      }

      try
      {
        response.ChatResponse = await aiResponseGenerator.GenerateResponseAsync(new System.Collections.Generic.List<AIMessage>(messages)).ConfigureAwait(false);
      }
      catch (Exception ex)
      {
        throw new InvalidOperationException("Error generating chat response: " + ex.Message);
      }
      return response;
    }
  }
}