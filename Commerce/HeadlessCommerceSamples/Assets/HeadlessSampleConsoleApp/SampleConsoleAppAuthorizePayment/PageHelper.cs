/**
 * SAMPLE CODE NOTICE
 * 
 * THIS SAMPLE CODE IS MADE AVAILABLE AS IS.  MICROSOFT MAKES NO WARRANTIES, WHETHER EXPRESS OR IMPLIED,
 * OF FITNESS FOR A PARTICULAR PURPOSE, OF ACCURACY OR COMPLETENESS OF RESPONSES, OF RESULTS, OR CONDITIONS OF MERCHANTABILITY.
 * THE ENTIRE RISK OF THE USE OR THE RESULTS FROM THE USE OF THIS SAMPLE CODE REMAINS WITH THE USER.
 * NO TECHNICAL SUPPORT IS PROVIDED.  YOU MAY NOT DISTRIBUTE THIS CODE UNLESS YOU HAVE A LICENSE AGREEMENT WITH MICROSOFT THAT ALLOWS YOU TO DO SO.
 */
namespace SampleConsoleAppAuthorizePayment
{
    class PageHelper
    {
        public static void HandlePaymentAuthorization()
        {
            AdyenPaymentHelper paymentHelper = new AdyenPaymentHelper()
            {
                ServiceAccountId = "serviceaccountid",
                PaymentServiceURL = "https://checkout-test.adyen.com/v69/",
                Amount = new Amount { Currency = "USD", Value = 100 },
                Reference = "TestReference",
                CountryCode = "US",
                PaymentMethod = new AdyenPaymentMethod
                {
                    Cvc = "737",
                    ExpiryMonth = "03",
                    ExpiryYear = "2030",
                    HolderName = "John Doe",
                    Number = "4111111111111111",
                    Type = "scheme",
                },
                ReturnUrl = "https://example.com/return",
                MerchantAccount = "MicrosoftDynamics",
                DeliveryAddress = new AdyenDeliveryAddress
                {
                    Street = "Microsoft Way",
                    City = "Redmond",
                    StateOrProvince = "WA",
                    Country = "US",
                    PostalCode = "98051",
                    HouseNumberOrName = "1"
                },

                Token = "[Provide Adyen API Token here]"
            };

            paymentHelper.AuthorizePaymentAsync().Wait();

            Console.ForegroundColor = ConsoleColor.Blue;
            Console.WriteLine("Card Token:\n" + paymentHelper.GetCardToken());

            Console.ForegroundColor = ConsoleColor.Green;
            Console.WriteLine("Authorization Token:\n" + paymentHelper.GetAuthorizationToken());

            Console.ForegroundColor = ConsoleColor.White;
            Console.ReadKey();
        }
    }
}
