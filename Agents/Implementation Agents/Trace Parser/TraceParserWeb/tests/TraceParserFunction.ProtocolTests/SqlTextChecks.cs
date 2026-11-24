using System.Data;
using System.Security.Cryptography;
using System.Text;
using Microsoft.Data.SqlClient;
using Microsoft.Extensions.Logging.Abstractions;
using TraceParserFunction;

// Issue #571: full SQL statement text. Runs last because the column widening persists in the fixture.
public static class SqlTextChecks
{
    static int checks;
    static string databaseString = "";

    public static async Task<int> RunAsync(string connectionString)
    {
        checks = 0;
        databaseString = connectionString;

        await using (var c = await Open())
        {
            Check(await ColumnLength(c) == 8000, "fixture Statement starts as nvarchar(4000)");
            Check(!Importer().QueryStatementsSupportFullText(c), "importer detects legacy 4000-char column");
        }
        var nullable = await Nullable();

        var legacy = Statement('A', 5000);
        await Import("legacy", [legacy]);
        var stored = await Stored(legacy);
        Check(stored is not null && stored.Length == 4000 && legacy.StartsWith(stored, StringComparison.OrdinalIgnoreCase),
            "legacy column stores first 4000 chars");

        var script = await File.ReadAllTextAsync(Path.Combine(AppContext.BaseDirectory, "full-sql-text.sql"));
        await using (var c = await Open()) { await Exec(c, script); await Exec(c, script); }
        await using (var c = await Open())
        {
            Check(await ColumnLength(c) == -1, "upgrade script widens Statement to nvarchar(max)");
            Check(Importer().QueryStatementsSupportFullText(c), "new importer detects full-text column");
        }
        Check(await Nullable() == nullable, "upgrade preserves nullability");
        Check((await Stored(legacy))?.Length == 4000, "existing truncated row is not rewritten");

        var lengths = new[] { 3999, 4000, 4001, 8000 };
        var viaDims = lengths.Select(n => Statement('B', n)).Append(UnicodeStatement(4500)).ToArray();
        await Import("dims", viaDims);
        foreach (var s in viaDims)
            Check(await Stored(s) == s.ToUpperInvariant(), $"dimension path stores {s.Length} chars in full");

        var prefix = Statement('C', 4000);
        var tailA = prefix + " ORDER BY COLUMN_A";
        var tailB = prefix + " ORDER BY COLUMN_B";
        await Import("tails", [tailA, tailB]);
        Check(await Stored(tailA) == tailA.ToUpperInvariant() && await Stored(tailB) == tailB.ToUpperInvariant(),
            "statements sharing a 4000-char prefix keep distinct tails");

        await using (var c = await Open())
        {
            var direct = Statement('D', 6000).ToUpperInvariant();
            var importer = Importer();
            var hash = importer.EnsureQueryStatement(c, direct);
            Check(hash == SqlImporter.ComputeHash(direct) && await Stored(direct) == direct,
                "direct EnsureQueryStatement stores full text");
        }

        await using (var c = await Open())
        {
            Check(await MaxLength(c, "Messages", "MessageText") == 8000, "Messages limit unchanged");
            Check(await MaxLength(c, "MethodNames", "Name") == 1000, "MethodNames limit unchanged");
        }
        return checks;
    }

    static string Statement(char tag, int length)
    {
        var head = $"SELECT T{tag}.RECID FROM TABLE{tag} T{tag} WHERE ";
        var sb = new StringBuilder(head, length);
        var i = 0;
        while (sb.Length < length) sb.Append($"T{tag}.F{i++ % 10}=1 AND ");
        return sb.ToString(0, length);
    }

    static string UnicodeStatement(int length)
    {
        var sb = new StringBuilder("SELECT NAME FROM CUSTTABLE WHERE NAME = N'", length);
        while (sb.Length < length) sb.Append("ÇĞİÖŞÜ漢字");
        return sb.ToString(0, length);
    }

    static async Task Import(string label, string[] statements)
    {
        var id = await Register();
        await using var c = await Open();
        var importer = Importer();
        var trace = (await importer.BeginImportAsync(c, "account", "etl-uploads", Name(id), $"\"sqltext-{label}\"", default)).TraceId;
        await importer.SetContentHashAsync(c, Hash("sqltext-" + label + Guid.NewGuid()));
        importer.FlushStageBatch(c, [Row(1, 64), Row(2, 8)], []);
        var dims = Dimensions(trace);
        foreach (var s in statements) dims.EnsureQueryStatement(s);
        importer.FinishDimensions(c, trace, dims, new() { Staged = 2 });
        await importer.PromoteStageToTraceLines(c);
        await importer.CompleteImportAsync(c);
        await importer.CleanupCompletedAsync(c);
    }

    static async Task<string?> Stored(string statement)
    {
        await using var c = await Open();
        using var cmd = c.CreateCommand();
        cmd.CommandText = "SELECT Statement FROM dbo.QueryStatements WHERE QueryStatementHash=@h";
        cmd.Parameters.Add("@h", SqlDbType.BigInt).Value = SqlImporter.ComputeHash(statement.ToUpperInvariant());
        return await cmd.ExecuteScalarAsync() as string;
    }

    static async Task<long> ColumnLength(SqlConnection c) => await MaxLength(c, "QueryStatements", "Statement");

    static async Task<long> MaxLength(SqlConnection c, string table, string column)
    {
        using var cmd = c.CreateCommand();
        cmd.CommandText = "SELECT COL_LENGTH(@t,@c)";
        cmd.Parameters.Add("@t", SqlDbType.NVarChar, 256).Value = "dbo." + table;
        cmd.Parameters.Add("@c", SqlDbType.NVarChar, 128).Value = column;
        return Convert.ToInt64(await cmd.ExecuteScalarAsync());
    }

    static async Task<bool> Nullable()
    {
        await using var c = await Open();
        using var cmd = c.CreateCommand();
        cmd.CommandText = "SELECT is_nullable FROM sys.columns WHERE object_id=OBJECT_ID(N'dbo.QueryStatements') AND name=N'Statement'";
        return Convert.ToBoolean(await cmd.ExecuteScalarAsync());
    }

    static SqlImporter Importer() => new(NullLogger<SqlImporter>.Instance);
    static byte[] Hash(string text) => SHA256.HashData(Encoding.UTF8.GetBytes(text));
    static string Name(Guid id) => $"_imports/{id:D}/sample.etl";
    static StageRow Row(int seq, int type) => new()
    {
        ThreadId = -1, Seq = seq, SeqEnd = seq, CallTypeId = type, TS = 1, TSEnd = 2, IsComplete = true,
        MethodHash = type == 8 ? SqlImporter.ComputeHash("test.method") : null, IncNano = 1000000, ExcNano = 1000000
    };
    static InMemoryDimensions Dimensions(int trace)
    {
        var dims = new InMemoryDimensions();
        var user = dims.GetUserId("synthetic-user");
        var cust = dims.GetCustomerId("synthetic-customer");
        var sess = dims.GetUserSessionId(trace, "session", user, cust);
        dims.GetThreadId("00000000-0000-0000-0000-000000000001", "", sess, trace);
        dims.EnsureMethodName("test.method", dims.GetMethodHash("test.method"));
        return dims;
    }
    static async Task<Guid> Register()
    {
        var id = Guid.NewGuid();
        await using var conn = await Open();
        using var cmd = conn.CreateCommand();
        cmd.CommandText = "EXEC dbo.tp_RegisterUpload @id,N'account',N'etl-uploads',@name,N'synthetic-session'";
        cmd.Parameters.Add("@id", SqlDbType.UniqueIdentifier).Value = id;
        cmd.Parameters.Add("@name", SqlDbType.NVarChar, 1024).Value = Name(id);
        await cmd.ExecuteNonQueryAsync();
        return id;
    }
    static async Task<SqlConnection> Open()
    {
        var conn = new SqlConnection(databaseString);
        await conn.OpenAsync();
        return conn;
    }
    static async Task Exec(SqlConnection conn, string sql)
    {
        using var cmd = conn.CreateCommand(); cmd.CommandText = sql; cmd.CommandTimeout = 120;
        await cmd.ExecuteNonQueryAsync();
    }
    static void Check(bool result, string label)
    {
        if (!result) throw new InvalidOperationException("FAIL sql text: " + label);
        checks++;
        Console.WriteLine("PASS sql text: " + label);
    }
}
