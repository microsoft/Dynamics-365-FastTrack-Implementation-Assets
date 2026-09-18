using Azure.Storage.Blobs;
using Azure.Storage.Blobs.Models;
using Azure.Storage.Sas;
using Microsoft.AspNetCore.Components.Forms;
using Microsoft.Extensions.Options;
using System.Text.Json;

namespace TraceParserWeb.Services;

public enum ImportStage
{
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
    ILogger<EtlUploadService> logger)
{
    /// <summary>
    /// Uploads an ETL file to Azure Blob Storage under {sessionName}/{fileName}.
    /// Returns the blob name.
    /// </summary>
    public async Task<string> UploadAsync(IBrowserFile file, string sessionName,
                                          IProgress<long>? progress = null,
                                          CancellationToken ct = default)
    {
        var blobName = $"{sessionName}/{Path.GetFileName(file.Name)}";
        var container = new BlobContainerClient(opts.Value.StorageConnectionString,
                                                opts.Value.ContainerName);
        await container.CreateIfNotExistsAsync(cancellationToken: ct);
        using var raw = file.OpenReadStream(maxAllowedSize: 1_073_741_824L, ct); // 1 GB
        Stream stream = progress != null ? new ProgressStream(raw, file.Size, progress) : raw;
        await container.GetBlobClient(blobName)
                       .UploadAsync(stream, overwrite: true, cancellationToken: ct);
        return blobName;
    }

    /// <summary>
    /// Generates a short-lived SAS URL for direct browser-to-blob upload.
    /// </summary>
    public string GenerateSasUrl(string sessionName, string fileName)
    {
        var blobName = $"{sessionName}/{Path.GetFileName(fileName)}";
        var serviceClient = new BlobServiceClient(opts.Value.StorageConnectionString);
        var blobClient = serviceClient
            .GetBlobContainerClient(opts.Value.ContainerName)
            .GetBlobClient(blobName);

        var sasBuilder = new BlobSasBuilder
        {
            BlobContainerName = opts.Value.ContainerName,
            BlobName = blobName,
            Resource = "b",
            ExpiresOn = DateTimeOffset.UtcNow.AddHours(2),
        };
        sasBuilder.SetPermissions(BlobSasPermissions.Create | BlobSasPermissions.Write);
        return blobClient.GenerateSasUri(sasBuilder).ToString();
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
