/**
 * SAMPLE CODE NOTICE
 * 
 * THIS SAMPLE CODE IS MADE AVAILABLE AS IS.  MICROSOFT MAKES NO WARRANTIES, WHETHER EXPRESS OR IMPLIED,
 * OF FITNESS FOR A PARTICULAR PURPOSE, OF ACCURACY OR COMPLETENESS OF RESPONSES, OF RESULTS, OR CONDITIONS OF MERCHANTABILITY.
 * THE ENTIRE RISK OF THE USE OR THE RESULTS FROM THE USE OF THIS SAMPLE CODE REMAINS WITH THE USER.
 * NO TECHNICAL SUPPORT IS PROVIDED.  YOU MAY NOT DISTRIBUTE THIS CODE UNLESS YOU HAVE A LICENSE AGREEMENT WITH MICROSOFT THAT ALLOWS YOU TO DO SO.
 */
 
namespace Microsoft.Dynamics.Commerce.Runtime.Workflow.CartManagement
{
    using System;
    using System.Collections.Generic;
    using System.Linq;
    using System.Net.Http;
    using System.Runtime.Serialization;
    using System.Threading.Tasks;

    using global::Microsoft.Dynamics.Commerce.Runtime.Messages;
    using global::Microsoft.Dynamics.Commerce.Runtime.Services.Messages;

    using Microsoft.Dynamics.Commerce.Runtime;
    using Microsoft.Dynamics.Commerce.Runtime.DataModel;
    using Microsoft.Dynamics.Commerce.Runtime.DataServices.Messages;
    using Microsoft.Dynamics.Commerce.Runtime.Framework.Exceptions;
    using Microsoft.Dynamics.Commerce.Runtime.Framework.Serialization;

    /// <summary>
    /// Captcha validation request trigger. Use this if you meet both of the following conditions:
    /// 1. You enable the single payment authorization
    /// 2. Your customized payment connector support card tokenize and authorize in the same request.
    /// Get more detail about how to use request trigger in this document https://learn.microsoft.com/en-us/dynamics365/commerce/dev-itpro/commerce-runtime-extensibility-trigger.
    /// </summary>
    internal sealed class CaptchaValidationTriggerOnCheckout : IRequestTriggerAsync
    {
        private static readonly HttpClient HttpClient = new HttpClient();

        /// <summary>
        /// Gets the supported requests for this trigger.
        /// </summary>
        public IEnumerable<Type> SupportedRequestTypes
        {
            get
            {
                return new[] { typeof(CheckoutCartRequest) };
            }
        }

        /// <summary>
        /// Post trigger code.
        /// </summary>
        /// <param name="request">The request.</param>
        /// <param name="response">The response.</param>
        /// <returns>The empty Task.</returns>
        public Task OnExecuted(Request request, Response response)
        {
            return Task.CompletedTask;
        }

        /// <summary>
        /// Pre trigger code.
        /// </summary>
        /// <param name="request">The request.</param>
        /// <returns>The empty Task.</returns>
        public async Task OnExecuting(Request request)
        {
            var checkoutRequest = request as CheckoutCartRequest;
            var channelConfiguration = request.RequestContext.GetChannelConfiguration();

            // Only validation for online store.
            if (channelConfiguration.IsOnlineStore())
            {
                // Skip if single payment authorization is off.
                if (checkoutRequest.CartTenderLines.FirstOrDefault().TokenizedPaymentCard != null)
                {
                    return;
                }

                // Get cart with cart id.
                CartSearchCriteria cartSearchCriteria = new CartSearchCriteria(checkoutRequest.CartId);
                var getCartRequest = new GetCartRequest(cartSearchCriteria, QueryResultSettings.SingleRecord);
                var getCartResponse = await request.RequestContext.ExecuteAsync<GetCartResponse>(getCartRequest).ConfigureAwait(false);
                var cart = getCartResponse.Carts.SingleOrDefault();

                if (cart == null)
                {
                    // Fail if cart is missing.
                    throw new CartValidationException(DataValidationErrors.Microsoft_Dynamics_Commerce_Runtime_CartNotFound, checkoutRequest.CartId);
                }

                // Use predefined key to retrieve captcha token.
                var commerceProperties = cart.ExtensionProperties;
                var token = commerceProperties.FirstOrDefault(p => p.Key == "captchaToken").Value?.StringValue;

                // Check the existence of token.
                if (string.IsNullOrEmpty(token))
                {
                    throw new CaptchaValidationException("CAPTCHA token is not found, please complete CAPTCHA challenge again.");
                }

                // Get the secret.
                GetUserDefinedSecretStringValueServiceRequest keyVaultRequest = new GetUserDefinedSecretStringValueServiceRequest("captchaToken");
                GetUserDefinedSecretStringValueServiceResponse keyVaultResponse = await request.RequestContext.ExecuteAsync<GetUserDefinedSecretStringValueServiceResponse>(keyVaultRequest).ConfigureAwait(false);
                string secretValue = keyVaultResponse.SecretStringValue;

                // Validate CAPTCHA.
                await this.ValidateCaptcha(token, secretValue).ConfigureAwait(false);
            }
        }

        private async Task ValidateCaptcha(string captchaToken, string secretValue)
        {
            ThrowIf.Null(captchaToken, nameof(captchaToken));

            var isCaptchaValid = false;
            var googleVerificationUrl = $"https://www.google.com/recaptcha/api/siteverify?secret={secretValue}&response={captchaToken}";

            // Verify token.
            var response = await HttpClient.PostAsync(googleVerificationUrl, content: null).ConfigureAwait(false);
            var jsonResponse = await response.Content.ReadAsStringAsync().ConfigureAwait(false);
            var result = JsonHelper.Deserialize<ReCaptchaResponse>(jsonResponse);

            if (result?.Success == true)
            {
                // Reject token with challenge time greater than 5 minutes.
                DateTime challengeTime = DateTime.Parse(result.Challenge_ts);
                if ((DateTime.UtcNow - challengeTime).TotalMinutes <= 5)
                {
                    isCaptchaValid = true;
                }
            }

            if (!isCaptchaValid)
            {
                throw new CaptchaValidationException("Captcha validation failed, please complete CAPTCHA challenge again");
            }
        }

        /// <summary>
        /// Response for request to validate ReCaptcha.
        /// </summary>
        [DataContract]
        private sealed class ReCaptchaResponse
        {
            /// <summary>
            /// Gets a value indicating whether success or not.
            /// </summary>
            [DataMember(Name = "success")]
            public bool Success { get; private set; }

            /// <summary>
            /// Gets a value indicating challenge time.
            /// </summary>
            [DataMember(Name = "challenge_ts")]
            public string Challenge_ts { get; private set; }

            /// <summary>
            /// Gets a value indicating host name.
            /// </summary>
            [DataMember(Name = "hostname")]
            public string Hostname { get; private set; }
        }

        private sealed class CaptchaValidationException : CommerceException
        {
            public CaptchaValidationException(string message)
            : base(nameof(CaptchaValidationException), ExceptionSeverity.Warning, null, message)
            {
            }
        }
    }
}
