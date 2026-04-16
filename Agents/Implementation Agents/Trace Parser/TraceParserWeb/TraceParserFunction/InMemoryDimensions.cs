namespace TraceParserFunction;

public record SessionInfo(int TempSessId, string SessionName, int TempUserId, int TempCustId);
public record ThreadInfo(int TempThreadId, string ActKey, string ReqStr, int TempSessId);

/// <summary>
/// Collects all unique dimension values during in-memory ETL parsing (Pass 1).
/// Assigns negative temporary IDs that get remapped to real DB IDs in Pass 2.
/// </summary>
public class InMemoryDimensions
{
    // Name-based dimensions: name → tempId (negative)
    private readonly Dictionary<string, int> _users = new();
    private readonly Dictionary<string, int> _customers = new();
    private int _nextTempUserId = -1;
    private int _nextTempCustId = -1;

    // Session: "traceId:sessStr" → tempSessionId
    private readonly Dictionary<string, int> _sessions = new();
    private readonly List<SessionInfo> _allSessions = new();
    private int _nextTempSessionId = -1;

    // Thread: actKey → tempThreadId (current cache)
    private readonly Dictionary<string, int> _threads = new();
    private readonly Dictionary<string, int> _threadSid = new();
    private readonly Dictionary<string, bool> _noSessKeys = new();
    private readonly List<ThreadInfo> _allThreadsEverCreated = new();
    private int _nextTempThreadId = -1;

    // Hash-based dimensions: hash → text
    private readonly Dictionary<long, string> _methodNames = new();
    private readonly Dictionary<long, string> _queryStatements = new();
    private readonly Dictionary<long, string> _queryTables = new();
    private readonly Dictionary<long, string> _messages = new();

    // ── Name-based dimension lookups ──────────────────────────────────

    public int GetUserId(string name)
    {
        if (string.IsNullOrWhiteSpace(name)) name = "_system";
        if (_users.TryGetValue(name, out var id)) return id;
        id = _nextTempUserId--;
        _users[name] = id;
        return id;
    }

    public int GetCustomerId(string name)
    {
        if (string.IsNullOrWhiteSpace(name)) name = "_unknown";
        if (_customers.TryGetValue(name, out var id)) return id;
        id = _nextTempCustId--;
        _customers[name] = id;
        return id;
    }

    // ── Session ───────────────────────────────────────────────────────

    public int GetUserSessionId(int traceId, string sessStr, int tempUserId, int tempCustId)
    {
        if (string.IsNullOrEmpty(sessStr)) sessStr = "_nosession";
        var ck = $"{traceId}:{sessStr}";
        if (_sessions.TryGetValue(ck, out var id)) return id;
        id = _nextTempSessionId--;
        _sessions[ck] = id;
        _allSessions.Add(new SessionInfo(id, sessStr, tempUserId, tempCustId));
        return id;
    }

    // ── Thread ────────────────────────────────────────────────────────

    public int GetThreadId(string actKey, string reqStr, int tempSessId, int traceId)
    {
        if (_threads.TryGetValue(actKey, out var id)) return id;
        id = _nextTempThreadId--;
        _threads[actKey] = id;
        _allThreadsEverCreated.Add(new ThreadInfo(id, actKey, reqStr, tempSessId));
        return id;
    }

    public bool HasCachedThread(string actKey) => _threads.ContainsKey(actKey);
    public void RemoveThread(string actKey) => _threads.Remove(actKey);
    public bool TryGetThreadSid(string actKey, out int sid) => _threadSid.TryGetValue(actKey, out sid);
    public void SetThreadSid(string actKey, int sid) => _threadSid[actKey] = sid;
    public bool HasNoSessKey(string actKey) => _noSessKeys.ContainsKey(actKey);

    public void SetNoSessKey(string actKey, bool v)
    {
        if (v) _noSessKeys[actKey] = true;
        else _noSessKeys.Remove(actKey);
    }

    // ── Hash-based dimensions ─────────────────────────────────────────

    public long GetMethodHash(string name)
    {
        if (string.IsNullOrWhiteSpace(name)) return 0L;
        return SqlImporter.ComputeHash(SqlImporter.StripMethodPrefix(name).ToLowerInvariant());
    }

    public void EnsureMethodName(string name, long hash)
    {
        if (hash == 0L || _methodNames.ContainsKey(hash)) return;
        _methodNames[hash] = SqlImporter.StripMethodPrefix(name);
    }

    public long EnsureQueryStatement(string stmt)
    {
        if (string.IsNullOrWhiteSpace(stmt)) return 0L;
        stmt = stmt.ToUpperInvariant();
        var h = SqlImporter.ComputeHash(stmt);
        _queryStatements.TryAdd(h, stmt);
        return h;
    }

    public long EnsureQueryTable(string tables)
    {
        tables ??= "";
        var h = SqlImporter.ComputeHash(tables);
        _queryTables.TryAdd(h, tables);
        return h;
    }

    public long? EnsureMessage(string text)
    {
        if (string.IsNullOrWhiteSpace(text)) return null;
        var h = SqlImporter.ComputeHash(text);
        _messages.TryAdd(h, text);
        return h;
    }

    // ── Getters for Pass 2 ────────────────────────────────────────────

    public Dictionary<string, int> GetAllUsers() => new(_users);
    public Dictionary<string, int> GetAllCustomers() => new(_customers);
    public List<SessionInfo> GetAllSessions() => new(_allSessions);
    public List<ThreadInfo> GetAllThreads() => new(_allThreadsEverCreated);
    public Dictionary<long, string> GetAllMethodNames() => new(_methodNames);
    public Dictionary<long, string> GetAllQueryStatements() => new(_queryStatements);
    public Dictionary<long, string> GetAllQueryTables() => new(_queryTables);
    public Dictionary<long, string> GetAllMessages() => new(_messages);
}
