using Microsoft.Dynamics.Commerce.Runtime;
using Microsoft.Dynamics.Retail.PaymentSDK.Portable;
using Microsoft.Dynamics.Retail.PaymentSDK.Portable.Constants;
using System.Reflection;
using System.Text;
using System.Text.Json;

namespace SampleConsoleAppAuthorizePayment
{

    /// <summary>
    /// Helper class for Adyen payment processing.
    /// </summary>
    /// 
    /// <remarks>
    /// 
    /// This class is used to perform payment processing using the Adyen payment service.
    /// It contains methods to authorize payments, handle payment responses, and manage payment details.
    /// The class uses the HttpClient class to make HTTP requests to the Adyen payment service.
    /// 
    /// </remarks>
    public class AdyenPaymentHelper
    {
        /// <summary>
        /// Card Type
        /// </summary>
        public Microsoft.Dynamics.Commerce.RetailProxy.CardType CardType { get; set; } = Microsoft.Dynamics.Commerce.RetailProxy.CardType.Unknown;
        /// <summary>
        /// Connector Service Account ID.
        /// </summary>
        public required string ServiceAccountId { get; set; }
        /// <summary>
        /// Adyen Merchant account name.
        /// </summary>
        public required string MerchantAccount { get; set; }
        /// <summary>
        /// Amount to be charged. Must contain the currency and the value. Ex. { "currency": "USD", "value": 10.00 }
        /// </summary>
        public required Amount Amount { get; set; }

        /// <summary>
        /// URL to redirect the user after payment is completed.
        /// </summary>
        public required string ReturnUrl { get; set; }

        /// <summary>
        /// Reference for the payment. This is usually the cart ID or order ID.
        /// </summary>
        public string? Reference { get; set; }

        /// <summary>
        /// Country code for the payment. This is usually the country code of the customer.
        /// </summary>
        public required string CountryCode { get; set; }

        /// <summary>
        /// Payment method details. This is usually the payment method selected by the customer.
        /// </summary>
        public required AdyenPaymentMethod PaymentMethod { get; set; }

        /// <summary>
        /// URL of the Adyen payment service. This is usually the URL of the Adyen payment service.
        /// </summary>
        public required string PaymentServiceURL { get; set; }
        /// <summary>
        /// Adyen API key. This is usually the API key generated in the Adyen dashboard.
        /// </summary>
        public required string Token { get; set; } = string.Empty;

        /// <summary>
        /// Delivery address tied to the payment
        /// </summary>
        public AdyenDeliveryAddress DeliveryAddress { get; set; }

        /// <summary>
        /// Shopper Interaction parameter (Adyen)
        /// </summary>
        public object ShopperInteraction { get; set; } = "Ecommerce";
        public object ShopperEmail { get; private set; }


        /// <summary>
        /// Deserialized response from the Adyen payment service. 
        /// </summary>
        public PaymentResponse PaymentResponse { get; set; } = new PaymentResponse();

        /// <summary>
        /// Adyen originating channel.
        /// </summary>
        public string Channel { get; set; } = "Web";
        public string RecurringProcessingModel { get; set; } = "UnscheduledCardOnFile";

        /// <summary>
        /// HttpClient instance for making HTTP requests.
        /// </summary>
        private static readonly HttpClient client = new();

        /// <summary>
        /// Executes an HTTP request to the Adyen payment service.
        /// </summary>
        /// <param name="endpoint"></param>
        /// <param name="requestBody"></param>
        /// <returns>responseBody</returns>
        private async Task<string?> ExecuteHttpRequestAsync(string endpoint, object requestBody)
        {
            var options = new JsonSerializerOptions { PropertyNamingPolicy = JsonNamingPolicy.CamelCase };
            try
            {
                var jsonPayload = JsonSerializer.Serialize(requestBody, options);
                client.DefaultRequestHeaders.Accept.Clear();

                var content = new StringContent(jsonPayload, Encoding.UTF8, "application/json");
                content.Headers.Add("x-api-key", Token);
                HttpResponseMessage response = await client.PostAsync(this.PaymentServiceURL + endpoint, content);
                response.EnsureSuccessStatusCode();

                string responseBody = await response.Content.ReadAsStringAsync();

                return responseBody;
            }
            catch (HttpRequestException e)
            {
                Console.WriteLine($"Request error: {e.Message}");
                return null;
            }
        }

        /// <summary>
        /// Performs authorization through Adyen API using the "payments" endpoint.
        /// </summary>
        /// <returns>PaymentResponse.ResultCode</returns>
        /// <exception cref="Exception"></exception>
        public async Task<string> AuthorizePaymentAsync()
        {
            var options = new JsonSerializerOptions
            {
                PropertyNameCaseInsensitive = true,
                PropertyNamingPolicy = JsonNamingPolicy.CamelCase
            };

            var requestBody = new
            {
                reference = Reference,
                channel = Channel,
                merchantAccount = MerchantAccount,
                recurringProcessingModel = RecurringProcessingModel,
                shopperInteraction = ShopperInteraction,
                returnUrl = ReturnUrl,
                countryCode = CountryCode,
                shopperReference = Reference,
                shopperEmail = ShopperEmail,
                additionalData = new
                {
                    manualCapture = true
                },
                applicationInfo = new
                {
                    merchantApplication = new
                    {
                        name = Assembly.GetExecutingAssembly().GetName().Name,
                        version = Assembly.GetExecutingAssembly().GetName().Version
                    }
                },
                deliveryAddress = DeliveryAddress,
                amount = Amount,
                paymentMethod = PaymentMethod
            };

            var response = await ExecuteHttpRequestAsync("payments", requestBody);

            if (response != null)
            {
                PaymentResponse? paymentResponse = JsonSerializer.Deserialize<PaymentResponse>(response, options);

                if (paymentResponse != null)
                {
                    PaymentResponse = paymentResponse;
                }
                else
                {
                    throw new Exception("Failed to deserialize payment response.");
                }
                return paymentResponse.ResultCode.IsNullOrEmpty() ? "N/A" : paymentResponse.ResultCode;
            }
            else
            {
                throw new Exception("Response is null.");
            }
        }
        public string GetCardToken()
        {
            #region PropertiesSection
            //MerchantAccount ServiceAccountId
            var paymentProperties = new List<PaymentProperty>
            {
                new PaymentProperty()
                {
                    Namespace = GenericNamespace.MerchantAccount,
                    Name = MerchantAccountProperties.ServiceAccountId,
                    ValueType = DataType.String,
                    StoredStringValue = this.ServiceAccountId
                },

                //TODO: Review ConnectorName property value.
                new PaymentProperty()
                {
                    Namespace = GenericNamespace.Connector,
                    Name = ConnectorProperties.ConnectorName,
                    ValueType = DataType.String,
                    StoredStringValue = "Dynamics 365 Payment Connector for Adyen"
                },

                //TODO: Review FraudResult property value.
                new PaymentProperty()
                {
                    Namespace = GenericNamespace.PaymentCard,
                    Name = "FraudResult",
                    ValueType = DataType.String,
                    StoredStringValue = "GREEN"
                },
                new PaymentProperty()
                {
                    Namespace = GenericNamespace.PaymentCard,
                    Name = PaymentCardProperties.Alias,
                    ValueType = DataType.String,
                    StoredStringValue = PaymentResponse.AdditionalData.Alias
                },
                new PaymentProperty()
                {
                    Namespace = GenericNamespace.PaymentCard,
                    Name = PaymentCardProperties.CardType,
                    ValueType = DataType.String,
                    StoredStringValue = PaymentResponse.AdditionalData.CardPaymentMethod
                },

                //TODO:Review AdyenPaymentMethod property value
                new PaymentProperty()
                {
                    Namespace = GenericNamespace.PaymentCard,
                    Name = "AdyenPaymentMethod",
                    ValueType = DataType.String,
                    StoredStringValue = PaymentResponse.AdditionalData.PaymentMethodVariant
                },

                //TODO: Review CardToken property value and PaymentResponse class structure to add token property 
                new PaymentProperty()
                {
                    Namespace = GenericNamespace.PaymentCard,
                    Name = PaymentCardProperties.CardToken,
                    ValueType = DataType.String,
                    StoredStringValue = ""
                },
                new PaymentProperty()
                {
                    Namespace = GenericNamespace.PaymentCard,
                    Name = PaymentCardProperties.Last4Digits,
                    ValueType = DataType.String,
                    StoredStringValue = PaymentMethod.Number?[^4..]
                },

                //TODO: Review response and documentation, there's no Shopper Reference in the standard response as referenced in the documentation.
                new PaymentProperty()
                {
                    Namespace = GenericNamespace.PaymentCard,
                    Name = PaymentCardProperties.UniqueCardId,
                    ValueType = DataType.String,
                    StoredStringValue = PaymentResponse.AdditionalData.AcquirerReference.ToString()
                },
                new PaymentProperty()
                {
                    Namespace = GenericNamespace.PaymentCard,
                    Name = PaymentCardProperties.ExpirationYear,
                    ValueType = DataType.Decimal,
                    DecimalValue = Convert.ToDecimal(PaymentMethod.ExpiryYear)
                },
                new PaymentProperty()
                {
                    Namespace = GenericNamespace.PaymentCard,
                    Name = PaymentCardProperties.ExpirationMonth,
                    ValueType = DataType.Decimal,
                    DecimalValue = Convert.ToDecimal(PaymentMethod.ExpiryMonth)
                },
                new PaymentProperty()
                {
                    Namespace = GenericNamespace.PaymentCard,
                    Name = PaymentCardProperties.Name,
                    ValueType = DataType.String,
                    StoredStringValue = PaymentResponse.AdditionalData.CardHolderName
                },
                new PaymentProperty()
                {
                    Namespace = GenericNamespace.PaymentCard,
                    Name = PaymentCardProperties.BankIdentificationNumberStart,
                    ValueType = DataType.String,
                    StoredStringValue = PaymentResponse.AdditionalData.BankAccountIban
                },

                //TODO: Review CardVerification property value 
                new PaymentProperty()
                {
                    Namespace = GenericNamespace.PaymentCard,
                    Name = PaymentCardProperties.CardVerificationValue,
                    ValueType = DataType.String,
                    StoredStringValue = "Success"
                },

                //TODO: Review ShowSameAsShippingAddress property value
                new PaymentProperty()
                {
                    Namespace = GenericNamespace.PaymentCard,
                    Name = PaymentCardProperties.ShowSameAsShippingAddress,
                    ValueType = DataType.String,
                    StoredStringValue = "True"
                },

                //TODO: Review House property value
                new PaymentProperty()
                {
                    Namespace = GenericNamespace.PaymentCard,
                    Name = PaymentCardProperties.House,
                    ValueType = DataType.String,
                    StoredStringValue = "N/A"
                },

                new PaymentProperty()
                {
                    Namespace = GenericNamespace.PaymentCard,
                    Name = PaymentCardProperties.StreetAddress,
                    ValueType = DataType.String,
                    StoredStringValue = DeliveryAddress.Street
                },

                new PaymentProperty()
                {
                    Namespace = GenericNamespace.PaymentCard,
                    Name = PaymentCardProperties.City,
                    ValueType = DataType.String,
                    StoredStringValue = DeliveryAddress.City
                },
                new PaymentProperty()
                {
                    Namespace = GenericNamespace.PaymentCard,
                    Name = PaymentCardProperties.State,
                    ValueType = DataType.String,
                    StoredStringValue = DeliveryAddress.StateOrProvince
                },
                new PaymentProperty()
                {
                    Namespace = GenericNamespace.PaymentCard,
                    Name = PaymentCardProperties.PostalCode,
                    ValueType = DataType.String,
                    StoredStringValue = DeliveryAddress.PostalCode
                },
                new PaymentProperty()
                {
                    Namespace = GenericNamespace.PaymentCard,
                    Name = PaymentCardProperties.Country,
                    ValueType = DataType.String,
                    StoredStringValue = DeliveryAddress.Country
                }
            };


            #endregion PropertiesSection
            var paymentBlob = PaymentProperty.ConvertPropertyArrayToXML(paymentProperties.ToArray());

            return paymentBlob;
        }
        public string GetAuthorizationToken()
        {
            #region PropertiesSection
            var paymentProperties = new List<PaymentProperty>();
            
            paymentProperties.Add(new PaymentProperty()
            {
                Namespace = GenericNamespace.MerchantAccount,
                Name = MerchantAccountProperties.ServiceAccountId,
                ValueType = DataType.String,
                StoredStringValue = ServiceAccountId
            });

            paymentProperties.Add(new PaymentProperty()
            {
                Namespace = GenericNamespace.Connector,
                Name = ConnectorProperties.ConnectorName,
                ValueType = DataType.String,
                StoredStringValue = MerchantAccount
            });

            var authorizationProperties = new List<PaymentProperty>
    {
        new PaymentProperty()
        {
            Namespace = GenericNamespace.AuthorizationResponse,
            Name = AuthorizationResponseProperties.AuthorizationResult,
            ValueType = DataType.String,
            StoredStringValue = nameof(AuthorizationResult.Success)
        },
        new PaymentProperty()
        {
            Namespace = GenericNamespace.AuthorizationResponse,
            Name = AuthorizationResponseProperties.ApprovedAmount,
            ValueType = DataType.Decimal,
            DecimalValue = Amount.Value
        },
        new PaymentProperty()
        {
            Namespace = GenericNamespace.AuthorizationResponse,
            Name = AuthorizationResponseProperties.UniqueCardId,
            ValueType = DataType.String,
            StoredStringValue = Guid.NewGuid().ToString()
        },
        new PaymentProperty()
        {
            Namespace = GenericNamespace.AuthorizationResponse,
            Name = AuthorizationResponseProperties.Last4Digits,
            ValueType = DataType.String,
            StoredStringValue = PaymentMethod.Number?[(PaymentMethod.Number.Length - 4)..]
        },
        new PaymentProperty()
        {
            Namespace = GenericNamespace.AuthorizationResponse,
            Name = AuthorizationResponseProperties.CardType,
            ValueType = DataType.String,
            StoredStringValue = PaymentResponse.AdditionalData.CardPaymentMethod
        },
        new PaymentProperty()
        {
            Namespace = GenericNamespace.AuthorizationResponse,
            Name = AuthorizationResponseProperties.ApprovalCode,
            ValueType = DataType.String,
            StoredStringValue = PaymentResponse.AdditionalData.AuthCode
        },
        new PaymentProperty()
        {
            Namespace = GenericNamespace.AuthorizationResponse,
            Name = AuthorizationResponseProperties.ProviderTransactionId,
            ValueType = DataType.String,
            StoredStringValue = Reference
        },
        new PaymentProperty()
        {
            Namespace = GenericNamespace.AuthorizationResponse,
            Name = AuthorizationResponseProperties.TransactionType,
            ValueType = DataType.String,
            StoredStringValue = TransactionType.Authorize.ToString()
        },
        new PaymentProperty()
        {
            Namespace = GenericNamespace.AuthorizationResponse,
            Name = AuthorizationResponseProperties.CurrencyCode,
            ValueType = DataType.String,
            StoredStringValue = this.Amount.Currency
        },
        new PaymentProperty()
        {
            Namespace = GenericNamespace.AuthorizationResponse,
            Name = AuthorizationResponseProperties.TransactionDateTime,
            ValueType = DataType.DateTime,
            DateValue = DateTime.UtcNow
        }
    };

            paymentProperties.Add(new PaymentProperty(
                GenericNamespace.AuthorizationResponse,
                AuthorizationResponseProperties.Properties,
                authorizationProperties.ToArray()
            ));

            #endregion PropertiesSection

            var paymentBlob = PaymentProperty.ConvertPropertyArrayToXML(paymentProperties.ToArray());

            return paymentBlob;
        }
    }
}