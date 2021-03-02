// This example solution requires OData Connected Service (https://github.com/odata/ODataConnectedService) 
// and NuGet packages System.Text.Json, Microsoft.Identity.Client, Microsoft.Extensions.Configuration, 
// Microsoft.Extensions.Configuration.Binder, Microsoft.Extensions.Configuration.Json
using System;
using System.Linq;
using System.Text.Json;
using System.Web;
using System.Threading.Tasks;
using Microsoft.Identity.Client;
using Microsoft.Dynamics.DataEntities;

namespace ODataCoreConsoleApp
{
    class Program
    {
        private static async Task<string> GetAuthenticationHeader(AuthenticationConfig config)
        {            
            IConfidentialClientApplication app = ConfidentialClientApplicationBuilder.Create(config.ClientId)
                    .WithClientSecret(config.ClientSecret)
                    .WithAuthority(new Uri(config.Authority))
                    .Build();
            string[] scopes = new string[] { $"{config.BaseUrl}/.default" };
            AuthenticationResult result = await app.AcquireTokenForClient(scopes)
                .ExecuteAsync();            
            return result.CreateAuthorizationHeader();
        }

        private static async Task MainAsync()
        {
            Console.WriteLine("Authenticating with AAD...");
            AuthenticationConfig config = AuthenticationConfig.ReadFromJsonFile("appsettings.json");
            string bearerToken = await GetAuthenticationHeader(config);
            
            var context = new Resources(new Uri($"{config.BaseUrl}/data/"));            

            //Make all the OData requests cross-company, otherwise you will only reference records in the default company
            context.BuildingRequest += (sender, eventArgs) =>
            {
                var uriBuilder = new UriBuilder(eventArgs.RequestUri);
                var paramValues = HttpUtility.ParseQueryString(uriBuilder.Query);
                if (paramValues.Get("cross-company") != null)
                {
                    //Console.WriteLine("Note: cross-company parameter already present - removing");
                    paramValues.Remove("cross-company");
                }
                paramValues.Add("cross-company", "true");
                uriBuilder.Query = paramValues.ToString();
                eventArgs.RequestUri = uriBuilder.Uri;
            };

            //Add authorization token. This should be requested from AAD programatically, expiry managed, etc.
            context.SendingRequest2 += (sender, eventArgs) =>
            {                
                eventArgs.RequestMessage.SetHeader("Authorization", bearerToken);
            };

            //Query some customer groups
            Console.WriteLine("Listing top 10 customer groups across companies...");
            var custGroupsQuery = context.CustomerGroups.AddQueryOption("$top", "10");
            //var custGroupsQuery = context.CustomerGroups.AddQueryOption("cross-company","true").AddQueryOption("$top", "10"); //You can add multiple query options like this
            var custGroups = custGroupsQuery.Execute();
            foreach (var group in custGroups)
            {
                Console.WriteLine("{0} {1} {2}", group.dataAreaId, group.CustomerGroupId, group.Description);
            }

            //Create a customer group
            Console.WriteLine("Creating Customer group...");
            context.AddToCustomerGroups(new CustomerGroup
            {
                dataAreaId = "ussi",
                CustomerGroupId = "99",
                Description = "Console app test"
            });
            context.SaveChanges();

            //Read the customer group
            Console.WriteLine("Reading Customer group...");
            var custGroup = context.CustomerGroups.Where(x => x.dataAreaId == "ussi" && x.CustomerGroupId == "99").First();

            //Other ways to query a specific record
            //var custGroup = context.CustomerGroups.ByKey(new Dictionary<string, object>() { { "dataAreaId", "ussi" }, { "CustomerGroupId", "99" } }).GetValue();
            //var custGroup = context.CustomerGroups.Where(x => x.dataAreaId == "ussi" && x.CustomerGroupId == "99").Single(); //Exception if there is more than one

            Console.WriteLine(JsonSerializer.Serialize(custGroup));

            //Update the customer group
            Console.WriteLine("Updating Customer group...");
            custGroup.Description = "Console app test updated";
            context.UpdateObject(custGroup);
            context.SaveChanges(); //No way to add a cross-company query option, so use BuildingRequest event if needed

            //Read the custmer group again
            Console.WriteLine("Re-reading Customer group...");
            var custGroupUpdated = context.CustomerGroups.Where(x => x.dataAreaId == "ussi" && x.CustomerGroupId == "99").First();
            Console.WriteLine(JsonSerializer.Serialize(custGroupUpdated));

            //Delete the customer group
            Console.WriteLine("Deleting Customer group...");
            context.DeleteObject(custGroupUpdated);
            context.SaveChanges();

            //Make sure the customer group is gone
            Console.WriteLine("Testing that Customer group has been deleted...");
            var custGroupAfterDelete = context.CustomerGroups.Where(x => x.dataAreaId == "ussi" && x.CustomerGroupId == "99");
            Console.WriteLine("Records found = {0}", custGroupAfterDelete.Count());

            Console.WriteLine("All done!");

        }

        public static int Main(string[] args)
        {            
            try
            {                
                MainAsync().Wait();
                return 0;
            }
            catch (Exception ex)
            {
                Console.Error.WriteLine(ex);
                return -1;
            }
        }
    }
    
}
