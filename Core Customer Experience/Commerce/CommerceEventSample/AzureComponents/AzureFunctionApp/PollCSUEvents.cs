using Azure.Messaging.ServiceBus;
using Microsoft.Azure.Cosmos;
using Microsoft.Azure.WebJobs;
using Microsoft.Extensions.Logging;
using System.Collections.Generic;
using System.Net.Http.Headers;
using System.Net.Http;
using System.Threading.Tasks;
using System;
using System.Text.Json;
using System.Net.Http.Json;

public static class PollCSUEvents
{
    private static readonly HttpClient httpClient = new HttpClient();
    private static readonly string cosmosDbEndpoint = Environment.GetEnvironmentVariable("CosmosDbEndpoint") ?? throw new ArgumentNullException("CosmosDbEndpoint");
    private static readonly string cosmosDbKey = Environment.GetEnvironmentVariable("CosmosDbKey") ?? throw new ArgumentNullException("CosmosDbKey");
    private static readonly string cosmosDbDatabaseId = Environment.GetEnvironmentVariable("CosmosDbDatabaseId") ?? throw new ArgumentNullException("CosmosDbDatabaseId");
    private static readonly string cosmosDbContainerId = Environment.GetEnvironmentVariable("CosmosDbContainerId") ?? throw new ArgumentNullException("CosmosDbContainerId");
    private static readonly CosmosClient cosmosClient = new CosmosClient(cosmosDbEndpoint, cosmosDbKey);
    private static readonly Container container = cosmosClient.GetContainer(cosmosDbDatabaseId, cosmosDbContainerId);

    private static readonly string csuUrl = Environment.GetEnvironmentVariable("CSUEndpoint") ?? throw new ArgumentNullException("CSUEndpoint");
    private static readonly string eventsControllerEndpoint = Environment.GetEnvironmentVariable("EventsControllerEndpoint") ?? throw new ArgumentNullException("EventsControllerEndpoint");
    private static readonly string eventTypes = Environment.GetEnvironmentVariable("EventTypes") ?? throw new ArgumentNullException("EventTypes");

    private static readonly string authority = Environment.GetEnvironmentVariable("AuthorityD365Commerce") ?? throw new ArgumentNullException("AuthorityD365Commerce");
    private static readonly string tenantId = Environment.GetEnvironmentVariable("TenantIdD365Commerce") ?? throw new ArgumentNullException("TenantIdD365Commerce");
    private static readonly string audience = Environment.GetEnvironmentVariable("AudienceD365Commerce") ?? throw new ArgumentNullException("AudienceD365Commerce");
    private static readonly string clientId = Environment.GetEnvironmentVariable("CommerceClientIdD365Commerce") ?? throw new ArgumentNullException("CommerceClientIdD365Commerce");
    private static readonly string clientSecret = Environment.GetEnvironmentVariable("CommerceClientSecretD365Commerce") ?? throw new ArgumentNullException("CommerceClientSecretD365Commerce");

    private static readonly string serviceBusConnectionString = Environment.GetEnvironmentVariable("ServiceBusConnectionString") ?? throw new ArgumentNullException("ServiceBusConnectionString");
    private static readonly string serviceBusTopicName = Environment.GetEnvironmentVariable("ServiceBusTopicName") ?? throw new ArgumentNullException("ServiceBusTopicName");
    private static readonly ServiceBusClient serviceBusClient = new ServiceBusClient(serviceBusConnectionString);
    private static readonly ServiceBusSender serviceBusSender = serviceBusClient.CreateSender(serviceBusTopicName);

    private const int maxRetries = 5; // Maximum number of retry attempts

    [FunctionName("PollCSUEvents")]
    public static async Task Run([TimerTrigger("*/20 * * * * *")] TimerInfo myTimer, ILogger log)
    {
        log.LogInformation("Function PollCSUEvents triggered at: {Timestamp}", DateTime.Now);

        try
        {
            log.LogInformation("Acquiring access token.");
            var accessToken = await GetAccessToken(log);
            log.LogInformation("Access token acquired successfully.");

            httpClient.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", accessToken);
            log.LogInformation("HTTP client configured with authorization header.");

            httpClient.DefaultRequestHeaders.Remove("OUN");
            var oun = Environment.GetEnvironmentVariable("OperatingUnitNumber") ?? throw new ArgumentNullException("OperatingUnitNumber");
            httpClient.DefaultRequestHeaders.Add("OUN", oun);
            log.LogInformation("OUN added to HTTP headers: {OUN}", oun);

            log.LogInformation("Retrieving last processed event from Cosmos DB.");
            var lastProcessedEvent = await GetLastProcessedEvent();
            log.LogInformation("Last processed event: {LastProcessedEvent}", lastProcessedEvent != null ? JsonSerializer.Serialize(lastProcessedEvent) : "No last processed event found.");

            string lastProcessedDateTime;
            if (lastProcessedEvent != null && lastProcessedEvent.ContainsKey("EventDateTime") && lastProcessedEvent["EventDateTime"] != null)
            {
                var eventDateTimeStr = lastProcessedEvent["EventDateTime"].ToString();
                DateTime eventDateTime = DateTime.Parse(eventDateTimeStr, null, System.Globalization.DateTimeStyles.RoundtripKind);
                lastProcessedDateTime = eventDateTime.ToString("o");
                log.LogInformation("Using last processed event date and time: {LastProcessedDateTime}", lastProcessedDateTime);
            }
            else
            {
                lastProcessedDateTime = DateTime.UtcNow.AddHours(-24).ToString("o");
                log.LogInformation("No last processed event found. Using default date and time: {LastProcessedDateTime}", lastProcessedDateTime);
            }

            var requestBody = new
            {
                commerceEventSearchCriteria = new
                {
                    EventType = eventTypes,
                    EventDateTimeFrom = lastProcessedDateTime,
                    EventDateTimeTo = DateTime.UtcNow.ToString("o")
                }
            };

            var requestUrl = $"{csuUrl}{eventsControllerEndpoint}";
            log.LogInformation("Fetching events from CSU with URL: {RequestUrl}", requestUrl);
            log.LogDebug("Request body: {RequestBody}", JsonSerializer.Serialize(requestBody));

            var events = await FetchEventsWithRetries(requestUrl, requestBody, log);

            if (events.ValueKind == JsonValueKind.Array && events.GetArrayLength() > 0)
            {
                foreach (var eventElement in events.EnumerateArray())
                {
                    // Convert JsonElement to Dictionary
                    var eventObj = JsonElementToDictionary(eventElement);

                    string eventId = eventObj["EventTransactionId"].ToString();
                    string eventChannelId = eventObj["EventChannelId"].ToString();

                    // Add required fields
                    eventObj["EventChannelId"] = eventChannelId;
                    eventObj["id"] = eventId;
                    eventObj["status"] = "new";
                    eventObj["retryCount"] = 0;

                    log.LogInformation("Checking if event {EventId} already exists in Cosmos DB.", eventId);

                    bool exists = false;
                    try
                    {
                        var existingEventResponse = await container.ReadItemAsync<Dictionary<string, object>>(eventId, new PartitionKey(eventChannelId));
                        exists = existingEventResponse.Resource != null;
                    }
                    catch (CosmosException cosmosEx1) when (cosmosEx1.StatusCode == System.Net.HttpStatusCode.NotFound)
                    {
                        // Event does not exist
                        exists = false;
                    }

                    if (exists)
                    {
                        log.LogInformation("Event {EventId} already exists in Cosmos DB. Skipping storage and processing.", eventId);
                    }
                    else
                    {
                        log.LogInformation("Event {EventId} does not exist in Cosmos DB. Storing event.", eventId);
                        try
                        {
                            await container.CreateItemAsync(eventObj, new PartitionKey(eventChannelId));
                            log.LogInformation("Event {EventId} stored successfully in Cosmos DB.", eventId);

                            // Process the event only if it is successfully stored
                            await ProcessEvent(eventObj, log);
                        }
                        catch (CosmosException cosmosEx2)
                        {
                            log.LogError(cosmosEx2, "Failed to store event {EventId} in Cosmos DB due to CosmosException.", eventId);
                        }
                        catch (Exception ex)
                        {
                            log.LogError(ex, "Failed to store event {EventId} in Cosmos DB due to general exception.", eventId);
                        }
                    }
                }
            }
            else
            {
                log.LogInformation("No events found in the response.");
            }
        }
        catch (Exception ex)
        {
            log.LogError(ex, "An error occurred during execution.");
            throw;
        }
    }

    private static async Task<JsonElement> FetchEventsWithRetries(string requestUrl, object requestBody, ILogger log)
    {
        int retryCount = 0;
        JsonElement emptyElement = default;
        while (retryCount < maxRetries)
        {
            try
            {
                log.LogDebug("Fetching events from CSU. Attempt: {RetryCount}", retryCount + 1);

                var response = await httpClient.PostAsJsonAsync(requestUrl, requestBody);
                string responseBody = await response.Content.ReadAsStringAsync();
                log.LogInformation("Received response from CSU with status code: {StatusCode}", response.StatusCode);
                log.LogDebug("Response body: {ResponseBody}", responseBody);

                if (response.IsSuccessStatusCode)
                {
                    log.LogInformation("Events fetched successfully from CSU.");
                    using var responseDoc = JsonDocument.Parse(responseBody);
                    var root = responseDoc.RootElement;

                    if (root.TryGetProperty("value", out JsonElement valueElement))
                    {
                        return valueElement;
                    }
                    else
                    {
                        log.LogInformation("No 'value' property in response.");
                        return emptyElement;
                    }
                }
                else
                {
                    log.LogError("Error fetching events from CSU: {StatusCode} {ReasonPhrase}", response.StatusCode, response.ReasonPhrase);
                    log.LogError("Response body: {ResponseBody}", responseBody);
                }
            }
            catch (Exception ex)
            {
                log.LogError(ex, "Exception occurred while fetching events from CSU.");
            }

            retryCount++;
            if (retryCount < maxRetries)
            {
                int delay = (int)Math.Pow(2, retryCount) * 1000;
                log.LogInformation("Retrying in {Delay} milliseconds. Attempt: {RetryCount}", delay, retryCount + 1);
                await Task.Delay(delay);
            }
        }

        log.LogError("Exceeded maximum retry attempts for fetching events from CSU.");
        return emptyElement;
    }

    private static async Task ProcessEvent(Dictionary<string, object> eventObj, ILogger log)
    {
        string eventId = eventObj["EventTransactionId"].ToString();
        string eventChannelId = eventObj["EventChannelId"].ToString();

        try
        {
            eventObj["status"] = "processing";
            await container.UpsertItemAsync(eventObj, new PartitionKey(eventChannelId));

            // Fetch order details
            var orderDetailsJson = await GetOrderDetails(eventId, log);
            using (var orderDoc = JsonDocument.Parse(orderDetailsJson))
            {
                var orderDetails = JsonElementToDictionary(orderDoc.RootElement);

                // Fetch customer details
                var customerId = orderDetails["CustomerId"].ToString();
                var customerDetailsJson = await GetCustomerDetails(customerId, log);
                using (var customerDoc = JsonDocument.Parse(customerDetailsJson))
                {
                    var customerDetails = JsonElementToDictionary(customerDoc.RootElement);

                    // Combine order details, customer details, and event fields
                    var combinedDetails = new Dictionary<string, object>
                    {
                        ["OrderDetails"] = orderDetails,
                        ["CustomerDetails"] = customerDetails,
                        ["EventDetails"] = eventObj
                    };

                    // Send combined details to Service Bus
                    await SendToServiceBus(JsonSerializer.Serialize(combinedDetails), eventId, log);

                    eventObj["status"] = "processed";
                    eventObj["retryCount"] = 0;  // Reset retry count on success
                    await container.UpsertItemAsync(eventObj, new PartitionKey(eventChannelId));
                }
            }
        }
        catch (Exception ex)
        {
            log.LogError(ex, "Error processing event {EventId}", eventId);

            int retryCount = Convert.ToInt32(eventObj["retryCount"]);
            if (retryCount < maxRetries)
            {
                retryCount++;
                eventObj["retryCount"] = retryCount;
                eventObj["status"] = "retrying";
                await container.UpsertItemAsync(eventObj, new PartitionKey(eventChannelId));

                // Calculate exponential backoff delay
                int delay = (int)Math.Pow(2, retryCount) * 1000;
                log.LogInformation("Retrying event {EventId} after {Delay} milliseconds. Retry count: {RetryCount}", eventId, delay, retryCount);
                await Task.Delay(delay);

                // Retry processing
                await ProcessEvent(eventObj, log);
            }
            else
            {
                eventObj["status"] = "failed";
                await container.UpsertItemAsync(eventObj, new PartitionKey(eventChannelId));
            }
        }
    }

    private static async Task<Dictionary<string, object>> GetLastProcessedEvent()
    {
        var sqlQueryText = "SELECT TOP 1 * FROM c WHERE c.status = 'processed' ORDER BY c._ts DESC";
        QueryDefinition queryDefinition = new QueryDefinition(sqlQueryText);
        FeedIterator<Dictionary<string, object>> queryResultSetIterator = container.GetItemQueryIterator<Dictionary<string, object>>(queryDefinition);

        if (queryResultSetIterator.HasMoreResults)
        {
            foreach (var item in await queryResultSetIterator.ReadNextAsync())
            {
                return item;
            }
        }
        return null;
    }

    private static async Task<string> GetOrderDetails(string transactionId, ILogger log)
    {
        var encodedTransactionId = Uri.EscapeDataString(transactionId);
        var orderDetailsUrl = $"{csuUrl}Commerce/SalesOrders/GetSalesOrderDetailsByTransactionId(transactionId=@p1,searchLocationValue=1)?@p1='{encodedTransactionId}'&api-version=7.3";

        log.LogInformation("Fetching order details from URL: {OrderDetailsUrl}", orderDetailsUrl);

        var requestMessage = new HttpRequestMessage(HttpMethod.Get, orderDetailsUrl);

        var response = await httpClient.SendAsync(requestMessage);
        if (!response.IsSuccessStatusCode)
        {
            string responseContent = await response.Content.ReadAsStringAsync();
            log.LogError("Error fetching order details: {StatusCode} {ReasonPhrase}", response.StatusCode, response.ReasonPhrase);
            log.LogError("Response body: {ResponseBody}", responseContent);
            throw new Exception($"Error fetching order details: {response.StatusCode} {response.ReasonPhrase}");
        }

        return await response.Content.ReadAsStringAsync();
    }

    private static async Task<string> GetCustomerDetails(string customerId, ILogger log)
    {
        var customerDetailsUrl = $"{csuUrl}/Commerce/Customers('{Uri.EscapeDataString(customerId)}')?api-version=7.3";

        log.LogInformation("Fetching customer details from URL: {CustomerDetailsUrl}", customerDetailsUrl);

        var requestMessage = new HttpRequestMessage(HttpMethod.Get, customerDetailsUrl);

        var response = await httpClient.SendAsync(requestMessage);
        if (!response.IsSuccessStatusCode)
        {
            string responseContent = await response.Content.ReadAsStringAsync();
            log.LogError("Error fetching customer details: {StatusCode} {ReasonPhrase}", response.StatusCode, response.ReasonPhrase);
            log.LogError("Response body: {ResponseBody}", responseContent);
            throw new Exception($"Error fetching customer details: {response.StatusCode} {response.ReasonPhrase}");
        }

        return await response.Content.ReadAsStringAsync();
    }

    private static async Task<string> GetAccessToken(ILogger log)
    {
        try
        {
            log.LogInformation("Acquiring access token from authority: {Authority}, tenant ID: {TenantId}", authority, tenantId);

            var client = new HttpClient();
            var request = new HttpRequestMessage(HttpMethod.Post, $"{authority}/{tenantId}/oauth2/v2.0/token");

            var postData = new List<KeyValuePair<string, string>>
            {
                new KeyValuePair<string, string>("client_id", clientId),
                new KeyValuePair<string, string>("client_secret", clientSecret),
                new KeyValuePair<string, string>("scope", $"{audience}/.default"),
                new KeyValuePair<string, string>("grant_type", "client_credentials")
            };
            request.Content = new FormUrlEncodedContent(postData);

            var response = await client.SendAsync(request);
            if (!response.IsSuccessStatusCode)
            {
                string responseContent = await response.Content.ReadAsStringAsync();
                log.LogError("Error acquiring access token: {StatusCode} {ReasonPhrase}", response.StatusCode, response.ReasonPhrase);
                log.LogError("Response body: {ResponseBody}", responseContent);
                throw new Exception($"Error acquiring access token: {response.StatusCode} {response.ReasonPhrase}");
            }

            var responseJson = await JsonSerializer.DeserializeAsync<Dictionary<string, object>>(await response.Content.ReadAsStreamAsync());
            var accessToken = responseJson["access_token"].ToString();
            log.LogInformation("Access token acquired successfully.");

            return accessToken;
        }
        catch (Exception ex)
        {
            log.LogError(ex, "Error acquiring access token.");
            throw;
        }
    }

    private static async Task SendToServiceBus(string message, string eventId, ILogger log)
    {
        try
        {
            var busMessage = new ServiceBusMessage(message) { MessageId = eventId };
            await serviceBusSender.SendMessageAsync(busMessage);
            log.LogInformation("Message with ID {EventId} sent to Service Bus successfully.", eventId);
        }
        catch (Exception ex)
        {
            log.LogError(ex, "Error sending message to Service Bus for event ID {EventId}.", eventId);
            throw;
        }
    }

    private static Dictionary<string, object> JsonElementToDictionary(JsonElement element)
    {
        // Recursively convert JsonElement to a Dictionary<string, object>
        Dictionary<string, object> dict = new Dictionary<string, object>();

        if (element.ValueKind == JsonValueKind.Object)
        {
            foreach (var prop in element.EnumerateObject())
            {
                dict[prop.Name] = JsonValueToObject(prop.Value);
            }
        }
        return dict;
    }

    private static object JsonValueToObject(JsonElement value)
    {
        switch (value.ValueKind)
        {
            case JsonValueKind.Object:
                {
                    var innerDict = new Dictionary<string, object>();
                    foreach (var prop in value.EnumerateObject())
                    {
                        innerDict[prop.Name] = JsonValueToObject(prop.Value);
                    }
                    return innerDict;
                }
            case JsonValueKind.Array:
                {
                    var list = new List<object>();
                    foreach (var item in value.EnumerateArray())
                    {
                        list.Add(JsonValueToObject(item));
                    }
                    return list;
                }
            case JsonValueKind.String:
                return value.GetString();
            case JsonValueKind.Number:
                if (value.TryGetInt64(out long l))
                    return l;
                if (value.TryGetDouble(out double d))
                    return d;
                return value.ToString(); // fallback as string
            case JsonValueKind.True:
                return true;
            case JsonValueKind.False:
                return false;
            case JsonValueKind.Null:
            default:
                return null;
        }
    }
}