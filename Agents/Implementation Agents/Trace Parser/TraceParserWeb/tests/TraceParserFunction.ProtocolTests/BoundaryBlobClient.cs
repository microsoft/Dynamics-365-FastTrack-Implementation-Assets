using Azure;
using Azure.Storage.Blobs;
using Azure.Storage.Blobs.Models;

// Protected SDK mock constructor: no credentials, pipeline, transport or network.
internal sealed class BoundaryBlobClient : BlobClient
{
    public override string AccountName => "account";
    public override string BlobContainerName => "etl-uploads";
    public int DownloadCalls { get; private set; }
    public bool DownloadWasPinned { get; private set; }

    public override Task<Response> DownloadToAsync(string path, BlobDownloadToOptions options,
        CancellationToken cancellationToken = default)
    {
        DownloadCalls++;
        DownloadWasPinned = options.Conditions.IfMatch == new ETag("\"size-v1\"");
        throw new BoundaryDownloadReachedException();
    }
}

internal sealed class BoundaryDownloadReachedException : Exception;
