using System.Data;
using Microsoft.Data.SqlClient;

namespace TraceParser.Deletion;

public sealed record DeletionJob(Guid JobId, int TraceId, string State, long Sequence, long CommittedRows,
    string LastPhase, int? ErrorCode, string? ErrorMessage, DateTime CreatedUtc, DateTime UpdatedUtc, DateTime NextDueUtc)
{
    public bool CanCancel => State is "Queued" or "Running" or "RetryScheduled";
    public bool CanResume => State is "Cancelled" or "Blocked" or "Failed";
}

public sealed record DeletionLease(Guid JobId, int TraceId, Guid Token, long Sequence);
public sealed record DeletionStep(long Sequence, string State);

public interface IDeletionJobStore
{
    Task<IReadOnlyList<DeletionJob>> ReadAsync(Guid tenant, Guid requester, Guid? job, CancellationToken ct);
    Task<DeletionJob> EnqueueAsync(Guid tenant, Guid requester, Guid key, int trace, CancellationToken ct);
    Task<DeletionJob> ControlAsync(Guid tenant, Guid requester, Guid job, string action, CancellationToken ct);
}

public interface IDeletionWorkerStore
{
    Task<DeletionLease?> ClaimAsync(Guid owner, CancellationToken ct);
    Task RenewAsync(DeletionLease lease, CancellationToken ct);
    Task<DeletionStep> StepAsync(DeletionLease lease, CancellationToken ct);
    Task<DeletionStep?> InspectAsync(DeletionLease lease, CancellationToken ct);
    Task ReleaseAsync(DeletionLease lease, int? error, CancellationToken ct);
}

public sealed class SqlDeletionJobStore(string connectionString) : IDeletionJobStore, IDeletionWorkerStore
{
    private async Task<T> ExecuteAsync<T>(string procedure, Action<SqlParameterCollection> parameters,
        Func<SqlDataReader, CancellationToken, Task<T>> read, CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(connectionString))
            throw new InvalidOperationException("The dedicated deletion connection is not configured.");
        await using var connection = new SqlConnection(new SqlConnectionStringBuilder(connectionString)
        {
            Encrypt = true, TrustServerCertificate = false, PersistSecurityInfo = false,
            ConnectTimeout = 10, ConnectRetryCount = 0
        }.ConnectionString);
        await connection.OpenAsync(ct);
        using var command = new SqlCommand(procedure, connection) { CommandType = CommandType.StoredProcedure, CommandTimeout = 30 };
        parameters(command.Parameters);
        using var reader = await command.ExecuteReaderAsync(ct);
        return await read(reader, ct);
    }

    private static void Id(SqlParameterCollection p, string name, Guid? value) =>
        p.Add(name, SqlDbType.UniqueIdentifier).Value = (object?)value ?? DBNull.Value;

    private static void Requester(SqlParameterCollection p, Guid tenant, Guid requester)
    {
        Id(p, "@TenantId", tenant);
        Id(p, "@RequesterId", requester);
    }

    private static void Lease(SqlParameterCollection p, DeletionLease lease)
    {
        Id(p, "@JobId", lease.JobId);
        Id(p, "@Token", lease.Token);
    }

    private static async Task<IReadOnlyList<DeletionJob>> Jobs(SqlDataReader r, CancellationToken ct)
    {
        var jobs = new List<DeletionJob>();
        while (await r.ReadAsync(ct))
            jobs.Add(new(r.GetGuid(0), r.GetInt32(1), r.GetString(2), r.GetInt64(3), r.GetInt64(4),
                r.GetString(5), r.IsDBNull(6) ? null : r.GetInt32(6), r.IsDBNull(7) ? null : r.GetString(7),
                r.GetDateTime(8), r.GetDateTime(9), r.GetDateTime(10)));
        return jobs;
    }

    public Task<IReadOnlyList<DeletionJob>> ReadAsync(Guid tenant, Guid requester, Guid? job, CancellationToken ct) =>
        ExecuteAsync("dbo.dj_Read", p => { Requester(p, tenant, requester); Id(p, "@JobId", job); }, Jobs, ct);

    public async Task<DeletionJob> EnqueueAsync(Guid tenant, Guid requester, Guid key, int trace, CancellationToken ct) =>
        (await ExecuteAsync("dbo.dj_Enqueue", p =>
        {
            Requester(p, tenant, requester); Id(p, "@RequestKey", key);
            p.Add("@TraceId", SqlDbType.Int).Value = trace;
        }, Jobs, ct)).Single();

    public async Task<DeletionJob> ControlAsync(Guid tenant, Guid requester, Guid job, string action, CancellationToken ct) =>
        (await ExecuteAsync("dbo.dj_Control", p =>
        {
            Requester(p, tenant, requester); Id(p, "@JobId", job);
            p.Add("@Action", SqlDbType.VarChar, 10).Value = action;
        }, Jobs, ct)).Single();

    public Task<DeletionLease?> ClaimAsync(Guid owner, CancellationToken ct) =>
        ExecuteAsync<DeletionLease?>("dbo.dj_Claim", p => Id(p, "@Owner", owner), async (r, token) =>
            await r.ReadAsync(token) ? new(r.GetGuid(0), r.GetInt32(1), r.GetGuid(2), r.GetInt64(3)) : null, ct);

    public Task RenewAsync(DeletionLease lease, CancellationToken ct) =>
        ExecuteAsync("dbo.dj_Renew", p => Lease(p, lease), (_, _) => Task.FromResult(true), ct);

    public Task<DeletionStep> StepAsync(DeletionLease lease, CancellationToken ct) =>
        ExecuteAsync("dbo.dj_Step", p =>
        {
            Lease(p, lease);
            p.Add("@ExpectedSequence", SqlDbType.BigInt).Value = lease.Sequence;
        }, async (r, token) =>
        {
            // The legacy three-column batch response is not a completion authority.
            if (!await r.NextResultAsync(token) || !await r.ReadAsync(token))
                throw new InvalidOperationException("Missing committed deletion sequence.");
            return new DeletionStep(r.GetInt64(0), r.GetString(1));
        }, ct);

    public Task<DeletionStep?> InspectAsync(DeletionLease lease, CancellationToken ct) =>
        ExecuteAsync<DeletionStep?>("dbo.dj_Inspect", p => Lease(p, lease), async (r, token) =>
            await r.ReadAsync(token) ? new(r.GetInt64(0), r.GetString(1)) : null, ct);

    public Task ReleaseAsync(DeletionLease lease, int? error, CancellationToken ct) =>
        ExecuteAsync("dbo.dj_Release", p =>
        {
            Lease(p, lease); p.Add("@ErrorCode", SqlDbType.Int).Value = (object?)error ?? DBNull.Value;
        }, (_, _) => Task.FromResult(true), ct);
}

// Shared with the console harness: orchestration contains no Function-host or wall-clock dependency.
public sealed class DeletionWorker(IDeletionWorkerStore store, TimeProvider clock)
{
    public async Task RunSliceAsync(CancellationToken stopping)
    {
        using var budget = new CancellationTokenSource(TimeSpan.FromSeconds(45), clock);
        using var linked = CancellationTokenSource.CreateLinkedTokenSource(stopping, budget.Token);
        var ct = linked.Token;
        var lease = await store.ClaimAsync(Guid.NewGuid(), ct);
        if (lease is null) return;
        int? error = null;
        try
        {
            for (var batch = 0; batch < 4; batch++)
            {
                ct.ThrowIfCancellationRequested();
                // SQL time and a successful fenced renewal, never extrapolated local lease time.
                await store.RenewAsync(lease, ct);
                var committed = await store.StepAsync(lease, ct);
                if (committed.State is "Completed" or "Cancelled") return;
                if (committed.State != "Running" || committed.Sequence != lease.Sequence + 1)
                    throw new InvalidOperationException("Unexpected committed deletion state.");
                lease = lease with { Sequence = committed.Sequence };
                await Task.Delay(TimeSpan.FromSeconds(1), clock, ct);
            }
        }
        catch (OperationCanceledException) when (ct.IsCancellationRequested) { }
        catch (SqlException ex) { error = ex.Number; }
        catch (InvalidOperationException) { error = 51209; }
        finally
        {
            // An interrupted command can have committed. Reconcile, never blindly replay it.
            // If reconciliation is unavailable, let the finite lease expire. Do not invent status.
            using var cleanup = new CancellationTokenSource(TimeSpan.FromSeconds(5), clock);
            var persisted = await store.InspectAsync(lease, cleanup.Token);
            if (persisted is not null)
                await store.ReleaseAsync(lease, error, cleanup.Token);
        }
    }
}
