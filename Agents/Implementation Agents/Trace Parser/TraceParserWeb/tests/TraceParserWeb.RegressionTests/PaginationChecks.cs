using System.Diagnostics;
using System.Net;
using System.Text.Json;
using Microsoft.Extensions.Logging.Abstractions;
using TraceParserWeb.Services;

static class PaginationChecks
{
    public static async Task<int> RunAsync()
    {
        var checks = 0;
        void Check(bool ok, string message)
        {
            if (!ok) throw new Exception(message);
            checks++;
        }
        static string Trace(int id) => $$"""{"TraceId":{{id}},"TraceName":"synthetic"}""";
        static string Metric(int trace, int session, int calls = 3) =>
            $$"""{"TraceId":{{trace}},"SessionId":{{session}},"TotalTraceLines":12,"TotalDurationMs":1.25,"TotalDatabaseMs":0.5,"TotalDatabaseCalls":{{calls}}}""";
        static string Page(string row, string? next = null) =>
            """{"value":[""" + row + "]" + (next is null ? "" : ",\"nextLink\":" + JsonSerializer.Serialize(next)) + "}";
        static TraceService Service(Pages handler) => new(handler, NullLogger<TraceService>.Instance);
        async Task Reject(Pages handler, bool stats = false, CancellationToken ct = default)
        {
            var returned = false;
            var rejected = false;
            try
            {
                if (stats) await Service(handler).GetTraceStatsAsync(ct);
                else await Service(handler).GetTracesAsync(ct);
                returned = true;
            }
            catch (Exception ex) when (ex is JsonException or HttpRequestException or OperationCanceledException)
            { rejected = true; }
            Check(rejected && !returned, "Incomplete pagination returned partial success.");
        }

        foreach (var next in new[] { "/api/Traces?$after=abc%2B%2F%3D",
            "https://dab.invalid/api/Traces?$after=abc%2B%2F%3D", "?$after=abc%2B%2F%3D",
            "Traces?$after=abc%2B%2F%3D", "/api/%54races?$after=abc%2B%2F%3D" })
        {
            using var h = new Pages(i => i == 0 ? Page(Trace(9), next) : Page(Trace(8)));
            var rows = await Service(h).GetTracesAsync();
            Check(rows.Select(x => x.TraceId).SequenceEqual(new[] { 9, 8 }), "Lost a trace continuation.");
            Check(h.Requests.Count == 2 && h.Requests[1].Query == "?$after=abc%2B%2F%3D",
                "Opaque continuation was reconstructed or decoded.");
        }
        using (var h = new Pages(i => i switch {
            0 => Page(Metric(42, 1, int.MaxValue), "/api/SessionMetrics?$after=one"),
            1 => Page(Metric(42, 2, int.MaxValue), "/api/SessionMetrics?$after=two"),
            _ => Page(Metric(43, 1)) }))
        {
            var stats = await Service(h).GetTraceStatsAsync();
            Check(stats.Count == 2 && stats[42].SessionCount == 2 && stats[42].TotalTraceLines == 24
                && stats[42].TotalDurationMs == 2.5m && stats[42].TotalDatabaseMs == 1m
                && stats[42].TotalDatabaseCalls == 4294967294L, "Cross-page aggregation lost or overflowed metrics.");
            Check(h.Requests[0].Query.Contains("SessionId") && !h.Requests[0].Query.Contains("$top"),
                "Session paging lacks a stable composite identity.");
        }
        using (var h = new Pages(_ => Page("")))
            Check((await Service(h).GetTracesAsync()).Count == 0, "Empty traces rejected.");
        using (var h = new Pages(_ => """{"value":[],"nextLink":null}"""))
            Check((await Service(h).GetTraceStatsAsync()).Count == 0, "Empty metrics rejected.");
        foreach (var next in new[] { "https://other.invalid/api/Traces?$after=1",
            "//other.invalid/api/Traces?$after=1", "http://dab.invalid/api/Traces?$after=1",
            "https://user@dab.invalid/api/Traces?$after=1", "/api/Other?$after=1",
            "/api/Traces#fragment", "", " ", "file:///api/Traces", "/api/Traces%2Fother?$after=1" })
        {
            using var h = new Pages(_ => Page(Trace(9), next));
            await Reject(h);
            Check(h.Requests.Count == 1, $"Invalid continuation received a request/authorization header: {next}");
        }
        foreach (var invalid in new[] { """{"value":[],"nextLink":42}""",
            """{"value":[],"nextLink":{}}""", """{"value":null}""", """{"other":[]}""", "not-json" })
        {
            using var h = new Pages(i => i == 0 ? Page(Trace(9), "?$after=one") : invalid);
            await Reject(h);
        }
        using (var h = new Pages(i => Page(Trace(9 - i), "?$after=loop")))
        {
            await Reject(h);
            Check(h.Requests.Count == 2, "A continuation loop made another HTTP request.");
        }
        using (var h = new Pages(i => Page(Trace(9), i == 0 ? "?$after=one" : null)))
            await Reject(h);
        using (var h = new Pages(i => Page(Metric(42, 1), i == 0 ? "?$after=one" : null)))
            await Reject(h, stats: true);
        using (var h = new Pages(i => Page(Trace(i), "?$after=" + i)))
        {
            await Reject(h);
            Check(h.Requests.Count == 1000, "Unbounded distinct continuation pages.");
        }
        using (var h = new Pages(_ => Page(string.Join(",", Enumerable.Range(1, 100001).Select(Trace)))))
            await Reject(h);
        using (var h = new Pages(_ => new string(' ', 16 * 1024 * 1024 + 1)))
            await Reject(h);
        using (var h = new Pages(i => Page(Metric(42, i + 1), "?$after=one")) { FailAt = 1 })
            await Reject(h, stats: true);
        using (var h = new Pages(i => i % 2 == 0 ? Page(Metric(42, 1), "?$after=one") : Page(Metric(42, 2))) { FailAt = 1 })
        {
            var service = Service(h);
            try { await service.GetTraceStatsAsync(); throw new Exception("Expected second-page failure."); }
            catch (HttpRequestException) { }
            var stats = await service.GetTraceStatsAsync();
            Check(stats[42].SessionCount == 2 && stats[42].TotalTraceLines == 24 && h.Requests.Count == 4,
                "Retry accumulated a failed attempt's partial totals.");
        }
        using (var h = new Pages(_ => Page(Trace(9))))
        using (var cts = new CancellationTokenSource())
        {
            cts.Cancel();
            await Reject(h, ct: cts.Token);
            Check(h.Requests.Count == 0, "Already cancelled read sent an HTTP request.");
        }
        using (var h = new Pages(i => Page(Metric(42, i + 1), "?$after=one")) { DelayAt = 1 })
        using (var cts = new CancellationTokenSource())
        {
            h.BeforeDelay = cts.Cancel;
            await Reject(h, stats: true, cts.Token);
            Check(h.Requests.Count == 2, "Cancellation did not stop later metric pages.");
        }
        using (var h = new Pages(i => Page(Metric(42, i + 1), "?$after=" + i)) { DelayEveryPage = true })
        {
            var clock = Stopwatch.StartNew();
            await Reject(h, stats: true);
            Check(h.Requests.Count == 2 && clock.Elapsed < TimeSpan.FromSeconds(12.5),
                "Ten-second budget restarted on each page.");
        }
        using (var h = new Pages(_ => Page(Trace(9))) { Redirect = true })
            await Reject(h);
        return checks;
    }

    sealed class Pages(Func<int, string> page) : HttpMessageHandler, IHttpClientFactory
    {
        public List<Uri> Requests { get; } = [];
        public int FailAt { get; init; } = -1;
        public int DelayAt { get; init; } = -1;
        public bool DelayEveryPage { get; init; }
        public bool Redirect { get; init; }
        public Action? BeforeDelay { get; set; }
        public HttpClient CreateClient(string name)
        {
            var client = new HttpClient(this, false) { BaseAddress = new Uri("https://dab.invalid") };
            client.DefaultRequestHeaders.Authorization = new("Bearer", "SYNTHETIC");
            return client;
        }
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken ct)
        {
            var i = Requests.Count;
            Requests.Add(request.RequestUri!);
            if (DelayEveryPage) await Task.Delay(6500, ct);
            if (i == DelayAt)
            {
                BeforeDelay?.Invoke();
                await Task.Delay(Timeout.Infinite, ct);
            }
            return new HttpResponseMessage(Redirect ? HttpStatusCode.Redirect :
                i == FailAt ? HttpStatusCode.ServiceUnavailable : HttpStatusCode.OK)
            { Content = new StringContent(page(i)), RequestMessage = request };
        }
    }
}
