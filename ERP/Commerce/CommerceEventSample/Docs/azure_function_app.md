# Azure Function App: PollCSUEvents

## Overview

The **PollCSUEvents** Azure Function App is a critical component of the Commerce Event Framework, responsible for polling and processing new events from Dynamics 365 Commerce. This function ensures that commerce events are reliably captured, enriched, and dispatched to downstream systems for further processing and customer interactions. Triggered at frequent intervals (e.g., every minute), it performs several essential tasks to maintain data integrity, performance, and scalability.

## Table of Contents

- [Overview](#overview)
- [Key Responsibilities](#key-responsibilities)
- [Code Walkthrough](#code-walkthrough)
- [Configuration](#configuration)
- [Deployment Instructions](#deployment-instructions)
- [Error Handling and Logging](#error-handling-and-logging)
- [Integration with Other Components](#integration-with-other-components)
- [Code Reference](#code-reference)


## Further Learning

For a deep dive and further learning on Azure Logic Apps, refer to the [Azure Logic Apps Documentation](https://learn.microsoft.com/en-us/azure/azure-functions/functions-overview?pivots=programming-language-csharp).

## Key Responsibilities

### 1. Authentication

The Azure Function App acquires an access token from the authority specified for Dynamics 365 Commerce using OAuth2 client credentials. This ensures secure communication with the Commerce Scale Unit (CSU) endpoint.

### 2. Polling Events

Triggered at frequent intervals (e.g., every minute), the function sends requests to the CSU to fetch new events. It retrieves the last processed event timestamp from **Azure Cosmos DB** to ensure only new events are processed, preventing duplication.

### 3. Data Enrichment

Each fetched event is enriched with additional customer and order details. The function retrieves relevant data from appropriate endpoints, combining it with the event data to provide a comprehensive context for downstream processing.

### 4. State Management

Events are stored in **Azure Cosmos DB**, which tracks properties such as `status` and `retryCount`. This ensures that each event's processing state is well-managed and auditable, facilitating monitoring and troubleshooting.

### 5. Error Handling and Retries

The function implements robust error handling using an exponential backoff strategy with a maximum retry count. If event retrieval or processing fails, the function updates the event's state in Cosmos DB and retries until the event is successfully processed or the retry limit is reached.

### 6. Sending to Azure Service Bus

Once enriched, events are sent to **Azure Service Bus** for reliable delivery to downstream consumers, such as Azure Logic Apps or other Azure Functions, ensuring seamless integration and processing.

## Code Walkthrough

### Run Method

The `Run` method is the entry point of the Azure Function, triggered by a Timer. It orchestrates the entire process of fetching, processing, and dispatching events.

```csharp
[FunctionName("PollCSUEvents")]
public static async Task Run([TimerTrigger("*/20 * * * * *")] TimerInfo myTimer, ILogger log)
{
    log.LogInformation("Function PollCSUEvents triggered at: {Timestamp}", DateTime.Now);

    try
    {
        // Authentication
        var accessToken = await GetAccessToken(log);
        httpClient.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", accessToken);

        // Add Operating Unit Number (OUN) to headers
        var oun = Environment.GetEnvironmentVariable("OperatingUnitNumber") ?? throw new ArgumentNullException("OperatingUnitNumber");
        httpClient.DefaultRequestHeaders.Remove("OUN");
        httpClient.DefaultRequestHeaders.Add("OUN", oun);

        // Retrieve last processed event
        var lastProcessedEvent = await GetLastProcessedEvent();
        string lastProcessedDateTime = lastProcessedEvent != null && lastProcessedEvent["EventDateTime"] != null
            ? lastProcessedEvent["EventDateTime"].ToObject<DateTime>().ToString("o")
            : DateTime.UtcNow.AddHours(-24).ToString("o");

        // Define search criteria
        var requestBody = new
        {
            commerceEventSearchCriteria = new
            {
                EventType = eventTypes,
                EventDateTimeFrom = lastProcessedDateTime,
                EventDateTimeTo = DateTime.UtcNow.ToString("o")
            }
        };

        // Fetch events from CSU
        var events = await FetchEventsWithRetries(requestUrl, requestBody, log);

        // Process each event
        if (events != null && events.Count > 0)
        {
            foreach (JToken eventToken in events)
            {
                var eventObj = (JObject)eventToken;
                string eventId = eventObj["EventTransactionId"].ToString();
                string eventChannelId = eventObj["EventChannelId"].ToString();

                eventObj["id"] = eventId;
                eventObj["status"] = "new";
                eventObj["retryCount"] = 0;

                try
                {
                    // Check if event already exists
                    var existingEvent = await container.ReadItemAsync<JObject>(eventId, new PartitionKey(eventChannelId));
                    log.LogInformation("Event {EventId} already exists in Cosmos DB. Skipping.", eventId);
                }
                catch (CosmosException cosmosEx1) when (cosmosEx1.StatusCode == System.Net.HttpStatusCode.NotFound)
                {
                    // Store new event and process
                    await container.CreateItemAsync(eventObj, new PartitionKey(eventChannelId));
                    await ProcessEvent(eventObj, log);
                }
            }
        }
        else
        {
            log.LogInformation("No new events found.");
        }
    }
    catch (Exception ex)
    {
        log.LogError(ex, "An error occurred during execution.");
        throw;
    }
}
```

#### FetchEventsWithRetries Method
This method attempts to fetch events from CSU with a defined retry strategy in case of failures.

```csharp
private static async Task<JArray> FetchEventsWithRetries(string requestUrl, object requestBody, ILogger log)
{
    int retryCount = 0;
    while (retryCount < maxRetries)
    {
        try
        {
            var response = await httpClient.PostAsJsonAsync(requestUrl, requestBody);
            string responseBody = await response.Content.ReadAsStringAsync();

            if (response.IsSuccessStatusCode)
            {
                JObject responseObject = JObject.Parse(responseBody);
                return (JArray)responseObject["value"];
            }
            else
            {
                log.LogError("Error fetching events: {StatusCode} {ReasonPhrase}", response.StatusCode, response.ReasonPhrase);
            }
        }
        catch (Exception ex)
        {
            log.LogError(ex, "Exception occurred while fetching events.");
        }

        retryCount++;
        if (retryCount < maxRetries)
        {
            int delay = (int)Math.Pow(2, retryCount) * 1000;
            log.LogInformation("Retrying in {Delay} milliseconds. Attempt: {RetryCount}", delay, retryCount + 1);
            await Task.Delay(delay);
        }
    }

    log.LogError("Exceeded maximum retry attempts for fetching events.");
    return null;
}
```

#### ProcessEvent Method

Handles the enrichment and dispatching of each event. It updates the event status in Cosmos DB based on processing outcomes.
```csharp
private static async Task ProcessEvent(JObject eventObj, ILogger log)
{
    string eventId = eventObj["EventTransactionId"].ToString();
    string eventChannelId = eventObj["EventChannelId"].ToString();

    try
    {
        eventObj["status"] = "processing";
        await container.UpsertItemAsync(eventObj, new PartitionKey(eventChannelId));

        // Enrich event with order and customer details
        var orderDetails = await GetOrderDetails(eventId, log);
        var customerId = JObject.Parse(orderDetails)["CustomerId"].ToString();
        var customerDetails = await GetCustomerDetails(customerId, log);

        var combinedDetails = new JObject
        {
            ["OrderDetails"] = JObject.Parse(orderDetails),
            ["CustomerDetails"] = JObject.Parse(customerDetails),
            ["EventDetails"] = eventObj
        };

        // Send enriched event to Service Bus
        await SendToServiceBus(combinedDetails.ToString(), eventId, log);

        eventObj["status"] = "processed";
        eventObj["retryCount"] = 0;
        await container.UpsertItemAsync(eventObj, new PartitionKey(eventChannelId));
    }
    catch (Exception ex)
    {
        log.LogError(ex, "Error processing event {EventId}", eventId);

        int retryCount = (int)eventObj["retryCount"];
        if (retryCount < maxRetries)
        {
            retryCount++;
            eventObj["retryCount"] = retryCount;
            eventObj["status"] = "retrying";
            await container.UpsertItemAsync(eventObj, new PartitionKey(eventChannelId));

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
```

### Helper Methods

Additional helper methods facilitate various tasks such as fetching order details, customer details, and acquiring access tokens.

```csharp
private static async Task<JObject> GetLastProcessedEvent()
{
    var sqlQueryText = "SELECT TOP 1 * FROM c WHERE c.status = 'processed' ORDER BY c._ts DESC";
    QueryDefinition queryDefinition = new QueryDefinition(sqlQueryText);
    FeedIterator<JObject> queryResultSetIterator = container.GetItemQueryIterator<JObject>(queryDefinition);

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

    var response = await httpClient.GetAsync(orderDetailsUrl);
    if (!response.IsSuccessStatusCode)
    {
        string responseContent = await response.Content.ReadAsStringAsync();
        log.LogError("Error fetching order details: {StatusCode} {ReasonPhrase}", response.StatusCode, response.ReasonPhrase);
        throw new Exception($"Error fetching order details: {response.StatusCode} {response.ReasonPhrase}");
    }

    return await response.Content.ReadAsStringAsync();
}

private static async Task<string> GetCustomerDetails(string customerId, ILogger log)
{
    var customerDetailsUrl = $"{csuUrl}/Commerce/Customers('{Uri.EscapeDataString(customerId)}')?api-version=7.3";

    var response = await httpClient.GetAsync(customerDetailsUrl);
    if (!response.IsSuccessStatusCode)
    {
        string responseContent = await response.Content.ReadAsStringAsync();
        log.LogError("Error fetching customer details: {StatusCode} {ReasonPhrase}", response.StatusCode, response.ReasonPhrase);
        throw new Exception($"Error fetching customer details: {response.StatusCode} {response.ReasonPhrase}");
    }

    return await response.Content.ReadAsStringAsync();
}

private static async Task<string> GetAccessToken(ILogger log)
{
    try
    {
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
            throw new Exception($"Error acquiring access token: {response.StatusCode} {response.ReasonPhrase}");
        }

        var responseJson = JObject.Parse(await response.Content.ReadAsStringAsync());
        var accessToken = responseJson["access_token"].ToString();

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
```

# Configuration

## Environment Variables

The Azure Function App relies on several environment variables for configuration. Ensure that these variables are correctly set in the Azure Function App settings.

| Variable Name                       | Description                                     | Example Value                                                                                     |
|-------------------------------------|-------------------------------------------------|---------------------------------------------------------------------------------------------------|
| `CosmosDbEndpoint`                  | Endpoint URL for Azure Cosmos DB               | `https://your-cosmos-db.documents.azure.com:443/`                                                 |
| `CosmosDbKey`                       | Primary key for Azure Cosmos DB                | `your-cosmos-db-key`                                                                              |
| `CosmosDbDatabaseId`                | Database ID in Azure Cosmos DB                 | `CommerceEventsDB`                                                                                |
| `CosmosDbContainerId`               | Container ID in Azure Cosmos DB                | `EventsContainer`                                                                                 |
| `CSUEndpoint`                       | Endpoint URL for Commerce Scale Unit (CSU)     | `https://your-csu-endpoint.com/api/`                                                              |
| `EventsControllerEndpoint`          | API endpoint for fetching events from CSU      | `Commerce/CommerceEventsController/Search?$top=250&$count=true&api-version=7.3`                                                                                        |
| `EventTypes`                        | Comma-separated list of event types to poll    | `AddCartLines,Checkout`                                                                           |
| `AuthorityD365Commerce`             | OAuth2 authority URL for Dynamics 365 Commerce | `https://login.microsoftonline.com/`                                                              |
| `TenantIdD365Commerce`              | Tenant ID for Dynamics 365 Commerce OAuth2 authentication | `your-tenant-id`                                                                      |
| `AudienceD365Commerce`              | Audience for OAuth2 token request              | `https://your-audience.com`                                                                       |
| `CommerceClientIdD365Commerce`      | Client ID for Dynamics 365 Commerce OAuth2 authentication | `your-client-id`                                                                      |
| `CommerceClientSecretD365Commerce`  | Client Secret for Dynamics 365 Commerce OAuth2 authentication | `your-client-secret`                                                                |
| `ServiceBusConnectionString`        | Connection string for Azure Service Bus        | `Endpoint=sb://your-servicebus.servicebus.windows.net/;SharedAccessKeyName=...`                    |
| `ServiceBusTopicName`               | Topic name in Azure Service Bus                | `CommerceEventsTopic`                                                                             |
| `OperatingUnitNumber`               | Operating Unit Number (OUN) to add to HTTP headers | `12345`                                                                                 |

## Azure Function Settings

1. Navigate to the Azure Portal and select your Azure Function App.
2. Go to **Configuration** under the **Settings** section.
3. Add the required environment variables as listed above.
4. Save the changes and restart the Function App to apply the new settings.

---

## Deployment Instructions

To deploy the Azure Logic App component, follow the [Azure Resource Manager (ARM) template deployment guide](https://learn.microsoft.com/en-us/azure/azure-resource-manager/templates/quickstart-create-templates-use-the-portal).

---

## Error Handling and Logging

The Azure Function App implements comprehensive error handling and logging mechanisms to ensure reliability and ease of troubleshooting.

### Logging

- Utilizes `ILogger` to log informational messages, debug details, and errors.

### Error Handling

- **Try-Catch Blocks**: Surrounds critical operations to catch and log exceptions.
- **Retry Strategy**: Implements exponential backoff with a maximum retry count to handle transient failures.
- **Status Updates**: Updates event status in Azure Cosmos DB to reflect processing states (`new`, `processing`, `processed`, `retrying`, `failed`).

---

## Integration with Other Components

- **Azure Cosmos DB**: Stores and tracks events with properties like `status` and `retryCount`.
- **Azure Service Bus**: Receives enriched events for downstream processing by services such as Azure Logic Apps.
- **Dynamics 365 Commerce**: Acts as the source of commerce events, providing data via CSU APIs.

### Dependencies

Before integrating the Azure Service Bus component, Start at the beginning of the documentation [README](../README.md)

Ensure that the [Commerce Events Framework](../Docs/commerce_event_framework.md) document is followed. This document outlines the necessary steps and configurations required for the Events Framework to function correctly with Azure Service Bus.

---

## Code Reference

You can view the implementation of the `PollCSUEvents` Azure Function [here](../AzureComponents/AzureFunctionApp/PollCSUEvents.cs)
