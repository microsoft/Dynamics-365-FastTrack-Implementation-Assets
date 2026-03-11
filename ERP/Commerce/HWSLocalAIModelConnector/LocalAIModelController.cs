/**
 * SAMPLE CODE NOTICE
 * 
 * THIS SAMPLE CODE IS MADE AVAILABLE AS IS.  MICROSOFT MAKES NO WARRANTIES, WHETHER EXPRESS OR IMPLIED,
 * OF FITNESS FOR A PARTICULAR PURPOSE, OF ACCURACY OR COMPLETENESS OF RESPONSES, OF RESULTS, OR CONDITIONS OF MERCHANTABILITY.
 * THE ENTIRE RISK OF THE USE OR THE RESULTS FROM THE USE OF THIS SAMPLE CODE REMAINS WITH THE USER.
 * NO TECHNICAL SUPPORT IS PROVIDED.  YOU MAY NOT DISTRIBUTE THIS CODE UNLESS YOU HAVE A LICENSE AGREEMENT WITH MICROSOFT THAT ALLOWS YOU TO DO SO.
 */

namespace Contoso
{
    namespace Commerce.HardwareStation
    {
        using Microsoft.Dynamics.Commerce.HardwareStation;
        using Microsoft.Dynamics.Commerce.Runtime.Hosting.Contracts;
        using System;
        using System.Collections.Generic;
        using System.Text;
        using System.Threading.Tasks;

        /// <summary>
        ///  Local AI Model Controller.
        /// </summary>
        [RoutePrefix("LocalAIModel")]
        public class LocalAIModelController : IController
        {
            /// <summary>
            /// Sends a message to the local AI model.
            /// </summary>
            /// <param name="request">The Local AI model request.</param>
            [HttpPost]
            public async Task<string> SendMessage(LocalAIModelRequest request)
            {
                ThrowIf.Null(request, "LocalAIModelRequest");

                var systemMessages = new OllamaChatMessage[]
                {
                    new OllamaChatMessage
                    {
                        Role = "system",
                        Content = "You are a helpful assistant."
                    },
                };

                var userMessages = new OllamaChatMessage[]
                {
                    new OllamaChatMessage
                    {
                        Role = "user",
                        Content = request.Message
                    }
                };

                var client = OllamaClient.Initialize("phi3:mini", systemMessages);
                await client.ChatSession.SetupSystemAsync().ConfigureAwait(false);
                return await client.ChatSession.SendUserMessagesAsync(userMessages).ConfigureAwait(false);
            }
        }
    }
}
