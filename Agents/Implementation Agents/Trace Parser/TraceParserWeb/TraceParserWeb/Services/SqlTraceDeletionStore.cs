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
    Task<bool> DeleteBatchAsync(int traceId, CancellationToken ct);
}

public class SqlTraceDeletionStore(IOptions<TraceAdministrationOptions> options) : ITraceDeletionStore
{
    public async Task<bool> DeleteBatchAsync(int traceId, CancellationToken ct)
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
        await using var command = connection.CreateCommand();
        command.CommandType = CommandType.StoredProcedure;
        command.CommandText = "dbo.sp_DeleteTrace";
        command.CommandTimeout = 120;
        command.Parameters.Add("@TraceId", SqlDbType.Int).Value = traceId;
        await command.ExecuteNonQueryAsync(ct);

        // The installed procedure may return after one batch. Confirm absence
        // independently, also supporting older procedures with no result set.
        command.CommandType = CommandType.Text;
        command.CommandText = "SELECT CAST(CASE WHEN EXISTS (SELECT 1 FROM dbo.Traces WHERE TraceId = @TraceId) THEN 1 ELSE 0 END AS bit)";
        var remaining = await command.ExecuteScalarAsync(ct);
        return remaining is bool exists
            ? exists
            : throw new InvalidOperationException("SQL did not confirm trace deletion.");
    }
}
