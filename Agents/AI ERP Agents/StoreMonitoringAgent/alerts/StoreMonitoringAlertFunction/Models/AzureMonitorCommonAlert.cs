using System.Text.Json;
using System.Text.Json.Serialization;

namespace StoreMonitoringAlertFunction.Models;

public sealed record AzureMonitorCommonAlert(
    [property: JsonPropertyName("schemaId")] string? SchemaId,
    [property: JsonPropertyName("data")] AzureMonitorAlertData? Data);

public sealed record AzureMonitorAlertData(
    [property: JsonPropertyName("essentials")] AzureMonitorAlertEssentials? Essentials,
    [property: JsonPropertyName("alertContext")] AzureMonitorAlertContext? AlertContext,
    [property: JsonPropertyName("customProperties")] StoreMonitoringAlertCustomProperties? CustomProperties);

public sealed record AzureMonitorAlertEssentials(
    [property: JsonPropertyName("alertId")] string? AlertId,
    [property: JsonPropertyName("alertRule")] string? AlertRule,
    [property: JsonPropertyName("severity")] string? Severity,
    [property: JsonPropertyName("signalType")] string? SignalType,
    [property: JsonPropertyName("monitorCondition")] string? MonitorCondition,
    [property: JsonPropertyName("monitoringService")] string? MonitoringService,
    [property: JsonPropertyName("targetResource")] string? TargetResource,
    [property: JsonPropertyName("targetResourceName")] string? TargetResourceName,
    [property: JsonPropertyName("targetResourceGroup")] string? TargetResourceGroup,
    [property: JsonPropertyName("targetResourceType")] string? TargetResourceType,
    [property: JsonPropertyName("configurationItems")] IReadOnlyList<string>? ConfigurationItems,
    [property: JsonPropertyName("firedDateTime")] DateTimeOffset? FiredDateTime,
    [property: JsonPropertyName("description")] string? Description);

public sealed record AzureMonitorAlertContext(
    [property: JsonPropertyName("condition")] AzureMonitorAlertCondition? Condition);

public sealed record AzureMonitorAlertCondition(
    [property: JsonPropertyName("allOf")] IReadOnlyList<AzureMonitorAlertConditionClause>? AllOf);

public sealed record AzureMonitorAlertConditionClause(
    [property: JsonPropertyName("dimensions")] IReadOnlyList<AzureMonitorAlertDimension>? Dimensions);

public sealed record AzureMonitorAlertDimension(
    [property: JsonPropertyName("name")] string? Name,
    [property: JsonPropertyName("value")] string? Value);

public sealed record StoreMonitoringAlertCustomProperties(
    [property: JsonPropertyName("alertType")] string? AlertType,
    [property: JsonPropertyName("offlineThresholdMinutes")] string? OfflineThresholdMinutes,
    [property: JsonPropertyName("performanceThresholdMs")] string? PerformanceThresholdMs,
    [property: JsonPropertyName("databaseSizeThresholdMB")] string? DatabaseSizeThresholdMB);