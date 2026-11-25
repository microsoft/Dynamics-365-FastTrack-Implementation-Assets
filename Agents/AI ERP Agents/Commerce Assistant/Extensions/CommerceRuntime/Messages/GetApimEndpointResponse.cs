/**
 * SAMPLE CODE NOTICE
 *
 * THIS SAMPLE CODE IS MADE AVAILABLE AS IS.  MICROSOFT MAKES NO WARRANTIES, WHETHER EXPRESS OR IMPLIED,
 * OF FITNESS FOR A PARTICULAR PURPOSE, OF ACCURACY OR COMPLETENESS OF RESPONSES, OF RESULTS, OR CONDITIONS OF MERCHANTABILITY.
 * THE ENTIRE RISK OF THE USE OR THE RESULTS FROM THE USE OF THIS SAMPLE CODE REMAINS WITH THE USER.
 * NO TECHNICAL SUPPORT IS PROVIDED.  YOU MAY NOT DISTRIBUTE THIS CODE UNLESS YOU HAVE A LICENSE AGREEMENT WITH MICROSOFT THAT ALLOWS YOU TO DO SO.
 */

namespace Contoso.CommerceRuntime.Messages
{
    using System.Runtime.Serialization;
    using Microsoft.Dynamics.Commerce.Runtime.Messages;

    /// <summary>
    /// Contains the configured APIM endpoint.
    /// </summary>
    [DataContract]
    public sealed class GetApimEndpointResponse : Response
    {
        /// <summary>
        /// Initializes a new instance of the <see cref="GetApimEndpointResponse"/> class.
        /// </summary>
        /// <param name="apimEndpoint">The configured APIM endpoint.</param>
        public GetApimEndpointResponse(string apimEndpoint)
        {
            this.ApimEndpoint = apimEndpoint;
        }

        /// <summary>
        /// Gets the configured APIM endpoint.
        /// </summary>
        [DataMember]
        public string ApimEndpoint { get; private set; }
    }
}
