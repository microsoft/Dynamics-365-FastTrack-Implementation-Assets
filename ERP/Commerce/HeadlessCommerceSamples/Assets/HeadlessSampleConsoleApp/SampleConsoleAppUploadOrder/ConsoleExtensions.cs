/**
 * SAMPLE CODE NOTICE
 * 
 * THIS SAMPLE CODE IS MADE AVAILABLE AS IS.  MICROSOFT MAKES NO WARRANTIES, WHETHER EXPRESS OR IMPLIED,
 * OF FITNESS FOR A PARTICULAR PURPOSE, OF ACCURACY OR COMPLETENESS OF RESPONSES, OF RESULTS, OR CONDITIONS OF MERCHANTABILITY.
 * THE ENTIRE RISK OF THE USE OR THE RESULTS FROM THE USE OF THIS SAMPLE CODE REMAINS WITH THE USER.
 * NO TECHNICAL SUPPORT IS PROVIDED.  YOU MAY NOT DISTRIBUTE THIS CODE UNLESS YOU HAVE A LICENSE AGREEMENT WITH MICROSOFT THAT ALLOWS YOU TO DO SO.
 */

namespace SampleConsoleAppUploadOrder
{
    using System;
    using Microsoft.Dynamics.Commerce.RetailProxy;
    using SampleConsoleApp.Common;
    internal static class ConsoleExtensions
    {
        private const int Start = 0;

        public static void DisplaySalesTransaction(this SalesOrder order, ConsoleLogger logger)
        {
            if (order == null)
            {
                logger.Error("Sales order is null.");
                return;
            }
            logger.Info($"> Sales transaction: \x1b[92m {order.Id} \x1b[39m");
            logger.Info($"> Customer: \x1b[93m {order.CustomerId} \x1b[39m");
            logger.Info($"> Customer Name: {order.Name}");
            logger.Info($"> Discount: {order.DiscountAmount}");
            logger.Info($"> Subtotal: {order.SubtotalAmount}");
            logger.Info($"> Taxes: {order.TaxAmount}");
            logger.Info($"> Charges: {order.ChargeAmount}");
            logger.Info($"> Amount Paid: \x1b[92m {order.AmountPaid} \x1b[39m");
            logger.Info($"> Amount Due: {order.AmountDue}");
            logger.Info($"> Total: \x1b[92m {order.TotalAmount} \x1b[39m");


            int[] columnwidths = [10, 25, 10, 10, 10, 10, 10];
            string[] columnheaders = ["ItemId", "Description", "Quantity", "Price", "Tax", "Discount", "Total"];



            logger.Info($"> Lines:");
            int totalwidth = columnwidths.Sum();

            logger.Info($"╔" + new string('═', totalwidth + columnheaders.Length + 2) + "╗");

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
                var tableLine = string.Concat("║", line.ItemId.PadRight(columnwidths[0]).AsSpan(Start, columnwidths[0]), "║");
                tableLine += string.Concat(line.Description.PadRight(columnwidths[1]).AsSpan(0, columnwidths[1]), "║");
                tableLine += line.Quantity?.ToString().PadRight(columnwidths[2])[..columnwidths[2]] + "║";
                tableLine += line.Price?.ToString().PadRight(columnwidths[3])[..columnwidths[3]] + "║";
                tableLine += line.TaxAmount?.ToString().PadRight(columnwidths[4])[..columnwidths[4]] + "║";
                tableLine += line.DiscountAmount?.ToString().PadRight(columnwidths[5])[..columnwidths[5]] + "║";
                tableLine += line.TotalAmount?.ToString().PadRight(columnwidths[6])[..columnwidths[6]] + "   ║";
                logger.Info(tableLine);
            }

            //footer


            logger.Info($"╚" + new string('═', totalwidth + columnheaders.Length + 2) + "╝");
        }

    }
}