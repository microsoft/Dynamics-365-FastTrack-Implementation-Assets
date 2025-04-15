/**
 * SAMPLE CODE NOTICE
 * 
 * THIS SAMPLE CODE IS MADE AVAILABLE AS IS.  MICROSOFT MAKES NO WARRANTIES, WHETHER EXPRESS OR IMPLIED,
 * OF FITNESS FOR A PARTICULAR PURPOSE, OF ACCURACY OR COMPLETENESS OF RESPONSES, OF RESULTS, OR CONDITIONS OF MERCHANTABILITY.
 * THE ENTIRE RISK OF THE USE OR THE RESULTS FROM THE USE OF THIS SAMPLE CODE REMAINS WITH THE USER.
 * NO TECHNICAL SUPPORT IS PROVIDED.  YOU MAY NOT DISTRIBUTE THIS CODE UNLESS YOU HAVE A LICENSE AGREEMENT WITH MICROSOFT THAT ALLOWS YOU TO DO SO.
 */

namespace SampleConsoleApp.Common
{
    using System;
    using Microsoft.Dynamics.Commerce.RetailProxy;
    internal static class ConsoleExtensions
    {
        private const int Start = 0;

        public static void DisplayCart(this Cart cart,ILogger logger)
        {
            if (cart == null || cart.CartLines.Count == 0)
            {
                logger.Error($"There is nothing in the cart.");
                return;
            }

            Console.ForegroundColor = ConsoleColor.Green;
            logger.Info("");
            logger.Info($"> Cart ID: {cart.Id,-25}");
            logger.Info($"> Total items: {cart.TotalItems,-25}");
            logger.Info("");
            logger.Info($"> Lines:");

            foreach (var cartLine in cart.CartLines)
            {
                logger.Info($"> Qty {cartLine.Quantity,-2}x {cartLine.ItemId,-10} ${cartLine.Price,-6}");
            }

            logger.Info("");
            logger.Info($"> Discount: ${cart.DiscountAmount,6}");
            logger.Info($"> Subtotal: ${cart.SubtotalAmount,6}");
            logger.Info($"> Taxes:    ${cart.TaxAmount,6}");
            logger.Info($"> Charges:  ${cart.ChargeAmount,6}");
            logger.Info($"> Total:    ${cart.TotalAmount,6}");
            logger.Info("");
            Console.ResetColor();
        }

        public static void DisplayAddress(this Address address,ILogger logger)
        {
            if (address == null)
            {
                logger.Error("Address is null.");
                return;
            }

            logger.Info("");
            logger.Info($"> Shipping address:");
            logger.Info($"> {address.Name}");
            logger.Info($"> {address.Street}");
            logger.Info($"> {address.City}, {address.State}");
            logger.Info($"> {address.ZipCode} {address.ThreeLetterISORegionName}");
            logger.Info("");
        }

        public static void DisplaySalesOrder(this SalesOrder order,ILogger logger)
        {
            if (order == null)
            {
                logger.Error("Sales order is null.");
                return;
            }
            logger.Info($"> Sales Order: \x1b[92m {order.SalesId} \x1b[39m");
            logger.Info($"> Customer: \x1b[93m {order.CustomerId} \x1b[39m");
            logger.Info($"> Customer Name: {order.Name}");
            logger.Info($"> Store: {order.StoreId}");
            logger.Info($"> Terminal: {order.TerminalId}");
            logger.Info($"> Discount: {order.DiscountAmount}");
            logger.Info($"> Subtotal: {order.SubtotalAmount}");
            logger.Info($"> Taxes: {order.TaxAmount}");
            logger.Info($"> Charges: {order.ChargeAmount}");
            logger.Info($"> Total: \x1b[92m {order.TotalAmount} \x1b[39m");


            int[] columnwidths = [10, 25, 10, 10, 10, 10, 10];
            string[] columnheaders = ["ItemId", "Description", "Quantity", "Price", "Tax", "Discount", "Total"];

            

            logger.Info($"> Lines:");
            int totalwidth = columnwidths.Sum();

            logger.Info($"╔" + new string('═', totalwidth+columnheaders.Length+2) + "╗");

            string tableHeader = "";
            for (int i = 0; i < columnheaders.Length; i++)
            {
                tableHeader += "║" + columnheaders[i].PadRight(columnwidths[i]);
            }
            tableHeader += "   ║";
            logger.Info(tableHeader);
            
            //separator
            logger.Info($"╠" + new string('═', totalwidth + columnheaders.Length + 2) + "╣");

            //lines
            foreach (var line in order.SalesLines)
            {
                var tableLine = string.Concat("║", line.ItemId.PadRight(columnwidths[0]).AsSpan(0, columnwidths[0]), "║"); 
                tableLine += string.Concat(line.Description.PadRight(columnwidths[1]).AsSpan(0, columnwidths[1]), "║");
                tableLine += line.Quantity?.ToString().PadRight(columnwidths[2])[..columnwidths[2]] + "║";
                tableLine += line.Price?.ToString().PadRight(columnwidths[3])[..columnwidths[3]] + "║";
                tableLine += line.TaxAmount?.ToString().PadRight(columnwidths[4])[..columnwidths[4]] + "║";
                tableLine += line.DiscountAmount?.ToString().PadRight(columnwidths[5])[..columnwidths[5]] + "║";
                tableLine += line.TotalAmount?.ToString().PadRight(columnwidths[6])[..columnwidths[6]] + "   ║";
                logger.Info(tableLine);
            }
            //footer
            logger.Info($"╚" + new string('═', totalwidth + columnheaders.Length+2) + "╝");
        }
    }
}