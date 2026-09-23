#pragma warning disable BL0006
using System.Net;
using System.Reflection;
using System.Security.Claims;
using Microsoft.AspNetCore.Components;
using Microsoft.AspNetCore.Components.Authorization;
using Microsoft.AspNetCore.Components.RenderTree;
using Microsoft.AspNetCore.Components.Rendering;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Options;
using TraceParserWeb.Services;
using TraceListPage = TraceParserWeb.Components.Pages.Traces.TraceList;
using UploadPage = TraceParserWeb.Components.Pages.Upload.EtlUpload;

static class ImportStatusChecks
{
    const string Empty = """{"value":[]}""";
    const string Thread = """{"value":[{"UserSessionProcessThreadId":7}]}""";
    const string Line = """{"value":[{"TraceLineId":9}]}""";
    const string Trace = """{"value":[{"TraceId":42}]}""";

    public static async Task<int> RunAsync()
    {
        var passed = 0;
        foreach (var test in new[] {
            (ImportStage.Parsing, new[] { Empty }),
            (ImportStage.ProcessingDimensions, new[] { Thread, Empty }),
            (ImportStage.Finalizing, new[] { Thread, Line, Empty }),
            (ImportStage.Complete, new[] { Thread, Line, Trace }) })
        {
            using var http = new StatusHttp(test.Item2);
            var stage = await Service(http).GetImportStageAsync(42);
            Check(stage == test.Item1 && http.Requests.Count == test.Item2.Length, "Incorrect import milestone");
            Check(http.Requests.All(uri => uri.Contains("$first=1") && uri.Contains("$select=")
                && !uri.Contains("$top")), "Status query used unsupported or unbounded parameters");
            passed++;
        }
        foreach (var body in new[] { "not-json", "null", "{}", """{"value":null}""", """{"value":[{}]}""" })
        {
            using var http = new StatusHttp(body);
            Check(await Service(http).GetImportStageAsync(42) == ImportStage.Unavailable,
                "Malformed response falsely indicated parsing");
            passed++;
        }
        foreach (var failure in new Exception[] { new HttpRequestException("Synthetic outage"), new TaskCanceledException() })
        {
            using var http = new StatusHttp(Empty) { Failure = failure };
            Check(await Service(http).GetImportStageAsync(42) == ImportStage.Unavailable,
                "Transport failure falsely indicated parsing");
            passed++;
        }
        {
            using var http = new StatusHttp(Empty) { Status = HttpStatusCode.BadRequest };
            Check(await Service(http).GetImportStageAsync(42) == ImportStage.Unavailable,
                "HTTP 400 falsely indicated parsing");
            passed++;
        }
        {
            using var http = new StatusHttp(Empty);
            using var ct = new CancellationTokenSource();
            ct.Cancel();
            var cancelled = false;
            try { await Service(http).GetImportStageAsync(42, ct.Token); }
            catch (OperationCanceledException) { cancelled = true; }
            Check(cancelled, "Caller cancellation was swallowed");
            passed++;
        }
        foreach (var malformed in new[] { "{}", "not-json", """{"value":[{}]}""" })
        {
            using var http = new StatusHttp(malformed);
            Check((await UploadService(http).GetImportStatusAsync("synthetic", default)).Stage == ImportStage.Unavailable,
                "Malformed upload status falsely indicated a queued job");
            passed++;
        }
        {
            using var http = new StatusHttp(Empty) { Status = HttpStatusCode.ServiceUnavailable };
            Check((await UploadService(http).GetImportStatusAsync("synthetic", default)).Stage == ImportStage.Unavailable,
                "Upload status hid HTTP failure");
            passed++;
        }
        {
            using var http = new StatusHttp(Empty);
            Check((await UploadService(http).GetImportStatusAsync("synthetic", default)).Stage == ImportStage.WaitingForFunction,
                "Absent trace did not remain pending");
            passed++;
        }
        {
            using var http = new StatusHttp(Trace, Thread, Line, Trace);
            var status = await UploadService(http).GetImportStatusAsync("O'Neil", default);
            Check(status.Stage == ImportStage.Complete && status.TraceId == 42, "Upload status did not reuse milestone checks");
            Check(http.Requests[0].Contains("TraceName eq 'O''Neil'"), "Trace name literal was not escaped");
            Check(http.Requests.Count == 4 && http.Requests.All(uri => uri.Contains("$first=1")), "Upload queries are not bounded");
            passed++;
        }
        {
            using var http = new StatusHttp(Trace, Empty) { FailAt = 2 };
            Check((await UploadService(http).GetImportStatusAsync("synthetic", default)).Stage == ImportStage.Unavailable,
                "Nested status failure became a progress state");
            passed++;
        }
        {
            var page = new TraceListPage();
            Set(page, "_loading", false);
            Set(page, "_statusMessage", "synthetic deletion failure");
            Set(page, "_statusIsError", true);
            Set(page, "_traces", new List<TraceDto> { new() { TraceId = 42, TraceName = "synthetic trace row" } });
            Set(page, "_importingStages", new Dictionary<int, ImportStage> { [42] = ImportStage.Parsing });
            Set(page, "DeletionSvc", new TraceDeletionService(new ProbeStore(false),
                new ProbeAuthentication(new ClaimsPrincipal()),
                Options.Create(new TraceAdministrationOptions { SqlConnectionString = "synthetic" }),
                new ConfigurationBuilder().Build(), NullLogger<TraceDeletionService>.Instance));
            using var builder = new RenderTreeBuilder();
            Invoke(page, "BuildRenderTree", builder);
            var frames = builder.GetFrames();
            var text = string.Concat(frames.Array.Take(frames.Count).Select(frame =>
                frame.FrameType == RenderTreeFrameType.Text ? frame.TextContent :
                frame.FrameType == RenderTreeFrameType.Markup ? frame.MarkupContent : ""));
            Check(text.IndexOf("synthetic deletion failure", StringComparison.Ordinal) >= 0
                && text.IndexOf("synthetic deletion failure", StringComparison.Ordinal)
                < text.IndexOf("synthetic trace row", StringComparison.Ordinal), "Deletion feedback is below the trace list");
            Check(!text.Contains("Parsing ETL events") && !text.Contains("importing-spinner"),
                "Missing data was rendered as an active parser");
            page.Dispose();
            passed++;
        }
        {
            var page = new UploadPage();
            Set(page, "_currentStage", ImportStage.Unavailable);
            foreach (var stage in new[] { ImportStage.WaitingForFunction, ImportStage.Parsing,
                ImportStage.ProcessingDimensions, ImportStage.Finalizing })
                Check((string)Invoke(page, "GetDotClass", stage)! == "stage-pending",
                    "Unavailable status falsely marked a stage complete");
            page.Dispose();
            passed++;
        }
        foreach (var test in new[] {
            (ImportStage.Parsing,true), (ImportStage.RetryableFailure,true), (ImportStage.RejectedOversize,true),
            (ImportStage.Deleting,false), (ImportStage.LegacyUntracked,false), (ImportStage.Unavailable,true) })
        {
            var page=new TraceListPage();
            Set(page,"_importingStages",new Dictionary<int,ImportStage>{{42,test.Item1}});
            Check((bool)Invoke(page,"IsImportBlocked",42)! == test.Item2,"Incorrect import deletion eligibility hint");
            page.Dispose();
            passed++;
        }
        {
            var page=new TraceListPage();
            Set(page,"_loading",false);
            Set(page,"_traces",new List<TraceDto>{new(){TraceId=42,TraceName="partial trace",TraceParserVersion="safe-import-v1"}});
            Set(page,"_traceStats",new Dictionary<int,TraceStats>{{42,new(){SessionCount=1,TotalTraceLines=20}}});
            Set(page,"_importingStages",new Dictionary<int,ImportStage>{{42,ImportStage.Deleting}});
            Set(page,"DeletionSvc",new TraceDeletionService(new ProbeStore(false),
                new ProbeAuthentication(new ClaimsPrincipal()),
                Options.Create(new TraceAdministrationOptions{SqlConnectionString="synthetic"}),
                new ConfigurationBuilder().Build(),NullLogger<TraceDeletionService>.Instance));
            using var builder=new RenderTreeBuilder();
            Invoke(page,"BuildRenderTree",builder);
            var frames=builder.GetFrames();
            var text=string.Concat(frames.Array.Take(frames.Count).Select(frame=>
                frame.FrameType==RenderTreeFrameType.Text?frame.TextContent:
                frame.FrameType==RenderTreeFrameType.Markup?frame.MarkupContent:""));
            Check(text.Contains("Deletion is incomplete") && text.Contains("lines"),
                "Surviving metrics hid partial deletion status");
            page.Dispose();
            passed++;
        }
        foreach (var upload in new[] { false, true })
        {
            using var http = new StatusHttp(Empty) { Block = true };
            using var services = new ServiceCollection().BuildServiceProvider();
            await using var renderer = new StatusRenderer(services);
            IComponent page;
            string method;
            if (upload)
            {
                var component = new UploadPage();
                var tenant = Guid.NewGuid().ToString();
                var registered = new RegisteredImportService(new PollingImportStore(http),
                    new ProbeAuthentication(new ClaimsPrincipal(new ClaimsIdentity(
                        [new Claim("tid", tenant)], "synthetic"))),
                    new ConfigurationBuilder().AddInMemoryCollection(new Dictionary<string,string?>
                        { ["AzureAd:TenantId"] = tenant }).Build(),
                    Options.Create(new EtlImportOptions()));
                Set(component, "UploadSvc", new EtlUploadService(Options.Create(new EtlImportOptions()),
                    http, Service(http), NullLogger<EtlUploadService>.Instance, registered));
                Set(component, "_importId", Guid.NewGuid());
                Set(component, "Logger", NullLogger<UploadPage>.Instance);
                Set(component, "SessionName", "synthetic");
                page = component;
                method = "PollImportStatusAsync";
            }
            else
            {
                var component = new TraceListPage();
                Set(component, "TraceSvc", Service(http));
                Set(component, "Logger", NullLogger<TraceListPage>.Instance);
                Set(component, "_importingStages", new Dictionary<int, ImportStage> { [42] = ImportStage.Parsing });
                page = component;
                method = "PollImportStagesAsync";
            }
            await renderer.Dispatcher.InvokeAsync(() => renderer.Attach(page));
            var first = (Task)Invoke(page, method)!;
            await http.Started.Task.WaitAsync(TimeSpan.FromSeconds(5));
            await ((Task)Invoke(page, method)!).WaitAsync(TimeSpan.FromSeconds(5));
            Check(http.Requests.Count == 1, "Status polls overlapped");
            await renderer.Dispatcher.InvokeAsync(((IDisposable)page).Dispose);
            http.Release.SetResult();
            await first.WaitAsync(TimeSpan.FromSeconds(5));
            passed++;
        }
        {
            var page=new UploadPage();
            var config=new ConfigurationBuilder().AddInMemoryCollection(new Dictionary<string,string?>
                { ["UploadAdmission:Hold"]="true" }).Build();
            using var http=new StatusHttp(Empty);
            Set(page,"Imports",new RegisteredImportService(new PollingImportStore(http),
                new ProbeAuthentication(new ClaimsPrincipal()),config,Options.Create(new EtlImportOptions())));
            using var builder=new RenderTreeBuilder();
            Invoke(page,"BuildRenderTree",builder);
            var frames=builder.GetFrames();
            var text=string.Concat(frames.Array.Take(frames.Count).Where(f=>f.FrameType==RenderTreeFrameType.Text).Select(f=>f.TextContent));
            Check(text.Contains("temporarily unavailable") && text.Contains("Existing imports"),
                "Held upload UI must explain temporary unavailability without implying active work is paused");
            Check(frames.Array.Take(frames.Count).Any(f=>f.FrameType==RenderTreeFrameType.Attribute
                && f.AttributeName=="disabled" && Equals(f.AttributeValue,true)),"Held upload button is not disabled");
            page.Dispose();
            Check((bool)Get(page,"_disposed")!,"Held upload page disposal failed");
            passed+=3;
        }
        {
            var page=new UploadPage();
            Set(page,"_isProcessing",true);
            Set(page,"Busy",true);
            using var timer=new System.Threading.Timer(_=>{},null,Timeout.Infinite,Timeout.Infinite);
            Set(page,"_pollTimer",timer);
            Invoke(page,"ShowOversizeRejection");
            Check(!(bool)Get(page,"_isProcessing")! && !(bool)Get(page,"Busy")!
                && !(bool)Get(page,"IsComplete")! && (bool)Get(page,"IsError")!
                && Get(page,"_pollTimer") is null,"Oversize rejection left processing polling or a success state active");
            Check(((string)Get(page,"StatusMessage")!).Contains("1 GiB")
                && ((string)Get(page,"StatusMessage")!).Contains("retained"),"Oversize rejection lacks an actionable retained-data message");
            page.Dispose();
            passed++;
        }
        return passed + await RunTraceListLoadingChecksAsync();
    }

    static async Task<int> RunTraceListLoadingChecksAsync()
    {
        var passed = 0;
        var services = new ServiceCollection();
        services.AddLogging();
        services.AddAuthorizationCore();
        services.AddCascadingAuthenticationState();
        services.AddSingleton<AuthenticationStateProvider>(new ProbeAuthentication(new ClaimsPrincipal()));
        using var provider = services.BuildServiceProvider();

        TraceListPage Page(TraceListHttp http)
        {
            var page = new TraceListPage();
            Set(page, "TraceSvc", new TraceService(http, NullLogger<TraceService>.Instance));
            Set(page, "Logger", NullLogger<TraceListPage>.Instance);
            Set(page, "DeletionSvc", new TraceDeletionService(new ProbeStore(false),
                new ProbeAuthentication(new ClaimsPrincipal()),
                Options.Create(new TraceAdministrationOptions { SqlConnectionString = "synthetic" }),
                new ConfigurationBuilder().Build(), NullLogger<TraceDeletionService>.Instance));
            return page;
        }
        async Task Call(StatusRenderer renderer, TraceListPage page, string method) =>
            await renderer.Dispatcher.InvokeAsync(() => (Task)Invoke(page, method)!).WaitAsync(TimeSpan.FromSeconds(5));
        string Text(TraceListPage page)
        {
            using var builder = new RenderTreeBuilder();
            Invoke(page, "BuildRenderTree", builder);
            var frames = builder.GetFrames();
            return string.Concat(frames.Array.Take(frames.Count).Select(frame =>
                frame.FrameType == RenderTreeFrameType.Text ? frame.TextContent :
                frame.FrameType == RenderTreeFrameType.Markup ? frame.MarkupContent : ""));
        }

        foreach (var failure in new[] { "503", "transport", "timeout", "json", "envelope", "null", "row", "count", "duration" })
        {
            using var http = new TraceListHttp();
            if (failure == "503") http.StatsStatus = HttpStatusCode.ServiceUnavailable;
            if (failure == "transport") http.StatsFailure = new HttpRequestException("Synthetic outage");
            if (failure == "timeout") http.StatsFailure = new TaskCanceledException("Synthetic timeout");
            if (failure == "json") http.StatsBody = "not-json";
            if (failure == "envelope") http.StatsBody = "{}";
            if (failure == "null") http.StatsBody = """{"value":null}""";
            if (failure == "row") http.StatsBody = """{"value":[{}]}""";
            if (failure == "count") http.StatsBody = TraceListHttp.Metrics.Replace("\"TotalTraceLines\":12", "\"TotalTraceLines\":\"unknown\"");
            if (failure == "duration") http.StatsBody = TraceListHttp.Metrics.Replace("\"TotalDurationMs\":100", "\"TotalDurationMs\":null");
            var page = Page(http);
            await using var renderer = new StatusRenderer(provider);
            await renderer.Dispatcher.InvokeAsync(() => renderer.Attach(page));
            await Call(renderer, page, "LoadTraces");
            var traces = (List<TraceDto>)Get(page, "_traces")!;
            Check(traces.Count == 1 && Get(page, "_error") is null && Get(page, "_statsError") is not null,
                $"{failure}: optional statistics failure hid trace metadata");
            Check(Text(page).Contains("synthetic visible trace") && Text(page).Contains("Retry statistics")
                && !Text(page).Contains("No traces imported"), $"{failure}: partial failure rendered as an empty list");
            Check(((Dictionary<int, TraceStats>)Get(page, "_traceStats")!).Count == 0,
                $"{failure}: unavailable statistics became numeric values");
            http.StatsStatus = HttpStatusCode.OK;
            http.StatsFailure = null;
            http.StatsBody = TraceListHttp.Metrics;
            await Call(renderer, page, "RefreshStatsAsync");
            var stats = ((Dictionary<int, TraceStats>)Get(page, "_traceStats")!)[42];
            Check(Get(page, "_statsError") is null && ReferenceEquals(traces, Get(page, "_traces"))
                && http.TraceRequests == 1 && stats.SessionCount == 1 && stats.TotalTraceLines == 12
                && stats.TotalDurationMs == 100, $"{failure}: statistics-only retry did not recover");
            page.Dispose();
            passed += 2;
        }
        using(var http=new TraceListHttp
        {
            StatsBody="""{"value":[{"TraceId":42,"SessionId":1,"TotalTraceLines":12,"TotalDurationMs":null,"TotalDatabaseMs":null,"TotalDatabaseCalls":null,"StoredDurationUnit":"unknown","AggregationVersion":"legacy-unverified"}]}"""
        })
        {
            var page=Page(http);
            await using var renderer=new StatusRenderer(provider);
            await renderer.Dispatcher.InvokeAsync(()=>renderer.Attach(page));
            await Call(renderer,page,"LoadTraces");
            Check(Get(page,"_statsError") is null && Text(page).Contains("12 lines")
                && Text(page).Contains("Duration/DB totals uncertain"),
                "Unclassified historical durations render honestly without losing valid counts");
            Check(!Text(page).Contains("Retry statistics") && Text(page).Contains("synthetic visible trace"),
                "Expected duration uncertainty is not an API outage");
            page.Dispose(); passed+=2;
        }
        using(var http=new TraceListHttp())
        {
            var page=Page(http);
            await using var renderer=new StatusRenderer(provider);
            await renderer.Dispatcher.InvokeAsync(()=>renderer.Attach(page));
            await Call(renderer,page,"LoadTraces");
            var stats=((Dictionary<int,TraceStats>)Get(page,"_traceStats")!)[42];
            Check(stats.TotalDurationMs==100 && !Text(page).Contains("Duration/DB totals uncertain")
                && Get(page,"_statsError") is null,"Nullable-aware held web must accept pre-migration numeric DAB shape");
            page.Dispose();passed++;
        }
        foreach (var blockTraces in new[] { false, true })
        {
            using var http = new TraceListHttp { BlockStats = !blockTraces, BlockTraces = blockTraces };
            var page = Page(http);
            await using var renderer = new StatusRenderer(provider);
            await renderer.Dispatcher.InvokeAsync(() => renderer.Attach(page));
            var load = renderer.Dispatcher.InvokeAsync(() => (Task)Invoke(page, "LoadTraces")!);
            await (blockTraces ? http.TraceStarted.Task : http.StatsStarted.Task).WaitAsync(TimeSpan.FromSeconds(5));
            if (!blockTraces)
            {
                Check(!(bool)Get(page, "_loading")! && Text(page).Contains("synthetic visible trace")
                    && Text(page).Contains("Loading statistics"), "Slow statistics prevented rows from rendering");
                Check((bool)Invoke(page, "IsImportBlocked", 42)!, "Unconfirmed status allowed deletion during initial load");
                await Call(renderer, page, "RefreshStatsAsync");
                Check(http.StatsRequests == 1, "Concurrent statistics retries overlapped");
            }
            await renderer.Dispatcher.InvokeAsync(page.Dispose);
            await load.WaitAsync(TimeSpan.FromSeconds(5));
            Check(Get(page, "_error") is null && Get(page, "_statsError") is null,
                "Navigation cancellation was shown as an outage");
            passed++;
        }
        {
            using var http = new TraceListHttp { TraceStatus = HttpStatusCode.ServiceUnavailable };
            var page = Page(http);
            await using var renderer = new StatusRenderer(provider);
            await renderer.Dispatcher.InvokeAsync(() => renderer.Attach(page));
            await Call(renderer, page, "LoadTraces");
            Check(Get(page, "_error") is not null && Text(page).Contains("Retry trace list")
                && !Text(page).Contains("No traces imported") && http.StatsRequests == 0,
                "Metadata failure was swallowed or triggered optional reads");
            http.TraceStatus = HttpStatusCode.OK;
            await Call(renderer, page, "LoadTraces");
            Check(Get(page, "_error") is null && Text(page).Contains("synthetic visible trace"),
                "Trace-list retry did not recover");
            page.Dispose();
            passed++;
        }
        {
            using var http = new TraceListHttp();
            var page = Page(http);
            await using var renderer = new StatusRenderer(provider);
            await renderer.Dispatcher.InvokeAsync(() => renderer.Attach(page));
            await Call(renderer, page, "LoadTraces");
            Set(page, "_importingStages", new Dictionary<int, ImportStage> { [42] = ImportStage.Finalizing });
            http.StatsStatus = HttpStatusCode.ServiceUnavailable;
            await Call(renderer, page, "PollImportStagesAsync");
            Check(Get(page, "_error") is null && Get(page, "_statsError") is not null
                && ((Dictionary<int, TraceStats>)Get(page, "_traceStats")!).Count == 0
                && ((Dictionary<int, ImportStage>)Get(page, "_importingStages")!).Count == 0
                && Get(page, "_importPollTimer") is null, "Completion refresh retained stale stats or lost progress");
            http.StatsStatus = HttpStatusCode.OK;
            await Call(renderer, page, "RefreshStatsAsync");
            Check(Get(page, "_statsError") is null, "Last-completion failure left statistics unrecoverable");
            page.Dispose();
            passed++;
        }
        foreach (var safeImport in new[] { false, true })
        {
            using var http = new TraceListHttp { FilteredMetricsBody = Empty };
            if (safeImport)
                http.TraceBody = http.TraceBody.Replace("\"TraceName\"", "\"TraceParserVersion\":\"safe-import-v1\",\"TraceName\"");
            else
                http.StatsBody = Empty;
            var page = Page(http);
            await using var renderer = new StatusRenderer(provider);
            await renderer.Dispatcher.InvokeAsync(() => renderer.Attach(page));
            await Call(renderer, page, "LoadTraces");
            Check(Get(page, "_statsError") is null && (bool)Invoke(page, "IsImportBlocked", 42)!,
                "Valid empty metrics or protocol eligibility were mistaken for a statistics outage");
            Check(((Dictionary<int, ImportStage>)Get(page, "_importingStages")!)[42] == ImportStage.Finalizing,
                "Import status was inferred from global statistics instead of its own query");
            page.Dispose();
            passed++;
        }
        {
            using var http = new TraceListHttp { TraceBody = Empty };
            var page = Page(http);
            await using var renderer = new StatusRenderer(provider);
            await renderer.Dispatcher.InvokeAsync(() => renderer.Attach(page));
            await Call(renderer, page, "LoadTraces");
            Check(Text(page).Contains("No traces imported") && Get(page, "_error") is null,
                "A genuinely empty trace list no longer renders its empty state");
            page.Dispose();
            passed++;
        }
        return passed;
    }

    static TraceService Service(StatusHttp http) => new(http, NullLogger<TraceService>.Instance);
    static EtlUploadService UploadService(StatusHttp http) => new(
        Options.Create(new EtlImportOptions()), http, Service(http), NullLogger<EtlUploadService>.Instance);

    static void Check(bool condition, string message)
    {
        if (!condition) throw new Exception(message);
    }

    static void Set(object instance, string name, object value)
    {
        if (name == "DeletionSvc") Set(instance, "DeletionJobsSvc", DurableDeletionChecks.DisabledService());
        var flags = BindingFlags.Instance | BindingFlags.NonPublic | BindingFlags.Public;
        var field = instance.GetType().GetField(name, flags);
        if (field is not null) field.SetValue(instance, value);
        else (instance.GetType().GetProperty(name, flags)
            ?? throw new Exception($"Missing property {name}")).SetValue(instance, value);
    }

    static object? Invoke(object instance, string name, params object[] args) =>
        (instance.GetType().GetMethod(name, BindingFlags.Instance | BindingFlags.NonPublic)
            ?? throw new Exception($"Missing method {name}")).Invoke(instance, args);

    static object? Get(object instance,string name)
    {
        var flags=BindingFlags.Instance|BindingFlags.NonPublic|BindingFlags.Public;
        var field=instance.GetType().GetField(name,flags);
        return field is not null ? field.GetValue(instance) : instance.GetType().GetProperty(name,flags)?.GetValue(instance);
    }
}

sealed class PollingImportStore(StatusHttp gate) : IRegisteredImportStore
{
    public Task RegisterAsync(Guid id, string account, string container, string blobName, string session, CancellationToken ct)
        => throw new NotSupportedException();

    public async Task<DurableImportStatus?> ReadAsync(Guid? importId, int? traceId, CancellationToken ct)
    {
        gate.Requests.Add("synthetic receipt status");
        gate.Started.TrySetResult();
        await gate.Release.Task.WaitAsync(ct);
        return new(importId!.Value, null, "Registered", false);
    }
}

sealed class StatusHttp(params string[] responses) : HttpMessageHandler, IHttpClientFactory
{
    public List<string> Requests { get; } = new();
    public HttpStatusCode Status { get; init; } = HttpStatusCode.OK;
    public Exception? Failure { get; init; }
    public int FailAt { get; init; }
    public bool Block { get; init; }
    public TaskCompletionSource Started { get; } = new(TaskCreationOptions.RunContinuationsAsynchronously);
    public TaskCompletionSource Release { get; } = new(TaskCreationOptions.RunContinuationsAsynchronously);

    public HttpClient CreateClient(string name)
    {
        if (name != "dab") throw new Exception("Unexpected HTTP client");
        return new HttpClient(this, disposeHandler: false) { BaseAddress = new Uri("https://dab.invalid") };
    }

    protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken ct)
    {
        ct.ThrowIfCancellationRequested();
        Requests.Add(Uri.UnescapeDataString(request.RequestUri!.PathAndQuery));
        Started.TrySetResult();
        if (Block) await Release.Task.WaitAsync(ct);
        if (Failure is not null) throw Failure;
        if (FailAt == Requests.Count) throw new HttpRequestException("Synthetic status failure");
        if (Requests.Count > responses.Length) throw new Exception("Unexpected status request");
        return new HttpResponseMessage(Status) {
            Content = new StringContent(responses[Requests.Count - 1], System.Text.Encoding.UTF8, "application/json")
        };
    }
}

sealed class StatusRenderer(IServiceProvider services) : Renderer(services, NullLoggerFactory.Instance)
{
    public override Dispatcher Dispatcher { get; } = Dispatcher.CreateDefault();
    public void Attach(IComponent component) => AssignRootComponentId(component);
    protected override Task UpdateDisplayAsync(in RenderBatch renderBatch) => Task.CompletedTask;
    protected override void HandleException(Exception exception) =>
        System.Runtime.ExceptionServices.ExceptionDispatchInfo.Capture(exception).Throw();
}

sealed class TraceListHttp : HttpMessageHandler, IHttpClientFactory
{
    public const string Metrics = """{"value":[{"TraceId":42,"SessionId":1,"TotalTraceLines":12,"TotalDurationMs":100,"TotalDatabaseMs":20,"TotalDatabaseCalls":3}]}""";
    public string TraceBody { get; set; } = """{"value":[{"TraceId":42,"TraceName":"synthetic visible trace"}]}""";
    public string StatsBody { get; set; } = Metrics;
    public string FilteredMetricsBody { get; set; } = """{"value":[{"TraceId":42}]}""";
    public HttpStatusCode StatsStatus { get; set; } = HttpStatusCode.OK;
    public HttpStatusCode TraceStatus { get; set; } = HttpStatusCode.OK;
    public Exception? StatsFailure { get; set; }
    public bool BlockStats { get; init; }
    public bool BlockTraces { get; init; }
    public int TraceRequests { get; private set; }
    public int StatsRequests { get; private set; }
    public TaskCompletionSource TraceStarted { get; } = new(TaskCreationOptions.RunContinuationsAsynchronously);
    public TaskCompletionSource StatsStarted { get; } = new(TaskCreationOptions.RunContinuationsAsynchronously);

    public HttpClient CreateClient(string name) =>
        name == "dab" ? new(this, disposeHandler: false) { BaseAddress = new Uri("https://dab.invalid") }
            : throw new Exception("Unexpected client");

    protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken ct)
    {
        ct.ThrowIfCancellationRequested();
        var path = request.RequestUri!.AbsolutePath;
        var status = HttpStatusCode.OK;
        string body;
        if (path == "/api/Traces")
        {
            TraceRequests++;
            TraceStarted.TrySetResult();
            if (BlockTraces) await Task.Delay(Timeout.Infinite, ct);
            body = TraceBody;
            status = TraceStatus;
        }
        else if (path == "/api/SessionMetrics" && !request.RequestUri.Query.Contains("$filter"))
        {
            StatsRequests++;
            StatsStarted.TrySetResult();
            if (BlockStats) await Task.Delay(Timeout.Infinite, ct);
            if (StatsFailure is not null) throw StatsFailure;
            body = StatsBody;
            status = StatsStatus;
        }
        else
            body = path switch
            {
                "/api/UserSessionProcessThreads" => """{"value":[{"UserSessionProcessThreadId":7}]}""",
                "/api/TraceLines" => """{"value":[{"TraceLineId":9}]}""",
                "/api/SessionMetrics" => FilteredMetricsBody,
                _ => throw new Exception("Unexpected request")
            };
        return new(status) { Content = new StringContent(body, System.Text.Encoding.UTF8, "application/json") };
    }
}
