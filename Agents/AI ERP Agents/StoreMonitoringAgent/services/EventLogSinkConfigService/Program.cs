/**
 * SAMPLE CODE NOTICE
 * 
 * THIS SAMPLE CODE IS MADE AVAILABLE AS IS.  MICROSOFT MAKES NO WARRANTIES, WHETHER EXPRESS OR IMPLIED,
 * OF FITNESS FOR A PARTICULAR PURPOSE, OF ACCURACY OR COMPLETENESS OF RESPONSES, OF RESULTS, OR CONDITIONS OF MERCHANTABILITY.
 * THE ENTIRE RISK OF THE USE OR THE RESULTS FROM THE USE OF THIS SAMPLE CODE REMAINS WITH THE USER.
 * NO TECHNICAL SUPPORT IS PROVIDED.  YOU MAY NOT DISTRIBUTE THIS CODE UNLESS YOU HAVE A LICENSE AGREEMENT WITH MICROSOFT THAT ALLOWS YOU TO DO SO.
 */
namespace EventLogSinkConfigService;

public class Program
{
    public static void Main(string[] args)
    {
        var builder = Host.CreateApplicationBuilder(args);

        // Configure Windows Service
        builder.Services.AddWindowsService(options =>
        {
            options.ServiceName = "EventLogSinkConfigService";
        });

        // Configure EventLog logging with proper source name
        builder.Logging.AddEventLog(settings =>
        {
            settings.SourceName = "EventLogSinkConfigService";
            settings.LogName = "Application";
        });

        // Add the worker service
        builder.Services.AddHostedService<EventLogSinkConfigWorker>();

        var host = builder.Build();
        host.Run();
    }
}
