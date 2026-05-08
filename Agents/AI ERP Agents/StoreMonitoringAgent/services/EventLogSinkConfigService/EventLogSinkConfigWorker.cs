/**
 * SAMPLE CODE NOTICE
 * 
 * THIS SAMPLE CODE IS MADE AVAILABLE AS IS.  MICROSOFT MAKES NO WARRANTIES, WHETHER EXPRESS OR IMPLIED,
 * OF FITNESS FOR A PARTICULAR PURPOSE, OF ACCURACY OR COMPLETENESS OF RESPONSES, OF RESULTS, OR CONDITIONS OF MERCHANTABILITY.
 * THE ENTIRE RISK OF THE USE OR THE RESULTS FROM THE USE OF THIS SAMPLE CODE REMAINS WITH THE USER.
 * NO TECHNICAL SUPPORT IS PROVIDED.  YOU MAY NOT DISTRIBUTE THIS CODE UNLESS YOU HAVE A LICENSE AGREEMENT WITH MICROSOFT THAT ALLOWS YOU TO DO SO.
 */
using System.Text.Json;
using System.Text.Json.Nodes;

namespace EventLogSinkConfigService;

public class EventLogSinkConfigWorker : BackgroundService
{
    private readonly ILogger<EventLogSinkConfigWorker> _logger;
    private readonly IConfiguration _configuration;
    private readonly TimeSpan _collectionInterval;
    private readonly string _configFilePath;

    // Custom Event IDs for Windows Event Log
    private static readonly EventId ServiceStartedEvent = new(1000, "ServiceStarted");
    private static readonly EventId ServiceStoppedEvent = new(1001, "ServiceStopped");
    private static readonly EventId ValidationStartedEvent = new(2000, "ValidationStarted");
    private static readonly EventId ValidationCompletedEvent = new(2001, "ValidationCompleted");
    private static readonly EventId ConfigValidEvent = new(3000, "ConfigValid");
    private static readonly EventId ConfigInvalidEvent = new(3001, "ConfigInvalid");
    private static readonly EventId ConfigUpdatedEvent = new(3002, "ConfigUpdated");
    private static readonly EventId ConfigUpdateFailedEvent = new(3003, "ConfigUpdateFailed");
    private static readonly EventId FileNotFoundEvent = new(4000, "FileNotFound");
    private static readonly EventId FileReadErrorEvent = new(4001, "FileReadError");
    private static readonly EventId GeneralErrorEvent = new(4002, "GeneralError");

    private static readonly JsonNodeOptions NodeOptions = new()
    {
        PropertyNameCaseInsensitive = false
    };

    public EventLogSinkConfigWorker(ILogger<EventLogSinkConfigWorker> logger, IConfiguration configuration)
    {
        _logger = logger;
        _configuration = configuration;

        _configFilePath = _configuration.GetValue<string>("ConfigFilePath")
            ?? @"C:\Program Files\Microsoft Dynamics 365\10.0\Store Commerce\Microsoft\contentFiles\Pos\config.json";

        // Default: 1440 minutes = 24 hours (once per day)
        var intervalMinutes = _configuration.GetValue<int>("CollectionIntervalMinutes", 1440);
        _collectionInterval = TimeSpan.FromMinutes(intervalMinutes);
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        _logger.LogInformation(ServiceStartedEvent, "EventLogSinkConfig Service started at: {time}", DateTimeOffset.Now);

        // Run immediately on start
        await ValidateConfigAsync(stoppingToken);

        // Continue running at the specified interval
        using PeriodicTimer timer = new PeriodicTimer(_collectionInterval);

        try
        {
            while (await timer.WaitForNextTickAsync(stoppingToken))
            {
                await ValidateConfigAsync(stoppingToken);
            }
        }
        catch (OperationCanceledException)
        {
            _logger.LogInformation(ServiceStoppedEvent, "EventLogSinkConfig Service stopped.");
        }
    }

    private async Task ValidateConfigAsync(CancellationToken stoppingToken)
    {
        try
        {
            _logger.LogInformation(ValidationStartedEvent, "Starting config validation at: {time}", DateTimeOffset.Now);

            if (!File.Exists(_configFilePath))
            {
                _logger.LogWarning(FileNotFoundEvent, "Config file not found at: {path}", _configFilePath);
                return;
            }

            var fileText = await File.ReadAllTextAsync(_configFilePath, stoppingToken);

            var rootNode = JsonNode.Parse(fileText, NodeOptions);
            if (rootNode is not JsonObject rootObject)
            {
                _logger.LogError(FileReadErrorEvent, "Config file root is not a JSON object: {path}", _configFilePath);
                return;
            }

            await ValidateAndFixWebViewEventLogSinkAsync(fileText, rootObject, stoppingToken);

            _logger.LogInformation(ValidationCompletedEvent, "Config validation completed successfully at: {time}", DateTimeOffset.Now);
        }
        catch (JsonException jsonEx)
        {
            _logger.LogError(FileReadErrorEvent, jsonEx, "Failed to parse config file as JSON: {path}", _configFilePath);
        }
        catch (IOException ioEx)
        {
            _logger.LogError(FileReadErrorEvent, ioEx, "Failed to read config file: {path}", _configFilePath);
        }
        catch (UnauthorizedAccessException uaEx)
        {
            _logger.LogError(FileReadErrorEvent, uaEx, "Access denied reading config file: {path}", _configFilePath);
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            _logger.LogError(GeneralErrorEvent, ex, "Unexpected error during config validation");
        }
    }

    private async Task ValidateAndFixWebViewEventLogSinkAsync(string fileText, JsonObject root, CancellationToken stoppingToken)
    {
        const string expectedLevel = "Informational";

        // Navigate to Diagnostics.Sinks.WebViewEventLogSink (read-only check)
        if (root["Diagnostics"] is not JsonObject diagnosticsObject)
        {
            _logger.LogWarning(ConfigInvalidEvent,
                "Diagnostics section not found in config file: {path}", _configFilePath);
            return;
        }

        if (diagnosticsObject["Sinks"] is not JsonObject sinksObject)
        {
            _logger.LogWarning(ConfigInvalidEvent,
                "Diagnostics.Sinks section not found in config file: {path}", _configFilePath);
            return;
        }

        if (sinksObject["WebViewEventLogSink"] is not JsonObject sinkObject)
        {
            _logger.LogWarning(ConfigInvalidEvent,
                "Diagnostics.Sinks.WebViewEventLogSink section not found or invalid in config file: {path}", _configFilePath);
            return;
        }

        if (!sinkObject.ContainsKey("EventLevel"))
        {
            _logger.LogWarning(ConfigInvalidEvent,
                "EventLevel property not found in Diagnostics.Sinks.WebViewEventLogSink. Config file: {path}", _configFilePath);
            return;
        }

        var currentLevel = sinkObject["EventLevel"]?.GetValue<string>();

        if (string.Equals(currentLevel, expectedLevel, StringComparison.OrdinalIgnoreCase))
        {
            _logger.LogInformation(ConfigValidEvent,
                "Diagnostics.Sinks.WebViewEventLogSink.EventLevel is correctly set to '{level}'. Config file: {path}",
                expectedLevel, _configFilePath);
            return;
        }

        _logger.LogWarning(ConfigInvalidEvent,
            "Diagnostics.Sinks.WebViewEventLogSink.EventLevel is '{currentLevel}' instead of '{expectedLevel}'. Updating config file: {path}",
            currentLevel, expectedLevel, _configFilePath);

        await ReplaceEventLevelInFileAsync(fileText, currentLevel!, expectedLevel, stoppingToken);
    }

    private async Task ReplaceEventLevelInFileAsync(string fileText, string currentLevel, string newLevel, CancellationToken stoppingToken)
    {
        try
        {
            // Locate the value within Diagnostics > Sinks > WebViewEventLogSink using sequential search
            int diagIdx = fileText.IndexOf("\"Diagnostics\"", StringComparison.Ordinal);
            if (diagIdx < 0) return;

            int sinksIdx = fileText.IndexOf("\"Sinks\"", diagIdx, StringComparison.Ordinal);
            if (sinksIdx < 0) return;

            int sinkIdx = fileText.IndexOf("\"WebViewEventLogSink\"", sinksIdx, StringComparison.Ordinal);
            if (sinkIdx < 0) return;

            int eventLevelIdx = fileText.IndexOf("\"EventLevel\"", sinkIdx, StringComparison.Ordinal);
            if (eventLevelIdx < 0) return;

            // Find the value: locate the colon, then the quoted value after it
            int colonIdx = fileText.IndexOf(':', eventLevelIdx + "\"EventLevel\"".Length);
            if (colonIdx < 0) return;

            int valueStart = fileText.IndexOf('"', colonIdx + 1);
            if (valueStart < 0) return;

            int valueEnd = fileText.IndexOf('"', valueStart + 1);
            if (valueEnd < 0) return;

            // Splice only the value between the quotes, preserving everything else
            string result = string.Concat(
                fileText.AsSpan(0, valueStart + 1),
                newLevel,
                fileText.AsSpan(valueEnd));

            await File.WriteAllTextAsync(_configFilePath, result, stoppingToken);
            _logger.LogInformation(ConfigUpdatedEvent,
                "Config file updated successfully. Diagnostics.Sinks.WebViewEventLogSink.EventLevel set to '{level}'. File: {path}",
                newLevel, _configFilePath);
        }
        catch (UnauthorizedAccessException uaEx)
        {
            _logger.LogError(ConfigUpdateFailedEvent, uaEx,
                "Access denied writing config file: {path}", _configFilePath);
        }
        catch (IOException ioEx)
        {
            _logger.LogError(ConfigUpdateFailedEvent, ioEx,
                "Failed to write config file: {path}", _configFilePath);
        }
    }
}
