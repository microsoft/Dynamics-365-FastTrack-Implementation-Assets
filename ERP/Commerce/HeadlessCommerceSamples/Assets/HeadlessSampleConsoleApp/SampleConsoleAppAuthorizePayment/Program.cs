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
    using SampleConsoleApp.Common;
    using System;
    using static SampleConsoleAppAuthorizePayment.PageHelper;

    internal sealed class Program
    {
#pragma warning disable IDE0060 // Remove unused parameter
        internal static async Task Main(string[] args)
#pragma warning restore IDE0060 // Remove unused parameter
        {
            ConsoleLogger consoleLogger = new();

            //Authorize sample payment.
            HandlePaymentAuthorization();
            
            //End of execution flow.
            Console.WriteLine("Press any key to exit.");
            Console.ReadKey();
        }
    }
}
