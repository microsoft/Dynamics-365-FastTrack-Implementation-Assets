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
using Microsoft.OData.Client;

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

        private static void ReportODataError(DataServiceQueryException ex)
        {
            //Client level Exception message
            Console.WriteLine(ex.Message);

            //The InnerException of DataServiceQueryException contains DataServiceClientException
            DataServiceClientException dataServiceClientException = ex.InnerException as DataServiceClientException;            

            // You can get ODataErrorException from dataServiceClientException.InnerException
            // This object holds Exception as thrown from the service
            // ODataErrorException contains odataErrorException.Message contains a message string that conforms to dotnet
            // Exception.Message standards
            var odataErrorException = dataServiceClientException.InnerException as Microsoft.OData.ODataErrorException;
            if (odataErrorException != null)
            {
                Console.WriteLine(odataErrorException.Message);
            }
            
            Console.WriteLine(dataServiceClientException.Message);
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
            Console.WriteLine("Listing top 10 customer groups with Id '20' in all companies...");
            var custGroupsQuery = context.CustomerGroups.AddQueryOption("$filter","CustomerGroupId eq '20'").AddQueryOption("$top", "10").IncludeCount();            
            try
            {
                var custGroupsResponse = custGroupsQuery.Execute() as QueryOperationResponse<CustomerGroup>; //Use this query form if you need response metadata
                Console.WriteLine("HTTP status = {0}", custGroupsResponse.StatusCode);
                if (custGroupsResponse.StatusCode == 429) //Handle throttling
                {                    
                    if (!custGroupsResponse.Headers.TryGetValue("Retry-After", out string retryAfterValue) 
                        || !System.Int32.TryParse(retryAfterValue, out int retryAfterSeconds))
                    {
                        retryAfterSeconds = 30;                        
                    }
                    
                    Console.WriteLine("Request throttled, retrying after {0} seconds...", retryAfterSeconds);
                    System.Threading.Thread.Sleep(TimeSpan.FromSeconds(retryAfterSeconds));
                    custGroupsResponse = custGroupsQuery.Execute() as QueryOperationResponse<CustomerGroup>;
                    Console.WriteLine("HTTP status = {0}", custGroupsResponse.StatusCode);
                    if (custGroupsResponse.StatusCode == 429) //Still throttled, give up
                    {
                        throw new ApplicationException("Throttling retry still throttled, giving up.");
                    }
                }
                var custGroupsList = custGroupsResponse.ToList(); //You can only enumerate the response once
                Console.WriteLine("Retrieved {0} of {1} records", custGroupsList.Count(), custGroupsResponse.Count);
                foreach (var group in custGroupsList)
                {
                    Console.WriteLine("{0} {1} {2}", group.dataAreaId, group.CustomerGroupId, group.Description);
                }
            }
            catch (DataServiceQueryException ex)
            {
                ReportODataError(ex);
            }

            //Read customer groups with Linq syntax
            Console.WriteLine("Reading customer groups with Id '50' (Linq)...");
            try
            {
                var custGroups = context.CustomerGroups.Where(x => x.CustomerGroupId == "50");

                CustomerGroup custGroup = new CustomerGroup();
                int num = 0;
                foreach (var group in custGroups)
                {
                    num++;
                    Console.WriteLine("{0} {1}", group.dataAreaId, group.CustomerGroupId);
                    if (num == 1)
                    {
                        custGroup = group; //Keep the first one
                    }
                }
                //Other ways to query specific record
                //var custGroup = context.CustomerGroups.Where(x => x.dataAreaId == "ussi" && x.CustomerGroupId == "10").First(); //Exception if none found
                //var custGroup = context.CustomerGroups.Where(x => x.dataAreaId == "ussi" && x.CustomerGroupId == "10").Single(); //Exception if more than one
                //var custGroup = context.CustomerGroups.ByKey(new Dictionary<string, object>() { { "dataAreaId", "ussi" }, { "CustomerGroupId", "10" } }).GetValue();
                Console.WriteLine("The first group was {0}", JsonSerializer.Serialize(custGroup));
            }
            catch (DataServiceQueryException ex)
            {
                ReportODataError(ex);
            }

            //Create a customer group
            Console.WriteLine("Creating customer group...");
            context.AddToCustomerGroups(new CustomerGroup
            {
                dataAreaId = "ussi",
                CustomerGroupId = "99",
                Description = "Console app test",
                PaymentTermId = "Net30"
            });
            try
            {
                DataServiceResponse responses = context.SaveChanges(); //No way to add a cross-company query option, so use BuildingRequest event if needed
                foreach (var response in responses) //non-empty response body if HTTP response isn't 204 (No Content)
                {
                    Console.WriteLine("HTTP status = {0}", response.StatusCode); //We expect a 201
                    var changeResponse = (ChangeOperationResponse)response;
                    var entityDescriptor = (EntityDescriptor)changeResponse.Descriptor;
                    var custGroupCreated = (CustomerGroup)entityDescriptor.Entity;
                    Console.WriteLine(JsonSerializer.Serialize(custGroupCreated));
                }
                
            }
            catch (DataServiceQueryException ex)
            {
                ReportODataError(ex);
            }

            
            //Read and update the new customer group
            Console.WriteLine("Reading the new customer group...");
            try
            {                
                var custGroup = context.CustomerGroups.Where(x => x.dataAreaId == "ussi" && x.CustomerGroupId == "99").First();
                Console.WriteLine(JsonSerializer.Serialize(custGroup)); //Should be the same as the response Json after creation

                Console.WriteLine("Updating Customer group...");
                custGroup.Description = "Console app test updated";
                context.UpdateObject(custGroup);
                DataServiceResponse dsr = context.SaveChanges();
                var changeResponse = (ChangeOperationResponse)dsr.First();
                Console.WriteLine("HTTP status = {0}", changeResponse.StatusCode); //We expect a 204
                var entityDescriptor = (EntityDescriptor)changeResponse.Descriptor;
                var custGroupUpdated = (CustomerGroup)entityDescriptor.Entity; //The response body is empty, so this is inferred, not actually sent back to us
                Console.WriteLine(JsonSerializer.Serialize(custGroupUpdated)); 
            }
            catch (DataServiceQueryException ex)
            {
                ReportODataError(ex);
            }

            //Read the customer group again, then delete it
            Console.WriteLine("Re-reading Customer group...");
            try
            {
                var custGroupUpdated = context.CustomerGroups.Where(x => x.dataAreaId == "ussi" && x.CustomerGroupId == "99").First();
                Console.WriteLine(JsonSerializer.Serialize(custGroupUpdated)); //Should be identical to the previously inferred Json
                
                Console.WriteLine("Deleting Customer group...");
                context.DeleteObject(custGroupUpdated);
                DataServiceResponse dsr = context.SaveChanges();
                Console.WriteLine("HTTP status = {0}", dsr.First().StatusCode); //We expect a 204
            }
            catch (DataServiceQueryException ex)
            {
                ReportODataError(ex);
            }

            //Make sure the customer group is gone
            Console.WriteLine("Testing that Customer group has been deleted...");
            try
            {
                var custGroupsAfterDelete = context.CustomerGroups.Where(x => x.dataAreaId == "ussi" && x.CustomerGroupId == "99");
                Console.WriteLine("Records found = {0}", custGroupsAfterDelete.Count());
            }
            catch (DataServiceQueryException ex)
            {
                ReportODataError(ex);
            }
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
