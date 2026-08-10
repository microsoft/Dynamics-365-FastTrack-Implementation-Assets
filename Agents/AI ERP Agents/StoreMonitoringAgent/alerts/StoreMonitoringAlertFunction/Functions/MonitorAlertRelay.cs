using System.Text.Json;
using Azure.Identity;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Logging;
using StoreMonitoringAlertFunction.Models;
using StoreMonitoringAlertFunction.Services;

namespace StoreMonitoringAlertFunction.Functions;

public sealed class MonitorAlertRelay(
    AgentFlowClient flowClient,
    ILogger<MonitorAlertRelay> logger)
{
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web)
    {
        PropertyNameCaseInsensitive = true
    };

    [Function("MonitorAlertRelay")]
    public async Task<IActionResult> Run(
        [HttpTrigger(AuthorizationLevel.Function, "post", Route = "monitor-alert")] HttpRequest request,
        CancellationToken cancellationToken)
    {
        var correlationId = request.HttpContext.TraceIdentifier;

        using var reader = new StreamReader(request.Body);
        var requestBody = await reader.ReadToEndAsync(cancellationToken);

        if (string.IsNullOrWhiteSpace(requestBody))
        {
            return new BadRequestObjectResult(new { error = "The alert request body is required." });
        }

        JsonElement rawAlert;
        AzureMonitorCommonAlert? alert;

        try
        {
            rawAlert = JsonSerializer.Deserialize<JsonElement>(requestBody, JsonOptions);
            alert = JsonSerializer.Deserialize<AzureMonitorCommonAlert>(requestBody, JsonOptions);
        }
        catch (JsonException ex)
        {
            logger.LogWarning(ex, "Rejected Azure Monitor alert because the request body was not valid JSON.");
            return new BadRequestObjectResult(new { error = "The alert request body must be valid JSON." });
        }

        if (!IsAzureMonitorCommonAlert(rawAlert))
        {
            logger.LogInformation("Received alert payload without the Azure Monitor common alert schema markers. The payload will still be relayed.");
        }

        AgentFlowResult flowResult;

        try
        {
            flowResult = await flowClient.SendAlertAsync(requestBody, cancellationToken);
        }
        catch (AuthenticationFailedException ex)
        {
            logger.LogError(
                ex,
                "Failed to acquire a Microsoft Entra token for the Agent Flow call. CorrelationId: {CorrelationId}",
                correlationId);

            return new ObjectResult(new
            {
                status = "Agent Flow authentication failed.",
                correlationId
            })
            {
                StatusCode = StatusCodes.Status502BadGateway
            };
        }
        catch (OperationCanceledException ex)
        {
            if (cancellationToken.IsCancellationRequested)
            {
                logger.LogWarning(ex, "The alert relay request was canceled while acquiring a Microsoft Entra token or calling the Agent Flow.");
            }
            else
            {
                logger.LogError(ex, "Agent Flow call timed out or token acquisition was canceled before completion.");
            }

            return new ObjectResult(new
            {
                status = "Agent Flow call timed out or token acquisition was canceled before completion.",
                requestCanceled = cancellationToken.IsCancellationRequested
            })
            {
                StatusCode = StatusCodes.Status504GatewayTimeout
            };
        }

        if (!flowResult.IsSuccessStatusCode)
        {
            logger.LogError(
                "Agent Flow call failed with status {StatusCode}. CorrelationId: {CorrelationId}",
                flowResult.StatusCode,
                correlationId);

            return new ObjectResult(new
            {
                status = "Agent Flow call failed.",
                statusCode = (int)flowResult.StatusCode,
                correlationId
            })
            {
                StatusCode = StatusCodes.Status502BadGateway
            };
        }

        logger.LogInformation(
            "Relayed Azure Monitor alert {AlertId} from rule {AlertRule} with custom alert type {AlertType} to Agent Flow.",
            alert?.Data?.Essentials?.AlertId,
            alert?.Data?.Essentials?.AlertRule,
            alert?.Data?.CustomProperties?.AlertType);

        return new AcceptedResult((string?)null, new
        {
            status = "Alert relayed to Agent Flow.",
            flowStatusCode = (int)flowResult.StatusCode,
            alertId = alert?.Data?.Essentials?.AlertId,
            alertRule = alert?.Data?.Essentials?.AlertRule,
            alertType = alert?.Data?.CustomProperties?.AlertType
        });
    }

    private static bool IsAzureMonitorCommonAlert(JsonElement root)
    {
        return root.ValueKind == JsonValueKind.Object
            && root.TryGetProperty("data", out var data)
            && data.ValueKind == JsonValueKind.Object
            && data.TryGetProperty("essentials", out _);
    }
}