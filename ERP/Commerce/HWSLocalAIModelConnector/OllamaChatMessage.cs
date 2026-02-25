/**
 * SAMPLE CODE NOTICE
 * 
 * THIS SAMPLE CODE IS MADE AVAILABLE AS IS.  MICROSOFT MAKES NO WARRANTIES, WHETHER EXPRESS OR IMPLIED,
 * OF FITNESS FOR A PARTICULAR PURPOSE, OF ACCURACY OR COMPLETENESS OF RESPONSES, OF RESULTS, OR CONDITIONS OF MERCHANTABILITY.
 * THE ENTIRE RISK OF THE USE OR THE RESULTS FROM THE USE OF THIS SAMPLE CODE REMAINS WITH THE USER.
 * NO TECHNICAL SUPPORT IS PROVIDED.  YOU MAY NOT DISTRIBUTE THIS CODE UNLESS YOU HAVE A LICENSE AGREEMENT WITH MICROSOFT THAT ALLOWS YOU TO DO SO.
 */

using System.Text.Json.Serialization;

namespace Contoso
{
    namespace Commerce.HardwareStation
    {
        /// <summary>
        /// Represents a chat message for the Ollama AI model.
        /// </summary>
        public class OllamaChatMessage
        {
            [JsonPropertyName("role")]
            public string Role { get; set; }
            [JsonPropertyName("content")]
            public string Content { get; set; }
        }
    }
}