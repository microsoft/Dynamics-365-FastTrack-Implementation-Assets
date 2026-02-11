/**
 * SAMPLE CODE NOTICE
 * 
 * THIS SAMPLE CODE IS MADE AVAILABLE AS IS.  MICROSOFT MAKES NO WARRANTIES, WHETHER EXPRESS OR IMPLIED,
 * OF FITNESS FOR A PARTICULAR PURPOSE, OF ACCURACY OR COMPLETENESS OF RESPONSES, OF RESULTS, OR CONDITIONS OF MERCHANTABILITY.
 * THE ENTIRE RISK OF THE USE OR THE RESULTS FROM THE USE OF THIS SAMPLE CODE REMAINS WITH THE USER.
 * NO TECHNICAL SUPPORT IS PROVIDED.  YOU MAY NOT DISTRIBUTE THIS CODE UNLESS YOU HAVE A LICENSE AGREEMENT WITH MICROSOFT THAT ALLOWS YOU TO DO SO.
 */
using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using ProductPublisherApp;
using ProductPublisher.Core;
using ProductPublisher.Core.Interface;
using ProductPublisherApp.Helper;

var host = new HostBuilder()
    .ConfigureFunctionsWebApplication()
    .ConfigureServices((hostContext, services) =>
    {
        services.AddApplicationInsightsTelemetryWorkerService();
        services.ConfigureFunctionsApplicationInsights();
        services.AddSingleton<IPublisher>(provider =>
        {
            ICatalogPublisher catalogPublisher = new ProductCatalogPublisher();
            IChannelPublisher channelPublisher = new ChannelPublisher();
            SamplePublisher publisher = new(channelPublisher,catalogPublisher,
                EnvironmentHelper.GetEnvironmentVariable("OUN"),
                new Uri(EnvironmentHelper.GetEnvironmentVariable("CSUURL")),
                EnvironmentHelper.GetEnvironmentVariable("AUTHORITY"),
                EnvironmentHelper.GetEnvironmentVariable("CLIENTID"),
                EnvironmentHelper.GetEnvironmentVariable("CLIENTSECRET"),
                EnvironmentHelper.GetEnvironmentVariable("AUDIENCE"),
                EnvironmentHelper.GetEnvironmentVariable("TENANTID"),
                Convert.ToInt64(EnvironmentHelper.GetEnvironmentVariable("CATALOGID")),
                Convert.ToInt32(EnvironmentHelper.GetEnvironmentVariable("DEFAULTPAGESIZE")),
                Convert.ToBoolean(EnvironmentHelper.GetEnvironmentVariable("PUBLISHPRICES")));
            return publisher;
        });
    })
    .Build();

host.Run();

