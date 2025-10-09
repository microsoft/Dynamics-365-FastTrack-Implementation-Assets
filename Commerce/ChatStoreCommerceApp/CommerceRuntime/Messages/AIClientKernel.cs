/**
 * SAMPLE CODE NOTICE
 * 
 * THIS SAMPLE CODE IS MADE AVAILABLE AS IS.  MICROSOFT MAKES NO WARRANTIES, WHETHER EXPRESS OR IMPLIED,
 * OF FITNESS FOR A PARTICULAR PURPOSE, OF ACCURACY OR COMPLETENESS OF RESPONSES, OF RESULTS, OR CONDITIONS OF MERCHANTABILITY.
 * THE ENTIRE RISK OF THE USE OR THE RESULTS FROM THE USE OF THIS SAMPLE CODE REMAINS WITH THE USER.
 * NO TECHNICAL SUPPORT IS PROVIDED.  YOU MAY NOT DISTRIBUTE THIS CODE UNLESS YOU HAVE A LICENSE AGREEMENT WITH MICROSOFT THAT ALLOWS YOU TO DO SO.
 */
using System;
using System.Threading.Tasks;
using Microsoft.SemanticKernel;
using Microsoft.SemanticKernel.ChatCompletion;

namespace Contoso.CommerceRuntime.Services
{
    public class AIClientKernel 
    {
        private static readonly Lazy<AIClientKernel> _instance = new Lazy<AIClientKernel>(() => new AIClientKernel());
        private Kernel _kernel;
        private string _modelName;
        private bool _initialized;
       

        /// <summary>
        /// Singleton instance of the AIClientKernel.
        /// /// This ensures that only one instance of the kernel is created and used throughout the application.
        /// /// </summary>
        private AIClientKernel() { }

        public static AIClientKernel Instance => _instance.Value;

        /// <summary>
        /// Initializes the AIClientKernel with the specified model name, endpoint, and API key.
        /// /// This method should be called before any AI operations are performed.
        /// /// </summary>
        /// /// <param name="modelName">The name of the AI model to use.</param>
        /// /// <param name="endpoint">The endpoint URL for the AI service.</param>
        /// /// <param name="apiKey">The API key for authenticating with the AI service.</param>
        /// /// <exception cref="InvalidOperationException">Thrown if the AIClientKernel is already initialized.</exception>
        /// /// <exception cref="ArgumentException">Thrown if any of the parameters are null or empty.</exception>
        public void Initialize(string modelName, string endpoint, string apiKey,string deploymentName, string apiVer)
        {
            if (_initialized)
                throw new InvalidOperationException("AIClientKernel is already initialized.");


            if (string.IsNullOrEmpty(modelName) || string.IsNullOrEmpty(endpoint) || string.IsNullOrEmpty(apiKey))
            {
                throw new ArgumentException("Model name, endpoint, and API key must be provided for initialization.");
            }

            _modelName = modelName;
            _kernel = Kernel.CreateBuilder()
                .AddAzureOpenAIChatCompletion(
                    deploymentName: deploymentName,
                    endpoint: endpoint,
                    apiKey: apiKey,
                    modelId: _modelName
                    )
                .Build();

            _initialized = true;
        }


        /// <summary>
        /// Indicates whether the AIClientKernel has been initialized.
        /// /// This property can be used to check if the kernel is ready to process requests.
        /// /// </summary>
        /// /// <value>
        /// True if the kernel is initialized; otherwise, false.
        public bool IsInitialized => _initialized;

        /// <summary>
        /// Sends a message to the AI model and returns the response.
        /// /// This method should only be called after Initialize() has been called.
        /// /// </summary>
        /// /// <param name="prompt">The input message to send to the AI model.</param>
        /// /// <returns>The response from the AI model.</returns>
        public async Task<string> SendMessageAsync(string prompt)
        {
            if (!_initialized)
                throw new InvalidOperationException("AIClientKernel is not initialized. Call Initialize() first.");

            var chat = _kernel.GetRequiredService<IChatCompletionService>();
            var history = new ChatHistory();
            history.AddUserMessage(prompt);

            var result = await chat.GetChatMessageContentAsync(history).ConfigureAwait(false);
            return result.Content;
        }

    }
}