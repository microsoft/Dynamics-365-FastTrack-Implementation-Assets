using System;
using System.Collections.Generic;
using System.Text;
using System.Threading.Tasks;
using Microsoft.Azure.Services.AppAuthentication;
using Microsoft.CommonDataModel.ObjectModel.Utilities.Network;

namespace CDMUtil.Manifest
{
    public class MSITokenProvider : TokenProvider
    {
        string Resource;
        public MSITokenProvider(string resource)
        {
            Resource = resource;
        }
        public string GetToken()
            {
                string token = this.GetAccessTokenAsync().Result;
                return $"Bearer {token}";
            }
            private async Task<string> GetAccessTokenAsync()
            {
                var tokenProvider = new AzureServiceTokenProvider();
                string token = await tokenProvider.GetAccessTokenAsync(Resource);

                return token;
            }
        }
}
