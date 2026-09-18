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

            using var http = httpFactory.CreateClient("dab");

            // Check USPT exists
            var threadUrl = $"/api/UserSessionProcessThreads?$filter=TraceId eq {traceId}&$first=1&$select=UserSessionProcessThreadId";
            var threadResp = await http.GetFromJsonAsync<JsonElement>(threadUrl, cts.Token);
            var threadArr = ReadRows(threadResp);
            if (threadArr.GetArrayLength() == 0)
                return ImportStage.Parsing;

            // Check TraceLines exist
            var threadId = ReadId(threadArr[0], "UserSessionProcessThreadId");
            var tlUrl = $"/api/TraceLines?$filter=UserSessionProcessThreadId eq {threadId}&$first=1&$select=TraceLineId";
            var tlResp = await http.GetFromJsonAsync<JsonElement>(tlUrl, cts.Token);
            if (ReadRows(tlResp).GetArrayLength() == 0)
                return ImportStage.ProcessingDimensions;

            // Check SessionMetrics exist
            var smUrl = $"/api/SessionMetrics?$filter=TraceId eq {traceId}&$first=1&$select=TraceId";
            var smResp = await http.GetFromJsonAsync<JsonElement>(smUrl, cts.Token);
            if (ReadRows(smResp).GetArrayLength() == 0)
                return ImportStage.Finalizing;

            return ImportStage.Complete;
        }
        catch (Exception ex) when (ex is HttpRequestException or JsonException or OperationCanceledException)
        {
            ct.ThrowIfCancellationRequested();
            logger.LogWarning(ex, "Import status unavailable for trace {TraceId}", traceId);
            return ImportStage.Unavailable;
        }
    }

    internal static JsonElement ReadRows(JsonElement response)
    {
        if (response.ValueKind != JsonValueKind.Object
            || !response.TryGetProperty("value", out var rows)
            || rows.ValueKind != JsonValueKind.Array)
            throw new JsonException("DAB returned an invalid row collection.");
        return rows;
    }

    internal static int ReadId(JsonElement row, string property)
    {
        if (row.ValueKind != JsonValueKind.Object
            || !row.TryGetProperty(property, out var id)
            || id.ValueKind != JsonValueKind.Number || !id.TryGetInt32(out var value))
            throw new JsonException("DAB returned an invalid identifier.");
        return value;
    }
}
