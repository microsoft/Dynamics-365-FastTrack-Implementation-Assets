/**
 * SAMPLE CODE NOTICE
 * 
 * THIS SAMPLE CODE IS MADE AVAILABLE AS IS.  MICROSOFT MAKES NO WARRANTIES, WHETHER EXPRESS OR IMPLIED,
 * OF FITNESS FOR A PARTICULAR PURPOSE, OF ACCURACY OR COMPLETENESS OF RESPONSES, OF RESULTS, OR CONDITIONS OF MERCHANTABILITY.
 * THE ENTIRE RISK OF THE USE OR THE RESULTS FROM THE USE OF THIS SAMPLE CODE REMAINS WITH THE USER.
 * NO TECHNICAL SUPPORT IS PROVIDED.  YOU MAY NOT DISTRIBUTE THIS CODE UNLESS YOU HAVE A LICENSE AGREEMENT WITH MICROSOFT THAT ALLOWS YOU TO DO SO.
 */

using System;
using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;

namespace Contoso
{
    namespace Commerce.HardwareStation
    {
        /// <summary>
        /// Represents a chat session with the Ollama AI model.
        /// </summary>
        public class OllamaChatSession
        {
            private readonly string _model;
            private readonly List<OllamaChatMessage> _systemMessages;
            private bool _systemSetupDone = false;
            private readonly Guid _sessionId;

            public OllamaChatSession(string model, IEnumerable<OllamaChatMessage> systemMessages)
            {
                _model = model ?? throw new ArgumentNullException(nameof(model));
                _systemMessages = new List<OllamaChatMessage>();
                _sessionId = Guid.NewGuid();

                if (systemMessages != null)
                {
                    foreach (var msg in systemMessages)
                    {
                        if (msg != null && !string.IsNullOrWhiteSpace(msg.Content))
                        {
                            _systemMessages.Add(new OllamaChatMessage() { Role = msg.Role, Content = msg.Content });
                        }
                    }
                }
            }

            // Sends system messages to set up the chat agent once
            public async Task<string> SetupSystemAsync(CancellationToken cancellationToken = default)
            {
                if (_systemSetupDone)
                    return string.Empty;

                if (_systemMessages.Count == 0)
                {
                    _systemSetupDone = true;
                    return string.Empty;
                }

                OllamaChatPrompt prompt = new OllamaChatPrompt()
                {
                    Model = _model,
                    Messages = _systemMessages.ToArray()
                };

                var response = await OllamaClient.SendRawChatAsync(prompt, cancellationToken).ConfigureAwait(false);

                _systemSetupDone = true;

                return response ?? string.Empty;
            }

            // Sends subsequent user messages, returns assistant reply
            public async Task<string> SendUserMessagesAsync(OllamaChatMessage[] userMessages, CancellationToken cancellationToken = default)
            {
                if (userMessages == null) throw new ArgumentNullException(nameof(userMessages));

                if (userMessages.Length == 0) throw new ArgumentException("No user messages provided.");

                OllamaChatPrompt prompt = new OllamaChatPrompt()
                {
                    Model = _model,
                    Messages = userMessages
                };

                var response = await OllamaClient.SendRawChatAsync(prompt, cancellationToken).ConfigureAwait(false);

                return response;
            }
        }
    }
}