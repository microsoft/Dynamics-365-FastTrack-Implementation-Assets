#pragma warning disable BL0006
using System.Reflection;
using System.Security.Claims;
using Microsoft.AspNetCore.Components;
using Microsoft.AspNetCore.Components.Authorization;
using Microsoft.AspNetCore.Components.Rendering;
using Microsoft.AspNetCore.Components.RenderTree;
using Microsoft.Data.SqlClient;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Options;
using TraceParserWeb.Services;
using TraceListPage = TraceParserWeb.Components.Pages.Traces.TraceList;

static class DeletionChecks
{
    internal const string Tenant = "11111111-1111-1111-1111-111111111111";

    internal static TraceDeletionService Service(ITraceDeletionStore store, TimeSpan? timeout = null) =>
        new(store, new ProbeAuthentication(new ClaimsPrincipal(new ClaimsIdentity(
                new[] { new Claim("tid", Tenant) }, "synthetic"))),
            Options.Create(new TraceAdministrationOptions { SqlConnectionString = "synthetic" }),
            new ConfigurationBuilder().AddInMemoryCollection(new Dictionary<string, string?> {
                ["AzureAd:TenantId"] = Tenant }).Build(), NullLogger<TraceDeletionService>.Instance)
        { OperationTimeout = timeout ?? TimeSpan.FromMinutes(5) };

    public static async Task<int> RunAsync()
    {
        var passed = 0;
        var events = new List<TraceDeletionProgress>();
        var calls = 0;
        await Service(new CallbackStore((_, _) => Task.FromResult(++calls == 1
            ? new TraceDeletionBatch(true, "TraceLines", 2000)
            : new TraceDeletionBatch(false, "Traces", 1))))
            .DeleteTraceAsync(42, progress: p => { events.Add(p); return Task.CompletedTask; });
        Check(events.Count == 2 && !events[0].Complete && events[1].Complete
            && events[1].ConfirmedRowsDeleted == 2001 && events[1].AllRowsKnown
            && events[0].Phase == "TraceLines", "Progress did not track confirmed actual rows/batches");
        passed++;

        events.Clear();
        await Service(new ProbeStore(true, false)).DeleteTraceAsync(42,
            progress: p => { events.Add(p); return Task.CompletedTask; });
        Check(events.All(p => !p.AllRowsKnown && p.ConfirmedRowsDeleted == 0),
            "Legacy procedure fabricated row counts");
        passed++;

        // Use actual provider exception types, not a made-up cancellation exception.
        foreach (var error in new Exception[] { SqlError(0), SqlError(-2), new OperationCanceledException() })
        {
            using var caller = new CancellationTokenSource();
            var store = new CallbackStore((_, _) => { caller.Cancel(); throw error; });
            try { await Service(store).DeleteTraceAsync(42, caller.Token); throw new Exception("Missing caller cancellation"); }
            catch (OperationCanceledException ex)
            {
                Check(ex.CancellationToken == caller.Token && ex.Message.Contains("may be partial")
                    && ReferenceEquals(ex.InnerException, error), "Cancellation was not normalized with partial state");
            }
            passed++;

            var timedStore = new CallbackStore(async (_, ct) =>
            {
                try { await Task.Delay(Timeout.InfiniteTimeSpan, ct); }
                catch (OperationCanceledException) { throw error; }
                throw new Exception("Unexpected timer completion");
            });
            try
            {
                await Service(timedStore, TimeSpan.FromMilliseconds(25)).DeleteTraceAsync(42);
                throw new Exception("Missing overall timeout");
            }
            catch (TimeoutException ex)
            {
                Check(ex.Message.Contains("may be partial") && ReferenceEquals(ex.InnerException, error),
                    "Overall budget was confused with caller cancellation");
            }
            passed++;
        }
        foreach (var error in new[] { SqlError(0), SqlError(-2), SqlError(547), SqlError(229) })
        {
            try
            {
                await Service(new CallbackStore((_, _) => throw error)).DeleteTraceAsync(42);
                throw new Exception("SQL error was swallowed");
            }
            catch (SqlException ex) { Check(ReferenceEquals(ex, error), "SQL error was replaced without a cancelled token"); }
            passed++;
        }
        foreach (var error in new[] { SqlError(547), SqlError(229), SqlError(0, 20) })
        {
            using var caller = new CancellationTokenSource();
            try
            {
                await Service(new CallbackStore((_, _) => { caller.Cancel(); throw error; }))
                    .DeleteTraceAsync(42, caller.Token);
                throw new Exception("Real SQL error masked by simultaneous cancellation");
            }
            catch (SqlException ex) { Check(ReferenceEquals(ex, error), "Real SQL error masked"); }
            passed++;
        }
        foreach (var number in new[] { 51130, 51131 })
        {
            var error=SqlError(number);
            try
            {
                await Service(new CallbackStore((_,_)=>throw error)).DeleteTraceAsync(42);
                throw new Exception("Importer exclusion was swallowed");
            }
            catch(InvalidOperationException ex)
            {
                Check(ReferenceEquals(ex.InnerException,error)
                    && ex.Message.Contains(number==51130?"busy":"blocked",StringComparison.OrdinalIgnoreCase),
                    "Importer exclusion did not produce actionable feedback");
            }
            passed++;
        }
        using (var caller = new CancellationTokenSource())
        {
            var callbackCompleted = false;
            calls = 0;
            var store = new CallbackStore((_, _) =>
            {
                Check(calls == 0 || callbackCompleted, "Progress callbacks were not awaited");
                return Task.FromResult(new TraceDeletionBatch(++calls < 2, "TraceLines", 3));
            });
            await Service(store).DeleteTraceAsync(42, caller.Token, async _ =>
            {
                await Task.Yield();
                callbackCompleted = true;
            });
            passed++;
        }
        foreach (var dispose in new[] { false, true })
        {
            var registrations = new ServiceCollection();
            registrations.AddLogging();
            registrations.AddAuthorizationCore();
            registrations.AddSingleton<AuthenticationStateProvider>(new ProbeAuthentication(new ClaimsPrincipal()));
            registrations.AddCascadingAuthenticationState();
            using var services = registrations.BuildServiceProvider();
            await using var renderer = new StatusRenderer(services);
            var started = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
            calls = 0;
            var store = new CallbackStore(async (_, ct) =>
            {
                if (++calls == 1) return new TraceDeletionBatch(true, "TraceLines", 2000);
                started.SetResult();
                await Task.Delay(Timeout.InfiniteTimeSpan, ct);
                return new(false);
            });
            var page = new TraceListPage();
            Set(page, "DeletionSvc", Service(store));
            Set(page, "Logger", NullLogger<TraceListPage>.Instance);
            await renderer.Dispatcher.InvokeAsync(() => renderer.Attach(page));
            var deletion = renderer.Dispatcher.InvokeAsync(() => (Task)Invoke(page, "ConfirmDelete", 42)!);
            await started.Task.WaitAsync(TimeSpan.FromSeconds(5));
            await renderer.Dispatcher.InvokeAsync(async () =>
            {
                Check((bool)Get(page, "_deleting")! && ((string)Get(page, "_deleteProgress")!).Contains("2,000"),
                    "Visible progress not updated on dispatcher");
                await (Task)Invoke(page, "ConfirmDelete", 43)!;
                Check(calls == 2, "Overlapping deletion reached store");
                using var builder = new RenderTreeBuilder();
                Invoke(page, "BuildRenderTree", builder);
                var frames = builder.GetFrames();
                Check(frames.Array.Take(frames.Count).Any(f =>
                    (f.FrameType == RenderTreeFrameType.Text && f.TextContent.Contains("Cancel deletion"))
                    || (f.FrameType == RenderTreeFrameType.Markup && f.MarkupContent.Contains("Cancel deletion"))),
                    "Cancel button missing");
                if (dispose) page.Dispose();
                else Invoke(page, "StopDeletion");
            });
            await deletion.WaitAsync(TimeSpan.FromSeconds(5));
            Check(!(bool)Get(page, "_deleting")! && Get(page, "_deleteCancellation") is null,
                "Deletion state/token leaked after cancellation");
            if (!dispose)
                Check(((string)Get(page, "_statusMessage")!).Contains("may be partial")
                    && (bool)Get(page, "_statusIsError")!, "UI lost partial cancellation feedback");
            page.Dispose();
            passed++;
        }
        foreach (var outcome in new[] { "success", "timeout", "sql-error" })
        {
            var registrations = new ServiceCollection();
            registrations.AddLogging();
            registrations.AddAuthorizationCore();
            registrations.AddSingleton<AuthenticationStateProvider>(new ProbeAuthentication(new ClaimsPrincipal()));
            registrations.AddCascadingAuthenticationState();
            using var services = registrations.BuildServiceProvider();
            await using var renderer = new StatusRenderer(services);
            var store = new CallbackStore(async (_, ct) =>
            {
                if (outcome == "sql-error") throw SqlError(547);
                if (outcome == "timeout") await Task.Delay(Timeout.InfiniteTimeSpan, ct);
                return new(false, "Traces", 1);
            });
            var page = new TraceListPage();
            Set(page, "DeletionSvc", Service(store, TimeSpan.FromMilliseconds(25)));
            Set(page, "Logger", NullLogger<TraceListPage>.Instance);
            Set(page, "_traces", new List<TraceDto> { new() { TraceId = 42 } });
            Set(page, "_importingStages", new Dictionary<int, ImportStage> { [42] = ImportStage.Parsing });
            using var timer = new Timer(_ => { }, null, Timeout.Infinite, Timeout.Infinite);
            Set(page, "_importPollTimer", timer);
            await renderer.Dispatcher.InvokeAsync(() => renderer.Attach(page));
            await renderer.Dispatcher.InvokeAsync(() => (Task)Invoke(page, "ConfirmDelete", 42)!);
            var message = (string)Get(page, "_statusMessage")!;
            Check(!(bool)Get(page, "_deleting")! && Get(page, "_deleteCancellation") is null,
                "Completion/error leaked operation state");
            if (outcome == "success")
                Check(message.Contains("deleted successfully") && Get(page, "_importPollTimer") is null
                    && ((List<TraceDto>)Get(page, "_traces")!).Count == 0, "Completed trace or poll timer was retained");
            else
                Check(message.Contains("may be partial") && (bool)Get(page, "_statusIsError")!
                    && ((List<TraceDto>)Get(page, "_traces")!).Count == 1
                    && (outcome != "timeout" || message.Contains("timed out")), "Partial UI failure was hidden or removed the trace");
            page.Dispose();
            passed++;
        }
        return passed;
    }

    internal static void Check(bool condition, string message)
    {
        if (!condition) throw new Exception(message);
    }

    static readonly BindingFlags Members = BindingFlags.Instance | BindingFlags.NonPublic | BindingFlags.Public;
    static void Set(object target, string member, object value)
    {
        if (member == "DeletionSvc") Set(target, "DeletionJobsSvc", DurableDeletionChecks.DisabledService());
        if (target.GetType().GetField(member, Members) is FieldInfo field) field.SetValue(target, value);
        else target.GetType().GetProperty(member, Members)!.SetValue(target, value);
    }
    static object? Get(object target, string member) => target.GetType().GetField(member, Members)!.GetValue(target);
    static object? Invoke(object target, string member, params object[] args) =>
        target.GetType().GetMethod(member, Members)!.Invoke(target, args);

    internal static SqlException SqlError(int number, byte severity = 11)
    {
        var ctor = typeof(SqlError).GetConstructors(BindingFlags.NonPublic | BindingFlags.Instance)
            .First(c => c.GetParameters().Length == 8);
        var error = (SqlError)ctor.Invoke(new object?[] { number, (byte)0, severity, "synthetic",
            "Synthetic provider error", "sp_DeleteTrace", 1, null });
        var errors = (SqlErrorCollection)Activator.CreateInstance(typeof(SqlErrorCollection), nonPublic: true)!;
        typeof(SqlErrorCollection).GetMethod("Add", BindingFlags.Instance | BindingFlags.NonPublic)!.Invoke(errors, new[] { error });
        return (SqlException)typeof(SqlException).GetMethod("CreateException",
            BindingFlags.Static | BindingFlags.NonPublic, null, new[] { typeof(SqlErrorCollection), typeof(string) }, null)!
            .Invoke(null, new object[] { errors, "17.0" })!;
    }
}

sealed class CallbackStore(Func<int, CancellationToken, Task<TraceDeletionBatch>> callback) : ITraceDeletionStore
{
    public Task<TraceDeletionBatch> DeleteBatchAsync(int traceId, CancellationToken ct) => callback(traceId, ct);
}
