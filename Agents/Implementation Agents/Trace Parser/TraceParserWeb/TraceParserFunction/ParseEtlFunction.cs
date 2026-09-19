using Azure.Storage.Blobs;
using Azure.Storage.Blobs.Models;
using Microsoft.Extensions.Logging;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Data.SqlClient;
using System.Security.Cryptography;

namespace TraceParserFunction;

public class ParseEtlFunction(EtlParser parser, SqlImporter importer, ILogger<ParseEtlFunction> logger)
{
    // Protect mutable parser services even if host concurrency is accidentally increased.
    // The SQL session lock is the authoritative cross-process/cross-instance ownership.
    private static readonly SemaphoreSlim WorkerGate = new(1, 1);

    [Function("ParseEtl")]
    public async Task RunAsync(
        [BlobTrigger("etl-uploads/{name}", Connection = "AzureWebJobsStorage")] BlobClient blob,
        string name, CancellationToken cancellationToken)
    {
        // Leave a bounded shutdown margin before the unchanged two-hour host timeout.
        using var budget = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        budget.CancelAfter(TimeSpan.FromMinutes(110));
        var ct = budget.Token;
        await WorkerGate.WaitAsync(ct);
        // App Service's package-mounted wwwroot can be read-only. HOME\data is writable.
        var localPath = Path.Combine(Environment.GetEnvironmentVariable("HOME") ?? AppContext.BaseDirectory,
            "data", "traceparser-imports", $"{Guid.NewGuid():N}.etl");
        SqlConnection? conn = null;
        try
        {
            var properties = (await blob.GetPropertiesAsync(cancellationToken: ct)).Value;
            var cs = new SqlConnectionStringBuilder(
                Environment.GetEnvironmentVariable("AZURE_SQL_CONNECTION_STRING")
                ?? throw new InvalidOperationException("AZURE_SQL_CONNECTION_STRING not set"))
            {
                // A reconnected SQL session has lost its ownership locks. Never reconnect
                // transparently or return a session with application locks to the pool.
                ConnectRetryCount = 0, Pooling = false, Encrypt = true,
                TrustServerCertificate = false, PersistSecurityInfo = false
            };
            conn = new SqlConnection(cs.ConnectionString);
            await conn.OpenAsync(ct);
            await ProcessRegisteredBlobAsync(blob, name, properties, conn, localPath, ct);
        }
        catch (SqlException ex) when (ex.Number is 51104 or 51105)
        {
            // Explicitly held, never claimed/imported. Host retry/poison handling must not
            // mistake this for a completed import; blob and legacy SQL data remain intact.
            var sourceHash=Convert.ToHexString(SHA256.HashData(System.Text.Encoding.UTF8.GetBytes(name)));
            logger.LogError("Import HELD for explicit review. SourceHash={SourceHash}, Code={Code}; no trace was created for this delivery.",
                sourceHash, ex.Number);
            throw;
        }
        catch
        {
            if (conn is not null)
            {
                try { await importer.RecordFailureAsync(conn); }
                catch (Exception ex) { logger.LogWarning("Failure status not recorded: {Type}", ex.GetType().Name); }
            }
            throw;
        }
        finally
        {
            if (conn is not null) await conn.DisposeAsync();
            try { if (File.Exists(localPath)) File.Delete(localPath); }
            finally { WorkerGate.Release(); }
        }
    }

    internal async Task ProcessRegisteredBlobAsync(BlobClient blob, string name, BlobProperties properties,
        SqlConnection conn, string localPath, CancellationToken ct)
    {
        ImportReceipt receipt;
        try
        {
            receipt = await importer.BeginImportAsync(conn, blob.AccountName, blob.BlobContainerName,
                name, properties.ETag.ToString(), ct, contentLength: properties.ContentLength);
        }
        catch (SqlException ex) when (ex.Number == 51127)
        {
            // SQL has durably rejected this version. Acknowledge the delivery,
            // not an import completion; retries must not download or parse it.
            logger.LogWarning("Import RejectedOversize: {Bytes} bytes exceeds {Limit}. Blob and receipt retained. SourceHash={SourceHash}",
                properties.ContentLength, TraceParser.Shared.ImportFilePolicy.MaxFileSizeBytes,
                Convert.ToHexString(SHA256.HashData(System.Text.Encoding.UTF8.GetBytes(name))));
            return;
        }
        logger.LogInformation("ImportId={ImportId}, TraceId={TraceId}, Phase={Phase}",
            receipt.ImportId, receipt.TraceId, receipt.Phase);
        if (receipt.IsTerminal)
        {
            await importer.CleanupCompletedAsync(conn);
            return;
        }
        // Defense in depth: a mismatched SQL deployment must never allow an
        // oversized download even if it erroneously returns a parsing receipt.
        TraceParser.Shared.ImportFilePolicy.ValidateLength(properties.ContentLength);
        if (receipt.Phase == "Parsing")
        {
            Directory.CreateDirectory(Path.GetDirectoryName(localPath)!);
            await blob.DownloadToAsync(localPath, new BlobDownloadToOptions
            {
                Conditions = new BlobRequestConditions { IfMatch = properties.ETag }
            }, ct);
            await using (var stream = File.OpenRead(localPath))
                await importer.SetContentHashAsync(conn, await SHA256.HashDataAsync(stream, ct));
            parser.Parse(localPath, receipt.TraceId, conn);
        }
        await importer.PromoteStageToTraceLines(conn);
        await importer.CompleteImportAsync(conn);
        logger.LogInformation("Import durably completed: ImportId={ImportId}, TraceId={TraceId}",
            receipt.ImportId, receipt.TraceId);
        await importer.CleanupCompletedAsync(conn);
    }
}
