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
    using System.Threading.Tasks;
    using Microsoft.Dynamics.Commerce.Runtime.DataModel;
    using Microsoft.Dynamics.Commerce.Runtime.Hosting.Contracts;
    using Contoso.CommerceRuntime.Messages;

    /// <summary>
    /// An extension controller to handle requests
    /// </summary>
    public class AIAgentController : IController
    {
        [HttpGet]
        [Authorization(CommerceRoles.Application, CommerceRoles.Customer, CommerceRoles.Device, CommerceRoles.Employee)]
        public async Task<string> GetChatResponse(IEndpointContext context, string cartId, string userPrompt, string data)
        {
            var request = new GetChatRequest();
            request.CartId = cartId;
            request.UserPrompt = userPrompt;
            request.Data = data;
            var response = await context.ExecuteAsync<GetChatResponse>(request).ConfigureAwait(false);
            return response.ChatResponse;
        }
    }
}
