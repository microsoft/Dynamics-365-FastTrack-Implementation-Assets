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
    public interface ILogger
    {
        void Log(LogStatus status,string message);
        void Print();
        void Info(string message);
        void Actions(string message);
        void Error(string message);
        string GetUserTextInput(string message);
        void Success(string message);
        void ReadKey();

    }
    public enum LogStatus
    {
        Error,
        Info

    }

    public class LogMessage(LogStatus status, string message)
    {
        public LogStatus Status { get; set; } = status;
        public string Message { get; set; } = message;
    }
}
