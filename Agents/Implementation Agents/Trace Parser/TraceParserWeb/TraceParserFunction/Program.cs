using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using TraceParserFunction;

var host = new HostBuilder()
    .ConfigureFunctionsWorkerDefaults()
    .ConfigureServices(s =>
    {
        s.AddSingleton<EtlParser>();
        s.AddSingleton<SqlImporter>();
    })
    .Build();

await host.RunAsync();
