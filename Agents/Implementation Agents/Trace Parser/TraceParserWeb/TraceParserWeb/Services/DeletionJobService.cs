using System.Security.Claims;
using Microsoft.AspNetCore.Components.Authorization;
using TraceParser.Deletion;

namespace TraceParserWeb.Services;

public sealed class DeletionJobService(IDeletionJobStore store, AuthenticationStateProvider authentication,
    IConfiguration configuration)
{
    public bool Enabled => configuration.GetValue<bool>("DurableDeletion:WebEnabled");

    public (Guid Tenant, Guid Requester) RequireIdentity(ClaimsPrincipal user)
    {
        var tid = user.FindFirst("tid")?.Value
            ?? user.FindFirst("http://schemas.microsoft.com/identity/claims/tenantid")?.Value;
        var oid = user.FindFirst("oid")?.Value
            ?? user.FindFirst("http://schemas.microsoft.com/identity/claims/objectidentifier")?.Value;
        if (user.Identity?.IsAuthenticated != true
            || !Guid.TryParse(configuration["AzureAd:TenantId"], out var expected) || expected == Guid.Empty
            || !Guid.TryParse(tid, out var tenant) || tenant != expected
            || !Guid.TryParse(oid, out var requester) || requester == Guid.Empty)
            throw new UnauthorizedAccessException("Sign in with an identified account in the configured tenant.");
        if (!Enabled) throw new InvalidOperationException("Durable deletion is disabled.");
        return (tenant, requester);
    }

    public async Task<IReadOnlyList<DeletionJob>> ReadAsync(Guid? id = null, CancellationToken ct = default) =>
        await ReadAsync((await authentication.GetAuthenticationStateAsync()).User, id, ct);

    public Task<IReadOnlyList<DeletionJob>> ReadAsync(ClaimsPrincipal user, Guid? id, CancellationToken ct)
    {
        var (tenant, requester) = RequireIdentity(user);
        if (id == Guid.Empty) throw new ArgumentException("A valid job ID is required.");
        return store.ReadAsync(tenant, requester, id, ct);
    }

    public async Task<DeletionJob> EnqueueAsync(Guid key, int trace, CancellationToken ct = default) =>
        await EnqueueAsync((await authentication.GetAuthenticationStateAsync()).User, key, trace, ct);

    public Task<DeletionJob> EnqueueAsync(ClaimsPrincipal user, Guid key, int trace, CancellationToken ct)
    {
        var (tenant, requester) = RequireIdentity(user);
        if (key == Guid.Empty || trace <= 0) throw new ArgumentException("A request key and positive trace ID are required.");
        return store.EnqueueAsync(tenant, requester, key, trace, ct);
    }

    public async Task<DeletionJob> ControlAsync(Guid id, string action, CancellationToken ct = default) =>
        await ControlAsync((await authentication.GetAuthenticationStateAsync()).User, id, action, ct);

    public Task<DeletionJob> ControlAsync(ClaimsPrincipal user, Guid id, string action, CancellationToken ct)
    {
        var (tenant, requester) = RequireIdentity(user);
        if (id == Guid.Empty || action is not ("Cancel" or "Resume")) throw new ArgumentException("Invalid job action.");
        return store.ControlAsync(tenant, requester, id, action, ct);
    }
}
