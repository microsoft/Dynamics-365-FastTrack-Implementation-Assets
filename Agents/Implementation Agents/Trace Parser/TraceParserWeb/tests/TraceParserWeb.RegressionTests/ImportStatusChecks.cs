#pragma warning disable BL0006
using System.Net;
using System.Reflection;
using System.Security.Claims;
using Microsoft.AspNetCore.Components;
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
                Set(component, "UploadSvc", UploadService(http));
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
        var flags = BindingFlags.Instance | BindingFlags.NonPublic | BindingFlags.Public;
        var field = instance.GetType().GetField(name, flags);
        if (field is not null) field.SetValue(instance, value);
        else (instance.GetType().GetProperty(name, flags)
            ?? throw new Exception($"Missing property {name}")).SetValue(instance, value);
    }

    static object? Invoke(object instance, string name, params object[] args) =>
        (instance.GetType().GetMethod(name, BindingFlags.Instance | BindingFlags.NonPublic)
            ?? throw new Exception($"Missing method {name}")).Invoke(instance, args);
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
