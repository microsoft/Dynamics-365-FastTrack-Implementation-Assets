using Azure.Storage.Blobs;
using Azure.Storage.Blobs.Models;
using Azure.Storage.Sas;
using Microsoft.AspNetCore.Components.Forms;
using Microsoft.Extensions.Options;
using System.Text.Json;

namespace TraceParserWeb.Services;

public enum ImportStage
{
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

public class EtlUploadService(IOptions<EtlImportOptions> opts, IHttpClientFactory httpFactory)
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
            var http = httpFactory.CreateClient("dab");

            // Step 1: Find the trace
            var url = $"/api/Traces?$filter=TraceName eq '{Uri.EscapeDataString(sessionName)}'";
            var resp = await http.GetFromJsonAsync<JsonElement>(url, ct);
            if (!resp.TryGetProperty("value", out var arr) || arr.GetArrayLength() == 0)
                return new ImportStatus { Stage = ImportStage.WaitingForFunction };

            var traceId = arr[0].GetProperty("TraceId").GetInt32();

            // Step 2: Check threads exist (created during BulkInsertDimensions, after staging)
            var threadUrl = $"/api/UserSessionProcessThreads?$filter=TraceId eq {traceId}&$top=1";
            var threadResp = await http.GetFromJsonAsync<JsonElement>(threadUrl, ct);
            if (!threadResp.TryGetProperty("value", out var threadArr) || threadArr.GetArrayLength() == 0)
                return new ImportStatus { Stage = ImportStage.Parsing, TraceId = traceId };

            // Step 3: Verify TraceLines exist (the final promote step)
            var threadId = threadArr[0].GetProperty("UserSessionProcessThreadId").GetInt32();
            var tlUrl = $"/api/TraceLines?$filter=UserSessionProcessThreadId eq {threadId}&$top=1";
            var tlResp = await http.GetFromJsonAsync<JsonElement>(tlUrl, ct);
            if (!tlResp.TryGetProperty("value", out var tlArr) || tlArr.GetArrayLength() == 0)
                return new ImportStatus { Stage = ImportStage.ProcessingDimensions, TraceId = traceId };

            // Step 4: Check SessionMetrics exist (aggregation complete)
            var smUrl = $"/api/SessionMetrics?$filter=TraceId eq {traceId}&$top=1";
            var smResp = await http.GetFromJsonAsync<JsonElement>(smUrl, ct);
            if (!smResp.TryGetProperty("value", out var smArr) || smArr.GetArrayLength() == 0)
                return new ImportStatus { Stage = ImportStage.Finalizing, TraceId = traceId };

            return new ImportStatus { Stage = ImportStage.Complete, TraceId = traceId };
        }
        catch
        {
            return new ImportStatus { Stage = ImportStage.WaitingForFunction };
        }
    }

    public async Task<bool> IsImportCompleteAsync(string sessionName, CancellationToken ct)
    {
        var status = await GetImportStatusAsync(sessionName, ct);
        return status.Stage == ImportStage.Complete;
    }
}
