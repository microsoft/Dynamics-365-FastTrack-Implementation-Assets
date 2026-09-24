using System.Data;
using System.Security.Cryptography;
using System.Text.Json;
using Microsoft.Data.SqlClient;

namespace TraceParserFunction;

public sealed record ImportReceipt(Guid ImportId, int TraceId, string Phase)
{
    public bool IsTerminal => Phase is "Complete" or "Deleted";
}

public partial class SqlImporter
{
    private static readonly JsonSerializerOptions FingerprintOptions = new() { IncludeFields = true };
    public Guid ImportId { get; private set; }
    public CancellationToken ImportCancellation { get; private set; }
    private long _parsedBinds;
    private SqlTransaction? _dimensionTransaction;
    internal void UseCancellation(CancellationToken token) => ImportCancellation = token;

    public async Task<ImportReceipt> BeginImportAsync(SqlConnection conn, string account, string container,
        string name, string etag, CancellationToken ct, bool waitForOwnership = true, long contentLength = 0)
    {
        ImportCancellation = ct;
        ImportId = Guid.Empty;
        _parsedBinds = 0;
        using var cmd = conn.CreateCommand();
        cmd.CommandType = CommandType.StoredProcedure;
        cmd.CommandText = "dbo.tp_BeginImport";
        cmd.Parameters.Add("@AccountName", SqlDbType.NVarChar, 128).Value = account;
        cmd.Parameters.Add("@ContainerName", SqlDbType.NVarChar, 63).Value = container;
        cmd.Parameters.Add("@BlobName", SqlDbType.NVarChar, 1024).Value = name;
        cmd.Parameters.Add("@ETag", SqlDbType.NVarChar, 128).Value = etag;
        cmd.Parameters.Add("@ContentLength", SqlDbType.BigInt).Value = contentLength;
        while (true)
        {
            try
            {
                using var reader = await cmd.ExecuteReaderAsync(ct);
                if (!await reader.ReadAsync(ct)) throw new InvalidOperationException("Import receipt was not returned.");
                ImportId = reader.GetGuid(0);
                return new(ImportId, reader.GetInt32(1), reader.GetString(2));
            }
            catch (SqlException ex) when (ex.Number == 51103 && waitForOwnership)
            {
                // Contention is not a failed parse. Wait within the invocation budget
                // rather than rapidly exhausting BlobTrigger's delivery retry count.
                await Task.Delay(TimeSpan.FromSeconds(5), ct);
            }
        }
    }

    private SqlCommand ImportCommand(SqlConnection conn, string procedure)
    {
        ImportCancellation.ThrowIfCancellationRequested();
        var cmd = conn.CreateCommand();
        cmd.CommandText = procedure;
        cmd.CommandType = CommandType.StoredProcedure;
        cmd.CommandTimeout = 120;
        cmd.Parameters.Add("@ImportId", SqlDbType.UniqueIdentifier).Value = ImportId;
        return cmd;
    }

    private SqlCommand DimensionCommand(SqlConnection conn)
    {
        ImportCancellation.ThrowIfCancellationRequested();
        var cmd = conn.CreateCommand();
        cmd.Transaction = _dimensionTransaction
            ?? throw new InvalidOperationException("Trace dimensions require an atomic Ready transaction.");
        return cmd;
    }

    public async Task SetContentHashAsync(SqlConnection conn, byte[] hash)
    {
        using var cmd = ImportCommand(conn, "dbo.tp_SetImportContentHash");
        cmd.Parameters.Add("@ContentHash", SqlDbType.Binary, 32).Value = hash;
        await cmd.ExecuteNonQueryAsync(ImportCancellation);
    }

    private void StageOwnedBatch(SqlConnection conn, List<StageRow> rows, List<BindParamRow> binds)
    {
        ImportCancellation.ThrowIfCancellationRequested();
        if (ImportId == Guid.Empty) throw new InvalidOperationException("No owned import.");
        // Stable replay fingerprint excludes the allocation; retained stage IDs win on replay.
        var fingerprints = rows.Select(row =>
        {
            row.TraceLineId = 0;
            checked { _ = (int)row.Seq; _ = (int)row.SeqEnd; }
            return SHA256.HashData(JsonSerializer.SerializeToUtf8Bytes(row, FingerprintOptions));
        }).ToArray();
        if (rows.Count > 0)
        {
            var first = ReserveTraceLineIds(conn, rows.Count);
            for (var i = 0; i < rows.Count; i++) rows[i].TraceLineId = checked(first + i);
        }
        using var lineData = BuildDataTable(rows);
        lineData.Columns.Add("ImportId", typeof(Guid));
        lineData.Columns.Add("PayloadHash", typeof(byte[]));
        for (var i = 0; i < rows.Count; i++)
        {
            lineData.Rows[i]["ImportId"] = ImportId;
            lineData.Rows[i]["PayloadHash"] = fingerprints[i];
        }
        using var bindData = new DataTable();
        bindData.Columns.Add("ImportId", typeof(Guid));
        bindData.Columns.Add("Sequence", typeof(int));
        bindData.Columns.Add("ParameterIndex", typeof(int));
        bindData.Columns.Add("BindValue", typeof(string));
        bindData.Columns.Add("PayloadHash", typeof(byte[]));
        foreach (var bind in binds)
            bindData.Rows.Add(ImportId, bind.TempSeq, bind.ParamIdx, (object?)bind.BindVal ?? DBNull.Value,
                SHA256.HashData(JsonSerializer.SerializeToUtf8Bytes(new { bind.TempSeq, bind.ParamIdx, bind.BindVal })));
        using (var create = conn.CreateCommand())
        {
            create.CommandText = """
                SELECT TOP(0) * INTO #ImportRows FROM dbo.TPImportLines;
                SELECT TOP(0) * INTO #ImportBinds FROM dbo.TPImportBinds;
                """;
            create.ExecuteNonQueryAsync(ImportCancellation).GetAwaiter().GetResult();
        }
        try
        {
            Copy("#ImportRows", lineData);
            Copy("#ImportBinds", bindData);
            using var stage = ImportCommand(conn, "dbo.tp_StageImportBatch");
            stage.ExecuteNonQueryAsync(ImportCancellation).GetAwaiter().GetResult();
            _parsedBinds += binds.Count;
        }
        finally
        {
            // On cancellation/connection loss the invocation closes its nonpooled connection.
            if (conn.State == ConnectionState.Open && !ImportCancellation.IsCancellationRequested)
            {
                using var drop = conn.CreateCommand();
                drop.CommandText = "DROP TABLE IF EXISTS #ImportRows; DROP TABLE IF EXISTS #ImportBinds;";
                drop.ExecuteNonQueryAsync(ImportCancellation).GetAwaiter().GetResult();
            }
        }

        void Copy(string table, DataTable data)
        {
            using var copy = new SqlBulkCopy(conn) { DestinationTableName = table, BulkCopyTimeout = 120 };
            foreach (DataColumn col in data.Columns) copy.ColumnMappings.Add(col.ColumnName, col.ColumnName);
            copy.WriteToServerAsync(data, ImportCancellation).GetAwaiter().GetResult();
        }
    }

    public void FinishDimensions(SqlConnection conn, int traceId, InMemoryDimensions dims, ParseStats stats)
    {
        // Shared content-addressed dimensions are safe to replay. Trace-owned dimensions
        // and the immutable mapping publish atomically, so an uncertain commit resumes Ready.
        BulkUpsertHashDim(conn, dims.GetAllMethodNames(), "MethodNames", "MethodHash", "Name", 500, true);
        BulkUpsertHashDim(conn, dims.GetAllQueryStatements(), "QueryStatements", "QueryStatementHash", "Statement", 4000, false);
        BulkUpsertHashDim(conn, dims.GetAllQueryTables(), "QueryTables", "QueryTableHash", "TableNames", 1000, false);
        BulkUpsertHashDim(conn, dims.GetAllMessages(), "Messages", "MessageHash", "MessageText", 4000, false);
        ImportCancellation.ThrowIfCancellationRequested();
        using var transaction = conn.BeginTransaction();
        _dimensionTransaction = transaction;
        try
        {
            using (var assert = ImportCommand(conn, "dbo.tp_AssertImportOwner"))
            {
                assert.Transaction = transaction;
                assert.ExecuteNonQueryAsync(ImportCancellation).GetAwaiter().GetResult();
            }
            var mapping = BulkInsertDimensions(conn, traceId, dims);
            PersistThreadMappings(conn, mapping);
            if (stats.MinFileTimeUtc <= stats.MaxFileTimeUtc)
            {
                using var times = DimensionCommand(conn);
                times.CommandText = "UPDATE dbo.Traces SET TimeStampBegin=@b,TimeStampEnd=@e WHERE TraceId=@t";
                times.Parameters.Add("@b", SqlDbType.DateTime).Value = DateTime.FromFileTimeUtc(stats.MinFileTimeUtc);
                times.Parameters.Add("@e", SqlDbType.DateTime).Value = DateTime.FromFileTimeUtc(stats.MaxFileTimeUtc);
                times.Parameters.Add("@t", SqlDbType.Int).Value = traceId;
                times.ExecuteNonQueryAsync(ImportCancellation).GetAwaiter().GetResult();
            }
            using var ready = ImportCommand(conn, "dbo.tp_MarkImportReady");
            ready.Transaction = transaction;
            ready.Parameters.Add("@ExpectedRows", SqlDbType.BigInt).Value = stats.Staged;
            ready.Parameters.Add("@ExpectedBinds", SqlDbType.BigInt).Value = _parsedBinds;
            ready.ExecuteNonQueryAsync(ImportCancellation).GetAwaiter().GetResult();
            transaction.CommitAsync(ImportCancellation).GetAwaiter().GetResult();
        }
        finally { _dimensionTransaction = null; }
    }

    public async Task CompleteImportAsync(SqlConnection conn)
    {
        using var cmd = ImportCommand(conn, "dbo.tp_CompleteImport");
        cmd.CommandTimeout = 1800;
        await cmd.ExecuteNonQueryAsync(ImportCancellation);
    }

    public async Task CleanupCompletedAsync(SqlConnection conn)
    {
        while (true)
        {
            using var cmd = ImportCommand(conn, "dbo.tp_CleanupCompletedImport");
            if (Convert.ToInt32(await cmd.ExecuteScalarAsync(ImportCancellation)) == 0) return;
        }
    }

    public async Task RecordFailureAsync(SqlConnection conn)
    {
        if (ImportId == Guid.Empty || conn.State != ConnectionState.Open) return;
        using var cmd = conn.CreateCommand();
        cmd.CommandType = CommandType.StoredProcedure;
        cmd.CommandText = "dbo.tp_RecordImportFailure";
        cmd.CommandTimeout = 5;
        cmd.Parameters.Add("@ImportId", SqlDbType.UniqueIdentifier).Value = ImportId;
        await cmd.ExecuteNonQueryAsync();
    }
}
