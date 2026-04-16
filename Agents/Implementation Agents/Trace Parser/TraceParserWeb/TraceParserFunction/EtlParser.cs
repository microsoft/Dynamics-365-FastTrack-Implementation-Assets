using System.Threading.Channels;
using Microsoft.Diagnostics.Tracing;
using Microsoft.Extensions.Logging;
using Microsoft.Data.SqlClient;

namespace TraceParserFunction;

/// <summary>
/// Per-activity-ID thread state (mirrors PS $script:TState[actKey]).
/// </summary>
public class ThreadState
{
    public Stack<CallFrame>          CallStack      = new();
    public Dictionary<string, int>   MethodsInStack = new();  // methodName → depth (recursion detect)
    public Dictionary<int, string>   BindParams     = new();  // colIdx → value
    public DateTime                  BindTimestamp  = DateTime.MinValue;
    public StageRow?                 LastSelectStmt;
}

public class CallFrame
{
    public long     Seq;
    public string   FullMethod  = "";
    public string   FileName    = "";
    public int      LineNumber;
    public DateTime EnterTime;
    public long     TSNs;           // FileTimeUtc at enter
    public long?    ParentSeq;
    public long     ChildTime;      // accumulated child duration (ticks)
    public int      DbCalls;
    public long     DbNano;
    public bool     IsRecursive;
    public int?     EnterEid;       // for FormServer interaction pairs
}

/// <summary>
/// Reads an ETL file via ETWTraceEventSource and produces StageTraceLines rows in batches.
/// Calls into SqlImporter for all dimension DB operations.
/// </summary>
public class EtlParser(SqlImporter importer, ILogger<EtlParser> logger)
{
    private static readonly HashSet<Guid> D365Providers = [
        new("8e410b1f-eb34-4417-be16-478a22c98916"), // Main
        new("c0d248ce-634d-426b-9e31-5a50a6d83024"), // XppTraces
        new("70560195-becd-45d4-ac93-97290953ad02"), // ExecutionTraces
        new("17712abf-12a2-46ab-a53c-6baebdbf6f0e"), // FormServer
    ];

    private static readonly Guid ProvFormServer = new("17712abf-12a2-46ab-a53c-6baebdbf6f0e");

    // FormServer interaction enter/exit EID pairs
    private static readonly Dictionary<int, string> InteractionEnter = new()
    {
        {28,"PrepareClientPayload"}, {40,"PropertyChange"},
        {44,"GetMenuStructure"},     {62,"InitExtDesign"},
        {66,"FormInitDataMethods"},  {68,"KcRun"},
    };
    private static readonly HashSet<int> InteractionExit = [29, 41, 45, 63, 67, 69];

    private static readonly Dictionary<int, string> EventNames = new()
    {
        {24500,"Entering X++ method."}, {24501,"Exiting X++ method."},
        {4920,"Execution time use of reflection."},
        {4922,"AosSqlStatementExecutionLatency"}, {4923,"AosSqlInputBind"}, {4924,"AosSqlRowFetch"},
        {4906,"AosSqlConnectionPoolInfo"}, {4908,"XppExceptionThrown"},
        {4911,"AosSessionInfo"}, {4919,"AosRuntimeCallStarted"},
        {4902,"MessageCreated"}, {4904,"AosFlushData"}, {4905,"AxCallStackTrace"},
    };

    private const int CT_XPP      = 8;
    private const int CT_SQL      = 64;
    private const int CT_SQLBIND  = 32;
    private const int CT_SQLFETCH = 128;
    private const int CT_MSG      = 8192;
    private const int BATCH_SIZE  = 200_000;

    // Session resolution maps (mirrors PS script globals)
    private readonly Dictionary<string, (string sess, string user, string cust)> _custToSession = new();
    private readonly Dictionary<string, (string sess, string user, string cust)> _reqToSession  = new();
    private readonly Dictionary<string, (string sess, string user, string cust)> _osToSessionInfo = new();
    private readonly Dictionary<string, string> _osToActKey = new();

    // Per-activity thread state
    private readonly Dictionary<string, ThreadState> _tState = new();

    private long _globalSeq;

    private ThreadState GetTState(string key)
    {
        if (!_tState.TryGetValue(key, out var ts))
            _tState[key] = ts = new ThreadState();
        return ts;
    }

    private static long ConvertSecToTicks(object? val)
    {
        if (val == null) return 0L;
        var s = val.ToString() ?? "";
        if (string.IsNullOrWhiteSpace(s)) return 0L;
        return double.TryParse(s, System.Globalization.NumberStyles.Any,
            System.Globalization.CultureInfo.InvariantCulture, out var d)
            ? (long)(d * 1e7) : 0L;
    }

    private static string P(TraceEvent evt, string name)
    {
        try { return evt.PayloadByName(name)?.ToString() ?? ""; }
        catch { return ""; }
    }

    private static string PUser(TraceEvent evt)
    {
        var g = P(evt, "userGuid").Trim('{', '}');
        if (!string.IsNullOrWhiteSpace(g) && g != "00000000-0000-0000-0000-000000000000") return g;
        var u = P(evt, "userId");
        return !string.IsNullOrWhiteSpace(u) ? u : "_system";
    }

    // String interning for repeated ETW payload values (fileName, methodName)
    private readonly Dictionary<string, string> _internedStrings = new();
    private string Intern(string s)
    {
        if (string.IsNullOrEmpty(s)) return s;
        if (_internedStrings.TryGetValue(s, out var cached)) return cached;
        _internedStrings[s] = s;
        return s;
    }

    public ParseStats Parse(string etlFilePath, int traceId, SqlConnection conn)
    {
        var dims = new InMemoryDimensions();
        importer.ClearState();

        // Clean up staging table from any previous/failed run
        using (var cmd = conn.CreateCommand())
        {
            cmd.CommandText = "TRUNCATE TABLE StageTraceLines";
            cmd.ExecuteNonQuery();
        }
        logger.LogInformation("StageTraceLines truncated.");

        // Phase 1: Parse ETL + stream rows to StageTraceLines (with temp negative ThreadIds)
        var stats = ParseAndStream(etlFilePath, traceId, dims, conn);

        // Phase 2: Bulk upsert all dimensions, get threadMap
        logger.LogInformation("Phase 1 complete. Enter={Enter} SQL={Stmt} Staged={Staged}. Starting Phase 2 (dimensions + remap)...",
            stats.Enter, stats.Stmt, stats.Staged);
        var threadMap = importer.BulkInsertDimensions(conn, traceId, dims);

        // Phase 3: Remap temp ThreadIds in StageTraceLines + bind params
        importer.RemapStageThreadIds(conn, threadMap);

        logger.LogInformation("Parse complete. Enter={Enter} Exit={Exit} Stmt={Stmt} Bind={Bind} Fetch={Fetch} Msg={Msg} Staged={Staged} Mismatch={Mismatch}",
            stats.Enter, stats.Exit, stats.Stmt, stats.Bind, stats.Fetch, stats.Msg, stats.Staged, stats.Mismatch);

        return stats;
    }

    private ParseStats ParseAndStream(string etlFilePath, int traceId, InMemoryDimensions dims, SqlConnection conn)
    {
        // Clear instance state (singleton safety)
        _custToSession.Clear();
        _reqToSession.Clear();
        _osToSessionInfo.Clear();
        _osToActKey.Clear();
        _tState.Clear();
        _internedStrings.Clear();
        _globalSeq = 0;

        var stats       = new ParseStats();
        var batch       = new List<StageRow>(BATCH_SIZE);
        var bpBatch     = new List<BindParamRow>();
        long totalFlushed = 0;
        long eventCount   = 0;
        int  batchNum     = 0;

        // Channel for parallel parse+SQL: producer (parse) → consumer (SQL flush)
        var channel = Channel.CreateBounded<(List<StageRow> rows, List<BindParamRow> bps)>(
            new BoundedChannelOptions(3) { FullMode = BoundedChannelFullMode.Wait });
        Exception? consumerError = null;
        var cts = new CancellationTokenSource();

        var consumerTask = Task.Run(async () =>
        {
            try
            {
                await foreach (var (rows, bps) in channel.Reader.ReadAllAsync())
                    importer.FlushStageBatch(conn, rows, bps);
            }
            catch (Exception ex) { consumerError = ex; cts.Cancel(); }
        });

        using var source = new ETWTraceEventSource(etlFilePath);

        // Pre-load D365 ETW provider manifests so DynamicTraceEventParser can decode
        // events on machines where the providers aren't registered (e.g. Azure)
        var manifestDir = Path.Combine(AppContext.BaseDirectory, "Manifests");
        if (Directory.Exists(manifestDir))
        {
            logger.LogInformation("Loading ETW manifests from: {Dir}", manifestDir);
            source.Dynamic.ReadAllManifests(manifestDir);
        }

        // Diagnostic counters to verify manifest coverage
        long allEventCount = 0;
        long d365AllCount = 0;
        var providersSeen = new HashSet<Guid>();
        source.AllEvents += evt =>
        {
            allEventCount++;
            providersSeen.Add(evt.ProviderGuid);
            if (D365Providers.Contains(evt.ProviderGuid)) d365AllCount++;
        };

        source.Dynamic.All += evt =>
        {
            if (!D365Providers.Contains(evt.ProviderGuid)) return;
            eventCount++;

            int eid          = (int)evt.ID;
            var actKey       = evt.ActivityID.ToString("D").ToUpperInvariant();
            var osKey        = $"{evt.ProcessID}-{evt.ThreadID}";
            var evTime       = evt.TimeStamp.ToUniversalTime();
            var tsFileTime   = evTime.ToFileTimeUtc();
            if (tsFileTime < stats.MinFileTimeUtc) stats.MinFileTimeUtc = tsFileTime;
            if (tsFileTime > stats.MaxFileTimeUtc) stats.MaxFileTimeUtc = tsFileTime;
            bool isFormServer = evt.ProviderGuid == ProvFormServer;

            // Resolve tKey (SQL events borrow the X++ activity via osKey)
            var tKey = actKey;
            if (eid >= 4900 && eid <= 4924 && _osToActKey.TryGetValue(osKey, out var osAct))
                tKey = osAct;

            // Inline session map building
            var custVal = P(evt, "customer");
            var sessStr  = P(evt, "sessionId");
            var userVal  = PUser(evt);
            var reqStr   = P(evt, "requestId");

            if (!string.IsNullOrEmpty(custVal) && custVal != "_unknown" && !_custToSession.ContainsKey(custVal)
                && !string.IsNullOrEmpty(sessStr) && sessStr != "NULL")
                _custToSession[custVal] = (sessStr, userVal, custVal);

            if (!string.IsNullOrEmpty(reqStr) && reqStr != "{00000000-0000-0000-0000-000000000000}"
                && !_reqToSession.ContainsKey(reqStr) && !string.IsNullOrEmpty(sessStr) && sessStr != "NULL")
                _reqToSession[reqStr] = (sessStr, userVal, !string.IsNullOrEmpty(custVal) ? custVal : "_unknown");

            // EnsureThread local helper — uses dims (in-memory), no SQL
            int EnsureThread()
            {
                bool hasSess = !string.IsNullOrEmpty(sessStr) && sessStr != "NULL";
                if (!hasSess && dims.HasCachedThread(tKey) && !dims.HasNoSessKey(tKey))
                {
                    if (dims.HasCachedThread(tKey))
                        return GetCachedThread();
                }

                var sess = hasSess ? sessStr : null;
                var user = userVal;
                var cust = !string.IsNullOrEmpty(custVal) ? custVal : "_unknown";

                if (sess == null && !string.IsNullOrEmpty(reqStr) && _reqToSession.TryGetValue(reqStr, out var ri))
                { sess = ri.sess; user = ri.user; cust = ri.cust; }
                if (sess == null && cust != "_unknown" && _custToSession.TryGetValue(cust, out var ci))
                { sess = ci.sess; user = ci.user; cust = ci.cust; }
                if (sess == null && _osToSessionInfo.TryGetValue(osKey, out var oi))
                { sess = oi.sess; user = oi.user; cust = oi.cust; }

                if ((sess == null || sess == "_nosession") && dims.HasCachedThread(tKey))
                    return GetCachedThread();

                if (dims.HasNoSessKey(tKey) && !string.IsNullOrEmpty(sess) && sess != "_nosession")
                {
                    dims.SetNoSessKey(tKey, false);
                    dims.RemoveThread(tKey);
                }

                if (!string.IsNullOrEmpty(osKey) && !string.IsNullOrEmpty(sess) && sess != "_nosession")
                    _osToSessionInfo[osKey] = (sess, user, cust);

                if (string.IsNullOrEmpty(sess) || sess == "_nosession")
                {
                    sess = "_nosession";
                    dims.SetNoSessKey(tKey, true);
                }

                var uid = dims.GetUserId(user);
                var cid = dims.GetCustomerId(cust);
                var sid = dims.GetUserSessionId(traceId, sess, uid, cid);

                if (dims.TryGetThreadSid(tKey, out var oldSid) && oldSid != sid)
                    dims.RemoveThread(tKey);
                dims.SetThreadSid(tKey, sid);
                return dims.GetThreadId(tKey, reqStr, sid, traceId);
            }

            int GetCachedThread()
                => dims.GetThreadId(tKey, reqStr, 0, traceId); // returns cached

            // ── Event dispatch ──────────────────────────────────────────────────
            switch (eid)
            {
                case 24500: // X++ Enter
                {
                    stats.Enter++;
                    var ts2 = GetTState(tKey);
                    _osToActKey[osKey] = tKey;
                    if (!string.IsNullOrEmpty(custVal) && _custToSession.TryGetValue(custVal, out var cv))
                        _osToSessionInfo[osKey] = cv;

                    var methodName = Intern(P(evt, "methodName"));
                    var isRec = ts2.MethodsInStack.ContainsKey(methodName);
                    var frame = new CallFrame
                    {
                        Seq         = ++_globalSeq,
                        FullMethod  = methodName,
                        FileName    = Intern(P(evt, "fileName")),
                        LineNumber  = int.TryParse(new string(P(evt, "lineNumber").Where(char.IsDigit).ToArray()), out var ln) ? ln : 0,
                        EnterTime   = evTime,
                        TSNs        = tsFileTime,
                        ParentSeq   = ts2.CallStack.Count > 0 ? ts2.CallStack.Peek().Seq : null,
                        IsRecursive = isRec,
                    };
                    ts2.MethodsInStack.TryGetValue(methodName, out var depth);
                    ts2.MethodsInStack[methodName] = depth + 1;
                    ts2.CallStack.Push(frame);
                    break;
                }
                case 24501: // X++ Exit
                {
                    stats.Exit++;
                    var ts2 = GetTState(tKey);
                    if (ts2.CallStack.Count == 0) break;
                    var exitMethod = P(evt, "methodName");
                    if (!string.IsNullOrEmpty(exitMethod) && ts2.CallStack.Peek().FullMethod != exitMethod)
                    { stats.Mismatch++; break; }
                    var f = ts2.CallStack.Pop();
                    if (ts2.MethodsInStack.TryGetValue(f.FullMethod, out var mc) && mc > 0)
                    { ts2.MethodsInStack[f.FullMethod] = mc - 1; if (mc - 1 == 0) ts2.MethodsInStack.Remove(f.FullMethod); }
                    var incTicks = Math.Max(0L, (evTime - f.EnterTime).Ticks);
                    var excTicks = Math.Max(0L, incTicks - f.ChildTime);
                    var exitSeq  = ++_globalSeq;
                    var mHash = dims.GetMethodHash(f.FullMethod);
                    dims.EnsureMethodName(f.FullMethod, mHash);
                    var tid = EnsureThread();
                    batch.Add(new StageRow
                    {
                        ThreadId = tid, CallTypeId = CT_XPP,
                        Seq = f.Seq, SeqEnd = exitSeq,
                        TS = f.TSNs, TSEnd = tsFileTime,
                        IncNano = incTicks, ExcNano = excTicks,
                        DbNano = f.DbNano, DbCalls = f.DbCalls,
                        ParentSeq = f.ParentSeq,
                        MethodHash = mHash, HasChildren = f.ChildTime > 0,
                        IsComplete = true, IsRecursive = f.IsRecursive,
                        FileName = f.FileName, LineNumber = f.LineNumber,
                        EventId = 24500, EventLevel = 5, EventType = 1,
                        EventName = "Entering X++ method.",
                    });
                    if (ts2.CallStack.Count > 0)
                    { var p = ts2.CallStack.Peek(); p.ChildTime += incTicks; p.DbCalls += f.DbCalls; p.DbNano += f.DbNano; }
                    break;
                }
                case 4923: // SQL Bind
                {
                    stats.Bind++;
                    var ts2 = GetTState(tKey);
                    var rawId = new string(P(evt, "sqlColumnId").Where(char.IsDigit).ToArray());
                    var colId = !string.IsNullOrEmpty(rawId) ? int.Parse(rawId) - 1 : -1;
                    if (colId < 0) { ts2.BindTimestamp = evTime; ts2.BindParams.Clear(); }
                    else ts2.BindParams[colId] = P(evt, "parameterValue");
                    var tid = EnsureThread();
                    var bindSeq = ++_globalSeq;
                    var pSeq = ts2.CallStack.Count > 0 ? ts2.CallStack.Peek().Seq : 0;
                    batch.Add(new StageRow { ThreadId = tid, CallTypeId = CT_SQLBIND, Seq = bindSeq, SeqEnd = bindSeq, TS = tsFileTime, TSEnd = tsFileTime, ParentSeq = pSeq, IsComplete = true, EventId = 4923, EventLevel = 5, EventType = 4, EventName = EventNames.GetValueOrDefault(4923, "") });
                    break;
                }
                case 4922: // SQL Statement
                {
                    stats.Stmt++;
                    var ts2 = GetTState(tKey);
                    var sql       = P(evt, "sqlStatement");
                    var prepTicks = ConvertSecToTicks(evt.PayloadByName("preparationTimeSeconds"));
                    var execTicks = ConvertSecToTicks(evt.PayloadByName("executionTimeSeconds"));
                    var bindTicks = 0L;
                    if (ts2.BindParams.Count > 0 && ts2.BindTimestamp != DateTime.MinValue)
                        bindTicks = Math.Max(0L, (evTime - ts2.BindTimestamp).Ticks - execTicks);
                    var incTicks  = prepTicks + execTicks + bindTicks;
                    var stmtHash  = dims.EnsureQueryStatement(sql);
                    var tableHash = dims.EnsureQueryTable(GetTableNamesInSql(sql));
                    var tid       = EnsureThread();
                    var stmtSeq   = ++_globalSeq;
                    var sqlStartFT = evTime.AddTicks(-incTicks).ToFileTimeUtc();
                    var parentSeq  = 0L;
                    if (ts2.CallStack.Count > 0) { var p = ts2.CallStack.Peek(); parentSeq = p.Seq; p.ChildTime += incTicks; p.DbCalls++; p.DbNano += incTicks; }
                    var rec = new StageRow
                    {
                        ThreadId = tid, CallTypeId = CT_SQL,
                        Seq = stmtSeq, SeqEnd = stmtSeq,
                        TS = sqlStartFT, TSEnd = tsFileTime,
                        IncNano = incTicks, ExcNano = execTicks,
                        DbNano = incTicks, DbCalls = 1,
                        ParentSeq = parentSeq,
                        StmtHash = stmtHash, TableHash = tableHash,
                        PrepNano = prepTicks, BindNano = bindTicks,
                        IsComplete = true, FileName = Intern(P(evt, "fileName")),
                        EventId = 4922, EventLevel = 4, EventType = 4,
                    };
                    foreach (var kv in ts2.BindParams)
                        bpBatch.Add(new BindParamRow { TempSeq = (int)stmtSeq, ThreadId = tid, ParamIdx = kv.Key, BindVal = kv.Value });
                    ts2.BindParams.Clear();
                    if (sql.TrimStart().StartsWith("SELECT", StringComparison.OrdinalIgnoreCase))
                    {
                        if (ts2.LastSelectStmt != null) batch.Add(ts2.LastSelectStmt);
                        ts2.LastSelectStmt = rec;
                    }
                    else batch.Add(rec);
                    break;
                }
                case 4924: // SQL Fetch
                {
                    stats.Fetch++;
                    var ts2 = GetTState(tKey);
                    var fetchTicks = ConvertSecToTicks(evt.PayloadByName("executionTimeSeconds"));
                    if (ts2.LastSelectStmt != null)
                    { ts2.LastSelectStmt.FetchNano += fetchTicks; ts2.LastSelectStmt.IncNano += fetchTicks; ts2.LastSelectStmt.FetchCount++; }
                    var tid = EnsureThread();
                    var fetchSeq = ++_globalSeq;
                    batch.Add(new StageRow { ThreadId = tid, CallTypeId = CT_SQLFETCH, Seq = fetchSeq, SeqEnd = fetchSeq, TS = tsFileTime, TSEnd = tsFileTime, IsComplete = true, EventId = 4924, EventLevel = 5, EventType = 4, EventName = EventNames.GetValueOrDefault(4924, "") });
                    break;
                }
                default:
                {
                    if (InteractionEnter.TryGetValue(eid, out var interName))
                    {
                        stats.Enter++;
                        var ts2 = GetTState(tKey);
                        _osToActKey[osKey] = tKey;
                        ts2.CallStack.Push(new CallFrame { Seq = ++_globalSeq, FullMethod = interName, EnterTime = evTime, TSNs = tsFileTime, ParentSeq = ts2.CallStack.Count > 0 ? ts2.CallStack.Peek().Seq : null, EnterEid = eid });
                    }
                    else if (InteractionExit.Contains(eid))
                    {
                        stats.Exit++;
                        var ts2 = GetTState(tKey);
                        if (ts2.CallStack.Count == 0) break;
                        var peek = ts2.CallStack.Peek();
                        if (peek.EnterEid == null || peek.EnterEid != eid - 1) { stats.Mismatch++; break; }
                        var f = ts2.CallStack.Pop();
                        var incTicks = Math.Max(0L, (evTime - f.EnterTime).Ticks);
                        var excTicks = Math.Max(0L, incTicks - f.ChildTime);
                        var exitSeq  = ++_globalSeq;
                        var mHash = dims.GetMethodHash(f.FullMethod);
                        dims.EnsureMethodName(f.FullMethod, mHash);
                        var tid = EnsureThread();
                        batch.Add(new StageRow
                        {
                            ThreadId = tid, CallTypeId = CT_XPP, Seq = f.Seq, SeqEnd = exitSeq,
                            TS = f.TSNs, TSEnd = tsFileTime, IncNano = incTicks, ExcNano = excTicks,
                            DbNano = f.DbNano, DbCalls = f.DbCalls, ParentSeq = f.ParentSeq,
                            MethodHash = mHash, HasChildren = f.ChildTime > 0, IsComplete = true,
                            EventId = f.EnterEid ?? eid, EventLevel = 5, EventType = 1,
                            EventName = EventNames.GetValueOrDefault(f.EnterEid ?? eid, ""),
                        });
                        if (ts2.CallStack.Count > 0) { var p = ts2.CallStack.Peek(); p.ChildTime += incTicks; p.DbCalls += f.DbCalls; p.DbNano += f.DbNano; }
                    }
                    else if (isFormServer)
                    {
                        stats.Msg++;
                        var ts2 = GetTState(tKey);
                        var tid = EnsureThread();
                        var msgSeq = ++_globalSeq;
                        var pSeq = ts2.CallStack.Count > 0 ? ts2.CallStack.Peek().Seq : 0L;
                        var msgText = "";
                        try { msgText = evt.PayloadByName("Message")?.ToString() ?? ""; } catch { }
                        var msgH = dims.EnsureMessage(msgText);
                        batch.Add(new StageRow { ThreadId = tid, CallTypeId = 0, Seq = msgSeq, SeqEnd = msgSeq, TS = tsFileTime, TSEnd = tsFileTime, ParentSeq = pSeq, MsgHash = msgH, IsComplete = true, EventId = eid, EventLevel = 5, EventType = 3 });
                    }
                    else
                    {
                        stats.Msg++;
                        var ts2 = GetTState(tKey);
                        var tid = EnsureThread();
                        var msgSeq = ++_globalSeq;
                        var pSeq = ts2.CallStack.Count > 0 ? ts2.CallStack.Peek().Seq : 0L;
                        var evtName = EventNames.GetValueOrDefault(eid, evt.EventName ?? $"Event_{eid}");
                        var msgH = dims.EnsureMessage($"[{eid}] {evtName}");
                        batch.Add(new StageRow { ThreadId = tid, CallTypeId = CT_MSG, Seq = msgSeq, SeqEnd = msgSeq, TS = tsFileTime, TSEnd = tsFileTime, ParentSeq = pSeq, MsgHash = msgH, IsComplete = true, EventId = eid, EventLevel = 4, EventType = 3, EventName = EventNames.GetValueOrDefault(eid, "") });
                    }
                    break;
                }
            }

            // Progress logging + streaming flush
            if (eventCount % 1_000_000 == 0)
                logger.LogInformation("  Parsed {Count:N0} D365 events, batch={Batch:N0}...", eventCount, batch.Count);

            if (batch.Count >= BATCH_SIZE)
            {
                batchNum++;
                logger.LogInformation("  Sending batch #{Num} ({Count:N0} rows, total so far: {Total:N0}) to SQL writer...",
                    batchNum, batch.Count, totalFlushed + batch.Count);
                totalFlushed += batch.Count;
                // Hand off batch to consumer; create new lists for next batch
                channel.Writer.WriteAsync((batch, bpBatch), cts.Token).AsTask().GetAwaiter().GetResult();
                batch = new List<StageRow>(BATCH_SIZE);
                bpBatch = new List<BindParamRow>();
                if (consumerError != null) throw new InvalidOperationException("SQL flush failed", consumerError);
            }
        };

        source.Process();

        // Diagnostic: report manifest coverage
        logger.LogInformation(
            "Event stats: TotalETW={All:N0}, D365viaAllEvents={D365:N0}, D365viaDynamic={Dyn:N0}, Providers={P}",
            allEventCount, d365AllCount, eventCount, providersSeen.Count);
        foreach (var pg in providersSeen)
            logger.LogInformation("  Provider: {Guid}, isD365={IsD365}", pg, D365Providers.Contains(pg));

        // Flush held SELECTs
        foreach (var ts2 in _tState.Values)
            if (ts2.LastSelectStmt != null) { batch.Add(ts2.LastSelectStmt); ts2.LastSelectStmt = null; }

        // Flush incomplete stack entries (IsComplete=false)
        foreach (var kvp in _tState)
        {
            var ts2 = kvp.Value;
            while (ts2.CallStack.Count > 0)
            {
                var f = ts2.CallStack.Pop();
                var exitSeq = ++_globalSeq;
                var mHash = dims.GetMethodHash(f.FullMethod);
                dims.EnsureMethodName(f.FullMethod, mHash);
                if (dims.HasCachedThread(kvp.Key))
                {
                    batch.Add(new StageRow
                    {
                        ThreadId = dims.GetThreadId(kvp.Key, "", 0, traceId),
                        CallTypeId = CT_XPP, Seq = f.Seq, SeqEnd = exitSeq,
                        TS = f.TSNs, TSEnd = f.TSNs, DbNano = f.DbNano, DbCalls = f.DbCalls,
                        ParentSeq = f.ParentSeq, MethodHash = mHash, HasChildren = f.ChildTime > 0,
                        IsComplete = false, IsRecursive = f.IsRecursive,
                        FileName = f.FileName, LineNumber = f.LineNumber,
                        EventId = 24500, EventLevel = 5, EventType = 1, EventName = "Entering X++ method.",
                    });
                }
            }
        }

        // Final flush — send remaining rows to channel and complete
        if (batch.Count > 0)
        {
            batchNum++;
            logger.LogInformation("  Sending final batch #{Num} ({Count:N0} rows, total: {Total:N0}) to SQL writer...",
                batchNum, batch.Count, totalFlushed + batch.Count);
            totalFlushed += batch.Count;
            channel.Writer.WriteAsync((batch, bpBatch), cts.Token).AsTask().GetAwaiter().GetResult();
        }
        channel.Writer.Complete();
        consumerTask.GetAwaiter().GetResult(); // wait for all SQL writes to finish
        if (consumerError != null) throw new InvalidOperationException("SQL flush failed", consumerError);

        stats.Staged = totalFlushed;
        logger.LogInformation("Streaming complete. {Total:N0} rows flushed to StageTraceLines in {Batches} batches.",
            totalFlushed, batchNum);

        return stats;
    }

    /// <summary>
    /// Port of PS Get-TableNamesInSql — extracts table names from a SQL statement.
    /// </summary>
    private static string GetTableNamesInSql(string sql)
    {
        if (string.IsNullOrWhiteSpace(sql)) return "";
        sql = sql.Trim('{', '}', ' ', '\t');
        if (sql.Length == 0) return "";
        var c = char.ToUpperInvariant(sql[0]);
        int pos = 0;
        if (c == 'E' && sql.Length > 24) { pos = 24; c = char.ToUpperInvariant(sql[pos]); }
        string tables = "";
        try
        {
            switch (c)
            {
                case 'S': // SELECT → FROM ... WHERE
                    int fi = sql.IndexOf(" FROM ", StringComparison.OrdinalIgnoreCase);
                    if (fi > 12)
                    {
                        fi += 6;
                        int wi = sql.IndexOf(" WHERE ", StringComparison.OrdinalIgnoreCase);
                        if (wi < 0) wi = sql.Length - 1;
                        var raw = sql[fi..(wi + 1)].Trim();
                        if (!raw.StartsWith("{"))
                        {
                            var parts = raw.Split(',');
                            if (parts.Length == 1)
                                tables = parts[0].Split(' ')[0].Trim().ToUpperInvariant();
                            else
                            {
                                var list = parts.Select(p => p.Split(' ')[0].Trim().ToUpperInvariant()).OrderBy(x => x).ToList();
                                tables = string.Join(", ", list);
                            }
                        }
                    }
                    break;
                case 'I' when sql.StartsWith("INSERT", StringComparison.OrdinalIgnoreCase):
                    var p2i = pos + 12; var eii = sql.IndexOf(" (", p2i, StringComparison.OrdinalIgnoreCase);
                    if (eii < 0) eii = sql.Length - 1;
                    tables = sql[p2i..eii].Trim().ToUpperInvariant();
                    break;
                case 'U' when sql.StartsWith("UPDATE", StringComparison.OrdinalIgnoreCase):
                    var p2u = pos + 7; var siu = sql.IndexOf(" SET ", p2u, StringComparison.OrdinalIgnoreCase);
                    if (siu < 0) siu = sql.Length - 1;
                    tables = sql[p2u..siu].Trim().ToUpperInvariant();
                    break;
                case 'D' when sql.StartsWith("DELETE", StringComparison.OrdinalIgnoreCase):
                    var p2d = pos + 12; var wid = sql.IndexOf(" WHERE ", p2d, StringComparison.OrdinalIgnoreCase);
                    if (wid < 0) wid = sql.Length - 1;
                    tables = sql[p2d..wid].Trim().ToUpperInvariant();
                    break;
            }
        }
        catch { }
        return tables;
    }
}
