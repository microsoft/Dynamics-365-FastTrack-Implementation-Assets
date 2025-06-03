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
    public class ConsoleLogger:ILogger
    {
        private readonly List<LogMessage> _logMessages = [];

        public void Log(LogStatus status, string message)
        {
            _logMessages.Add(new LogMessage(status,message));
        }


        public void Print()
        {
            foreach (var log in _logMessages)
            {
                if (log.Status == LogStatus.Error)
                    Error(log.Message);
                else
                    Console.WriteLine(log.Message);
            }
            _logMessages.Clear();
        }

        public void Info(string message)
        {
            Console.WriteLine(message);
        }

        public void Actions(string message)
        {
            Console.ForegroundColor = ConsoleColor.Magenta;
            Console.WriteLine();
            Console.WriteLine(message);
            Console.ResetColor();
        }

        public string GetUserTextInput(string message)
        {
            Console.WriteLine();
            Console.ForegroundColor = ConsoleColor.Yellow;
            Console.Write(message);
            Console.ResetColor();
            string input = Console.ReadLine();
            return input;
        }

        public void ReadKey()
        {
            Console.ReadKey();
        }

        public void Error(string message)
        {
            Console.ForegroundColor = ConsoleColor.Red;
            Console.WriteLine(message);
            Console.ResetColor();
        }

        public void Success(string message)
        {
            Console.ForegroundColor = ConsoleColor.Green;
            Console.WriteLine(message);
            Console.ResetColor();
        }
    }

}