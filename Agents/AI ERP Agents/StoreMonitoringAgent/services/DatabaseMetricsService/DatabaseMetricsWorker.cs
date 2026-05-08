/**
 * SAMPLE CODE NOTICE
 * 
 * THIS SAMPLE CODE IS MADE AVAILABLE AS IS.  MICROSOFT MAKES NO WARRANTIES, WHETHER EXPRESS OR IMPLIED,
 * OF FITNESS FOR A PARTICULAR PURPOSE, OF ACCURACY OR COMPLETENESS OF RESPONSES, OF RESULTS, OR CONDITIONS OF MERCHANTABILITY.
 * THE ENTIRE RISK OF THE USE OR THE RESULTS FROM THE USE OF THIS SAMPLE CODE REMAINS WITH THE USER.
 * NO TECHNICAL SUPPORT IS PROVIDED.  YOU MAY NOT DISTRIBUTE THIS CODE UNLESS YOU HAVE A LICENSE AGREEMENT WITH MICROSOFT THAT ALLOWS YOU TO DO SO.
 */
using System.Text;
using Microsoft.Data.SqlClient;
namespace DatabaseMetricsService;

public class DatabaseMetricsWorker : BackgroundService
{
    private readonly ILogger<DatabaseMetricsWorker> _logger;
    private readonly IConfiguration _configuration;
    private readonly TimeSpan _collectionInterval;

    // Custom Event IDs for Windows Event Log
    private static readonly EventId ServiceStartedEvent = new(1000, "ServiceStarted");
    private static readonly EventId ServiceStoppedEvent = new(1001, "ServiceStopped");
    private static readonly EventId CollectionStartedEvent = new(2000, "CollectionStarted");
    private static readonly EventId CollectionCompletedEvent = new(2001, "CollectionCompleted");
    private static readonly EventId MetricsReportEvent = new(3000, "MetricsReport");
    private static readonly EventId SqlErrorEvent = new(4000, "SqlError");
    private static readonly EventId GeneralErrorEvent = new(4001, "GeneralError");

    public DatabaseMetricsWorker(ILogger<DatabaseMetricsWorker> logger, IConfiguration configuration)
    {
        _logger = logger;
        _configuration = configuration;

        // Get collection interval from configuration (default: 6 hours = 360 minutes)
        var intervalMinutes = _configuration.GetValue<int>("CollectionIntervalMinutes", 360);
        _collectionInterval = TimeSpan.FromMinutes(intervalMinutes);
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        _logger.LogInformation(ServiceStartedEvent, "Database Metrics Service started at: {time}", DateTimeOffset.Now);

        // Run immediately on start
        await CollectAndLogMetricsAsync(stoppingToken);

        // Continue running at the specified interval
        using PeriodicTimer timer = new PeriodicTimer(_collectionInterval);

        try
        {
            while (await timer.WaitForNextTickAsync(stoppingToken))
            {
                await CollectAndLogMetricsAsync(stoppingToken);
            }
        }
        catch (OperationCanceledException)
        {
            _logger.LogInformation(ServiceStoppedEvent, "Database Metrics Service stopped.");
        }
    }

    private async Task CollectAndLogMetricsAsync(CancellationToken stoppingToken)
    {
        try
        {
            _logger.LogInformation(CollectionStartedEvent, "Starting database metrics collection at: {time}", DateTimeOffset.Now);

            // Collect database metrics
            var dbMetrics = await CollectDatabaseMetricsAsync(stoppingToken);

            // Format the metrics message and log it
            string metricsMessage = FormatMetricsMessage(dbMetrics);
            _logger.LogInformation(MetricsReportEvent, "Database Metrics Report:\n{MetricsReport}", metricsMessage);

            _logger.LogInformation(CollectionCompletedEvent, "Database metrics collection completed successfully.");
        }
        catch (SqlException sqlEx)
        {
            _logger.LogError(SqlErrorEvent, sqlEx, "SQL Error collecting database metrics. Error Number: {ErrorNumber}, Server: {Server}",
                sqlEx.Number, sqlEx.Server);
        }
        catch (Exception ex)
        {
            _logger.LogError(GeneralErrorEvent, ex, "Error collecting database metrics");
        }
    }

    private async Task<DatabaseMetrics> CollectDatabaseMetricsAsync(CancellationToken stoppingToken)
    {
        var connectionString = _configuration.GetConnectionString("DefaultConnection")
            ?? throw new InvalidOperationException("Connection string 'DefaultConnection' not found.");
        var databaseName = _configuration.GetValue<string>("DatabaseName") ?? "RetailOfflineDatabase"; var metrics = new DatabaseMetrics
        {
            DatabaseName = databaseName,
            CollectionTime = DateTime.Now
        };

        await using var connection = new SqlConnection(connectionString);
        await connection.OpenAsync(stoppingToken);

        // Get database size
        metrics.DatabaseSizeMB = await GetDatabaseSizeAsync(connection, databaseName, stoppingToken);

        // Get table sizes
        metrics.TableMetrics = await GetTableSizesAsync(connection, stoppingToken);

        // Get index sizes
        metrics.IndexMetrics = await GetIndexSizesAsync(connection, stoppingToken);

        // Get additional database properties
        metrics.DataFileSizeMB = await GetDataFileSizeAsync(connection, databaseName, stoppingToken);
        metrics.LogFileSizeMB = await GetLogFileSizeAsync(connection, databaseName, stoppingToken);
        metrics.UnallocatedSpaceMB = await GetUnallocatedSpaceAsync(connection, databaseName, stoppingToken);

        return metrics;
    }

    private async Task<decimal> GetDatabaseSizeAsync(SqlConnection connection, string databaseName, CancellationToken stoppingToken)
    {
        const string query = @"
            SELECT 
                SUM(size * 8.0 / 1024) AS DatabaseSizeMB
            FROM sys.master_files
            WHERE database_id = DB_ID(@DatabaseName)";

        await using var command = new SqlCommand(query, connection);
        command.Parameters.AddWithValue("@DatabaseName", databaseName);

        var result = await command.ExecuteScalarAsync(stoppingToken);
        return result != DBNull.Value ? Convert.ToDecimal(result) : 0;
    }

    private async Task<decimal> GetDataFileSizeAsync(SqlConnection connection, string databaseName, CancellationToken stoppingToken)
    {
        const string query = @"
            SELECT 
                SUM(size * 8.0 / 1024) AS DataFileSizeMB
            FROM sys.master_files
            WHERE database_id = DB_ID(@DatabaseName)
            AND type = 0";

        await using var command = new SqlCommand(query, connection);
        command.Parameters.AddWithValue("@DatabaseName", databaseName);

        var result = await command.ExecuteScalarAsync(stoppingToken);
        return result != DBNull.Value ? Convert.ToDecimal(result) : 0;
    }

    private async Task<decimal> GetLogFileSizeAsync(SqlConnection connection, string databaseName, CancellationToken stoppingToken)
    {
        const string query = @"
            SELECT 
                SUM(size * 8.0 / 1024) AS LogFileSizeMB
            FROM sys.master_files
            WHERE database_id = DB_ID(@DatabaseName)
            AND type = 1";

        await using var command = new SqlCommand(query, connection);
        command.Parameters.AddWithValue("@DatabaseName", databaseName);

        var result = await command.ExecuteScalarAsync(stoppingToken);
        return result != DBNull.Value ? Convert.ToDecimal(result) : 0;
    }

    private async Task<decimal> GetUnallocatedSpaceAsync(SqlConnection connection, string databaseName, CancellationToken stoppingToken)
    {
        const string query = @"
            SELECT 
                SUM(unallocated_extent_page_count) * 8.0 / 1024 AS UnallocatedSpaceMB
            FROM sys.dm_db_file_space_usage
            WHERE database_id = DB_ID(@DatabaseName)";

        await using var command = new SqlCommand(query, connection);
        command.Parameters.AddWithValue("@DatabaseName", databaseName);

        var result = await command.ExecuteScalarAsync(stoppingToken);
        return result != DBNull.Value ? Convert.ToDecimal(result) : 0;
    }

    private async Task<string> GetTableSizesAsync(SqlConnection connection, CancellationToken stoppingToken)
    {
        const string query = @"
            SELECT TOP 10
                s.Name AS SchemaName,
                t.Name AS TableName,
                p.rows AS [RowCount],
                SUM(a.total_pages) * 8.0 / 1024 AS TotalSpaceMB,
                SUM(a.used_pages) * 8.0 / 1024 AS UsedSpaceMB,
                (SUM(a.total_pages) - SUM(a.used_pages)) * 8.0 / 1024 AS UnusedSpaceMB
            FROM sys.tables t
            INNER JOIN sys.indexes i ON t.object_id = i.object_id
            INNER JOIN sys.partitions p ON i.object_id = p.object_id AND i.index_id = p.index_id
            INNER JOIN sys.allocation_units a ON p.partition_id = a.container_id
            INNER JOIN sys.schemas s ON t.schema_id = s.schema_id
            WHERE t.is_ms_shipped = 0
            AND i.object_id > 255
            GROUP BY s.Name, t.Name, p.rows
            ORDER BY SUM(a.total_pages) DESC";

        var sb = new StringBuilder();
        sb.AppendLine("\nTOP 10 TABLES BY SIZE");

        await using var command = new SqlCommand(query, connection);
        await using var reader = await command.ExecuteReaderAsync(stoppingToken);

        while (await reader.ReadAsync(stoppingToken))
        {
            string schemaName = reader["SchemaName"].ToString() ?? "";
            string tableName = reader["TableName"].ToString() ?? "";
            long rowCount = Convert.ToInt64(reader["RowCount"]);
            decimal totalSpaceMB = Convert.ToDecimal(reader["TotalSpaceMB"]);
            decimal usedSpaceMB = Convert.ToDecimal(reader["UsedSpaceMB"]);
            decimal unusedSpaceMB = Convert.ToDecimal(reader["UnusedSpaceMB"]);

            sb.AppendLine($"Table: [{schemaName}].[{tableName}]");
            sb.AppendLine($"  Rows: {rowCount:N0}");
            sb.AppendLine($"  Total Space: {totalSpaceMB:F2} MB");
            sb.AppendLine($"  Used Space: {usedSpaceMB:F2} MB");
            sb.AppendLine($"  Unused Space: {unusedSpaceMB:F2} MB");
            sb.AppendLine();
        }

        return sb.ToString();
    }

    private async Task<string> GetIndexSizesAsync(SqlConnection connection, CancellationToken stoppingToken)
    {
        const string query = @"
            SELECT TOP 10
                s.Name AS SchemaName,
                t.Name AS TableName,
                i.Name AS IndexName,
                i.type_desc AS IndexType,
                SUM(p.rows) AS [RowCount],
                SUM(a.total_pages) * 8.0 / 1024 AS TotalSpaceMB,
                SUM(a.used_pages) * 8.0 / 1024 AS UsedSpaceMB
            FROM sys.tables t
            INNER JOIN sys.indexes i ON t.object_id = i.object_id
            INNER JOIN sys.partitions p ON i.object_id = p.object_id AND i.index_id = p.index_id
            INNER JOIN sys.allocation_units a ON p.partition_id = a.container_id
            INNER JOIN sys.schemas s ON t.schema_id = s.schema_id
            WHERE t.is_ms_shipped = 0
            AND i.object_id > 255
            AND i.type > 0
            GROUP BY s.Name, t.Name, i.Name, i.type_desc
            ORDER BY SUM(a.total_pages) DESC";

        var sb = new StringBuilder();
        sb.AppendLine("\nTOP 10 INDEXES BY SIZE");

        await using var command = new SqlCommand(query, connection);
        await using var reader = await command.ExecuteReaderAsync(stoppingToken);

        while (await reader.ReadAsync(stoppingToken))
        {
            string schemaName = reader["SchemaName"].ToString() ?? "";
            string tableName = reader["TableName"].ToString() ?? "";
            string indexName = reader["IndexName"].ToString() ?? "";
            string indexType = reader["IndexType"].ToString() ?? "";
            long rowCount = Convert.ToInt64(reader["RowCount"]);
            decimal totalSpaceMB = Convert.ToDecimal(reader["TotalSpaceMB"]);
            decimal usedSpaceMB = Convert.ToDecimal(reader["UsedSpaceMB"]);

            sb.AppendLine($"Index: [{schemaName}].[{tableName}].[{indexName}]");
            sb.AppendLine($"  Type: {indexType}");
            sb.AppendLine($"  Rows: {rowCount:N0}");
            sb.AppendLine($"  Total Space: {totalSpaceMB:F2} MB");
            sb.AppendLine($"  Used Space: {usedSpaceMB:F2} MB");
            sb.AppendLine();
        }

        return sb.ToString();
    }

    private string FormatMetricsMessage(DatabaseMetrics metrics)
    {
        var sb = new StringBuilder();

        sb.AppendLine("DATABASE METRICS REPORT");
        sb.AppendLine($"Database: {metrics.DatabaseName}");
        sb.AppendLine($"Collection Time: {metrics.CollectionTime:yyyy-MM-dd HH:mm:ss}");
        sb.AppendLine($"Server: {_configuration.GetValue<string>("ServerName", "localhost")}");
        sb.AppendLine();
        sb.AppendLine("DATABASE SIZE SUMMARY");
        sb.AppendLine($"Total Database Size: {metrics.DatabaseSizeMB:F2} MB");
        sb.AppendLine($"Data File Size: {metrics.DataFileSizeMB:F2} MB");
        sb.AppendLine($"Log File Size: {metrics.LogFileSizeMB:F2} MB");
        sb.AppendLine($"Unallocated Space: {metrics.UnallocatedSpaceMB:F2} MB");
        sb.AppendLine();
        sb.Append(metrics.TableMetrics);
        sb.Append(metrics.IndexMetrics);
        sb.AppendLine("END OF REPORT");

        return sb.ToString();
    }

    private class DatabaseMetrics
    {
        public string DatabaseName { get; set; } = string.Empty;
        public DateTime CollectionTime { get; set; }
        public decimal DatabaseSizeMB { get; set; }
        public decimal DataFileSizeMB { get; set; }
        public decimal LogFileSizeMB { get; set; }
        public decimal UnallocatedSpaceMB { get; set; }
        public string TableMetrics { get; set; } = string.Empty;
        public string IndexMetrics { get; set; } = string.Empty;
    }
}
