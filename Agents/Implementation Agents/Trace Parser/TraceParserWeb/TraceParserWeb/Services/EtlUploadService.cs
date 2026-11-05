using Azure.Storage.Blobs;
using Azure.Storage.Blobs.Models;
using Microsoft.AspNetCore.Components.Forms;
using Microsoft.Extensions.Options;
using System.Text.Json;

namespace TraceParserWeb.Services;

public enum ImportStage
{
    RejectedOversize = -6,
    Deleting = -5,
    LegacyUntracked = -4,
    Deleted = -3,
    RetryableFailure = -2,
    Unavailable = -1,
    WaitingForFunction,
    Parsing,
    ProcessingDimensions,
    Finalizing,
    Complete
}

public class ImportStatus
{
    public ImportStage Stage { get; set; }
    public int? TraceId { get; set; }
}

public class EtlImportOptions
{
    public string StorageConnectionString { get; set; } = "";
    public string ContainerName { get; set; } = "etl-uploads";
    public string DabBaseUrl { get; set; } = "";
}

public class EtlUploadService(
    IOptions<EtlImportOptions> opts,
    IHttpClientFactory httpFactory,
    TraceService traceService,
    ILogger<EtlUploadService> logger,
    RegisteredImportService? registrations = null)
{
    public Task<RegisteredUpload> RegisterAsync(string sessionName, string fileName, CancellationToken ct = default)
        => (registrations ?? throw new InvalidOperationException("Registered uploads are unavailable."))
            .RegisterAsync(sessionName, fileName, ct);

    public async Task<ImportStatus> GetImportStatusAsync(Guid importId, CancellationToken ct)
        => RegisteredImportService.ToDisplay(await
            (registrations ?? throw new InvalidOperationException("Registered import status is unavailable."))
            .GetAsync(importId, ct));
    /// <summary>
    /// Uploads an ETL file to Azure Blob Storage under {sessionName}/{fileName}.
    /// Returns the blob name.
    /// </summary>
    public async Task<string> UploadAsync(IBrowserFile file, string sessionName,
                                          IProgress<long>? progress = null,
                                          CancellationToken ct = default)
    {
        TraceParser.Shared.ImportFilePolicy.ValidateLength(file.Size);
        var upload = await RegisterAsync(sessionName, file.Name, ct);
        using var raw = file.OpenReadStream(maxAllowedSize: TraceParser.Shared.ImportFilePolicy.MaxFileSizeBytes, ct);
        Stream stream = progress != null ? new ProgressStream(raw, file.Size, progress) : raw;
        var blobName = new BlobUriBuilder(new Uri(upload.SasUrl)).BlobName;
        await new BlobClient(opts.Value.StorageConnectionString, opts.Value.ContainerName, blobName)
            .UploadAsync(stream, overwrite: false, cancellationToken: ct);
        return upload.ImportId.ToString("D");
    }

    /// <summary>
    /// Generates a short-lived SAS URL for direct browser-to-blob upload.
    /// </summary>
    public string GenerateSasUrl(string sessionName, string fileName)
    {
        throw new InvalidOperationException("Unregistered upload URLs are disabled. Register a fresh upload first.");
    }

    /// <summary>
    /// Polls DAB to determine the current import stage.
    /// Checks DB milestones: Trace → USPT → TraceLines → SessionMetrics.
    /// </summary>
    public async Task<ImportStatus> GetImportStatusAsync(string sessionName, CancellationToken ct)
    {
        try
        {
            using var cts = CancellationTokenSource.CreateLinkedTokenSource(ct);
            cts.CancelAfter(TimeSpan.FromSeconds(10));
            using var http = httpFactory.CreateClient("dab");

            // Step 1: Find the trace
            var escapedName = Uri.EscapeDataString(sessionName.Replace("'", "''"));
            var url = $"/api/Traces?$filter=TraceName eq '{escapedName}'&$first=1&$select=TraceId";
            var resp = await http.GetFromJsonAsync<JsonElement>(url, cts.Token);
            var arr = TraceService.ReadRows(resp);
            if (arr.GetArrayLength() == 0)
                return new ImportStatus { Stage = ImportStage.WaitingForFunction };

            var traceId = TraceService.ReadId(arr[0], "TraceId");
            return new ImportStatus {
                Stage = await traceService.GetImportStageAsync(traceId, cts.Token),
                TraceId = traceId
            };
        }
        catch (Exception ex) when (ex is HttpRequestException or JsonException or OperationCanceledException)
        {
            ct.ThrowIfCancellationRequested();
            logger.LogWarning(ex, "Import status lookup unavailable");
            return new ImportStatus { Stage = ImportStage.Unavailable };
        }
    }

    public async Task<bool> IsImportCompleteAsync(string sessionName, CancellationToken ct)
    {
        var status = await GetImportStatusAsync(sessionName, ct);
        return status.Stage == ImportStage.Complete;
    }
}
