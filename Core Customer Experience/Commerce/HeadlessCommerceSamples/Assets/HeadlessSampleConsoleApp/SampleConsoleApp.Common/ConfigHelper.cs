/**
 * SAMPLE CODE NOTICE
 * 
 * THIS SAMPLE CODE IS MADE AVAILABLE AS IS.  MICROSOFT MAKES NO WARRANTIES, WHETHER EXPRESS OR IMPLIED,
 * OF FITNESS FOR A PARTICULAR PURPOSE, OF ACCURACY OR COMPLETENESS OF RESPONSES, OF RESULTS, OR CONDITIONS OF MERCHANTABILITY.
 * THE ENTIRE RISK OF THE USE OR THE RESULTS FROM THE USE OF THIS SAMPLE CODE REMAINS WITH THE USER.
 * NO TECHNICAL SUPPORT IS PROVIDED.  YOU MAY NOT DISTRIBUTE THIS CODE UNLESS YOU HAVE A LICENSE AGREEMENT WITH MICROSOFT THAT ALLOWS YOU TO DO SO.
 */
using Azure.Identity;
using Azure.Security.KeyVault.Secrets;
using Microsoft.Dynamics.Commerce.RetailProxy;
using Microsoft.Extensions.Configuration;

namespace SampleConsoleApp.Common
{
    public class ConfigHelper
    {
        public static ManagerFactory InitFactory()
        {
            try
            {
                var configuration = new ConfigurationBuilder()
               .SetBasePath(Directory.GetCurrentDirectory())
               .AddJsonFile("appsettings.json", optional: false, reloadOnChange: true)
               .Build();

                // Get configuration values
                string commerceApiEndpoint = configuration["CommerceApiEndpoint"];
                string vaultUri = configuration["AzureKeyVault:VaultUri"];
                string appIdentifier = configuration["AzureKeyVault:AppIdentifier"];
                string clientId = configuration["AzureAd:ClientId"];
                string authority = configuration["AzureAd:Authority"];
                string tenantId = configuration["AzureAd:TenantId"];
                string audience = configuration["AzureAd:Audience"];
                string keyVaultTenantId = configuration["AzureKeyVault:KeyVaultTenantId"];

                // Validate configuration values
                if (string.IsNullOrEmpty(commerceApiEndpoint) || string.IsNullOrEmpty(vaultUri) || string.IsNullOrEmpty(appIdentifier) ||
                    string.IsNullOrEmpty(clientId) || string.IsNullOrEmpty(authority) || string.IsNullOrEmpty(tenantId) || string.IsNullOrEmpty(audience) ||
                    string.IsNullOrEmpty(keyVaultTenantId))
                {
                    throw new ArgumentException("One or more configuration values are missing or invalid.");
                }

                // Use InteractiveBrowserCredential for authentication
                var credential = new InteractiveBrowserCredential(new InteractiveBrowserCredentialOptions
                {
                    TenantId = keyVaultTenantId
                });

                var cs = new SecretClient(new Uri(vaultUri), credential).GetSecret(appIdentifier).Value.Value;
                var context = RetailServerContext.Create(new Uri(commerceApiEndpoint), "", AuthenticationHelper.GetAuthenticationResult(clientId, authority, cs, tenantId, audience).Result);
                return ManagerFactory.Create(context);
            }
            catch (Exception ex)
            {
                Console.WriteLine($"Error initializing ManagerFactory: {ex.Message}");
                throw;
            }
        }
    }
}
