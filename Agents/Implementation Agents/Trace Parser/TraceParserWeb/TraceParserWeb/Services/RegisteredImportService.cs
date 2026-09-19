using System.Data;
using System.Security.Claims;
using Azure.Storage.Blobs;
using Azure.Storage.Sas;
using Microsoft.AspNetCore.Components.Authorization;
using Microsoft.Data.SqlClient;
using Microsoft.Extensions.Options;

namespace TraceParserWeb.Services;

public sealed record RegisteredUpload(Guid ImportId, string SasUrl, string FileName);
public sealed record DurableImportStatus(Guid ImportId, int? TraceId, string Phase, bool RetryableFailure);

public interface IRegisteredImportStore
{
    Task RegisterAsync(Guid id, string account, string container, string blobName, string session, CancellationToken ct);
    Task<DurableImportStatus?> ReadAsync(Guid? importId, int? traceId, CancellationToken ct);
}

public sealed class SqlRegisteredImportStore(IOptions<TraceAdministrationOptions> options) : IRegisteredImportStore
{
    private SqlConnection Connection()
    {
        if (string.IsNullOrWhiteSpace(options.Value.SqlConnectionString))
            throw new InvalidOperationException("Registered imports have not been configured.");
        return new SqlConnection(new SqlConnectionStringBuilder(options.Value.SqlConnectionString)
        {
            Encrypt = true, TrustServerCertificate = false, PersistSecurityInfo = false
        }.ConnectionString);
    }

    public async Task RegisterAsync(Guid id, string account, string container, string blobName, string session, CancellationToken ct)
    {
        await using var conn = Connection();
        await conn.OpenAsync(ct);
        using var cmd = conn.CreateCommand();
        cmd.CommandType = CommandType.StoredProcedure;
        cmd.CommandText = "dbo.tp_RegisterUpload";
        cmd.Parameters.Add("@ImportId", SqlDbType.UniqueIdentifier).Value = id;
        cmd.Parameters.Add("@AccountName", SqlDbType.NVarChar, 128).Value = account;
        cmd.Parameters.Add("@ContainerName", SqlDbType.NVarChar, 63).Value = container;
        cmd.Parameters.Add("@BlobName", SqlDbType.NVarChar, 1024).Value = blobName;
        cmd.Parameters.Add("@SessionName", SqlDbType.NVarChar, 500).Value = session;
        await cmd.ExecuteNonQueryAsync(ct);
    }

    public async Task<DurableImportStatus?> ReadAsync(Guid? importId, int? traceId, CancellationToken ct)
    {
        await using var conn = Connection();
        await conn.OpenAsync(ct);
        using var cmd = conn.CreateCommand();
        cmd.CommandType = CommandType.StoredProcedure;
        cmd.CommandText = "dbo.tp_GetImportStatus";
        cmd.CommandTimeout = 10;
        cmd.Parameters.Add("@ImportId", SqlDbType.UniqueIdentifier).Value = (object?)importId ?? DBNull.Value;
        cmd.Parameters.Add("@TraceId", SqlDbType.Int).Value = (object?)traceId ?? DBNull.Value;
        using var reader = await cmd.ExecuteReaderAsync(ct);
        if (!await reader.ReadAsync(ct)) return null;
        return new(reader.GetGuid(0), reader.IsDBNull(1) ? null : reader.GetInt32(1),
            reader.GetString(2), reader.GetBoolean(3));
    }
}

public sealed class RegisteredImportService(
    IRegisteredImportStore store,
    AuthenticationStateProvider authentication,
    IConfiguration configuration,
    IOptions<EtlImportOptions> options)
{
    public async Task<RegisteredUpload> RegisterAsync(string session, string fileName, CancellationToken ct = default)
        => await RegisterAsync((await authentication.GetAuthenticationStateAsync()).User, session, fileName, ct);

    public async Task<RegisteredUpload> RegisterAsync(ClaimsPrincipal user, string session, string fileName, CancellationToken ct)
    {
        RequireTenant(user);
        ct.ThrowIfCancellationRequested();
        ArgumentNullException.ThrowIfNull(session);
        ArgumentNullException.ThrowIfNull(fileName);
        session = session.Trim();
        fileName = fileName.Replace('\\', '/').Split('/')[^1];
        if (session.Length is < 1 or > 500 || session.Any(char.IsControl)
            || fileName.Length is < 5 or > 255 || fileName.Any(char.IsControl)
            || !fileName.EndsWith(".etl", StringComparison.OrdinalIgnoreCase))
            throw new ArgumentException("A session name (1–500 characters) and an ETL filename are required.");
        var id = Guid.NewGuid();
        // Logical re-uploads retain the displayed filename but get a fresh, write-once path.
        // No historic path can accidentally satisfy a new registration.
        var blobName = $"_imports/{id:D}/{fileName}";
        var service = new BlobServiceClient(options.Value.StorageConnectionString);
        var blob = service.GetBlobContainerClient(options.Value.ContainerName).GetBlobClient(blobName);
        if (blob.Uri.Scheme != Uri.UriSchemeHttps)
            throw new InvalidOperationException("Registered uploads require HTTPS storage.");
        if (!blob.CanGenerateSasUri)
            throw new InvalidOperationException("Server-side upload signing is not configured.");
        await store.RegisterAsync(id, blob.AccountName, blob.BlobContainerName, blobName, session, ct);
        var sas = new BlobSasBuilder
        {
            BlobContainerName = blob.BlobContainerName, BlobName = blobName, Resource = "b",
            Protocol = SasProtocol.Https, ExpiresOn = DateTimeOffset.UtcNow.AddHours(2)
        };
        // Single Put Blob only. No overwrite/read/list/delete permissions.
        sas.SetPermissions(BlobSasPermissions.Create);
        return new(id, blob.GenerateSasUri(sas).ToString(), fileName);
    }

    public async Task<DurableImportStatus> GetAsync(Guid importId, CancellationToken ct)
        => await GetAsync((await authentication.GetAuthenticationStateAsync()).User, importId, ct);

    public async Task<DurableImportStatus> GetAsync(ClaimsPrincipal user, Guid importId, CancellationToken ct)
    {
        RequireTenant(user);
        if (importId == Guid.Empty) throw new ArgumentException("An import receipt is required.");
        return await store.ReadAsync(importId, null, ct)
            ?? new(importId, null, "LegacyUntracked", false);
    }

    public async Task<DurableImportStatus?> GetTraceAsync(int traceId, CancellationToken ct)
    {
        RequireTenant((await authentication.GetAuthenticationStateAsync()).User);
        ArgumentOutOfRangeException.ThrowIfNegativeOrZero(traceId);
        return await store.ReadAsync(null, traceId, ct);
    }

    public void RequireTenant(ClaimsPrincipal user)
    {
        var claim = user.FindFirst("tid")?.Value
            ?? user.FindFirst("http://schemas.microsoft.com/identity/claims/tenantid")?.Value;
        if (user.Identity?.IsAuthenticated != true
            || !Guid.TryParse(configuration["AzureAd:TenantId"], out var expected) || expected == Guid.Empty
            || !Guid.TryParse(claim, out var actual) || actual != expected)
            throw new UnauthorizedAccessException("Sign in to the configured tenant to register or inspect imports.");
    }

    public static ImportStatus ToDisplay(DurableImportStatus status) => new()
    {
        TraceId = status.TraceId,
        Stage = status.Phase == "RejectedOversize" ? ImportStage.RejectedOversize
            : status.RetryableFailure ? ImportStage.RetryableFailure : status.Phase switch
        {
            "Registered" => ImportStage.WaitingForFunction,
            "Parsing" => ImportStage.Parsing,
            "Ready" or "Promoting" or "Binding" => ImportStage.ProcessingDimensions,
            "Finalizing" => ImportStage.Finalizing,
            "Complete" => ImportStage.Complete,
            "Deleted" => ImportStage.Deleted,
            "Deleting" => ImportStage.Deleting,
            _ => ImportStage.LegacyUntracked
        }
    };
}
