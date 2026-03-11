using System.Threading.Tasks;
using Microsoft.Azure.Services.AppAuthentication;
using Microsoft.CommonDataModel.ObjectModel.Utilities.Network;

namespace CDMUtil.Manifest
{
    public class MSITokenProvider : TokenProvider
    {
        string Resource;
        string Tenant;
        public MSITokenProvider(string resource, string tenant)
        {
            Resource = resource;
            Tenant = tenant;
        }
        public string GetToken()
        {
            string token = this.GetAccessTokenAsync().Result;
            return $"Bearer {token}";
        }
        private async Task<string> GetAccessTokenAsync()
        {
            var tokenProvider = new AzureServiceTokenProvider();
            string token = await tokenProvider.GetAccessTokenAsync(Resource, Tenant);

            return token;
        }
    }
}
