using Microsoft.Extensions.Logging;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Data.SqlClient;

namespace TraceParserFunction;

public class ParseEtlFunction(EtlParser parser, SqlImporter importer,
                               ILogger<ParseEtlFunction> logger)
{
    [Function("ParseEtl")]
    public async Task RunAsync(
        [BlobTrigger("etl-uploads/{name}", Connection = "AzureWebJobsStorage")] Stream blobStream,
        string name)
    {
        logger.LogInformation("ParseEtl triggered. Blob: {Name}", name);

        var tempFile = Path.Combine(Path.GetTempPath(), $"{Guid.NewGuid()}.etl");
        try
        {
            // ETWTraceEventSource requires a file path — download blob to temp file
            logger.LogInformation("Downloading blob to temp file: {TempFile}", tempFile);
            using (var fs = File.Create(tempFile))
                await blobStream.CopyToAsync(fs);

            var fileInfo = new FileInfo(tempFile);
            logger.LogInformation("Blob downloaded. Size: {SizeMB} MB", fileInfo.Length / 1_048_576);

            // Derive session name from blob path: "sessionName/fileName.etl" → "sessionName"
            var sessionName = name.Contains('/') ? name[..name.LastIndexOf('/')] : Path.GetFileNameWithoutExtension(name);
            sessionName = sessionName.Replace("/", "_").Replace("\\", "_");

            var connStr = Environment.GetEnvironmentVariable("AZURE_SQL_CONNECTION_STRING")
                ?? throw new InvalidOperationException("AZURE_SQL_CONNECTION_STRING not set");

            using var conn = new SqlConnection(connStr);
            await conn.OpenAsync();

            // Create Traces row
            var traceId = await importer.EnsureTraceAsync(conn, sessionName, name);
            logger.LogInformation("TraceId={TraceId} created for session '{Session}'", traceId, sessionName);

            // Parse ETL and insert staging rows
            var stats = parser.Parse(tempFile, traceId, conn);
            await importer.UpdateTraceTimestampsAsync(conn, traceId, stats.MinFileTimeUtc, stats.MaxFileTimeUtc);
            logger.LogInformation("Parsed {Staged} rows. Enter={Enter} SQL={Stmt} Bind={Bind} Fetch={Fetch} Msg={Msg}",
                stats.Staged, stats.Enter, stats.Stmt, stats.Bind, stats.Fetch, stats.Msg);

            // Promote staging → TraceLines (direct INSERT with IDENTITY_INSERT, index disable/rebuild)
            logger.LogInformation("Promoting StageTraceLines → TraceLines for TraceId={TraceId}...", traceId);
            await importer.PromoteStageToTraceLines(conn);

            // Insert bind parameters (requires TraceLines to exist for FK)
            await importer.InsertBindParamsAsync(conn, traceId);

            // Pre-compute aggregation tables for fast Copilot queries
            logger.LogInformation("Populating session aggregations for TraceId={TraceId}...", traceId);
            await importer.PopulateSessionAggregationsAsync(conn, traceId);

            logger.LogInformation("Import complete. TraceId={TraceId} Session='{Session}' Staged={Staged}",
                traceId, sessionName, stats.Staged);
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "ParseEtl failed for blob '{Name}'", name);
            throw; // Let Functions retry/dead-letter
        }
        finally
        {
            if (File.Exists(tempFile))
            {
                File.Delete(tempFile);
                logger.LogInformation("Temp file deleted: {TempFile}", tempFile);
            }
        }
    }
}
