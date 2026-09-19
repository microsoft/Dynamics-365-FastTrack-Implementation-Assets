using Microsoft.AspNetCore.Components.Authorization;
using Microsoft.Extensions.Options;

namespace TraceParserWeb.Services;

public class TraceDeletionService(
    ITraceDeletionStore store,
    AuthenticationStateProvider authenticationState,
    IOptions<TraceAdministrationOptions> options,
    IConfiguration configuration,
    ILogger<TraceDeletionService> logger)
{
    public bool IsConfigured => !string.IsNullOrWhiteSpace(options.Value.SqlConnectionString);

    public async Task DeleteTraceAsync(int traceId, CancellationToken ct = default)
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
        cts.CancelAfter(TimeSpan.FromMinutes(5));
        try
        {
            while (true)
            {
                cts.Token.ThrowIfCancellationRequested();
                if (!await store.DeleteBatchAsync(traceId, cts.Token))
                    break;
            }
        }
        catch (OperationCanceledException) when (!ct.IsCancellationRequested && cts.IsCancellationRequested)
        {
            throw new TimeoutException("Deletion timed out and may be partial. Refresh the trace list and retry.");
        }

        logger.LogInformation("Deleted trace {TraceId} for a signed-in user in the configured tenant", traceId);
    }
}
