using System.Security.Claims;
using System.Text.Json;
using Microsoft.AspNetCore.Components.Authorization;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Options;
using TraceParserWeb.Services;

const string tenant = "11111111-1111-1111-1111-111111111111";
const int traceId = 42;
var passed = 0;

ClaimsPrincipal User(string? tid = tenant, bool authenticated = true, bool mapped = false) =>
    new(new ClaimsIdentity(
        tid is null ? Array.Empty<Claim>() : new[] {
            new Claim(mapped ? "http://schemas.microsoft.com/identity/claims/tenantid" : "tid", tid) },
        authenticated ? "test-cookie" : null));

TraceDeletionService Service(ProbeStore store, ClaimsPrincipal user, bool configured = true, string configuredTenant = tenant) =>
    new(store, new ProbeAuthentication(user),
        Options.Create(new TraceAdministrationOptions {
            SqlConnectionString = configured ? "SYNTHETIC-NOT-A-CONNECTION-STRING" : "" }),
        new ConfigurationBuilder().AddInMemoryCollection(new Dictionary<string, string?> {
            ["AzureAd:TenantId"] = configuredTenant }).Build(),
        NullLogger<TraceDeletionService>.Instance);

void Assert(bool condition, string name)
{
    if (!condition) throw new Exception(name);
}

async Task Reject<T>(TraceDeletionService service, ProbeStore store, string name, int id = traceId,
    CancellationToken ct = default) where T : Exception
{
    var rejected = false;
    try { await service.DeleteTraceAsync(id, ct); }
    catch (T) { rejected = true; }
    Assert(rejected && store.Calls == 0, name);
    passed++;
}

foreach (var user in new[] { User(authenticated: false), User(tid: null), User("invalid"),
    User("22222222-2222-2222-2222-222222222222") })
{
    var store = new ProbeStore(false);
    await Reject<UnauthorizedAccessException>(Service(store, user), store, "Unauthorized user reached deletion");
}
foreach (var configuredTenant in new[] { "", "common", Guid.Empty.ToString() })
{
    var store = new ProbeStore(false);
    await Reject<UnauthorizedAccessException>(Service(store, User(), configuredTenant: configuredTenant),
        store, "Invalid configured tenant allowed deletion");
}
foreach (var id in new[] { 0, -1 })
{
    var store = new ProbeStore(false);
    await Reject<ArgumentOutOfRangeException>(Service(store, User()), store, "Invalid trace ID reached deletion", id);
}
{
    var store = new ProbeStore(false);
    var service = Service(store, User(), configured: false);
    Assert(!service.IsConfigured, "Missing configuration advertised deletion");
    await Reject<InvalidOperationException>(service, store, "Missing connection allowed deletion");
}
foreach (var mapped in new[] { false, true })
{
    var store = new ProbeStore(false);
    await Service(store, User(mapped: mapped)).DeleteTraceAsync(traceId);
    Assert(store.Calls == 1 && store.LastTraceId == traceId, "Ordinary tenant user could not delete");
    passed++;
}
{
    var store = new ProbeStore(true, true, false);
    await Service(store, User()).DeleteTraceAsync(traceId);
    Assert(store.Calls == 3 && store.LastTraceId == traceId, "Incremental deletion reported success early");
    passed++;
}
{
    var store = new ProbeStore(false) { Failure = new InvalidOperationException("Synthetic SQL failure") };
    var failed = false;
    try { await Service(store, User()).DeleteTraceAsync(traceId); }
    catch (InvalidOperationException ex) when (ex.Message == "Synthetic SQL failure") { failed = true; }
    Assert(failed && store.Calls == 1, "SQL failure was swallowed");
    passed++;
}
{
    using var cts = new CancellationTokenSource();
    cts.Cancel();
    var store = new ProbeStore(false);
    await Reject<OperationCanceledException>(Service(store, User()), store, "Cancellation reached SQL", ct: cts.Token);
}
{
    using var cts = new CancellationTokenSource();
    var store = new ProbeStore(true) { AfterCall = cts.Cancel };
    var cancelled = false;
    try { await Service(store, User()).DeleteTraceAsync(traceId, cts.Token); }
    catch (OperationCanceledException) { cancelled = true; }
    Assert(cancelled && store.Calls == 1, "Partial deletion ignored cancellation");
    passed++;
}

var configPath = Path.GetFullPath(Path.Combine(AppContext.BaseDirectory,
    "..", "..", "..", "..", "..", "..", "TraceParserMCP", "dab-config.json"));
using (var config = JsonDocument.Parse(File.ReadAllText(configPath)))
{
    var entities = config.RootElement.GetProperty("entities");
    Assert(!entities.TryGetProperty("DeleteTrace", out _), "DAB exposes deletion");
    var searches = new HashSet<string> { "SearchTracesByKeyword", "SearchSqlStatements", "SearchMethods", "SearchMessages" };
    foreach (var entity in entities.EnumerateObject())
    {
        var isSearch = searches.Contains(entity.Name);
        foreach (var permission in entity.Value.GetProperty("permissions").EnumerateArray())
        {
            Assert(permission.GetProperty("role").GetString() == "anonymous", "Analysis access unexpectedly changed");
            foreach (var action in permission.GetProperty("actions").EnumerateArray())
                Assert(action.GetProperty("action").GetString() == (isSearch ? "execute" : "read"),
                    $"Unexpected DAB operation on {entity.Name}");
        }
    }
    Assert(searches.All(name => entities.TryGetProperty(name, out _)), "An analysis procedure was removed");
    passed++;
}
passed += await ImportStatusChecks.RunAsync();
passed += await AgentDestinationChecks.RunAsync();
passed += await DeletionChecks.RunAsync();
Console.WriteLine($"{passed} regression checks passed.");
if (args.Contains("--sql-integration"))
    await DeletionSqlChecks.RunAsync();
if (args.Contains("--batch-selection"))
    await BatchSelectionChecks.RunAsync();

sealed class ProbeAuthentication(ClaimsPrincipal user) : AuthenticationStateProvider
{
    public override Task<AuthenticationState> GetAuthenticationStateAsync() =>
        Task.FromResult(new AuthenticationState(user));
}

sealed class ProbeStore(params bool[] remaining) : ITraceDeletionStore
{
    public int Calls { get; private set; }
    public int LastTraceId { get; private set; }
    public Exception? Failure { get; init; }
    public Action? AfterCall { get; init; }

    public Task<TraceDeletionBatch> DeleteBatchAsync(int traceId, CancellationToken ct)
    {
        ct.ThrowIfCancellationRequested();
        LastTraceId = traceId;
        Calls++;
        if (Failure is not null) throw Failure;
        if (Calls > remaining.Length) throw new Exception("Unexpected extra deletion batch");
        AfterCall?.Invoke();
        return Task.FromResult(new TraceDeletionBatch(remaining[Calls - 1]));
    }
}
