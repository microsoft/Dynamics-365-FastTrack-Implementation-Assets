/**
 * SAMPLE CODE NOTICE
 *
 * THIS SAMPLE CODE IS MADE AVAILABLE AS IS.  MICROSOFT MAKES NO WARRANTIES, WHETHER EXPRESS OR IMPLIED,
 * OF FITNESS FOR A PARTICULAR PURPOSE, OF ACCURACY OR COMPLETENESS OF RESPONSES, OF RESULTS, OR CONDITIONS OF MERCHANTABILITY.
 * THE ENTIRE RISK OF THE USE OR THE RESULTS FROM THE USE OF THIS SAMPLE CODE REMAINS WITH THE USER.
 * NO TECHNICAL SUPPORT IS PROVIDED.  YOU MAY NOT DISTRIBUTE THIS CODE UNLESS YOU HAVE A LICENSE AGREEMENT WITH MICROSOFT THAT ALLOWS YOU TO DO SO.
 */

namespace Contoso.CommerceRuntime.RequestHandlers
{
    using System;
    using System.Threading.Tasks;
    using Contoso.CommerceRuntime.Messages;
    using Microsoft.Dynamics.Commerce.Runtime;
    using Microsoft.Dynamics.Commerce.Runtime.Messages;

    /// <summary>
    /// Reads the APIM endpoint from Commerce Runtime configuration.
    /// </summary>
    public sealed class GetApimEndpointRequestHandler : SingleAsyncRequestHandler<GetApimEndpointRequest>
    {
        private const string ApimEndpointSettingName = "ext.Contoso.ApimEndpoint";

        /// <summary>
        /// Returns the configured APIM endpoint.
        /// </summary>
        /// <param name="request">The APIM endpoint request.</param>
        /// <returns>The configured APIM endpoint.</returns>
        protected override Task<Response> Process(GetApimEndpointRequest request)
        {
            ThrowIf.Null(request, nameof(request));

            string settingValue;
            if (!request.RequestContext.Runtime.Configuration.Settings.TryGetValue(ApimEndpointSettingName, out settingValue)
                || string.IsNullOrWhiteSpace(settingValue))
            {
                throw new InvalidOperationException(
                    $"Commerce Runtime setting '{ApimEndpointSettingName}' is required.");
            }

            string apimEndpoint = settingValue.Trim().TrimEnd('/');
            Uri endpointUri;
            if (!Uri.TryCreate(apimEndpoint, UriKind.Absolute, out endpointUri)
                || !string.Equals(endpointUri.Scheme, Uri.UriSchemeHttps, StringComparison.OrdinalIgnoreCase)
                || !string.IsNullOrEmpty(endpointUri.UserInfo)
                || !string.IsNullOrEmpty(endpointUri.Query)
                || !string.IsNullOrEmpty(endpointUri.Fragment))
            {
                throw new InvalidOperationException(
                    $"Commerce Runtime setting '{ApimEndpointSettingName}' must be an HTTPS base URL without credentials, a query, or a fragment.");
            }

            return Task.FromResult<Response>(new GetApimEndpointResponse(apimEndpoint));
        }
    }
}
