using System.Net.Http.Json;
using System.Text.Json;

namespace TraceParserWeb.Services;

public class TraceDto
{
    public int TraceId { get; set; }
    public string TraceName { get; set; } = "";
    public string TraceFile { get; set; } = "";
    public DateTime? TimeStampBegin { get; set; }
    public DateTime? TimeStampEnd { get; set; }
    public string? TraceParserVersion { get; set; }
}

public class SessionMetricDto
{
    public int SessionId { get; set; }
    public int TraceId { get; set; }
    public int TotalTraceLines { get; set; }
    public int RootCalls { get; set; }
    public decimal TotalDurationMs { get; set; }
    public decimal TotalDatabaseMs { get; set; }
    public int TotalDatabaseCalls { get; set; }
    public long TotalRpcCalls { get; set; }
    public int TotalRowsFetched { get; set; }
}

public class TraceStats
{
    public int SessionCount { get; set; }
    public long TotalTraceLines { get; set; }
    public decimal TotalDurationMs { get; set; }
    public decimal TotalDatabaseMs { get; set; }
    public int TotalDatabaseCalls { get; set; }
}

public class TraceService(IHttpClientFactory httpFactory, ILogger<TraceService> logger)
{
    public async Task<List<TraceDto>> GetTracesAsync(CancellationToken ct = default)
    {
        using var cts = CancellationTokenSource.CreateLinkedTokenSource(ct);
        cts.CancelAfter(TimeSpan.FromSeconds(10));

        var http = httpFactory.CreateClient("dab");
        var resp = await http.GetFromJsonAsync<JsonElement>("/api/Traces?$orderby=TraceId desc", cts.Token);

        var traces = new List<TraceDto>();
        if (resp.TryGetProperty("value", out var arr))
        {
            foreach (var item in arr.EnumerateArray())
            {
                traces.Add(new TraceDto
                {
                    TraceId = item.GetProperty("TraceId").GetInt32(),
                    TraceName = item.GetProperty("TraceName").GetString() ?? "",
                    TraceFile = item.TryGetProperty("TraceFile", out var tf) ? tf.GetString() ?? "" : "",
                    TimeStampBegin = item.TryGetProperty("TimeStampBegin", out var tsb) && tsb.ValueKind != JsonValueKind.Null
                        ? tsb.GetDateTime() : null,
                    TimeStampEnd = item.TryGetProperty("TimeStampEnd", out var tse) && tse.ValueKind != JsonValueKind.Null
                        ? tse.GetDateTime() : null,
                    TraceParserVersion = item.TryGetProperty("TraceParserVersion", out var v) ? v.GetString() : null
                });
            }
        }

        return traces;
    }

    public async Task<Dictionary<int, TraceStats>> GetTraceStatsAsync(CancellationToken ct = default)
    {
        using var cts = CancellationTokenSource.CreateLinkedTokenSource(ct);
        cts.CancelAfter(TimeSpan.FromSeconds(10));

        var http = httpFactory.CreateClient("dab");
        var resp = await http.GetFromJsonAsync<JsonElement>(
            "/api/SessionMetrics?$select=TraceId,TotalTraceLines,RootCalls,TotalDurationMs,TotalDatabaseMs,TotalDatabaseCalls",
            cts.Token);

        var byTrace = new Dictionary<int, TraceStats>();
        if (resp.TryGetProperty("value", out var arr))
        {
            foreach (var item in arr.EnumerateArray())
            {
                var traceId = item.GetProperty("TraceId").GetInt32();
                if (!byTrace.TryGetValue(traceId, out var stats))
                {
                    stats = new TraceStats();
                    byTrace[traceId] = stats;
                }
                stats.SessionCount++;
                stats.TotalTraceLines += item.TryGetProperty("TotalTraceLines", out var tl) && tl.ValueKind == JsonValueKind.Number
                    ? tl.GetInt32() : 0;
                stats.TotalDurationMs += item.TryGetProperty("TotalDurationMs", out var td) && td.ValueKind == JsonValueKind.Number
                    ? td.GetDecimal() : 0;
                stats.TotalDatabaseMs += item.TryGetProperty("TotalDatabaseMs", out var db) && db.ValueKind == JsonValueKind.Number
                    ? db.GetDecimal() : 0;
                stats.TotalDatabaseCalls += item.TryGetProperty("TotalDatabaseCalls", out var dc) && dc.ValueKind == JsonValueKind.Number
                    ? dc.GetInt32() : 0;
            }
        }

        return byTrace;
    }

    public async Task<ImportStage> GetImportStageAsync(int traceId, CancellationToken ct = default)
    {
        try
        {
            using var cts = CancellationTokenSource.CreateLinkedTokenSource(ct);
            cts.CancelAfter(TimeSpan.FromSeconds(10));

            var http = httpFactory.CreateClient("dab");

            // Check USPT exists
            var threadUrl = $"/api/UserSessionProcessThreads?$filter=TraceId eq {traceId}&$top=1";
            var threadResp = await http.GetFromJsonAsync<JsonElement>(threadUrl, cts.Token);
            if (!threadResp.TryGetProperty("value", out var threadArr) || threadArr.GetArrayLength() == 0)
                return ImportStage.Parsing;

            // Check TraceLines exist
            var threadId = threadArr[0].GetProperty("UserSessionProcessThreadId").GetInt32();
            var tlUrl = $"/api/TraceLines?$filter=UserSessionProcessThreadId eq {threadId}&$top=1";
            var tlResp = await http.GetFromJsonAsync<JsonElement>(tlUrl, cts.Token);
            if (!tlResp.TryGetProperty("value", out var tlArr) || tlArr.GetArrayLength() == 0)
                return ImportStage.ProcessingDimensions;

            // Check SessionMetrics exist
            var smUrl = $"/api/SessionMetrics?$filter=TraceId eq {traceId}&$top=1";
            var smResp = await http.GetFromJsonAsync<JsonElement>(smUrl, cts.Token);
            if (!smResp.TryGetProperty("value", out var smArr) || smArr.GetArrayLength() == 0)
                return ImportStage.Finalizing;

            return ImportStage.Complete;
        }
        catch
        {
            return ImportStage.Parsing;
        }
    }

    public async Task DeleteTraceAsync(int traceId, CancellationToken ct = default)
    {
        using var cts = CancellationTokenSource.CreateLinkedTokenSource(ct);
        cts.CancelAfter(TimeSpan.FromMinutes(5));

        var http = httpFactory.CreateClient("dab");
        // DAB requires SP parameters in JSON body (not query string).
        // Use explicit options to preserve PascalCase — DAB rejects camelCase field names.
        var jsonOptions = new JsonSerializerOptions { PropertyNamingPolicy = null };
        var content = JsonContent.Create(new { TraceId = traceId }, options: jsonOptions);
        var response = await http.PostAsync("/api/DeleteTrace", content, cts.Token);

        if (!response.IsSuccessStatusCode)
        {
            var body = await response.Content.ReadAsStringAsync(cts.Token);
            logger.LogError("Delete trace {TraceId} failed: {Status} {Body}", traceId, response.StatusCode, body);
            throw new InvalidOperationException($"Failed to delete trace {traceId}: {response.StatusCode}");
        }

        logger.LogInformation("Deleted trace {TraceId}", traceId);
    }
}
