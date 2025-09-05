// This example solution requires  NuGet packages System.Text.Json, Microsoft.Identity.Client,
// Microsoft.Extensions.Configuration, Microsoft.Extensions.Configuration.Binder, Microsoft.Extensions.Configuration.Json

using Microsoft.Extensions.Configuration;
using Microsoft.Identity.Client;
using System;
using System.Diagnostics.Metrics;
using System.Linq;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using System.Threading.Tasks;
using System.Web;




namespace ODataCoreConsoleApp
{
    class Program
    {
        private const string Endpoint = "/api/services/SysMessageServices/SysMessageService/SendMessage";
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

        private static void ReportError(Exception ex)
        {
            while (ex != null)
            {
                Console.WriteLine(ex.Message);
                ex = ex.InnerException;
            }

        }


        private static async Task MainAsync()
        {
            string? orderPrefix = "IMP";
            int initialOrderNumber = 1;
            int numberOfOrders = 2;

            //Get user input for order details
            Console.WriteLine("Please provide the number of orders to generate (default=2, limit 2000)...");
            string? input = Console.ReadLine();
            if (!string.IsNullOrEmpty(input))
            {
                numberOfOrders = int.Parse(input);
            }
            numberOfOrders = numberOfOrders > 0 ? numberOfOrders : 2;
            numberOfOrders = numberOfOrders > 2000 ? 2000 : numberOfOrders;

            Console.WriteLine("Please provide the OrederPrefix (default IMP)...");
            orderPrefix = Console.ReadLine();
            orderPrefix = string.IsNullOrEmpty(orderPrefix) ? "IMP" : orderPrefix;

            Console.WriteLine("Please provide the initial order number (default=1)...");
            input = Console.ReadLine();
            if (!string.IsNullOrEmpty(input))
            {
                initialOrderNumber = int.Parse(input);
            }
            initialOrderNumber = initialOrderNumber > 0 ? initialOrderNumber : 1;
            try
            {
                //Authenticate with Entra ID
                Console.WriteLine("Authenticating with EntraId...");
                AuthenticationConfig config = AuthenticationConfig.ReadFromJsonFile("appsettings.json");
                string bearerToken = await GetAuthenticationHeader(config);
                bearerToken = bearerToken.Split(' ')[1];


                string fullUrl = $"{config.BaseUrl.TrimEnd('/')}{Endpoint}";
                Console.WriteLine(fullUrl);

                //Prepare oreders and send them to the Message Procesor endpoint
                for (int i = 0; i < numberOfOrders; i++)
                {
                    string nextOrderNumber = orderPrefix + (initialOrderNumber + i).ToString("D4");
                    Console.Write($"Sending order {nextOrderNumber}...");

                    var jsonBody = @"
                                {
                                    ""_companyId"": ""USMF"",
                                    ""_messageQueue"": ""SalesOrderQuickQueue"",
                                    ""_messageType"": ""SalesOrderQuickMessage"",
                                    ""_messageContent"": ""{\""CustomerAccount\"": \""US-001\"", \""SalesOrderNumber\"": \""" + nextOrderNumber + @"\"", \""SalesOrderLines\"": [{\""ItemNumber\"": \""D0001\"", \""Qty\"": 23},{\""ItemNumber\"": \""D0003\"", \""Qty\"": 17}]}""
                                }";


                    using var httpClient = new HttpClient();
                    httpClient.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", bearerToken);

                    var content = new StringContent(jsonBody, Encoding.UTF8, "application/json");

                    var response = await httpClient.PostAsync(fullUrl, content);
                    string responseContent = await response.Content.ReadAsStringAsync();

                    Console.WriteLine($"Status Code: {response.StatusCode}");
                    if (!String.IsNullOrEmpty(responseContent))
                    {
                        Console.WriteLine("Response:");
                        Console.WriteLine(responseContent);
                    }
                }
            }
            catch (Exception ex)
            {
                ReportError(ex);
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
