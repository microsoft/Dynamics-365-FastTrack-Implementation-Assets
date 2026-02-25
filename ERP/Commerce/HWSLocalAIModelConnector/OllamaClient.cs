/**
 * SAMPLE CODE NOTICE
 * 
 * THIS SAMPLE CODE IS MADE AVAILABLE AS IS.  MICROSOFT MAKES NO WARRANTIES, WHETHER EXPRESS OR IMPLIED,
 * OF FITNESS FOR A PARTICULAR PURPOSE, OF ACCURACY OR COMPLETENESS OF RESPONSES, OF RESULTS, OR CONDITIONS OF MERCHANTABILITY.
 * THE ENTIRE RISK OF THE USE OR THE RESULTS FROM THE USE OF THIS SAMPLE CODE REMAINS WITH THE USER.
 * NO TECHNICAL SUPPORT IS PROVIDED.  YOU MAY NOT DISTRIBUTE THIS CODE UNLESS YOU HAVE A LICENSE AGREEMENT WITH MICROSOFT THAT ALLOWS YOU TO DO SO.
 */


using System;
using System.Net.Http;
using System.Text;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using System.Text.Json.Serialization;
using System.Collections.Generic;

namespace Contoso
{
    namespace Commerce.HardwareStation
    {
        /// <summary>
        /// Ollama AI model client for chat sessions.
        /// </summary>
        public class OllamaClient
        {
            private static OllamaClient _instance;
            private static readonly object _lock = new object();

            public static OllamaClient Instance
            {
                get
                {
                    if (_instance == null)
                        throw new InvalidOperationException("OllamaClient is not initialized. Call Initialize() first.");
                    return _instance;
                }
            }

            public OllamaChatSession ChatSession { get; private set; }

            private OllamaClient(string model, IEnumerable<OllamaChatMessage> systemMessages)
            {
                ChatSession = new OllamaChatSession(model, systemMessages);
            }

            public static OllamaClient Initialize(string model, IEnumerable<OllamaChatMessage> systemMessages)
            {
                if (string.IsNullOrWhiteSpace(model))
                    throw new ArgumentNullException(nameof(model));
                if (systemMessages == null)
                    throw new ArgumentNullException(nameof(systemMessages));

                lock (_lock)
                {
                    if (_instance == null)
                    {
                        _instance = new OllamaClient(model, systemMessages);
                    }
                    return _instance;
                }
            }

            private static readonly Lazy<HttpClient> _lazyClient = new Lazy<HttpClient>(() =>
            {
                var handler = new HttpClientHandler();
                var client = new HttpClient(handler, disposeHandler: true);
                client.Timeout = TimeSpan.FromSeconds(60);
                return client;
            });

            public static HttpClient HttpClient => _lazyClient.Value;

            public static async Task<string> SendRawChatAsync(OllamaChatPrompt prompt, CancellationToken cancellationToken = default)
            {
                var json = JsonSerializer.Serialize(prompt);

                using (var content = new StringContent(json, Encoding.UTF8, "application/json"))
                {
                    using (var response = await HttpClient.PostAsync("http://localhost:11434/api/chat", content, cancellationToken).ConfigureAwait(false))
                    {
                        response.EnsureSuccessStatusCode();

                        // Ollama returns NDJSON streamed response, parse line by line and concat content
                        var stream = await response.Content.ReadAsStreamAsync().ConfigureAwait(false);
                        using (var reader = new System.IO.StreamReader(stream))
                        {
                            var resultBuilder = new StringBuilder();

                            while (!reader.EndOfStream)
                            {
                                var line = await reader.ReadLineAsync().ConfigureAwait(false);
                                if (string.IsNullOrWhiteSpace(line)) continue;

                                try
                                {
                                    var jsonDoc = JsonDocument.Parse(line);
                                    if (jsonDoc.RootElement.TryGetProperty("message", out var messageElement) &&
                                        messageElement.TryGetProperty("content", out var contentElement))
                                    {
                                        resultBuilder.Append(contentElement.GetString());
                                    }
                                }
                                catch (JsonException)
                                {
                                    // Skip malformed lines silently
                                }
                            }

                            return resultBuilder.ToString();
                        }
                    }
                }
            }
        }
    }
}
