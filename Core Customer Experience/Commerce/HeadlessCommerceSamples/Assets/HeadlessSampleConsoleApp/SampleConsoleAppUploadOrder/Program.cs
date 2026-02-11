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
    using static SampleConsoleAppUploadOrder.OrderHelper;
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
                consoleLogger.Info("\u001b[92m Welcome to the Headless Sample Console App! \u001b[39m");
                consoleLogger.Info("\u001b[93m This sample app demonstrates how to upload a sale transaction to the Commerce Scale Unit. \u001b[39m");
                CommerceClient client = new(InitFactory(), consoleLogger);
                await client.InitializeContext();
                var order = await client.UploadOrder(await FillOrder(client));
                order.DisplaySalesTransaction(consoleLogger);
                consoleLogger.Info($"Transaction {order.Id} has been uploaded successfully.");
            }
            catch (Exception ex)
            {
                consoleLogger.Error($"Error: {ex.Message}");
            }
            finally
            {
                consoleLogger.Info("Press any key to exit.");
                consoleLogger.ReadKey();
            }

        }


    }
}
