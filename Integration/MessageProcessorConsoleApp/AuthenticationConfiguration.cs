/**
 * SAMPLE CODE NOTICE
 * 
 * THIS SAMPLE CODE IS MADE AVAILABLE AS IS.  MICROSOFT MAKES NO WARRANTIES, WHETHER EXPRESS OR IMPLIED,
 * OF FITNESS FOR A PARTICULAR PURPOSE, OF ACCURACY OR COMPLETENESS OF RESPONSES, OF RESULTS, OR CONDITIONS OF MERCHANTABILITY.
 * THE ENTIRE RISK OF THE USE OR THE RESULTS FROM THE USE OF THIS SAMPLE CODE REMAINS WITH THE USER.
 * NO TECHNICAL SUPPORT IS PROVIDED.  YOU MAY NOT DISTRIBUTE THIS CODE UNLESS YOU HAVE A LICENSE AGREEMENT WITH MICROSOFT THAT ALLOWS YOU TO DO SO.
 */
using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using Microsoft.Extensions.Configuration;

namespace MessageProcessorConsoleApp
{
   
    public class AuthenticationConfiguration
    {
        public string BaseUri { get; set; }
        public AzureKeyVaultConfig AzureKeyVault { get; set; }
        public AzureAdConfig AzureAd { get; set; }
        public string Instance { get; set; } = "https://login.microsoftonline.com/{0}";
        public string Authority
        {
            get
            {
                return String.Format(CultureInfo.InvariantCulture, Instance, AzureAd.TenantId);
            }
        }

        public static AuthenticationConfiguration ReadFromJsonFile(string path)
        {
            // build a config object, using the appsettings.json file as the default source
            var config = new ConfigurationBuilder()
                .SetBasePath(Directory.GetCurrentDirectory())
                .AddJsonFile(path, optional: false, reloadOnChange: true)
                .Build();
            // bind the config object to the AppSettings class
            var result = new AuthenticationConfiguration();
            config.Bind(result);
            // return the populated AppSettings object
            return result;
        }

    }

    public class AzureKeyVaultConfig
    {
        public string VaultUri { get; set; }
        public string AppIdentifier { get; set; }
        public string KeyVaultTenantId { get; set; }
    }

    public class AzureAdConfig
    {
        public string ClientId { get; set; }
        public string TenantId { get; set; }
        public string Audience { get; set; }
    }
}
