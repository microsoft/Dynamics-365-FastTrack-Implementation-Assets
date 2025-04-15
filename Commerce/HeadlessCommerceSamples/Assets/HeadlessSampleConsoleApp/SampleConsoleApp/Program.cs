/**
 * SAMPLE CODE NOTICE
 * 
 * THIS SAMPLE CODE IS MADE AVAILABLE AS IS.  MICROSOFT MAKES NO WARRANTIES, WHETHER EXPRESS OR IMPLIED,
 * OF FITNESS FOR A PARTICULAR PURPOSE, OF ACCURACY OR COMPLETENESS OF RESPONSES, OF RESULTS, OR CONDITIONS OF MERCHANTABILITY.
 * THE ENTIRE RISK OF THE USE OR THE RESULTS FROM THE USE OF THIS SAMPLE CODE REMAINS WITH THE USER.
 * NO TECHNICAL SUPPORT IS PROVIDED.  YOU MAY NOT DISTRIBUTE THIS CODE UNLESS YOU HAVE A LICENSE AGREEMENT WITH MICROSOFT THAT ALLOWS YOU TO DO SO.
 */

namespace SampleConsoleAppCheckout
{
    using System;
    using Microsoft.Dynamics.Commerce.RetailProxy;
    using static SampleConsoleAppCheckout.PageHelper;
    using SampleConsoleApp.Common;
    using static SampleConsoleApp.Common.ConfigHelper;

    internal sealed class Program
    {
#pragma warning disable IDE0060 // Remove unused parameter
        internal static async Task Main(string[] args)
#pragma warning restore IDE0060 // Remove unused parameter
        {
            ConsoleLogger consoleLogger = new();
            try
            {
                string cartId = string.Empty;
                string orderId;
               
                consoleLogger.Info("\u001b[92m Welcome to the Headless Sample Console App! \u001b[39m");
                consoleLogger.Info("\u001b[93m This sample app demonstrates how to checkout a cart and view orders.\u001b[39m");
                consoleLogger.Info("\u001b[93m You can search for products, add them to the cart, checkout, view orders and request cancellation of an order.\u001b[39m");
                CommerceClient client = new(InitFactory(), consoleLogger);
                await client.InitializeContext();
                StateModel model = new(consoleLogger);
                while (model.CurrentPage != Page.Terminated)
                {
                    Console.WriteLine();
                    consoleLogger.Info($"> You are on the {model.CurrentPage} page.");

                    switch (model.CurrentPage)
                    {
                        case Page.Search:
                            string keyword = consoleLogger.GetUserTextInput($"Search products by keyword (e.g. bag): ");
                            await client.SearchProductsByKeyword(keyword);
                            break;

                        case Page.Cart:
                            string selectedItemId = consoleLogger.GetUserTextInput($"Enter Item ID to add to cart: ");
                            cartId = await HandleAddItemToCart(client, cartId, selectedItemId);
                            break;

                        case Page.Checkout:
                            await HandleCheckout(client, cartId);
                            break;

                        case Page.Order:
                            orderId = consoleLogger.GetUserTextInput($"Enter Sales Order ID:");
                            await HandleOrders(client, orderId);
                            break;
                        case Page.RequestCancel:
                            orderId = consoleLogger.GetUserTextInput($"Enter Sales Order ID to request cancellation:");
                            await HandleCancelOrder(client, orderId);
                            break;
                        default:
                            break;
                    }
                    consoleLogger.Print();
                    consoleLogger.Actions($"> Actions to take: {model.GetActions()}");

                    string input = consoleLogger.GetUserTextInput($"Enter action: ");
                    Action action = model.Convert(input);
                    model.MoveNext(action);
                }

                consoleLogger.Info("Press any key to exit.");
                consoleLogger.ReadKey();
            }
            catch (Exception ex)
            {
                consoleLogger.Error($"Error: {ex.Message}");
                return;
            }
        }


    }
}
