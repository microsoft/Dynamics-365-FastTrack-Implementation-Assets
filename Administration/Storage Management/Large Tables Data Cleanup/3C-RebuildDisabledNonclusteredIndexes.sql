
/* ===========================================
   Azure SQL Index Rebuild (Quick Wins First) - Stored Procedure
   - Targets disabled nonclustered indexes
   - Excludes BATCH, BATCHJOB tables
   - Optional include-only: @FilterTablesCsv (CSV, no spaces, no schema; assumes dbo)
   - Optional skip-by-index: @SkipIndexesCsv (CSV of index names, no spaces)
   - MAXDOP configurable, ONLINE + WAIT_AT_LOW_PRIORITY optional
   - Exponential backoff for transient errors (Azure-safe)
   - Logs duration & SQL text per attempt
   =========================================== */
CREATE OR ALTER PROCEDURE dbo.RebuildDisabledNonclusteredIndexes
    @TargetDOP             INT           = 1,      -- preferred MAXDOP for rebuilds
    @UseOnline             BIT           = 1,      -- Azure SQL supports ONLINE
    @UseLowPriorityWait    BIT           = 1,      -- ONLINE = ON (WAIT_AT_LOW_PRIORITY(...))
    @PauseBetweenItemsMs   INT           = 2000,   -- per-index pause (ms)
    @PauseBetweenBatchesMs INT           = 3000,   -- micro-batch cool-off (ms)
    @ItemsPerBatch         INT           = 5,      -- batch size per cool-off
    /* Optional include-only filter (tables):
       Comma-separated list of table names (no spaces, no schema).
       Example: N'SalesTable,InventTrans,ProdTable'
       Behavior:
       - If NULL or empty => no filter (process all candidates)
       - If provided => process only dbo.<table> in the list
    */
    @FilterTablesCsv       NVARCHAR(MAX) = NULL,   -- e.g., N'SalesTable,InventTrans,ProdTable'
    /* Optional skip-by-index filter:
       Comma-separated list of index names (no spaces). Exact names, case-insensitive.
       Behavior:
       - If NULL or empty => no exclusions
       - If provided => exclude any index whose i.name is in this list
    */
    @SkipIndexesCsv        NVARCHAR(MAX) = NULL    -- e.g., N'I_SalesIdx1,I_ProdIdx3'
AS
BEGIN
    SET NOCOUNT ON;

    /* ==== SAFETY: ensure log table exists ==== */
    IF OBJECT_ID('dbo.IndexRebuildLog') IS NULL
    BEGIN
        THROW 50001, 'dbo.IndexRebuildLog does not exist. Run the Log Table script first.', 1;
    END;

    /* ==== NORMALIZE TABLE FILTER (no schema expected) ==== */
    IF OBJECT_ID('tempdb..#FilterTables') IS NOT NULL
        DROP TABLE #FilterTables;

    CREATE TABLE #FilterTables
    (
        table_name SYSNAME NOT NULL
    );

    IF COALESCE(LTRIM(RTRIM(@FilterTablesCsv)), N'') <> N''
    BEGIN
        INSERT INTO #FilterTables(table_name)
        SELECT DISTINCT CAST(TRIM(value) AS SYSNAME)
        FROM STRING_SPLIT(@FilterTablesCsv, N',')
        WHERE TRIM(value) <> N'';
    END;

    /* ==== NORMALIZE INDEX SKIP LIST ==== */
    IF OBJECT_ID('tempdb..#SkipIndexes') IS NOT NULL
        DROP TABLE #SkipIndexes;

    CREATE TABLE #SkipIndexes
    (
        index_name SYSNAME NOT NULL
    );

    IF COALESCE(LTRIM(RTRIM(@SkipIndexesCsv)), N'') <> N''
    BEGIN
        INSERT INTO #SkipIndexes(index_name)
        SELECT DISTINCT CAST(TRIM(value) AS SYSNAME)
        FROM STRING_SPLIT(@SkipIndexesCsv, N',')
        WHERE TRIM(value) <> N'';
    END;

    /* ==== CANDIDATES: disabled nonclustered ==== */
    IF OBJECT_ID('tempdb..#IndexWork') IS NOT NULL
        DROP TABLE #IndexWork;

    CREATE TABLE #IndexWork
    (
        schema_name       SYSNAME NOT NULL,
        table_name        SYSNAME NOT NULL,
        index_name        SYSNAME NOT NULL,
        object_id         INT     NOT NULL,
        index_id          INT     NOT NULL,
        table_size_pages  BIGINT  NOT NULL,  -- data pages (heap/clustered)
        key_count         INT     NOT NULL   -- number of key columns
    );

    /* Build base candidate set and apply optional filters:
       - Table include-only (assumes dbo)
       - Index skip list (by exact index_name)
    */
    INSERT INTO #IndexWork (schema_name, table_name, index_name, object_id, index_id, table_size_pages, key_count)
    SELECT
        s.name AS schema_name,
        t.name AS table_name,
        i.name AS index_name,
        t.object_id,
        i.index_id,

        /* Table DATA size (heap=0, cluster=1) */
        (
            SELECT SUM(ps.reserved_page_count)
            FROM sys.dm_db_partition_stats AS ps
            WHERE ps.object_id = t.object_id
              AND ps.index_id IN (0, 1)
        ) AS table_size_pages,

        /* Key count (exclude included columns) */
        (
            SELECT COUNT(*)
            FROM sys.index_columns AS ic
            WHERE ic.object_id = i.object_id
              AND ic.index_id = i.index_id
              AND ic.is_included_column = 0
        ) AS key_count
    FROM sys.indexes AS i
    JOIN sys.tables  AS t ON t.object_id = i.object_id
    JOIN sys.schemas AS s ON s.schema_id = t.schema_id
    LEFT JOIN #FilterTables ft
           ON s.name = N'dbo'                     -- enforce dbo schema for filter
          AND t.name = ft.table_name              -- table name match
    LEFT JOIN #SkipIndexes sk
           ON i.name = sk.index_name              -- index name match (exact)
    WHERE i.type = 2                  -- nonclustered
      AND i.is_disabled = 1           -- disabled only
      AND t.name NOT IN ('BATCH', 'BATCHJOB')
      AND i.name LIKE 'I\_%' ESCAPE '\'
      AND (
            /* If a table filter is provided, include ONLY those tables under dbo;
               if no filter provided, include all candidates. */
            (SELECT COUNT(*) FROM #FilterTables) = 0
            OR ft.table_name IS NOT NULL
          )
      AND (
            /* If skip list provided, exclude any matched index */
            (SELECT COUNT(*) FROM #SkipIndexes) = 0
            OR sk.index_name IS NULL
          );

    /* ==== EXECUTION LOOP ==== */
    DECLARE @schema SYSNAME, @table SYSNAME, @index SYSNAME;
    DECLARE @sql    NVARCHAR(MAX);
    DECLARE @processed INT = 0;

    DECLARE idx CURSOR FAST_FORWARD FOR
        SELECT schema_name, table_name, index_name
        FROM #IndexWork
        ORDER BY table_size_pages ASC, key_count ASC;

    OPEN idx;
    FETCH NEXT FROM idx INTO @schema, @table, @index;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        DECLARE @attempt INT = 0, @maxAttempts INT = 6;
        DECLARE @delayMs INT = 500; -- initial backoff in ms
        DECLARE @log_id BIGINT;
        DECLARE @start_time DATETIME2(2);

        WHILE @attempt < @maxAttempts
        BEGIN
            BEGIN TRY
                SET @attempt += 1;

                /* Build ALTER INDEX statement */
                SET @sql = N'ALTER INDEX ' + QUOTENAME(@index) + N' ON '
                         + QUOTENAME(@schema) + N'.' + QUOTENAME(@table)
                         + N' REBUILD WITH ('
                         + N'MAXDOP = ' + CAST(@TargetDOP AS NVARCHAR(10));

                IF @UseOnline = 1
                BEGIN
                    SET @sql += N', ONLINE = ON';
                    IF @UseLowPriorityWait = 1
                        -- WAIT_AT_LOW_PRIORITY must be nested with ONLINE option
                        SET @sql += N' (WAIT_AT_LOW_PRIORITY (MAX_DURATION = 1 MINUTES, ABORT_AFTER_WAIT = BLOCKERS))';
                END

                SET @sql += N');';

                /* ---- LOG: start ---- */
                SET @start_time = SYSUTCDATETIME();
                INSERT INTO dbo.IndexRebuildLog(schema_name, table_name, index_name, status, attempt, start_time, sql_text)
                VALUES(@schema, @table, @index, 'WORKING', @attempt, @start_time, @sql);
                SET @log_id = SCOPE_IDENTITY();

                /* ---- Execute ---- */
                EXEC sys.sp_executesql @sql;

                /* ---- LOG: success ---- */
                UPDATE dbo.IndexRebuildLog
                SET status      = 'SUCCESS',
                    end_time    = SYSUTCDATETIME(),
                    duration_ms = DATEDIFF(MILLISECOND, @start_time, SYSUTCDATETIME())
                WHERE log_id = @log_id;

                BREAK; -- success -> next index
            END TRY
            BEGIN CATCH
                DECLARE @err INT = ERROR_NUMBER(),
                        @msg NVARCHAR(4000) = ERROR_MESSAGE();

                /* Transient errors (retry with backoff) */
                IF @err IN (40501, 10928, 10929, 40613, 49918, 49919, 49920, 1205)
                BEGIN
                    UPDATE dbo.IndexRebuildLog
                    SET status      = 'RETRY',
                        err_number  = @err,
                        err_message = @msg,
                        end_time    = SYSUTCDATETIME(),
                        duration_ms = CASE WHEN start_time IS NULL THEN NULL
                                           ELSE DATEDIFF(MILLISECOND, start_time, SYSUTCDATETIME())
                                      END
                    WHERE log_id = @log_id;

                    -- Exponential backoff with jitter (WAITFOR DELAY string)
                    DECLARE @jitter   INT = ABS(CHECKSUM(NEWID())) % 400;
                    DECLARE @waitMs   INT = @delayMs + @jitter;
                    DECLARE @delayStr VARCHAR(20);

                    SET @delayStr =
                        RIGHT('00' + CAST((@waitMs / 3600000) AS VARCHAR(2)), 2) + ':' +
                        RIGHT('00' + CAST((@waitMs / 60000 % 60) AS VARCHAR(2)), 2) + ':' +
                        RIGHT('00' + CAST((@waitMs / 1000 % 60) AS VARCHAR(2)), 2) + '.' +
                        RIGHT('000' + CAST((@waitMs % 1000) AS VARCHAR(3)), 3);

                    WAITFOR DELAY @delayStr;

                    SET @delayMs = CASE WHEN @delayMs < 16000 THEN @delayMs * 2 ELSE 30000 END; -- cap ~30s
                END
                ELSE
                BEGIN
                    UPDATE dbo.IndexRebuildLog
                    SET status      = 'FAILED',
                        err_number  = @err,
                        err_message = @msg,
                        end_time    = SYSUTCDATETIME(),
                        duration_ms = CASE WHEN start_time IS NULL THEN NULL
                                           ELSE DATEDIFF(MILLISECOND, start_time, SYSUTCDATETIME())
                                      END
                    WHERE log_id = @log_id;

                    BREAK; -- non-transient: give up on this index
                END
            END CATCH
        END

        SET @processed += 1;

        -- Optional per-item pause
        IF @PauseBetweenItemsMs > 0
        BEGIN
            DECLARE @itemDelayStr VARCHAR(20);
            SET @itemDelayStr =
                RIGHT('00' + CAST((@PauseBetweenItemsMs / 3600000) AS VARCHAR(2)), 2) + ':' +
                RIGHT('00' + CAST((@PauseBetweenItemsMs / 60000 % 60) AS VARCHAR(2)), 2) + ':' +
                RIGHT('00' + CAST((@PauseBetweenItemsMs / 1000 % 60) AS VARCHAR(2)), 2) + '.' +
                RIGHT('000' + CAST((@PauseBetweenItemsMs % 1000) AS VARCHAR(3)), 3);

            WAITFOR DELAY @itemDelayStr;
        END

        -- Micro-batch cool-off
        IF @ItemsPerBatch > 0 AND (@processed % @ItemsPerBatch = 0) AND @PauseBetweenBatchesMs > 0
        BEGIN
            DECLARE @batchDelayStr VARCHAR(20);
            SET @batchDelayStr =
                RIGHT('00' + CAST((@PauseBetweenBatchesMs / 3600000) AS VARCHAR(2)), 2) + ':' +
                RIGHT('00' + CAST((@PauseBetweenBatchesMs / 60000 % 60) AS VARCHAR(2)), 2) + ':' +
                RIGHT('00' + CAST((@PauseBetweenBatchesMs / 1000 % 60) AS VARCHAR(2)), 2) + '.' +
                RIGHT('000' + CAST((@PauseBetweenBatchesMs % 1000) AS VARCHAR(3)), 3);

            WAITFOR DELAY @batchDelayStr;
        END

        FETCH NEXT FROM idx INTO @schema, @table, @index;
    END

    CLOSE idx;
    DEALLOCATE idx;
END
GO
