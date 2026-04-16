using System.Runtime.CompilerServices;
using System.Text;
using System.Text.Json;
using TraceParserWeb.Services.Authentication;
using Microsoft.Agents.CopilotStudio.Client;
using Microsoft.Agents.Core.Models;
using Microsoft.Extensions.AI;

namespace TraceParserWeb.Services
{
    public class CopilotStudioIChatClient(CopilotClient copilotClient) : IChatClient
    {
        private CopilotClient _copilotClient = copilotClient
            ?? throw new ArgumentNullException(nameof(copilotClient));

        private bool _conversationStarted = false;
        private string? _activeScope;

        /// <summary>
        /// The display name of the currently active agent (shared across pages in the same circuit).
        /// </summary>
        public string? ActiveAgentName { get; set; }

        /// <summary>
        /// Replaces the underlying CopilotClient with a new one (for agent switching).
        /// Resets conversation state and sets the scope override for auth token acquisition.
        /// </summary>
        public void SwitchAgent(CopilotClient newClient, string newScope)
        {
            _copilotClient = newClient ?? throw new ArgumentNullException(nameof(newClient));
            _activeScope = newScope;
            _conversationStarted = false;
        }

        public ChatClientMetadata Metadata { get; } =
            new("CopilotStudio", new Uri("https://copilotstudio.microsoft.com"));

        /// <summary>
        /// Represents the parsed streaming metadata from ChannelData
        /// </summary>
        private class StreamingMetadata
        {
            public string? StreamType { get; set; }
            public string? StreamId { get; set; }
            public int StreamSequence { get; set; }
        }

        /// <summary>
        /// Resets the conversation state so the next message starts a fresh conversation.
        /// </summary>
        public async Task ResetConversationAsync(CancellationToken cancellationToken = default)
        {
            _conversationStarted = false;

            // Start a fresh conversation immediately so it's ready for the next message
            await EnsureConversationStartedAsync(cancellationToken);
        }

        public async Task<ChatResponse> GetResponseAsync(
            IEnumerable<ChatMessage> messages,
            ChatOptions? options = null,
            CancellationToken cancellationToken = default)
        {
            var responseMessages = new List<ChatMessage>();
            // Track the latest text  streaming yields accumulated text, so replace not append
            string lastText = string.Empty;

            await foreach (var update in GetStreamingResponseAsync(messages, options, cancellationToken))
            {
                foreach (var content in update.Contents)
                {
                    if (content is TextContent textContent && !string.IsNullOrEmpty(textContent.Text))
                    {
                        lastText = textContent.Text;
                    }
                }
            }

            var fullText = lastText.Trim();
            if (fullText.Length > 0)
            {
                responseMessages.Add(new ChatMessage(ChatRole.Assistant, fullText));
            }

            var lastUserMessage = messages.LastOrDefault()?.Text ?? string.Empty;

            return new ChatResponse(responseMessages)
            {
                Usage = new UsageDetails
                {
                    InputTokenCount = EstimateTokenCount(lastUserMessage),
                    OutputTokenCount = EstimateTokenCount(fullText)
                },
                CreatedAt = DateTimeOffset.UtcNow,
                ModelId = Metadata.DefaultModelId
            };
        }

        public async IAsyncEnumerable<ChatResponseUpdate> GetStreamingResponseAsync(
            IEnumerable<ChatMessage> messages,
            ChatOptions? options = null,
            [EnumeratorCancellation] CancellationToken cancellationToken = default)
        {
            var lastMessage = messages.LastOrDefault();
            if (lastMessage == null)
                throw new ArgumentException("At least one message is required", nameof(messages));

            await EnsureConversationStartedAsync(cancellationToken);

            var messageActivity = new Activity
            {
                Type = "message",
                Text = lastMessage.Text ?? string.Empty
            };

            await foreach (var update in StreamResponseAsync(messageActivity, cancellationToken))
            {
                yield return update;
            }
        }

        public async IAsyncEnumerable<ChatResponseUpdate> SendAdaptiveCardResponseAsync(
            Activity invokeActivity,
            [EnumeratorCancellation] CancellationToken cancellationToken = default)
        {
            // Ensure conversation is started (Safety check, though typically invoked after start)
            await EnsureConversationStartedAsync(cancellationToken);

            await foreach (var update in StreamResponseAsync(invokeActivity, cancellationToken))
            {
                yield return update;
            }
        }

        private async IAsyncEnumerable<ChatResponseUpdate> StreamResponseAsync(
            Activity activityToSend,
            [EnumeratorCancellation] CancellationToken cancellationToken)
        {
            var createdAt = DateTimeOffset.UtcNow;

            // Accumulate streaming text
            var accumulatedText = new StringBuilder();

            // Buffer tool call events by planIdentifier — yield only when complete
            var toolCallBuffer = new Dictionary<string, Dictionary<string, object?>>();

            // Set per-circuit scope override for auth token acquisition
            if (_activeScope is not null)
                AuthTokenHandler.ScopeOverride.Value = _activeScope;

            await foreach (var activity in _copilotClient.SendActivityAsync(activityToSend, cancellationToken))
            {
                // Parse streaming metadata from ChannelData
                var metadata = ParseStreamingMetadata(activity.ChannelData);

                if (activity.Type == "event" && !string.IsNullOrEmpty(activity.Name)
                    && activity.Value is not null)
                {
                    var json = JsonSerializer.Deserialize<JsonElement>(activity.Value.ToString()!);

                    // Extract all relevant fields from the event
                    var taskDialogId = TryGetJsonString(json, "taskDialogId");
                    var planIdentifier = TryGetJsonString(json, "planIdentifier");
                    var state = TryGetJsonString(json, "state");
                    var executionTime = TryGetJsonString(json, "executionTime");
                    var stepId = TryGetJsonString(json, "stepId");
                    var arguments = TryGetJsonRaw(json, "arguments");
                    var observation = TryGetJsonRaw(json, "observation");

                    if (taskDialogId != null && planIdentifier != null)
                    {
                        if (!toolCallBuffer.TryGetValue(planIdentifier, out var entry))
                        {
                            entry = new Dictionary<string, object?>();
                            toolCallBuffer[planIdentifier] = entry;
                        }

                        // Merge fields — only overwrite with non-null values
                        entry["taskDialogId"] = taskDialogId;
                        entry["eventName"] = activity.Name;
                        entry["planIdentifier"] = planIdentifier;
                        entry["timestamp"] = DateTimeOffset.UtcNow.ToString("o");
                        if (arguments != null) entry["arguments"] = arguments;
                        if (observation != null) entry["observation"] = observation;
                        if (state != null) entry["state"] = state;
                        if (executionTime != null) entry["executionTime"] = executionTime;
                        if (stepId != null) entry["stepId"] = stepId;

                        // Yield only when the tool call reaches "completed" state
                        if (state == "completed")
                        {
                            yield return new ChatResponseUpdate
                            {
                                CreatedAt = createdAt,
                                Role = ChatRole.Assistant,
                                Contents =
                                [
                                    new FunctionCallContent("ToolCallInfo", taskDialogId)
                                    {
                                        Arguments = new Dictionary<string, object?>(entry)
                                    }
                                ]
                            };
                            toolCallBuffer.Remove(planIdentifier);
                        }
                    }
                    continue;
                }

                // Case A: Adaptive Card Attachment
                if (activity.Type == "message" &&
                    activity.Attachments?.Count > 0 &&
                    activity.Attachments[0].ContentType == "application/vnd.microsoft.card.adaptive")
                {
                    var adaptiveCardJson = JsonSerializer.Serialize(activity.Attachments[0].Content);

                    yield return new ChatResponseUpdate
                    {
                        CreatedAt = createdAt,
                        Role = ChatRole.Assistant,
                        Contents =
                        [
                            new FunctionCallContent("RenderAdaptiveCardAsync", adaptiveCardJson)
                            {
                                Arguments = new Dictionary<string, object?>
                                {
                                    ["adaptiveCardJson"] = adaptiveCardJson,
                                    ["incomingActivityId"] = activity.Id
                                }
                            }
                        ]
                    };
                    continue;
                }

                // Case B: Text content
                if (!string.IsNullOrEmpty(activity.Text) &&
                    (activity.Type == "message" || activity.Type == "typing"))
                {
                    if (metadata?.StreamType == "informative")
                    {
                        // Informative messages are complete replacements, not deltas
                        yield return new ChatResponseUpdate
                        {
                            CreatedAt = createdAt,
                            Role = ChatRole.Assistant,
                            Contents =
                            [
                                new FunctionCallContent("InformativeMessage", activity.Text)
                                {
                                    Arguments = new Dictionary<string, object?>
                                    {
                                        ["message"] = activity.Text,
                                        ["sequence"] = metadata.StreamSequence,
                                        ["streamId"] = metadata.StreamId
                                    }
                                }
                            ]
                        };
                    }
                    else if (metadata?.StreamType == "streaming")
                    {
                        // Streaming chunk - accumulate and yield full text
                        accumulatedText.Append(activity.Text);

                        yield return new ChatResponseUpdate
                        {
                            CreatedAt = createdAt,
                            Contents = [new TextContent(accumulatedText.ToString())],
                            Role = ChatRole.Assistant
                        };
                    }
                    else if (metadata?.StreamType == "final" || metadata?.StreamType == null)
                    {
                        // Final message or no metadata - use as-is (complete message)
                        // Don't accumulate, just yield the full text
                        yield return new ChatResponseUpdate
                        {
                            CreatedAt = createdAt,
                            Contents = [new TextContent(activity.Text)],
                            Role = ChatRole.Assistant
                        };
                    }
                }
            }

            // Flush any buffered tool calls that never reached "completed"
            foreach (var entry in toolCallBuffer.Values)
            {
                if (entry.TryGetValue("taskDialogId", out var tidVal) && tidVal is string tid)
                {
                    yield return new ChatResponseUpdate
                    {
                        CreatedAt = createdAt,
                        Role = ChatRole.Assistant,
                        Contents =
                        [
                            new FunctionCallContent("ToolCallInfo", tid)
                            {
                                Arguments = new Dictionary<string, object?>(entry)
                            }
                        ]
                    };
                }
            }
        }

        /// <summary>
        /// Extracts a string property from a JsonElement, returns null if missing or not a string.
        /// </summary>
        private static string? TryGetJsonString(JsonElement json, string property)
        {
            return json.TryGetProperty(property, out var el) && el.ValueKind == JsonValueKind.String
                ? el.GetString()
                : null;
        }

        /// <summary>
        /// Extracts a property as raw JSON text (for objects/arrays), returns null if missing.
        /// </summary>
        private static string? TryGetJsonRaw(JsonElement json, string property)
        {
            return json.TryGetProperty(property, out var el)
                && el.ValueKind != JsonValueKind.Null
                && el.ValueKind != JsonValueKind.Undefined
                ? el.GetRawText()
                : null;
        }

        /// <summary>
        /// Parses the ChannelData to extract streaming metadata
        /// </summary>
        private static StreamingMetadata? ParseStreamingMetadata(object? channelData)
        {
            if (channelData == null) return null;

            try
            {
                JsonElement jsonElement;

                if (channelData is JsonElement je)
                {
                    jsonElement = je;
                }
                else
                {
                    // Try to serialize and deserialize to get JsonElement
                    var json = JsonSerializer.Serialize(channelData);
                    jsonElement = JsonSerializer.Deserialize<JsonElement>(json);
                }

                var metadata = new StreamingMetadata();

                if (jsonElement.TryGetProperty("streamType", out var streamTypeProp))
                {
                    metadata.StreamType = streamTypeProp.GetString();
                }

                if (jsonElement.TryGetProperty("streamId", out var streamIdProp))
                {
                    metadata.StreamId = streamIdProp.GetString();
                }

                if (jsonElement.TryGetProperty("streamSequence", out var streamSeqProp))
                {
                    metadata.StreamSequence = streamSeqProp.GetInt32();
                }

                return metadata;
            }
            catch
            {
                return null;
            }
        }

        private async Task EnsureConversationStartedAsync(CancellationToken cancellationToken)
        {
            if (_conversationStarted) return;

            // Set per-circuit scope override for auth token acquisition
            if (_activeScope is not null)
                AuthTokenHandler.ScopeOverride.Value = _activeScope;

            // Drain the start conversation activities
            await foreach (var _ in _copilotClient.StartConversationAsync(
                emitStartConversationEvent: true,
                cancellationToken))
            {
                // Deliberately empty
            }

            _conversationStarted = true;
        }

        public TService? GetService<TService>(object? key = null) where TService : class
        {
            return typeof(TService) == typeof(CopilotClient) ? _copilotClient as TService : null;
        }

        object? IChatClient.GetService(Type serviceType, object? key)
        {
            return serviceType == typeof(CopilotClient) ? _copilotClient : null;
        }

        private static int EstimateTokenCount(string text)
        {
            return string.IsNullOrEmpty(text) ? 0 : Math.Max(1, text.Length / 4);
        }

        public void Dispose()
        {
            // _copilotClient does not implement IDisposable
            GC.SuppressFinalize(this);
        }
    }
}
