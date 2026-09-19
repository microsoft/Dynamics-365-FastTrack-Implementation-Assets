using Microsoft.AspNetCore.Components.Authorization;
using Microsoft.Extensions.Options;
using Microsoft.Data.SqlClient;

namespace TraceParserWeb.Services;

public class TraceDeletionService(
    ITraceDeletionStore store,
    AuthenticationStateProvider authenticationState,
    IOptions<TraceAdministrationOptions> options,
    IConfiguration configuration,
    ILogger<TraceDeletionService> logger)
{
    public bool IsConfigured => !string.IsNullOrWhiteSpace(options.Value.SqlConnectionString);
    internal TimeSpan OperationTimeout { get; init; } = TimeSpan.FromMinutes(5);

    public async Task DeleteTraceAsync(int traceId, CancellationToken ct = default,
        Func<TraceDeletionProgress, Task>? progress = null)
    {
        ArgumentOutOfRangeException.ThrowIfNegativeOrZero(traceId);
        ct.ThrowIfCancellationRequested();

        var user = (await authenticationState.GetAuthenticationStateAsync()).User;
        var tenantClaim = user.FindFirst("tid")?.Value
            ?? user.FindFirst("http://schemas.microsoft.com/identity/claims/tenantid")?.Value;
        if (user.Identity?.IsAuthenticated != true
            || !Guid.TryParse(configuration["AzureAd:TenantId"], out var configuredTenant)
            || configuredTenant == Guid.Empty
            || !Guid.TryParse(tenantClaim, out var userTenant)
            || userTenant != configuredTenant)
        {
            logger.LogWarning("Denied trace deletion for a user outside the configured tenant");
            throw new UnauthorizedAccessException("Sign in to the configured tenant to delete traces.");
        }
        if (!IsConfigured)
            throw new InvalidOperationException("Authenticated trace deletion has not been configured.");

        using var cts = CancellationTokenSource.CreateLinkedTokenSource(ct);
        cts.CancelAfter(OperationTimeout);
        var batches = 0;
        long confirmedRows = 0;
        var allRowsKnown = true;
        try
        {
            while (true)
            {
                cts.Token.ThrowIfCancellationRequested();
                var batch = await store.DeleteBatchAsync(traceId, cts.Token);
                batches++;
                if (batch.RowsDeleted is int rows) confirmedRows += rows;
                else allRowsKnown = false;
                if (progress is not null)
                    await progress(new(batches, confirmedRows, allRowsKnown, batch.Phase, !batch.HasMore));
                if (!batch.HasMore)
                    break;
            }
        }
        catch (Exception ex) when (cts.IsCancellationRequested && IsCancellation(ex))
        {
            if (ct.IsCancellationRequested)
                throw new OperationCanceledException(
                    "Deletion cancelled and may be partial. Committed batches remain deleted. Refresh and retry to finish.", ex, ct);
            throw new TimeoutException(
                "Deletion timed out and may be partial. Committed batches remain deleted. Refresh and retry to finish.", ex);
        }
        catch (SqlException ex) when (ex.Number == 51131)
        {
            throw new InvalidOperationException(
                "This import is active or awaiting retry. Deletion is blocked until durable import completion.", ex);
        }
        catch (SqlException ex) when (ex.Number == 51130)
        {
            throw new InvalidOperationException(
                "This trace is busy with an import or another deletion batch. Refresh and retry later.", ex);
        }

        logger.LogInformation("Deleted trace {TraceId} for a signed-in user in the configured tenant", traceId);
    }

    internal static bool IsCancellation(Exception ex) => ex is OperationCanceledException
        || ex is SqlException sql && sql.Errors.Count > 0
            && sql.Errors.Cast<SqlError>().All(error => error.Number == -2
                || error.Number == 0 && error.Class == 11);
}

public sealed record TraceDeletionProgress(int Batches, long ConfirmedRowsDeleted, bool AllRowsKnown,
    string? Phase, bool Complete);
