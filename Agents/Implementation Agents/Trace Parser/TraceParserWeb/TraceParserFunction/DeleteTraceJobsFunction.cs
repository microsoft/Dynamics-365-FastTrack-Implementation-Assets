using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;
using TraceParser.Deletion;

namespace TraceParserFunction;

public sealed class DeleteTraceJobsFunction(IConfiguration configuration, ILogger<DeleteTraceJobsFunction> logger)
{
    [Function("DeleteTraceJobs")]
    public async Task Run([TimerTrigger("0 * * * * *", UseMonitor = true, RunOnStartup = false)] TimerInfo timer,
        CancellationToken cancellationToken)
    {
        if (!bool.TryParse(configuration["DurableDeletion:WorkerEnabled"], out var enabled) || !enabled)
            return;
        var connection = configuration["DurableDeletion:WorkerSqlConnectionString"];
        if (string.IsNullOrWhiteSpace(connection))
            throw new InvalidOperationException("A dedicated least-privilege deletion worker SQL connection is required.");
        // Deliberately no fallback to the importer's connection or privileges.
        await new DeletionWorker(new SqlDeletionJobStore(connection), TimeProvider.System).RunSliceAsync(cancellationToken);
        logger.LogInformation("Durable deletion timer slice finished; next scheduled tick will check the SQL queue.");
    }
}
