using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging.Abstractions;
using TraceParserFunction;

internal static class DeletionTimerChecks
{
    public static async Task<int> RunAsync()
    {
        var config = new ConfigurationBuilder().AddInMemoryCollection(new Dictionary<string, string?>
        {
            ["SqlConnectionString"] = "SYNTHETIC-IMPORTER-CONNECTION-MUST-NOT-BE-USED"
        }).Build();
        var function = new DeleteTraceJobsFunction(config, NullLogger<DeleteTraceJobsFunction>.Instance);
        await function.Run(new TimerInfo(), CancellationToken.None);
        config["DurableDeletion:WorkerEnabled"] = "true";
        try
        {
            await function.Run(new TimerInfo(), CancellationToken.None);
            throw new Exception("Worker fell back to importer credentials.");
        }
        catch (InvalidOperationException ex) when (ex.Message.Contains("dedicated")) { }
        var trigger = typeof(DeleteTraceJobsFunction).GetMethod("Run")!.GetParameters()[0]
            .GetCustomAttributes(typeof(TimerTriggerAttribute), false).Cast<TimerTriggerAttribute>().Single();
        if (trigger.Schedule != "0 * * * * *" || trigger.RunOnStartup || !trigger.UseMonitor)
            throw new Exception("Unbounded or unmonitored deletion timer schedule.");
        return 3;
    }
}
