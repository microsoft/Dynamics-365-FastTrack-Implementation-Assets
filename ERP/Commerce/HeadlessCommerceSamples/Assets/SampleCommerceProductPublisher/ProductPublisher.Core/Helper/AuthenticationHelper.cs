/**
 * SAMPLE CODE NOTICE
 * 
 * THIS SAMPLE CODE IS MADE AVAILABLE AS IS.  MICROSOFT MAKES NO WARRANTIES, WHETHER EXPRESS OR IMPLIED,
 * OF FITNESS FOR A PARTICULAR PURPOSE, OF ACCURACY OR COMPLETENESS OF RESPONSES, OF RESULTS, OR CONDITIONS OF MERCHANTABILITY.
 * THE ENTIRE RISK OF THE USE OR THE RESULTS FROM THE USE OF THIS SAMPLE CODE REMAINS WITH THE USER.
 * NO TECHNICAL SUPPORT IS PROVIDED.  YOU MAY NOT DISTRIBUTE THIS CODE UNLESS YOU HAVE A LICENSE AGREEMENT WITH MICROSOFT THAT ALLOWS YOU TO DO SO.
 */
using Microsoft.Identity.Client;

namespace ProductPublisher.Core.Helper
{
    internal class AuthenticationHelper
    {
        /// <summary>
        /// Get the access token to call CSU API
        /// </summary>
        /// <param name="clientId"></param>
        /// <param name="authority"></param>
        /// <param name="clientSecret"></param>
        /// <param name="tenantId"></param>
        /// <param name="audience"></param>
        /// <returns></returns>
        public static async Task<string> GetAuthenticationResult(string clientId, string authority, string clientSecret, string tenantId, string audience)
        {
            var confidentialClientApplication = ConfidentialClientApplicationBuilder.
                Create(clientId)
                .WithAuthority(authority + tenantId)
                .WithClientSecret(clientSecret);
            string[] scopes = new string[] { $"{audience}/.default" };
            AuthenticationResult authResult = await confidentialClientApplication
                .Build()
                .AcquireTokenForClient(scopes)
                .ExecuteAsync()
                .ConfigureAwait(false);

            return authResult.AccessToken;
        }
    }
}