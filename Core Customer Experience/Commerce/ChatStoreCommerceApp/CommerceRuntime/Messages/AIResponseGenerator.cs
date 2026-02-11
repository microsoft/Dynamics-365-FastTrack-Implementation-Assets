/**
 * SAMPLE CODE NOTICE
 * 
 * THIS SAMPLE CODE IS MADE AVAILABLE AS IS.  MICROSOFT MAKES NO WARRANTIES, WHETHER EXPRESS OR IMPLIED,
 * OF FITNESS FOR A PARTICULAR PURPOSE, OF ACCURACY OR COMPLETENESS OF RESPONSES, OF RESULTS, OR CONDITIONS OF MERCHANTABILITY.
 * THE ENTIRE RISK OF THE USE OR THE RESULTS FROM THE USE OF THIS SAMPLE CODE REMAINS WITH THE USER.
 * NO TECHNICAL SUPPORT IS PROVIDED.  YOU MAY NOT DISTRIBUTE THIS CODE UNLESS YOU HAVE A LICENSE AGREEMENT WITH MICROSOFT THAT ALLOWS YOU TO DO SO.
 */
using System.Collections.Generic;
using System.Threading.Tasks;
using Contoso.CommerceRuntime.Messages;

namespace Contoso.CommerceRuntime.Services
{
    public class AIResponseGenerator
    {
        private readonly AIClientKernel _aiClient;

        public AIResponseGenerator(AIClientKernel aiClient)
        {
            _aiClient = aiClient;
        }

        public async Task<string> GenerateResponseAsync(List<AIMessage> messages)
        {
            // Combine all messages into a single prompt for simplicity
            var prompt = string.Join("\n", messages.ConvertAll(m => $"{m.Role}: {m.Content}"));
            return await _aiClient.SendMessageAsync(prompt).ConfigureAwait(false);
        }
    }
}