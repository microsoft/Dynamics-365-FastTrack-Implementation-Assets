using System.Net.Http.Json;
using System.Runtime.CompilerServices;
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
    public long TotalDatabaseCalls { get; set; }
}

public class TraceService(IHttpClientFactory httpFactory, ILogger<TraceService> logger,
    RegisteredImportService? registrations = null)
{
    public async Task<List<TraceDto>> GetTracesAsync(CancellationToken ct = default)
    {
        using var cts = CancellationTokenSource.CreateLinkedTokenSource(ct);
        cts.CancelAfter(TimeSpan.FromSeconds(10));

        using var http = httpFactory.CreateClient("dab");
        var traces = new List<TraceDto>();
        var ids = new HashSet<int>();
        await foreach (var item in ReadAllRowsAsync(http, "/api/Traces?$orderby=TraceId desc", cts.Token))
        {
            var id = ReadId(item, "TraceId");
            if (!ids.Add(id)) throw new JsonException("DAB returned a repeated trace.");
            traces.Add(new TraceDto
            {
                TraceId = id,
                TraceName = item.GetProperty("TraceName").GetString() ?? "",
                TraceFile = item.TryGetProperty("TraceFile", out var tf) ? tf.GetString() ?? "" : "",
                TimeStampBegin = item.TryGetProperty("TimeStampBegin", out var tsb) && tsb.ValueKind != JsonValueKind.Null
                    ? tsb.GetDateTime() : null,
                TimeStampEnd = item.TryGetProperty("TimeStampEnd", out var tse) && tse.ValueKind != JsonValueKind.Null
                    ? tse.GetDateTime() : null,
                TraceParserVersion = item.TryGetProperty("TraceParserVersion", out var v) ? v.GetString() : null
            });
        }

        return traces;
    }

    public async Task<Dictionary<int, TraceStats>> GetTraceStatsAsync(CancellationToken ct = default)
    {
        using var cts = CancellationTokenSource.CreateLinkedTokenSource(ct);
        cts.CancelAfter(TimeSpan.FromSeconds(10));

        using var http = httpFactory.CreateClient("dab");
        var byTrace = new Dictionary<int, TraceStats>();
        var sessions = new HashSet<(int TraceId, int SessionId)>();
        await foreach (var item in ReadAllRowsAsync(http,
            "/api/SessionMetrics?$select=TraceId,SessionId,TotalTraceLines,RootCalls,TotalDurationMs,TotalDatabaseMs,TotalDatabaseCalls&$orderby=TraceId,SessionId",
            cts.Token))
        {
            var traceId = ReadId(item, "TraceId");
            if (!sessions.Add((traceId, ReadId(item, "SessionId"))))
                throw new JsonException("DAB returned repeated session metrics.");
            if (!byTrace.TryGetValue(traceId, out var stats))
            {
                stats = new TraceStats();
                byTrace[traceId] = stats;
            }
            stats.SessionCount++;
            stats.TotalTraceLines += ReadCount(item, "TotalTraceLines");
            stats.TotalDurationMs += ReadDuration(item, "TotalDurationMs");
            stats.TotalDatabaseMs += ReadDuration(item, "TotalDatabaseMs");
            stats.TotalDatabaseCalls += ReadCount(item, "TotalDatabaseCalls");
        }

        return byTrace;
    }

    // DAB's nextLink is opaque: preserve its escaped cursor, but never leave this entity/origin.
    private static async IAsyncEnumerable<JsonElement> ReadAllRowsAsync(HttpClient http, string path,
        [EnumeratorCancellation] CancellationToken ct)
    {
        var initial = new Uri(http.BaseAddress ?? throw new InvalidOperationException("DAB URL is missing."), path);
        var next = initial;
        var visited = new HashSet<string>(StringComparer.Ordinal);
        var rowCount = 0;
        http.MaxResponseContentBufferSize = 16 * 1024 * 1024;
        for (var page = 0; page < 1000; page++)
        {
            ct.ThrowIfCancellationRequested();
            if (!visited.Add(next.AbsoluteUri)) throw new JsonException("DAB pagination repeated a page.");
            using var response = await http.GetAsync(next, ct);
            response.EnsureSuccessStatusCode();
            var document = await response.Content.ReadFromJsonAsync<JsonElement>(ct);
            var rows = ReadRows(document);
            rowCount = checked(rowCount + rows.GetArrayLength());
            if (rowCount > 100_000) throw new JsonException("DAB pagination exceeded the row budget.");
            foreach (var row in rows.EnumerateArray())
            {
                ct.ThrowIfCancellationRequested();
                yield return row;
            }

            if (!document.TryGetProperty("nextLink", out var link) || link.ValueKind == JsonValueKind.Null)
                yield break;
            if (link.ValueKind != JsonValueKind.String || string.IsNullOrWhiteSpace(link.GetString())
                || !Uri.TryCreate(next, link.GetString(), out var continuation)
                || continuation.Scheme != initial.Scheme || continuation.Authority != initial.Authority
                || continuation.UserInfo.Length != 0 || continuation.Fragment.Length != 0
                || continuation.AbsolutePath != initial.AbsolutePath)
                throw new JsonException("DAB returned an invalid continuation URL.");
            next = continuation;
        }
        throw new JsonException("DAB pagination exceeded the page budget.");
    }

    public async Task<ImportStage> GetImportStageAsync(int traceId, CancellationToken ct = default)
    {
        try
        {
            using var cts = CancellationTokenSource.CreateLinkedTokenSource(ct);
            cts.CancelAfter(TimeSpan.FromSeconds(10));
            if (registrations is not null)
            {
                var status = await registrations.GetTraceAsync(traceId, cts.Token);
                return status is null ? ImportStage.LegacyUntracked : RegisteredImportService.ToDisplay(status).Stage;
            }

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
        catch (Microsoft.Data.SqlClient.SqlException)
        {
            logger.LogWarning("Durable import status unavailable for trace {TraceId}", traceId);
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

    static int ReadCount(JsonElement row, string property)
    {
        if (!row.TryGetProperty(property, out var number) || number.ValueKind != JsonValueKind.Number
            || !number.TryGetInt32(out var value))
            throw new JsonException("DAB returned an invalid statistics count.");
        return value;
    }

    static decimal ReadDuration(JsonElement row, string property)
    {
        if (!row.TryGetProperty(property, out var number) || number.ValueKind != JsonValueKind.Number
            || !number.TryGetDecimal(out var value))
            throw new JsonException("DAB returned an invalid statistics duration.");
        return value;
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
