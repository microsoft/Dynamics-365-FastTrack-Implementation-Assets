using System.Data;
using System.Text;
using Microsoft.Data.SqlClient;
using Microsoft.Extensions.Logging;

namespace TraceParserFunction;

/// <summary>
/// Row to be inserted into StageTraceLines (matches PS script's batch hashtable keys).
/// </summary>
public class StageRow
{
    public long   TraceLineId;  // assigned during flush
    public int    ThreadId;
    public int    CallTypeId;
    public long   Seq;
    public long   SeqEnd;
    public long   TS;           // FileTimeUtc
    public long   TSEnd;
    public long   IncNano;
    public long   ExcNano;
    public long   DbNano;
    public int    DbCalls;
    public long?  ParentSeq;
    public long?  StmtHash;
    public long?  TableHash;
    public long   PrepNano;
    public long   BindNano;
    public long   FetchNano;
    public int    FetchCount;
    public long?  MethodHash;
    public long?  MsgHash;
    public long?  StackHash;
    public bool   HasChildren;
    public bool   IsComplete;
    public bool   IsRecursive;
    public long   TxParentSeq;
    public string FileName   = "";
    public int    LineNumber;
    public int    EventId;
    public int    EventLevel;
    public int    EventType;
    public string EventName  = "";
    public long   Rpc;
    public int    RoleId;
    public int    RoleInstId;
    public int    TenantId;
}

public class BindParamRow
{
    public int    TempSeq;   // Seq of parent SQL statement
    public int    ThreadId;
    public int    ParamIdx;
    public string? BindVal;
    public long?  TraceLineId;
}

public class ParseStats
{
    public int Enter, Exit, Stmt, Bind, Fetch, Msg, Mismatch;
    public long Staged;
    public long MinFileTimeUtc = long.MaxValue;  // earliest event
    public long MaxFileTimeUtc = long.MinValue;  // latest event
}

/// <summary>
/// Handles all SQL operations: dimension upserts, TraceLineId reservation, bulk copy, SP call.
/// </summary>
public class SqlImporter(ILogger<SqlImporter> logger)
{
    // In-memory caches (string/hash → id or true)
    private readonly Dictionary<string, int>  _cacheHost    = new();
    private readonly Dictionary<string, int>  _cacheCust    = new();
    private readonly Dictionary<string, int>  _cacheUser    = new();
    private readonly Dictionary<string, int>  _cacheSession = new(); // "traceId:sessStr" → SessionId
    private readonly Dictionary<string, int>  _cacheThread  = new(); // actKey → ThreadId
    private readonly Dictionary<string, int>  _cacheThreadSid = new(); // actKey → SessionId
    private readonly Dictionary<long, bool>   _cacheMethod  = new();
    private readonly Dictionary<long, bool>   _cacheStmt    = new();
    private readonly Dictionary<long, bool>   _cacheTable   = new();
    private readonly Dictionary<long, bool>   _cacheMsg     = new();
    private readonly List<BindParamRow>        _allBindParams = new();

    // ----- Hash -----
    private static readonly System.Security.Cryptography.SHA256 Sha256
        = System.Security.Cryptography.SHA256.Create();
    private static readonly Dictionary<string, long> HashCache = new();

    public static long ComputeHash(string text)
    {
        text ??= "";
        if (HashCache.TryGetValue(text, out var cached)) return cached;
        var bytes = System.Text.Encoding.UTF8.GetBytes(text);
        var sha = Sha256.ComputeHash(bytes);
        var h = BitConverter.ToInt64(sha, 0);
        HashCache[text] = h;
        return h;
    }

    internal static string StripMethodPrefix(string name)
    {
        const string prefix = "Dynamics.AX.";
        if (name.StartsWith(prefix, StringComparison.Ordinal))
        {
            var dot = name.IndexOf('.', prefix.Length);
            if (dot >= 0) return name[(dot + 1)..];
        }
        return name;
    }

    public long GetMethodHash(string name)
    {
        if (string.IsNullOrWhiteSpace(name)) return 0L;
        return ComputeHash(StripMethodPrefix(name).ToLowerInvariant());
    }

    // ----- Dimension helpers -----
    public int GetHostId(SqlConnection conn, string name)
        => UpsertLookup(conn, _cacheHost, name ?? "_unknown", "Hosts", "HostName", "HostId");

    public int GetCustomerId(SqlConnection conn, string name)
        => UpsertLookup(conn, _cacheCust, name ?? "_unknown", "Customers", "CustomerName", "CustomerId");

    public int GetUserId(SqlConnection conn, string name)
        => UpsertLookup(conn, _cacheUser, name ?? "_system", "Users", "UserName", "UserId");

    private int UpsertLookup(SqlConnection conn, Dictionary<string, int> cache, string val,
                              string table, string keyCol, string idCol)
    {
        if (string.IsNullOrWhiteSpace(val)) val = "_unknown";
        if (cache.TryGetValue(val, out var id)) return id;
        using var cmd = conn.CreateCommand();
        cmd.CommandText = $"SELECT {idCol} FROM {table} WHERE {keyCol}=@v";
        cmd.Parameters.AddWithValue("@v", val);
        var r = cmd.ExecuteScalar();
        if (r != null && r != DBNull.Value) { id = (int)r; cache[val] = id; return id; }
        cmd.CommandText = $"INSERT INTO {table} ({keyCol}) OUTPUT INSERTED.{idCol} VALUES(@v)";
        id = (int)cmd.ExecuteScalar()!;
        cache[val] = id;
        return id;
    }

    public int GetUserSessionId(SqlConnection conn, int traceId, string sessStr, int userId, int custId)
    {
        if (string.IsNullOrEmpty(sessStr)) sessStr = "_nosession";
        var ck = $"{traceId}:{sessStr}";
        if (_cacheSession.TryGetValue(ck, out var id)) return id;
        using var cmd = conn.CreateCommand();
        cmd.CommandText = @"
            DECLARE @nextId int
            SELECT @nextId = ISNULL(MAX(SessionId),0) + 1 FROM UserSessions
            INSERT INTO UserSessions(SessionId,TraceId,UserId,SessionName,CustomerCustomerId)
            VALUES(@nextId,@t,@u,@s,@c)
            SELECT @nextId";
        cmd.Parameters.AddWithValue("@t", traceId);
        cmd.Parameters.AddWithValue("@u", userId);
        cmd.Parameters.AddWithValue("@s", sessStr);
        cmd.Parameters.AddWithValue("@c", custId);
        id = (int)cmd.ExecuteScalar()!;
        _cacheSession[ck] = id;
        return id;
    }

    public int GetThreadId(SqlConnection conn, string actStr, string reqStr, int sessId, int traceId)
    {
        if (_cacheThread.TryGetValue(actStr, out var id)) return id;
        Guid.TryParse(actStr, out var ag);
        Guid.TryParse(reqStr, out var rg);
        using var cmd = conn.CreateCommand();
        cmd.CommandText = @"
            INSERT INTO UserSessionProcessThreads(RequestId,ActivityId,RelatedActivityId,SessionId,TraceId)
            OUTPUT INSERTED.UserSessionProcessThreadId VALUES(@r,@a,@ra,@s,@t)";
        cmd.Parameters.AddWithValue("@r", rg);
        cmd.Parameters.AddWithValue("@a", ag);
        cmd.Parameters.AddWithValue("@ra", Guid.Empty);
        cmd.Parameters.AddWithValue("@s", sessId);
        cmd.Parameters.AddWithValue("@t", traceId);
        id = (int)cmd.ExecuteScalar()!;
        _cacheThread[actStr] = id;
        return id;
    }

    public void EnsureMethodName(SqlConnection conn, string name, long hash)
    {
        if (hash == 0L || _cacheMethod.ContainsKey(hash)) return;
        var shortName = StripMethodPrefix(name);
        using var cmd = conn.CreateCommand();
        cmd.CommandText = @"
            IF NOT EXISTS(SELECT 1 FROM MethodNames WHERE MethodHash=@h)
                INSERT INTO MethodNames(MethodHash,Name,TargetType) VALUES(@h,@n,1)";
        cmd.Parameters.AddWithValue("@h", hash);
        cmd.Parameters.AddWithValue("@n", shortName.Length > 500 ? shortName[..500] : shortName);
        cmd.ExecuteNonQuery();
        _cacheMethod[hash] = true;
    }

    public long EnsureQueryStatement(SqlConnection conn, string stmt)
    {
        if (string.IsNullOrWhiteSpace(stmt)) return 0L;
        stmt = stmt.ToUpperInvariant();
        var h = ComputeHash(stmt);
        if (_cacheStmt.ContainsKey(h)) return h;
        using var cmd = conn.CreateCommand();
        cmd.CommandText = @"
            IF NOT EXISTS(SELECT 1 FROM QueryStatements WHERE QueryStatementHash=@h)
                INSERT INTO QueryStatements(QueryStatementHash,Statement) VALUES(@h,@s)";
        cmd.Parameters.AddWithValue("@h", h);
        cmd.Parameters.AddWithValue("@s", stmt.Length > 4000 ? stmt[..4000] : stmt);
        cmd.ExecuteNonQuery();
        _cacheStmt[h] = true;
        return h;
    }

    public long EnsureQueryTable(SqlConnection conn, string tables)
    {
        tables ??= "";
        var h = ComputeHash(tables);
        if (_cacheTable.ContainsKey(h)) return h;
        using var cmd = conn.CreateCommand();
        cmd.CommandText = @"
            IF NOT EXISTS(SELECT 1 FROM QueryTables WHERE QueryTableHash=@h)
                INSERT INTO QueryTables(QueryTableHash,TableNames) VALUES(@h,@t)";
        cmd.Parameters.AddWithValue("@h", h);
        cmd.Parameters.AddWithValue("@t", tables.Length > 1000 ? tables[..1000] : tables);
        cmd.ExecuteNonQuery();
        _cacheTable[h] = true;
        return h;
    }

    public long? EnsureMessage(SqlConnection conn, string text)
    {
        if (string.IsNullOrWhiteSpace(text)) return null;
        var h = ComputeHash(text);
        if (!_cacheMsg.ContainsKey(h))
        {
            using var cmd = conn.CreateCommand();
            cmd.CommandText = @"
                IF NOT EXISTS(SELECT 1 FROM Messages WHERE MessageHash=@h)
                    INSERT INTO Messages(MessageHash,MessageText) VALUES(@h,@t)";
            cmd.Parameters.AddWithValue("@h", h);
            cmd.Parameters.AddWithValue("@t", text.Length > 4000 ? text[..4000] : text);
            cmd.ExecuteNonQuery();
            _cacheMsg[h] = true;
        }
        return h;
    }

    public void AddBindParams(List<BindParamRow> rows) => _allBindParams.AddRange(rows);

    // ----- TraceId management -----
    public async Task<int> EnsureTraceAsync(SqlConnection conn, string sessionName, string blobName)
    {
        using var cmd = conn.CreateCommand();
        cmd.CommandText = @"
            INSERT INTO Traces(TraceName,TraceFile,TimeStampBegin,TimeStampEnd,TraceParserVersion)
            OUTPUT INSERTED.TraceId
            VALUES(@n,@f,GETUTCDATE(),GETUTCDATE(),'C#-AzureFunction')";
        cmd.Parameters.AddWithValue("@n", sessionName.Length > 500 ? sessionName[..500] : sessionName);
        cmd.Parameters.AddWithValue("@f", blobName.Length > 500 ? blobName[..500] : blobName);
        return (int)(await cmd.ExecuteScalarAsync())!;
    }

    public async Task UpdateTraceTimestampsAsync(SqlConnection conn, int traceId,
        long minFileTimeUtc, long maxFileTimeUtc)
    {
        if (minFileTimeUtc >= maxFileTimeUtc) return;
        var tsBegin = DateTime.FromFileTimeUtc(minFileTimeUtc);
        var tsEnd   = DateTime.FromFileTimeUtc(maxFileTimeUtc);
        using var cmd = conn.CreateCommand();
        cmd.CommandText = @"UPDATE Traces SET TimeStampBegin=@b, TimeStampEnd=@e WHERE TraceId=@id";
        cmd.Parameters.AddWithValue("@b", tsBegin);
        cmd.Parameters.AddWithValue("@e", tsEnd);
        cmd.Parameters.AddWithValue("@id", traceId);
        await cmd.ExecuteNonQueryAsync();
    }

    // ----- TraceLineId reservation -----
    private long ReserveTraceLineIds(SqlConnection conn, int count)
    {
        using var cmd = conn.CreateCommand();
        cmd.CommandText = "EXEC ReserveTraceLineIds @batchSize";
        cmd.CommandTimeout = 60;
        cmd.Parameters.AddWithValue("@batchSize", (long)count);
        var r = cmd.ExecuteScalar();
        return r == null || r == DBNull.Value ? 1L : (long)Convert.ChangeType(r, typeof(long));
    }

    // ----- Batch flush (streaming: rows may have temp negative ThreadIds) -----
    public void FlushStageBatch(SqlConnection conn, List<StageRow> rows, List<BindParamRow> bpRows)
    {
        if (rows.Count == 0) return;
        var firstId = ReserveTraceLineIds(conn, rows.Count);
        var seqMap = new Dictionary<long, long>();
        for (int i = 0; i < rows.Count; i++)
        {
            rows[i].TraceLineId = firstId + i;
            seqMap[rows[i].Seq] = firstId + i;
        }
        foreach (var bp in bpRows)
            if (seqMap.TryGetValue(bp.TempSeq, out var tlid))
                bp.TraceLineId = tlid;

        using var bc = new SqlBulkCopy(conn)
        {
            DestinationTableName = "StageTraceLines",
            BatchSize = rows.Count,
            BulkCopyTimeout = 300
        };
        var dt = BuildDataTable(rows);
        foreach (DataColumn col in dt.Columns)
            bc.ColumnMappings.Add(col.ColumnName, col.ColumnName);
        bc.WriteToServer(dt);
        dt.Dispose();

        foreach (var bp in bpRows)
            if (seqMap.TryGetValue(bp.TempSeq, out var stlid))
                bp.TraceLineId = stlid;
        _allBindParams.AddRange(bpRows);
    }

    // ----- Promote stage rows → TraceLines (replaces CopyTraceLinesFromStage SP) -----
    public async Task PromoteStageToTraceLines(SqlConnection conn)
    {
        var sw = System.Diagnostics.Stopwatch.StartNew();

        // 1. Discover and disable nonclustered indexes on TraceLines
        var ncIndexes = new List<string>();
        using (var cmd = conn.CreateCommand())
        {
            cmd.CommandText = @"SELECT i.name FROM sys.indexes i
                WHERE i.object_id = OBJECT_ID('TraceLines')
                  AND i.type_desc = 'NONCLUSTERED' AND i.name IS NOT NULL";
            using var rdr = cmd.ExecuteReader();
            while (rdr.Read()) ncIndexes.Add(rdr.GetString(0));
        }
        foreach (var idx in ncIndexes)
        {
            using var cmd = conn.CreateCommand();
            cmd.CommandText = $"ALTER INDEX [{idx}] ON TraceLines DISABLE";
            cmd.CommandTimeout = 120;
            cmd.ExecuteNonQuery();
        }
        logger.LogInformation("Disabled {Count} nonclustered indexes ({Elapsed}ms)",
            ncIndexes.Count, sw.ElapsedMilliseconds);

        // 2. INSERT with IDENTITY_INSERT ON + TABLOCK (TraceLineIds already reserved)
        using (var cmd = conn.CreateCommand())
        {
            cmd.CommandTimeout = 3600;  // 60 min (safety margin for 10M+ rows)
            cmd.CommandText = @"
                SET IDENTITY_INSERT TraceLines ON;
                INSERT INTO TraceLines WITH (TABLOCK)
                    (TraceLineId, UserSessionProcessThreadId, CallTypeId,
                     Sequence, SequenceEnd, [TimeStamp], TimeStampEnd,
                     InclusiveDurationNano, ExclusiveDurationNano, DatabaseDurationNano,
                     ParentSequence, InclusiveRpc, DatabaseCalls,
                     QueryStatementHash, QueryTableHash,
                     PrepDurationNano, BindDurationNano, RowFetchDurationNano, RowFetchCount,
                     MethodHash, MessageHash, CallstackHash,
                     HasChildren, IsComplete, IsRecursive, TransactionParentSequence,
                     FileName, RoleRoleId, RoleInstanceRoleInstanceId,
                     EventLevel, EventId, AzureTenantAzureTenantId,
                     EventType, PropertiesXml, LineNumber, EventName)
                SELECT
                     TraceLineId, UserSessionProcessThreadId, CallTypeId,
                     Sequence, SequenceEnd, [TimeStamp], TimeStampEnd,
                     InclusiveDurationNano, ExclusiveDurationNano, DatabaseDurationNano,
                     ParentSequence, InclusiveRpc, DatabaseCalls,
                     QueryStatementHash, QueryTableHash,
                     PrepDurationNano, BindDurationNano, RowFetchDurationNano, RowFetchCount,
                     MethodHash, MessageHash, CallstackHash,
                     HasChildren, IsComplete, IsRecursive, TransactionParentSequence,
                     FileName, RoleRoleId, RoleInstanceRoleInstanceId,
                     EventLevel, EventId, AzureTenantAzureTenantId,
                     EventType, PropertiesXml, LineNumber, EventName
                FROM StageTraceLines;
                SET IDENTITY_INSERT TraceLines OFF;";
            var rows = await cmd.ExecuteNonQueryAsync();
            logger.LogInformation("Inserted {Rows:N0} rows into TraceLines ({Elapsed}ms)",
                rows, sw.ElapsedMilliseconds);
        }

        // 3. Rebuild nonclustered indexes
        foreach (var idx in ncIndexes)
        {
            using var cmd = conn.CreateCommand();
            cmd.CommandText = $"ALTER INDEX [{idx}] ON TraceLines REBUILD";
            cmd.CommandTimeout = 1800;  // 30 min (safety margin for 10M+ rows)
            cmd.ExecuteNonQuery();
            logger.LogInformation("  Rebuilt index [{Index}] ({Elapsed}ms)", idx, sw.ElapsedMilliseconds);
        }

        // 4. Update statistics + truncate staging
        using (var cmd = conn.CreateCommand())
        {
            cmd.CommandTimeout = 300;
            cmd.CommandText = "UPDATE STATISTICS TraceLines; TRUNCATE TABLE StageTraceLines;";
            await cmd.ExecuteNonQueryAsync();
        }
        logger.LogInformation("PromoteStageToTraceLines complete. Total: {Elapsed}ms", sw.ElapsedMilliseconds);
    }

    // ----- Bind param insert (after SP promotes stage rows to TraceLines) -----
    public async Task InsertBindParamsAsync(SqlConnection conn, int traceId)
    {
        logger.LogInformation("Inserting {Count:N0} bind parameters...", _allBindParams.Count);
        if (_allBindParams.Count == 0) return;
        // Build lookup: threadId_seq → TraceLineId
        var tlMap = new Dictionary<string, long>();
        using (var cmd = conn.CreateCommand())
        {
            cmd.CommandText = @"
                SELECT tl.UserSessionProcessThreadId, tl.Sequence, tl.TraceLineId
                FROM TraceLines tl
                INNER JOIN UserSessionProcessThreads t ON tl.UserSessionProcessThreadId = t.UserSessionProcessThreadId
                WHERE t.TraceId=@tid AND tl.CallTypeId=64";
            cmd.CommandTimeout = 300;
            cmd.Parameters.AddWithValue("@tid", traceId);
            using var rdr = await cmd.ExecuteReaderAsync();
            while (await rdr.ReadAsync())
                tlMap[$"{rdr[0]}_{rdr[1]}"] = (long)rdr[2];
        }
        var dt = new DataTable();
        dt.Columns.Add("TraceLineId",    typeof(long));
        dt.Columns.Add("ParameterIndex", typeof(int));
        var vc = dt.Columns.Add("BindValue", typeof(string)); vc.AllowDBNull = true;
        foreach (var bp in _allBindParams)
        {
            var key = $"{bp.ThreadId}_{bp.TempSeq}";
            if (!tlMap.TryGetValue(key, out var tlid)) continue;
            var dr = dt.NewRow();
            dr["TraceLineId"]    = tlid;
            dr["ParameterIndex"] = bp.ParamIdx;
            dr["BindValue"]      = (object?)bp.BindVal ?? DBNull.Value;
            dt.Rows.Add(dr);
        }
        if (dt.Rows.Count > 0)
        {
            using var bc = new SqlBulkCopy(conn) { DestinationTableName = "QueryBindParameters", BulkCopyTimeout = 300 };
            bc.ColumnMappings.Add("TraceLineId", "TraceLineId");
            bc.ColumnMappings.Add("ParameterIndex", "ParameterIndex");
            bc.ColumnMappings.Add("BindValue", "BindValue");
            await bc.WriteToServerAsync(dt);
        }
        if (dt.Rows.Count > 0)
            logger.LogInformation("Bind parameters inserted: {Rows:N0} rows.", dt.Rows.Count);
        dt.Dispose();
    }

    /// <summary>
    /// Populates pre-computed SessionMetrics and TopMethodsBySession tables.
    /// Called after PromoteStageToTraceLines + InsertBindParamsAsync.
    /// </summary>
    public async Task PopulateSessionAggregationsAsync(SqlConnection conn, int traceId)
    {
        var sw = System.Diagnostics.Stopwatch.StartNew();
        using var cmd = conn.CreateCommand();
        cmd.CommandText = "EXEC dbo.sp_PopulateSessionAggregations @TraceId";
        cmd.CommandTimeout = 1800;
        cmd.Parameters.AddWithValue("@TraceId", traceId);
        await cmd.ExecuteNonQueryAsync();
        logger.LogInformation("PopulateSessionAggregations complete for TraceId={TraceId} ({Elapsed}ms)",
            traceId, sw.ElapsedMilliseconds);
    }

    /// <summary>
    /// Clears accumulated state (singleton safety between imports).
    /// </summary>
    public void ClearState()
    {
        _allBindParams.Clear();
        _cacheHost.Clear();
        _cacheCust.Clear();
        _cacheUser.Clear();
        _cacheSession.Clear();
        _cacheThread.Clear();
        _cacheThreadSid.Clear();
        _cacheMethod.Clear();
        _cacheStmt.Clear();
        _cacheTable.Clear();
        _cacheMsg.Clear();
        _noSessKeys.Clear();
    }

    // ═══════════════════════════════════════════════════════════════════
    //  Streaming Pass 2: bulk insert dimensions, remap StageTraceLines
    // ═══════════════════════════════════════════════════════════════════

    /// <summary>
    /// Bulk-inserts all dimension tables. Returns threadMap (tempId → realId).
    /// </summary>
    public Dictionary<int, int> BulkInsertDimensions(SqlConnection conn, int traceId, InMemoryDimensions dims)
    {
        logger.LogInformation("Upserting dimensions...");

        var userMap = BulkUpsertNameDim(conn, dims.GetAllUsers(), "Users", "UserName", "UserId");
        logger.LogInformation("  Users: {Count} mapped.", userMap.Count);
        var custMap = BulkUpsertNameDim(conn, dims.GetAllCustomers(), "Customers", "CustomerName", "CustomerId");
        logger.LogInformation("  Customers: {Count} mapped.", custMap.Count);

        var sessMap = BulkUpsertSessions(conn, traceId, dims.GetAllSessions(), userMap, custMap);
        logger.LogInformation("  Sessions: {Count} inserted.", sessMap.Count);

        var threadMap = BulkUpsertThreads(conn, traceId, dims.GetAllThreads(), sessMap);
        logger.LogInformation("  Threads: {Count} inserted.", threadMap.Count);

        BulkUpsertHashDim(conn, dims.GetAllMethodNames(), "MethodNames", "MethodHash", "Name", 500, true);
        BulkUpsertHashDim(conn, dims.GetAllQueryStatements(), "QueryStatements", "QueryStatementHash", "Statement", 4000, false);
        BulkUpsertHashDim(conn, dims.GetAllQueryTables(), "QueryTables", "QueryTableHash", "TableNames", 1000, false);
        BulkUpsertHashDim(conn, dims.GetAllMessages(), "Messages", "MessageHash", "MessageText", 4000, false);
        logger.LogInformation("  Hash dims: Methods={M} Stmts={S} Tables={T} Msgs={Msg}",
            dims.GetAllMethodNames().Count, dims.GetAllQueryStatements().Count,
            dims.GetAllQueryTables().Count, dims.GetAllMessages().Count);

        return threadMap;
    }

    /// <summary>
    /// Remaps temp (negative) ThreadIds in StageTraceLines to real DB ThreadIds via UPDATE JOIN.
    /// Also remaps ThreadIds in the accumulated _allBindParams.
    /// </summary>
    public void RemapStageThreadIds(SqlConnection conn, Dictionary<int, int> threadMap)
    {
        if (threadMap.Count == 0) return;
        logger.LogInformation("Remapping {Count} temp ThreadIds in StageTraceLines...", threadMap.Count);

        // Create temp mapping table
        using (var cmd = conn.CreateCommand())
        {
            cmd.CommandText = "CREATE TABLE #ThreadMap (TempId INT NOT NULL PRIMARY KEY, RealId INT NOT NULL)";
            cmd.ExecuteNonQuery();
        }

        // Insert mappings
        foreach (var (tempId, realId) in threadMap)
        {
            using var cmd = conn.CreateCommand();
            cmd.CommandText = "INSERT INTO #ThreadMap(TempId, RealId) VALUES(@t, @r)";
            cmd.Parameters.AddWithValue("@t", tempId);
            cmd.Parameters.AddWithValue("@r", realId);
            cmd.ExecuteNonQuery();
        }

        // Add index on the join column for faster UPDATE
        using (var cmd = conn.CreateCommand())
        {
            cmd.CommandText = @"IF EXISTS (SELECT 1 FROM sys.indexes WHERE name='IX_Stage_ThreadId' AND object_id=OBJECT_ID('StageTraceLines'))
                                    DROP INDEX IX_Stage_ThreadId ON StageTraceLines;
                                CREATE NONCLUSTERED INDEX IX_Stage_ThreadId ON StageTraceLines(UserSessionProcessThreadId)";
            cmd.CommandTimeout = 600;
            cmd.ExecuteNonQuery();
        }
        logger.LogInformation("Created index on StageTraceLines.UserSessionProcessThreadId");

        // Single UPDATE with JOIN
        using (var cmd = conn.CreateCommand())
        {
            cmd.CommandText = @"UPDATE s SET s.UserSessionProcessThreadId = m.RealId
                                FROM StageTraceLines s
                                INNER JOIN #ThreadMap m ON s.UserSessionProcessThreadId = m.TempId";
            cmd.CommandTimeout = 3600; // 60 min — 10M+ rows on S3 100 DTU needs ~30 min
            var affected = cmd.ExecuteNonQuery();
            logger.LogInformation("Remapped {Affected:N0} rows in StageTraceLines.", affected);
        }

        using (var cmd = conn.CreateCommand())
        {
            cmd.CommandText = "DROP TABLE #ThreadMap";
            cmd.ExecuteNonQuery();
        }

        // Also remap accumulated bind params
        foreach (var bp in _allBindParams)
            if (threadMap.TryGetValue(bp.ThreadId, out var realId))
                bp.ThreadId = realId;
    }

    private Dictionary<int, int> BulkUpsertNameDim(SqlConnection conn,
        Dictionary<string, int> tempValues, string table, string keyCol, string idCol)
    {
        var map = new Dictionary<int, int>(); // tempId → realId
        if (tempValues.Count == 0) return map;

        // Load all existing rows
        var existing = new Dictionary<string, int>();
        using (var cmd = conn.CreateCommand())
        {
            cmd.CommandTimeout = 300;
            cmd.CommandText = $"SELECT {idCol}, {keyCol} FROM {table}";
            using var rdr = cmd.ExecuteReader();
            while (rdr.Read())
                existing[rdr.GetString(1)] = rdr.GetInt32(0);
        }

        // Map existing, collect new
        var toInsert = new List<(string name, int tempId)>();
        foreach (var (name, tempId) in tempValues)
        {
            if (existing.TryGetValue(name, out var realId))
                map[tempId] = realId;
            else
                toInsert.Add((name, tempId));
        }

        // Insert new values
        foreach (var (name, tempId) in toInsert)
        {
            using var cmd = conn.CreateCommand();
            cmd.CommandTimeout = 300;
            cmd.CommandText = $"INSERT INTO {table} ({keyCol}) OUTPUT INSERTED.{idCol} VALUES(@v)";
            cmd.Parameters.AddWithValue("@v", name);
            var realId = (int)cmd.ExecuteScalar()!;
            map[tempId] = realId;
        }

        return map;
    }

    private Dictionary<int, int> BulkUpsertSessions(SqlConnection conn, int traceId,
        List<SessionInfo> sessions, Dictionary<int, int> userMap, Dictionary<int, int> custMap)
    {
        var map = new Dictionary<int, int>(); // tempSessId → realSessId
        if (sessions.Count == 0) return map;

        using var cmd = conn.CreateCommand();
        cmd.CommandTimeout = 300;
        cmd.CommandText = "SELECT ISNULL(MAX(SessionId), 0) FROM UserSessions";
        var maxId = (int)cmd.ExecuteScalar()!;

        foreach (var sess in sessions)
        {
            maxId++;
            using var ins = conn.CreateCommand();
            ins.CommandTimeout = 300;
            ins.CommandText = @"INSERT INTO UserSessions(SessionId, TraceId, UserId, SessionName, CustomerCustomerId)
                               VALUES(@sid, @tid, @uid, @sn, @cid)";
            ins.Parameters.AddWithValue("@sid", maxId);
            ins.Parameters.AddWithValue("@tid", traceId);
            ins.Parameters.AddWithValue("@uid", userMap[sess.TempUserId]);
            ins.Parameters.AddWithValue("@sn", sess.SessionName);
            ins.Parameters.AddWithValue("@cid", custMap[sess.TempCustId]);
            ins.ExecuteNonQuery();
            map[sess.TempSessId] = maxId;
        }

        return map;
    }

    private Dictionary<int, int> BulkUpsertThreads(SqlConnection conn, int traceId,
        List<ThreadInfo> threads, Dictionary<int, int> sessMap)
    {
        var map = new Dictionary<int, int>(); // tempThreadId → realThreadId
        if (threads.Count == 0) return map;

        foreach (var t in threads)
        {
            Guid.TryParse(t.ActKey, out var ag);
            Guid.TryParse(t.ReqStr, out var rg);
            var realSessId = t.TempSessId == 0 ? 0 : sessMap.GetValueOrDefault(t.TempSessId, 0);
            using var cmd = conn.CreateCommand();
            cmd.CommandTimeout = 300;
            cmd.CommandText = @"INSERT INTO UserSessionProcessThreads(RequestId, ActivityId, RelatedActivityId, SessionId, TraceId)
                               OUTPUT INSERTED.UserSessionProcessThreadId VALUES(@r, @a, @ra, @s, @t)";
            cmd.Parameters.AddWithValue("@r", rg);
            cmd.Parameters.AddWithValue("@a", ag);
            cmd.Parameters.AddWithValue("@ra", Guid.Empty);
            cmd.Parameters.AddWithValue("@s", realSessId);
            cmd.Parameters.AddWithValue("@t", traceId);
            var realId = (int)cmd.ExecuteScalar()!;
            map[t.TempThreadId] = realId;
        }

        return map;
    }

    private void BulkUpsertHashDim(SqlConnection conn, Dictionary<long, string> items,
        string table, string hashCol, string textCol, int maxLen, bool addTargetType)
    {
        if (items.Count == 0) return;

        logger.LogInformation("  BulkUpsertHashDim: {Table} — {Count:N0} unique items", table, items.Count);
        var sw = System.Diagnostics.Stopwatch.StartNew();

        const int chunkSize = 50_000;
        var allItems = items.ToList();
        int totalInserted = 0;

        for (int offset = 0; offset < allItems.Count; offset += chunkSize)
        {
            var chunk = allItems.Skip(offset).Take(chunkSize).ToList();
            var chunkNum = offset / chunkSize + 1;
            var totalChunks = (allItems.Count + chunkSize - 1) / chunkSize;

            if (totalChunks > 1)
                logger.LogInformation("  BulkUpsertHashDim: {Table} — chunk {Chunk}/{Total} ({Count:N0} rows)",
                    table, chunkNum, totalChunks, chunk.Count);

            // Build DataTable for this chunk
            var dt = new DataTable();
            dt.Columns.Add("HashVal", typeof(long));
            dt.Columns.Add("TextVal", typeof(string));
            foreach (var (hash, text) in chunk)
            {
                var truncated = text.Length > maxLen ? text[..maxLen] : text;
                dt.Rows.Add(hash, truncated);
            }

            // Create temp table
            using (var cmd = conn.CreateCommand())
            {
                cmd.CommandText = $"CREATE TABLE #HashStage (HashVal BIGINT PRIMARY KEY, TextVal NVARCHAR({maxLen}))";
                cmd.ExecuteNonQuery();
            }

            // SqlBulkCopy to temp table
            using (var bcp = new SqlBulkCopy(conn) { DestinationTableName = "#HashStage", BulkCopyTimeout = 1800 })
            {
                bcp.ColumnMappings.Add("HashVal", "HashVal");
                bcp.ColumnMappings.Add("TextVal", "TextVal");
                bcp.WriteToServer(dt);
            }
            dt.Dispose();

            // INSERT WHERE NOT EXISTS
            var colExtra = addTargetType ? ",TargetType" : "";
            var selectExtra = addTargetType ? ",1" : "";
            using (var cmd = conn.CreateCommand())
            {
                cmd.CommandTimeout = 1800;
                cmd.CommandText = $@"
                    INSERT INTO {table} ({hashCol},{textCol}{colExtra})
                    SELECT s.HashVal, s.TextVal{selectExtra}
                    FROM #HashStage s
                    WHERE NOT EXISTS (SELECT 1 FROM {table} t WHERE t.{hashCol} = s.HashVal)";
                var inserted = cmd.ExecuteNonQuery();
                totalInserted += inserted;
            }

            using (var cmd = conn.CreateCommand())
            {
                cmd.CommandText = "DROP TABLE #HashStage";
                cmd.ExecuteNonQuery();
            }
        }

        logger.LogInformation("  BulkUpsertHashDim: {Table} — {Inserted:N0} new rows inserted ({Elapsed}ms total)",
            table, totalInserted, sw.ElapsedMilliseconds);
    }

    // ----- DataTable builder -----
    private static DataTable BuildDataTable(List<StageRow> rows)
    {
        var dt = new DataTable();
        (string name, Type t)[] cols = [
            ("TraceLineId",                  typeof(long)),
            ("UserSessionProcessThreadId",   typeof(int)),
            ("CallTypeId",                   typeof(int)),
            ("Sequence",                     typeof(long)),
            ("SequenceEnd",                  typeof(long)),
            ("TimeStamp",                    typeof(long)),
            ("TimeStampEnd",                 typeof(long)),
            ("InclusiveDurationNano",        typeof(long)),
            ("ExclusiveDurationNano",        typeof(long)),
            ("DatabaseDurationNano",         typeof(long)),
            ("DatabaseCalls",                typeof(int)),
            ("ParentSequence",               typeof(long)),
            ("QueryStatementHash",           typeof(long)),
            ("QueryTableHash",               typeof(long)),
            ("PrepDurationNano",             typeof(long)),
            ("BindDurationNano",             typeof(long)),
            ("RowFetchDurationNano",         typeof(long)),
            ("RowFetchCount",                typeof(int)),
            ("MethodHash",                   typeof(long)),
            ("MessageHash",                  typeof(long)),
            ("CallstackHash",                typeof(long)),
            ("HasChildren",                  typeof(bool)),
            ("IsComplete",                   typeof(bool)),
            ("IsRecursive",                  typeof(bool)),
            ("TransactionParentSequence",    typeof(long)),
            ("FileName",                     typeof(string)),
            ("LineNumber",                   typeof(int)),
            ("EventId",                      typeof(int)),
            ("EventLevel",                   typeof(int)),
            ("EventType",                    typeof(int)),
            ("EventName",                    typeof(string)),
            ("InclusiveRpc",                 typeof(long)),
            ("RoleRoleId",                   typeof(int)),
            ("RoleInstanceRoleInstanceId",   typeof(int)),
            ("AzureTenantAzureTenantId",     typeof(int)),
        ];
        foreach (var (name, t) in cols)
        {
            var col = dt.Columns.Add(name, t);
            col.AllowDBNull = true;
        }
        foreach (var r in rows)
        {
            var dr = dt.NewRow();
            dr["TraceLineId"]                = r.TraceLineId;
            dr["UserSessionProcessThreadId"] = r.ThreadId;
            dr["CallTypeId"]                 = r.CallTypeId;
            dr["Sequence"]                   = r.Seq;
            dr["SequenceEnd"]                = r.SeqEnd;
            dr["TimeStamp"]                  = r.TS;
            dr["TimeStampEnd"]               = r.TSEnd;
            dr["InclusiveDurationNano"]      = r.IncNano;
            dr["ExclusiveDurationNano"]      = r.ExcNano;
            dr["DatabaseDurationNano"]       = r.DbNano;
            dr["DatabaseCalls"]              = r.DbCalls;
            dr["ParentSequence"]             = (object?)r.ParentSeq ?? DBNull.Value;
            dr["QueryStatementHash"]         = (object?)r.StmtHash  ?? DBNull.Value;
            dr["QueryTableHash"]             = (object?)r.TableHash ?? DBNull.Value;
            dr["PrepDurationNano"]           = r.PrepNano;
            dr["BindDurationNano"]           = r.BindNano;
            dr["RowFetchDurationNano"]       = r.FetchNano;
            dr["RowFetchCount"]              = r.FetchCount;
            dr["MethodHash"]                 = (object?)r.MethodHash ?? DBNull.Value;
            dr["MessageHash"]                = (object?)r.MsgHash    ?? DBNull.Value;
            dr["CallstackHash"]              = (object?)r.StackHash  ?? DBNull.Value;
            dr["HasChildren"]                = r.HasChildren;
            dr["IsComplete"]                 = r.IsComplete;
            dr["IsRecursive"]                = r.IsRecursive;
            dr["TransactionParentSequence"]  = r.TxParentSeq;
            dr["FileName"]                   = (object?)r.FileName   ?? DBNull.Value;
            dr["LineNumber"]                 = r.LineNumber;
            dr["EventId"]                    = r.EventId;
            dr["EventLevel"]                 = r.EventLevel;
            dr["EventType"]                  = r.EventType;
            dr["EventName"]                  = (object?)r.EventName  ?? DBNull.Value;
            dr["InclusiveRpc"]               = r.Rpc;
            dr["RoleRoleId"]                 = r.RoleId;
            dr["RoleInstanceRoleInstanceId"] = r.RoleInstId;
            dr["AzureTenantAzureTenantId"]   = r.TenantId;
            dt.Rows.Add(dr);
        }
        return dt;
    }

    public bool HasCachedThread(string actKey) => _cacheThread.ContainsKey(actKey);
    public bool HasNoSessKey(string actKey) => _noSessKeys.ContainsKey(actKey);
    private readonly Dictionary<string, bool> _noSessKeys = new();
    public void SetNoSessKey(string actKey, bool v) { if (v) _noSessKeys[actKey] = true; else _noSessKeys.Remove(actKey); }
    public bool TryGetThreadSid(string actKey, out int sid) => _cacheThreadSid.TryGetValue(actKey, out sid);
    public void SetThreadSid(string actKey, int sid) => _cacheThreadSid[actKey] = sid;
    public void RemoveThread(string actKey) => _cacheThread.Remove(actKey);
}
