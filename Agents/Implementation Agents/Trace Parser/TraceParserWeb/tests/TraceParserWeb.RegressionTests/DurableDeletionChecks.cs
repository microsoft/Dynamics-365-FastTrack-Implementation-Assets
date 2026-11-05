using System.Reflection;
using System.Security.Claims;
using Microsoft.AspNetCore.Components.Authorization;
using Microsoft.AspNetCore.Components.Rendering;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging.Abstractions;
using TraceParser.Deletion;
using TraceParserWeb.Services;
using TraceParserWeb.Components.Pages.Traces;

#pragma warning disable BL0006 // Existing console harness inspects component render frames.
internal static class DurableDeletionChecks
{
    const BindingFlags Members = BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic;
    static readonly Guid Tenant = Guid.NewGuid(), Requester = Guid.NewGuid();
    internal static DeletionJobService DisabledService() => Service(new Store(), User(), false);

    static ClaimsPrincipal User(Guid? tenant = null, Guid? requester = null, bool authenticated = true) =>
        new(new ClaimsIdentity([new Claim("tid", (tenant ?? Tenant).ToString()),
            new Claim("oid", (requester ?? Requester).ToString())], authenticated ? "synthetic" : null));

    static DeletionJobService Service(Store store, ClaimsPrincipal user, bool enabled = true) => new(store,
        new Authentication(user), new ConfigurationBuilder().AddInMemoryCollection(new Dictionary<string, string?>
        { ["AzureAd:TenantId"] = Tenant.ToString(), ["DurableDeletion:WebEnabled"] = enabled.ToString() }).Build());

    public static async Task<int> RunAsync()
    {
        var passed = 0;
        void Check(bool value, string message) { if (!value) throw new Exception(message); passed++; }
        foreach (var user in new[] { User(authenticated: false), User(Guid.NewGuid()), User(requester: Guid.Empty),
            new ClaimsPrincipal(new ClaimsIdentity([new Claim("tid", Tenant.ToString())], "synthetic")) })
        {
            var store = new Store();
            try { await Service(store, user).EnqueueAsync(Guid.NewGuid(), 1); throw new Exception("Authorization bypass"); }
            catch (UnauthorizedAccessException) { Check(store.Calls == 0, "Unauthorized request reached job store"); }
        }
        var jobs = new Store();
        var service = Service(jobs, User());
        var queued = await service.EnqueueAsync(Guid.NewGuid(), 1);
        Check(jobs.Tenant == Tenant && jobs.Requester == Requester, "Identity not taken from authentication");
        Check((await service.ReadAsync())[0].JobId == queued.JobId, "Refresh did not recover persisted job");
        var restarted = Service(jobs, User());
        Check((await restarted.ReadAsync())[0].JobId == queued.JobId, "Reconnection lost job");
        try { await DisabledService().ReadAsync(); throw new Exception("Disabled service read jobs"); }
        catch (InvalidOperationException) { passed++; }

        // Render the job panel independently of the trace/statistics component.
        var panel = new DeletionJobs();
        Set(panel, "Jobs", service);
        Set(panel, "Logger", NullLogger<DeletionJobs>.Instance);
        await (Task)Invoke(panel, "Refresh")!;
        using (var render = new RenderTreeBuilder())
        {
            Invoke(panel, "BuildRenderTree", render);
            var text = string.Join(" ", render.GetFrames().Array.Take(render.GetFrames().Count).Select(f => f.TextContent));
            Check(text.Contains("Queued") && text.Contains("committed rows"), "Persisted job progress not rendered");
        }
        jobs.FailRead = true;
        await (Task)Invoke(panel, "Refresh")!;
        Check(((IReadOnlyList<DeletionJob>)Get(panel, "_jobs")!).Count == 1
            && (string?)Get(panel, "_error") is not null, "Failed poll erased last confirmed progress");
        await panel.DisposeAsync();
        Check(jobs.Controls == 0, "Disposal cancelled durable work");

        // A manual clock advances multi-minute pacing/deadlines without sleeping through lifecycles.
        var clock = new ManualClock();
        var workerStore = new WorkerStore();
        var run = new DeletionWorker(workerStore, clock).RunSliceAsync(CancellationToken.None);
        for (var n = 0; n < 4; n++) { clock.Advance(TimeSpan.FromSeconds(1)); await Task.Yield(); }
        while (!run.IsCompleted) { clock.Advance(TimeSpan.FromSeconds(1)); await Task.Delay(1); }
        await run;
        Check(workerStore.Steps == 4 && workerStore.Renews == 4 && workerStore.Releases == 1, "Slice is not finite and paced");
        Check(workerStore.Inspects == 1 && workerStore.ReleasedSequence == 4, "Release did not reconcile committed state");
        clock = new ManualClock();
        workerStore = new WorkerStore { BlockStep = true };
        run = new DeletionWorker(workerStore, clock).RunSliceAsync(CancellationToken.None);
        clock.Advance(TimeSpan.FromSeconds(45));
        await run;
        Check(workerStore.Steps == 1 && workerStore.Releases == 1, "Deadline allowed another batch");
        clock = new ManualClock();
        workerStore = new WorkerStore { InvalidState = true };
        await new DeletionWorker(workerStore, clock).RunSliceAsync(CancellationToken.None);
        Check(workerStore.Error == 51209 && workerStore.Inspects == 1, "Permanent protocol failure was silently ignored");
        workerStore = new WorkerStore { MissingLease = true };
        await new DeletionWorker(workerStore, clock).RunSliceAsync(CancellationToken.None);
        Check(workerStore.Steps == 0, "Worker fabricated a lease");
        workerStore = new WorkerStore { Finish = true };
        await new DeletionWorker(workerStore, clock).RunSliceAsync(CancellationToken.None);
        Check(workerStore.Steps == 1 && workerStore.Releases == 0, "Terminal job was released/retried");
        workerStore = new WorkerStore { RenewFails = true };
        await new DeletionWorker(workerStore, clock).RunSliceAsync(CancellationToken.None);
        Check(workerStore.Steps == 0, "Worker extrapolated lease after failed renewal");
        foreach (var number in new[] { -2, 1205, 51130, 51131, 229, 51202, 10054 })
        {
            workerStore = new WorkerStore { StepError = DeletionChecks.SqlError(number) };
            await new DeletionWorker(workerStore, clock).RunSliceAsync(CancellationToken.None);
            Check(workerStore.Steps == 1 && workerStore.Inspects == 1 && workerStore.Error == number,
                "Worker retried an uncertain batch instead of reconciling its classified SQL failure");
        }
        workerStore = new WorkerStore { StepError = DeletionChecks.SqlError(10054), InspectFails = true };
        try
        {
            await new DeletionWorker(workerStore, clock).RunSliceAsync(CancellationToken.None);
            throw new Exception("Reconciliation outage was silently swallowed");
        }
        catch (InvalidOperationException)
        { Check(workerStore.Releases == 0 && workerStore.Steps == 1, "Reconciliation failure released or repeated uncertain work"); }
        using (var stop = new CancellationTokenSource())
        {
            workerStore = new WorkerStore { BlockStep = true };
            run = new DeletionWorker(workerStore, clock).RunSliceAsync(stop.Token);
            stop.Cancel();
            await run;
            Check(workerStore.Steps == 1 && workerStore.Inspects == 1, "Host cancellation bypassed reconciliation");
        }
        clock = new ManualClock();
        workerStore = new WorkerStore { StepClock = () => clock.Advance(TimeSpan.FromSeconds(5)) };
        for (var slice = 0; slice < 20; slice++)
        {
            run = new DeletionWorker(workerStore, clock).RunSliceAsync(default);
            while (!run.IsCompleted) { clock.Advance(TimeSpan.FromSeconds(1)); await Task.Delay(1); }
            await run;
            clock.Advance(TimeSpan.FromSeconds(60));
        }
        Check(workerStore.Steps == 80 && workerStore.Releases == 20
            && clock.GetUtcNow() > DateTimeOffset.UnixEpoch.AddMinutes(20),
            "Simulated slow SQL across twenty scheduled slices lost bounded pacing or durable sequence");
        jobs.FailRead = false;
        passed += await DurableDeletionEndpointChecks.RunAsync(service, Tenant, Requester, () => jobs.Calls);
        Check(jobs.Tenant == Tenant && jobs.Requester == Requester, "HTTP body overrode authenticated requester identity");
        return passed;
    }

    static object? Invoke(object target, string name, params object[] args) => target.GetType().GetMethod(name, Members)!.Invoke(target, args);
    static object? Get(object target, string name) => target.GetType().GetField(name, Members)!.GetValue(target);
    static void Set(object target, string name, object value)
    {
        if (target.GetType().GetField(name, Members) is { } field) field.SetValue(target, value);
        else target.GetType().GetProperty(name, Members)!.SetValue(target, value);
    }
    sealed class Authentication(ClaimsPrincipal user) : AuthenticationStateProvider
    { public override Task<AuthenticationState> GetAuthenticationStateAsync() => Task.FromResult(new AuthenticationState(user)); }
    sealed class Store : IDeletionJobStore
    {
        public int Calls, Controls;
        public Guid Tenant, Requester;
        public bool FailRead;
        readonly DeletionJob job = new(Guid.NewGuid(), 1, "Queued", 0, 0, "Queued", null, null, DateTime.UtcNow, DateTime.UtcNow, DateTime.UtcNow);
        public Task<IReadOnlyList<DeletionJob>> ReadAsync(Guid tenant, Guid requester, Guid? id, CancellationToken ct)
        {
            if (FailRead) throw new InvalidOperationException("Synthetic unavailable");
            Calls++; return Task.FromResult<IReadOnlyList<DeletionJob>>([job]);
        }
        public Task<DeletionJob> EnqueueAsync(Guid tenant, Guid requester, Guid key, int trace, CancellationToken ct)
        { Calls++; Tenant = tenant; Requester = requester; return Task.FromResult(job); }
        public Task<DeletionJob> ControlAsync(Guid tenant, Guid requester, Guid id, string action, CancellationToken ct)
        { Calls++; Controls++; return Task.FromResult(job); }
    }
    sealed class WorkerStore : IDeletionWorkerStore
    {
        public int Steps, Renews, Inspects, Releases;
        public long ReleasedSequence;
        public int? Error;
        public bool BlockStep, InvalidState, MissingLease, Finish, RenewFails, InspectFails;
        public Exception? StepError;
        public Action? StepClock;
        public Task<DeletionLease?> ClaimAsync(Guid owner, CancellationToken ct) =>
            Task.FromResult<DeletionLease?>(MissingLease ? null : new(Guid.NewGuid(), 1, Guid.NewGuid(), Steps));
        public Task RenewAsync(DeletionLease lease, CancellationToken ct)
        { Renews++; if (RenewFails) throw new InvalidOperationException("No lease"); return Task.CompletedTask; }
        public async Task<DeletionStep> StepAsync(DeletionLease lease, CancellationToken ct)
        {
            Steps++;
            StepClock?.Invoke();
            if (StepError is not null) throw StepError;
            if (BlockStep) await Task.Delay(Timeout.Infinite, ct);
            return new(lease.Sequence + 1, InvalidState ? "Unknown" : Finish ? "Completed" : "Running");
        }
        public Task<DeletionStep?> InspectAsync(DeletionLease lease, CancellationToken ct)
        {
            Inspects++;
            if (InspectFails) throw new InvalidOperationException("Synthetic reconciliation unavailable");
            return Task.FromResult<DeletionStep?>(Finish ? null : new(Steps, "Running"));
        }
        public Task ReleaseAsync(DeletionLease lease, int? error, CancellationToken ct)
        { Releases++; Error = error; ReleasedSequence = Steps; return Task.CompletedTask; }
    }
    sealed class ManualClock : TimeProvider
    {
        TimeSpan now;
        readonly List<Timer> timers = [];
        public override DateTimeOffset GetUtcNow() => DateTimeOffset.UnixEpoch + now;
        public override long GetTimestamp() => now.Ticks;
        public override long TimestampFrequency => TimeSpan.TicksPerSecond;
        public override ITimer CreateTimer(TimerCallback callback, object? state, TimeSpan dueTime, TimeSpan period)
        {
            lock (timers)
            {
                var timer = new Timer(this, callback, state, now + dueTime); timers.Add(timer); return timer;
            }
        }
        public void Advance(TimeSpan time)
        {
            Timer[] due;
            lock (timers)
            {
                now += time;
                due = timers.Where(t => !t.Done && t.Due <= now).ToArray();
                foreach (var timer in due) timer.Done = true;
            }
            foreach (var timer in due) timer.Callback(timer.State);
        }
        sealed class Timer(ManualClock clock, TimerCallback callback, object? state, TimeSpan due) : ITimer
        {
            public bool Done;
            public TimeSpan Due = due;
            public TimerCallback Callback = callback;
            public object? State = state;
            public bool Change(TimeSpan dueTime, TimeSpan period)
            { lock (clock.timers) { Due = clock.now + dueTime; Done = false; return true; } }
            public void Dispose() { lock (clock.timers) Done = true; }
            public ValueTask DisposeAsync() { Dispose(); return ValueTask.CompletedTask; }
        }
    }
}
