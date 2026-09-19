using System.Data;
using Microsoft.Data.SqlClient;
using Microsoft.Extensions.Options;

namespace TraceParserWeb.Services;

public class TraceAdministrationOptions
{
    public string SqlConnectionString { get; set; } = "";
}

public interface ITraceDeletionStore
{
    Task<TraceDeletionBatch> DeleteBatchAsync(int traceId, CancellationToken ct);
}

public sealed record TraceDeletionBatch(bool HasMore, string? Phase = null, int? RowsDeleted = null);

public class SqlTraceDeletionStore(IOptions<TraceAdministrationOptions> options) : ITraceDeletionStore
{
    public async Task<TraceDeletionBatch> DeleteBatchAsync(int traceId, CancellationToken ct)
    {
        ArgumentOutOfRangeException.ThrowIfNegativeOrZero(traceId);
        if (string.IsNullOrWhiteSpace(options.Value.SqlConnectionString))
            throw new InvalidOperationException("Authenticated trace deletion has not been configured.");

        var connectionString = new SqlConnectionStringBuilder(options.Value.SqlConnectionString)
        {
            Encrypt = true,
            TrustServerCertificate = false,
            PersistSecurityInfo = false
        };
        await using var connection = new SqlConnection(connectionString.ConnectionString);
        await connection.OpenAsync(ct);
        return await ExecuteBatchAsync(connection, traceId, ct);
    }

    // An already-open connection allows isolated contract tests without weakening production TLS.
    internal static async Task<TraceDeletionBatch> ExecuteBatchAsync(SqlConnection connection, int traceId, CancellationToken ct)
    {
        ArgumentOutOfRangeException.ThrowIfNegativeOrZero(traceId);
        await using var command = connection.CreateCommand();
        command.CommandType = CommandType.StoredProcedure;
        command.CommandText = "dbo.sp_DeleteTrace";
        command.CommandTimeout = 120;
        command.Parameters.Add("@TraceId", SqlDbType.Int).Value = traceId;
        string? phase = null;
        int? rowsDeleted = null;
        await using (var reader = await command.ExecuteReaderAsync(ct))
        {
            if (await reader.ReadAsync(ct))
            {
                // Older installations return no result, or only HasMore. Never use
                // that flag as proof of completion; the root query below is authoritative.
                for (var i = 0; i < reader.FieldCount; i++)
                {
                    if (reader.GetName(i) == "Phase" && !reader.IsDBNull(i))
                        phase = reader.GetString(i);
                    if (reader.GetName(i) == "RowsDeleted" && !reader.IsDBNull(i))
                        rowsDeleted = reader.GetInt32(i);
                }
            }
        }

        // The installed procedure may return after one batch. Confirm absence
        // independently, also supporting older procedures with no result set.
        command.CommandType = CommandType.Text;
        command.CommandText = "SELECT CAST(CASE WHEN EXISTS (SELECT 1 FROM dbo.Traces WHERE TraceId = @TraceId) THEN 1 ELSE 0 END AS bit)";
        var remaining = await command.ExecuteScalarAsync(ct);
        return remaining is bool exists
            ? new TraceDeletionBatch(exists, phase, rowsDeleted)
            : throw new InvalidOperationException("SQL did not confirm trace deletion.");
    }
}
