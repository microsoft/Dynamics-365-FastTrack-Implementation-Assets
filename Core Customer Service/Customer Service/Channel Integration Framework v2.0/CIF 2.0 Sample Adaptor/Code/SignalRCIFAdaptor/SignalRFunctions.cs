

using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Azure.WebJobs;
using Microsoft.Azure.WebJobs.Extensions.Http;
using Microsoft.Azure.WebJobs.Extensions.SignalRService;
using Microsoft.Extensions.Logging;
using Microsoft.Identity.Client;
using Newtonsoft.Json;
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Security.Claims;
using System.Threading.Tasks;
using Microsoft.WindowsAzure.Storage.Table;
using Microsoft.WindowsAzure.Storage;
using System.Runtime.CompilerServices;
using Microsoft.Azure.SignalR.Management;
using Microsoft.Azure.WebJobs.Extensions.EventGrid;
using Azure.Messaging.EventGrid;
using SignalRCIFAdaptor;
using Newtonsoft.Json.Linq;
using Azure.Data.Tables;
using System.Collections.Concurrent;
using Microsoft.AspNetCore.Connections;
using System.Reflection.Metadata;
namespace CIFadaptorServer
{

    public static class MySignalRFunction
    {
        private static IServiceManager _serviceManager;   
        /// <summary>
        /// Returns the connection information about signalr using 
        /// </summary>
        /// <param name="req">Http Request</param>
        /// <param name="connectionInfo">Signal R connection Information like Signal R Hub Name, User Connecting to SignalR</param>
        /// <param name="log">Trace Log</param>
        /// <returns>Signal R conenction Oject</returns>

        [FunctionName("negotiate")]
        [Authorize]
        public static SignalRConnectionInfo Negotiate(
       [HttpTrigger(AuthorizationLevel.Anonymous, "get")] HttpRequest req,
       [SignalRConnectionInfo(HubName = "myhub", UserId = "{headers.x-ms-client-principal-id}")] SignalRConnectionInfo connectionInfo,
       ILogger log)
        {
            log.LogInformation("Negotiating SignalR connection.");          

            return connectionInfo;
        }

        [FunctionName("userclient")]
        [Authorize]
        public static async Task<IActionResult> StoreConnectionInfo(
    [HttpTrigger(AuthorizationLevel.Anonymous, "post")] HttpRequest req,
    ILogger log)
        {
            string requestBody = await new StreamReader(req.Body).ReadToEndAsync();
            dynamic data = JsonConvert.DeserializeObject(requestBody);
            string userId = data?.userId;
            string connectionId = data?.connectionId;
            int connctionStatus = data?.conenctionStatus;

            if (string.IsNullOrEmpty(userId) || string.IsNullOrEmpty(connectionId))
            {
                return new BadRequestObjectResult("Please provide a userId in the request body.");
            }

            try
            {
                // Retrieve storage connection string from App Settings
                string storageConnectionString = Environment.GetEnvironmentVariable("AzureWebJobsStorage");
                string hubName = Environment.GetEnvironmentVariable("HubName");
                string tableName = Environment.GetEnvironmentVariable("StorageUserTable");

                // Create CloudStorageAccount object
                CloudStorageAccount storageAccount = CloudStorageAccount.Parse(storageConnectionString);

                // Create the table client
                CloudTableClient tableClient = storageAccount.CreateCloudTableClient();

                // Create the table if it doesn't exist
                CloudTable table = tableClient.GetTableReference(tableName);
                await table.CreateIfNotExistsAsync();

                /// Check Conenction Already exists
                await StoreUserInformation(userId, connectionId, hubName, table, connctionStatus,log);               

                return new OkObjectResult("Client Registered");
            }
            catch (Exception ex) { return new BadRequestObjectResult(ex.Message+ "Client Not Registered."); }
        }

        /// <summary>
        /// Send a Notification to Specific User using Signal R Conenction ID. if already connected
        /// </summary>
        /// <param name="req">Http Request</param>
        /// <param name="signalRMessages">SignalR Message Object</param>
        /// <param name="connectionInfo">Conenction Information</param>
        /// <param name="log">Trace Log</param>
        /// <returns>Success/Failure to send Messae</returns>
        [FunctionName("SendMessageToUser")]
        [Authorize]
        public static async Task<IActionResult> Run(
       [HttpTrigger(AuthorizationLevel.Anonymous, "post", Route = null)] HttpRequest req,
       [SignalR(HubName = "myhub")] IAsyncCollector<SignalRMessage> signalRMessages,
       [SignalRConnectionInfo(HubName = "myhub")] SignalRConnectionInfo connectionInfo,
       ILogger log)
        {
            log.LogInformation("C# HTTP trigger function processed a request.");

            string requestBody = await new StreamReader(req.Body).ReadToEndAsync();
            dynamic data = JsonConvert.DeserializeObject(requestBody);
            string userId = data?.userId;
            string message = data?.message;

            string storageConnectionString = Environment.GetEnvironmentVariable("AzureWebJobsStorage");
            string hubName = Environment.GetEnvironmentVariable("HubName");
            string tableName = Environment.GetEnvironmentVariable("StorageUserTable");


            // Create CloudStorageAccount object
            CloudStorageAccount storageAccount = CloudStorageAccount.Parse(storageConnectionString);

            // Create the table client
            CloudTableClient tableClient = storageAccount.CreateCloudTableClient();

            // Create the table if it doesn't exist
            CloudTable table = tableClient.GetTableReference(tableName);

            /**
            TableOperation retrieveOperation = TableOperation.Retrieve<ConnectionEntity>(hubName, userId);
            TableResult retrievedResult = await table.ExecuteAsync(retrieveOperation);
            ConnectionEntity existingEntity = (ConnectionEntity)retrievedResult.Result;
            **/

            string filterCondition1 = TableQuery.GenerateFilterCondition("PartitionKey", QueryComparisons.Equal, userId);
            string filterCondition2 = TableQuery.GenerateFilterConditionForInt("ConnectionStatus", QueryComparisons.GreaterThanOrEqual, 1);

            // Combine the filter conditions using logical operators
            string combinedFilterCondition = TableQuery.CombineFilters(filterCondition1, TableOperators.And, filterCondition2);

            TableQuery<ConnectionEntity> query = new TableQuery<ConnectionEntity>().Where(combinedFilterCondition);
            log.LogInformation("Called the result");
            var results = await table.ExecuteQuerySegmentedAsync<ConnectionEntity>(query, null);
            log.LogInformation($"Results: {results.Results.Count}");
            var recentuserconnection = results.OrderByDescending(e => e.Timestamp).FirstOrDefault();

            if (recentuserconnection != null)
            {             

                await signalRMessages.AddAsync(
                    new SignalRMessage
                    {
                        ConnectionId = recentuserconnection.RowKey,
                        UserId = userId,
                        Target = "ReceiveNotification",
                        Arguments = new[] { message }
                    });
                return new OkObjectResult($"Sent message '{message}' to user '{userId}'");

            }
            else
            {
                return new BadRequestObjectResult("User Not Connected Currently");
            }

            
        }


        [FunctionName("SignalRConnectionEvents")]
        public static IActionResult SignalRConnectionEvents(
        [HttpTrigger(AuthorizationLevel.Anonymous, "post", Route = null)] HttpRequest req,
        ILogger log)
        {
            log.LogInformation("Received a request.");

            string requestBody = new StreamReader(req.Body).ReadToEnd();
            dynamic data = JObject.Parse(requestBody);

            if (data[0]?["data"]?["validationCode"] != null)
            {
                // This is a validation request
                string validationCode = data[0]["data"]["validationCode"];
                log.LogInformation($"Validation request received. Responding with validation code: {validationCode}");

                return new OkObjectResult(new { validationResponse = validationCode });
            }
            else
            {
                // This is an event
                log.LogInformation("Event received.");
                // Process the event data here

                return new OkResult();
            }
        }      

        /// <summary>
        /// Manages the user Connecting and stores in table storage, Events are trigged by signal R when Client Connects
        /// </summary>
        /// <param name="invocationContext">Invocation Context</param>
        /// <param name="log">Trace Log Object</param>
        /// <returns>Success/Failure status</returns>
        [FunctionName(nameof(OnClientConnected))]      
        public static async Task<IActionResult> OnClientConnected([SignalRTrigger("myhub", "connections", "connected",ConnectionStringSetting = "AzureSignalRConnectionString")] InvocationContext invocationContext, ILogger log)
        {
            // Handle connection event
            log.LogInformation($"Client connected: {invocationContext.ConnectionId}");

            string storageConnectionString = Environment.GetEnvironmentVariable("AzureWebJobsStorage");
            string hubName = Environment.GetEnvironmentVariable("HubName");
            string tableName = Environment.GetEnvironmentVariable("StorageUserTable"); 

            // Create CloudStorageAccount object
            CloudStorageAccount storageAccount = CloudStorageAccount.Parse(storageConnectionString);

            // Create the table client
            CloudTableClient tableClient = storageAccount.CreateCloudTableClient();

            // Create the table if it doesn't exist
            CloudTable table = tableClient.GetTableReference(tableName);
            await table.CreateIfNotExistsAsync();

            /// Check Conenction Already exists
            await StoreUserInformation(invocationContext.UserId, invocationContext.ConnectionId, hubName, table, 1,log);


            // You can send custom data to Event Grid or perform any other action here

             return new OkObjectResult("Client Conencted");
        }

        /// <summary>
        /// Signal R Event trigger when client Disconnects from browser or client application
        /// </summary>
        /// <param name="invocationContext">Invocation Object</param>
        /// <param name="log">trace log object</param>
        /// <returns>success/Failure status</returns>
        [FunctionName("OnClientDisconnect")]
        public static async Task<IActionResult> OnClientDisconnect(
            [SignalRTrigger("myhub", "connections", "disconnected")] InvocationContext invocationContext,
            ILogger log)
        {
            // Handle disconnection event
            log.LogInformation($"Client Disconnected: {invocationContext.ConnectionId}");

            string storageConnectionString = Environment.GetEnvironmentVariable("AzureWebJobsStorage");
            string hubName = Environment.GetEnvironmentVariable("HubName");
            string tableName = Environment.GetEnvironmentVariable("StorageUserTable");

            // Create CloudStorageAccount object
            CloudStorageAccount storageAccount = CloudStorageAccount.Parse(storageConnectionString);

            // Create the table client
            CloudTableClient tableClient = storageAccount.CreateCloudTableClient();
            CloudTable table = tableClient.GetTableReference(tableName);
            await table.CreateIfNotExistsAsync();

            // Check if the record exists before attempting to delete it


            /// Check Conenction Already exists
            await StoreUserInformation(invocationContext.UserId, invocationContext.ConnectionId, hubName, table, 0, log);

            log.LogInformation($"Client Connection: deleted");

            return new OkObjectResult("Client Disconnected");
        }
        /// <summary>
        /// Client wants to sent an acknowledgement of receive a notification and further can be processed to accomplish the business requirement
        /// </summary>
        /// <param name="invocationContext">Invocation Context object</param>
        /// <param name="content">Message sent from Client</param>
        /// <param name="log">Trace log object</param>
        [FunctionName(nameof(SendMessageAcknowlegement))]
        public static void SendMessageAcknowlegement(
        [SignalRTrigger("myhub", "messages","sendMessage","content")]
        InvocationContext invocationContext, string content, ILogger log)
        {        
            log.LogInformation("Connection {connectionId} sent a message. Message content: {content}", invocationContext.ConnectionId, content);
        }

        /// <summary>
        /// Stores the conenction information in Azure Table Storage
        /// </summary>
        /// <param name="userId">User Connects it</param>
        /// <param name="connectionId">Signal R Connection Id</param>
        /// <param name="hubName">Signal R HubName</param>
        /// <param name="table">Azure Table object</param>
        /// <param name="connectionStatus">Active/Inactive</param>
        /// <param name="log">Trace log objects</param>
        /// <returns></returns>
        private static async Task StoreUserInformation(string userId, string connectionId, string hubName, CloudTable table, int connectionStatus, ILogger log)
        {
            TableOperation retrieveOperation = TableOperation.Retrieve<ConnectionEntity>(userId, connectionId);            
            TableResult retrievedResult = await table.ExecuteAsync(retrieveOperation);
            ConnectionEntity existingEntity = (ConnectionEntity)retrievedResult.Result;
            log.LogInformation("Store Information");
            if (connectionStatus == 1)
            {
                if (existingEntity != null)
                {
                    log.LogInformation("userinformation" + existingEntity.PartitionKey +"connect" + connectionStatus);
                    // Update the existing entity                    
                    existingEntity.ConnectionStatus = connectionStatus;
                    existingEntity.HubName = hubName;
                    // Assuming HubName is a property of ConnectionEntity that you want to update
                    TableOperation updateOperation = TableOperation.Replace(existingEntity);
                    await table.ExecuteAsync(updateOperation);
                }
                else
                {
                    // Create the entity and insert it into the table
                    ConnectionEntity entity = new ConnectionEntity(userId, connectionId, hubName, connectionStatus);
                    TableOperation insertOperation = TableOperation.InsertOrReplace(entity);
                    await table.ExecuteAsync(insertOperation);

                }
            }
            else if(connectionStatus == 0)
            {
                log.LogInformation("clean up the record");
                if (existingEntity != null)
                {
                    log.LogInformation("userinformation" + existingEntity.PartitionKey +"Disconnect"+ connectionStatus);
                    var operation = TableOperation.Delete(existingEntity);
                    await table.ExecuteAsync(operation);
                }
            }

           
        }
    }

}
