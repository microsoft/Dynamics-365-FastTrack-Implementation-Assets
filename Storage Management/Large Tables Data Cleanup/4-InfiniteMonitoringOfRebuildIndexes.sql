/* ==========================================================================================
   Azure SQL - ALTER INDEX Monitor (Infinite, 10-min cadence) with Kill & Rebuild (Skip list)
   - "Slow rebuild" = no delta in reads/writes/logical_reads across the 10-min interval
   - KILL non-progressing spids, parse index name, accumulate skip list, re-run your proc:
       EXEC dbo.RebuildDisabledNonclusteredIndexes @SkipIndexesCsv = N'<csv>'
   - Safe for Azure SQL DMVs; streaming output via RAISERROR ... WITH NOWAIT (severity 10)
   - Stop by cancelling the batch in SSMS/Azure Data Studio
   ========================================================================================== */

SET NOCOUNT ON;

-- =================== Parameters ===================
DECLARE @TargetSqlTextLike      NVARCHAR(4000) = N'%ALTER INDEX%'; 
DECLARE @IncludeBaselineOnce    BIT            = 1;           -- 1 = print baseline once
DECLARE @SleepDelay             CHAR(8)        = '00:10:00';  -- 10 minutes
DECLARE @InvokeRebuildAfterKill BIT            = 1;           -- call rebuild proc when new skips added
DECLARE @RebuildProcSysName     SYSNAME        = N'dbo.RebuildDisabledNonclusteredIndexes';

-- =================== State tables ===================
IF OBJECT_ID('tempdb..#prev') IS NOT NULL DROP TABLE #prev;
CREATE TABLE #prev
(
    session_id          INT           NOT NULL PRIMARY KEY,
    command             NVARCHAR(60)  NULL,
    sql_text            NVARCHAR(MAX) NULL,
    reads               BIGINT        NOT NULL,
    writes              BIGINT        NOT NULL,
    logical_reads       BIGINT        NOT NULL,
    percent_complete    DECIMAL(9,4)  NULL,
    total_elapsed_time  BIGINT        NOT NULL,
    sample_time         DATETIME2(3)  NOT NULL
);

IF OBJECT_ID('tempdb..#skip_master') IS NOT NULL DROP TABLE #skip_master;
CREATE TABLE #skip_master
(
    index_name SYSNAME NOT NULL,
    CONSTRAINT PK_skip_master PRIMARY KEY (index_name)
);

DECLARE @AddedSkipsThisLoop INT;
DECLARE @first BIT = @IncludeBaselineOnce;

-- =================== Loop ===================
WHILE (1 = 1)
BEGIN
    SET @AddedSkipsThisLoop = 0;

    DECLARE @sample_time      DATETIME2(3) = SYSDATETIME();
    DECLARE @sample_time_str  VARCHAR(33)  = CONVERT(VARCHAR(33), @sample_time, 126);
    DECLARE @msg              NVARCHAR(MAX) = N'--- Sampling at ' + @sample_time_str + N' ---';

    RAISERROR('%s', 10, 1, @msg) WITH NOWAIT;

    -- === Capture current ALTER INDEX requests matching target text ===
    ;WITH base_req AS
    (
        SELECT
            r.session_id,
            r.status,
            r.command,
            r.percent_complete,
            r.wait_type,
            r.last_wait_type,
            r.wait_time,
            r.cpu_time,
            r.total_elapsed_time,
            r.blocking_session_id,
            r.plan_handle,
            r.sql_handle,
            r.reads,
            r.writes,
            r.logical_reads
        FROM sys.dm_exec_requests AS r
    ),
    req AS
    (
        SELECT
            br.*,
            txt.text AS sql_text
        FROM base_req AS br
        CROSS APPLY sys.dm_exec_sql_text(br.sql_handle) AS txt
        WHERE
            br.command = 'ALTER INDEX'
            AND txt.text LIKE @TargetSqlTextLike
    ),
    ses AS
    (
        SELECT
            s.session_id,
            s.login_name,
            s.host_name,
            s.program_name,
            s.status AS session_status
        FROM sys.dm_exec_sessions AS s
    ),
    curr AS
    (
        SELECT
            r.session_id,
            r.status,
            r.command,
            r.percent_complete,
            r.wait_type,
            r.last_wait_type,
            r.wait_time,
            r.cpu_time,
            r.total_elapsed_time,
            r.reads,
            r.writes,
            r.logical_reads,
            r.blocking_session_id,
            s.login_name,
            s.host_name,
            s.program_name,
            s.session_status,
            r.sql_text,
            CASE
                WHEN r.percent_complete = 0 AND r.wait_type IN ('CXSYNC_PORT','CXCONSUMER')
                    THEN N'⚠ ONLINE init stalled (metadata latch/sync)'
                WHEN r.percent_complete > 0 AND r.status = 'running'
                    THEN N'✅ Rebuild progressing'
                WHEN r.status = 'suspended' AND r.wait_type IS NOT NULL
                    THEN N'⏸ On hold (resource wait)'
                ELSE N'ℹ Active request'
            END AS diagnosis_hint
        FROM req AS r
        LEFT JOIN ses AS s ON s.session_id = r.session_id
    )
    SELECT
        c.session_id,
        c.command,
        c.status,
        c.percent_complete,
        c.wait_type,
        c.last_wait_type,
        c.total_elapsed_time,
        c.reads,
        c.writes,
        c.logical_reads,
        c.blocking_session_id,
        c.login_name,
        c.host_name,
        c.program_name,
        c.session_status,
        c.diagnosis_hint,
        c.sql_text
    INTO #curr
    FROM curr AS c;

    -- === Compute deltas vs previous sample ===
    IF OBJECT_ID('tempdb..#result') IS NOT NULL DROP TABLE #result;

    SELECT
        cur.session_id,
        cur.command,
        cur.status,
        cur.percent_complete,
        cur.wait_type,
        cur.last_wait_type,
        cur.total_elapsed_time,
        cur.reads,
        cur.writes,
        cur.logical_reads,
        cur.blocking_session_id,
        cur.login_name,
        cur.host_name,
        cur.program_name,
        cur.session_status,
        cur.diagnosis_hint,
        cur.sql_text,
        CASE WHEN p.session_id IS NOT NULL AND cur.total_elapsed_time >= p.total_elapsed_time
             THEN cur.reads - p.reads ELSE NULL END AS delta_reads,
        CASE WHEN p.session_id IS NOT NULL AND cur.total_elapsed_time >= p.total_elapsed_time
             THEN cur.writes - p.writes ELSE NULL END AS delta_writes,
        CASE WHEN p.session_id IS NOT NULL AND cur.total_elapsed_time >= p.total_elapsed_time
             THEN cur.logical_reads - p.logical_reads ELSE NULL END AS delta_logical_reads,
        CASE 
            WHEN p.session_id IS NULL THEN CASE WHEN @first = 1 THEN 1 ELSE 0 END
            WHEN cur.total_elapsed_time < p.total_elapsed_time THEN 0
            WHEN (cur.reads > p.reads) OR (cur.writes > p.writes) OR (cur.logical_reads > p.logical_reads) THEN 1
            ELSE 0
        END AS is_progressing,
        CASE 
            WHEN p.session_id IS NOT NULL
             AND cur.total_elapsed_time >= p.total_elapsed_time
             AND (cur.reads = p.reads AND cur.writes = p.writes AND cur.logical_reads = p.logical_reads)
            THEN 1 ELSE 0
        END AS is_no_progress
    INTO #result
    FROM #curr AS cur
    LEFT JOIN #prev AS p
      ON p.session_id = cur.session_id;

    -- === Progress output ===
    IF EXISTS (SELECT 1 FROM #result WHERE is_progressing = 1)
    BEGIN
        SET @msg = N'Progress detected for ALTER INDEX requests:';
        RAISERROR('%s', 10, 1, @msg) WITH NOWAIT;

        SELECT
            @sample_time AS sample_time,
            session_id,
            status,
            command,
            percent_complete,
            wait_type,
            last_wait_type,
            total_elapsed_time,
            reads, writes, logical_reads,
            delta_reads, delta_writes, delta_logical_reads,
            blocking_session_id,
            login_name, host_name, program_name,
            diagnosis_hint,
			sql_text
        FROM #result
        WHERE is_progressing = 1
        ORDER BY total_elapsed_time DESC;
    END
    ELSE
    BEGIN
        DECLARE @active INT = (SELECT COUNT(*) FROM #curr);
        SET @msg = N'No progressing ALTER INDEX this interval. Active matching: ' + CAST(@active AS NVARCHAR(20));
        RAISERROR('%s', 10, 1, @msg) WITH NOWAIT;
    END

    -- === Identify and KILL non-progressing ALTER INDEX spids ===
    IF OBJECT_ID('tempdb..#to_kill') IS NOT NULL DROP TABLE #to_kill;

    ;WITH np AS
    (
        SELECT r.session_id, r.sql_text
        FROM #result AS r
        WHERE r.is_no_progress = 1
    ),
    parsed AS
    (
        SELECT
            n.session_id,
            n.sql_text,
            UPPER(CONVERT(NVARCHAR(MAX), n.sql_text)) AS utext
        FROM np AS n
    ),
    bounds AS
    (
        SELECT
            p.session_id,
            p.sql_text,
            p.utext,
            CHARINDEX('ALTER INDEX', p.utext) AS pos_alter,
            CASE 
                WHEN CHARINDEX('ALTER INDEX', p.utext) > 0 
                THEN CHARINDEX(' ON', p.utext, CHARINDEX('ALTER INDEX', p.utext) + LEN('ALTER INDEX'))
                ELSE 0
            END AS pos_on
        FROM parsed AS p
    ),
    extracted AS
    (
        SELECT
            b.session_id,
            CASE 
                WHEN b.pos_alter > 0 AND b.pos_on > b.pos_alter
                THEN LTRIM(RTRIM(SUBSTRING(
                        b.sql_text,
                        b.pos_alter + LEN('ALTER INDEX'),
                        b.pos_on - (b.pos_alter + LEN('ALTER INDEX'))
                    )))
                ELSE NULL
            END AS raw_index_part
        FROM bounds AS b
    )
    SELECT
        x.session_id,
        CASE 
            WHEN x.raw_index_part IS NULL THEN NULL
            ELSE
                CASE 
                    WHEN UPPER(LTRIM(RTRIM(x.raw_index_part))) LIKE N'ALL%' THEN NULL
                    ELSE REPLACE(REPLACE(LTRIM(RTRIM(x.raw_index_part)), N'[', N''), N']', N'')
                END
        END AS index_name_clean,
        r.sql_text
    INTO #to_kill
    FROM extracted AS x
    JOIN #result AS r ON r.session_id = x.session_id;

    IF EXISTS (SELECT 1 FROM #to_kill)
    BEGIN
        SET @msg = N'Non-progressing ALTER INDEX requests detected. Initiating KILL ...';
        RAISERROR('%s', 10, 1, @msg) WITH NOWAIT;

        DECLARE @sid INT, @idx SYSNAME;

        DECLARE kill_cur CURSOR LOCAL FAST_FORWARD FOR
        SELECT session_id, index_name_clean
        FROM #to_kill;

        OPEN kill_cur;
        FETCH NEXT FROM kill_cur INTO @sid, @idx;

        WHILE @@FETCH_STATUS = 0
        BEGIN
            BEGIN TRY
                DECLARE @killCmd NVARCHAR(50) = N'KILL ' + CAST(@sid AS NVARCHAR(12)) + N';';
                SET @msg = N'KILLing session ' + CAST(@sid AS NVARCHAR(12)) + N' ...';
                RAISERROR('%s', 10, 1, @msg) WITH NOWAIT;

                EXEC (@killCmd);

                SET @msg = N'KILL ' + CAST(@sid AS NVARCHAR(12)) + N' completed.';
                RAISERROR('%s', 10, 1, @msg) WITH NOWAIT;

                IF @idx IS NOT NULL AND LEN(@idx) > 0
                BEGIN
                    SET @idx = REPLACE(@idx, N' ', N'');  -- normalize
                    IF NOT EXISTS (SELECT 1 FROM #skip_master WHERE index_name = @idx)
                    BEGIN
                        INSERT INTO #skip_master(index_name) VALUES(@idx);
                        SET @AddedSkipsThisLoop += 1;

                        SET @msg = N'Added to skip: ' + @idx;
                        RAISERROR('%s', 10, 1, @msg) WITH NOWAIT;
                    END
                END
                ELSE
                BEGIN
                    SET @msg = N'WARNING: Could not parse a specific index name (maybe ALTER INDEX ALL). Not added to skip list.';
                    RAISERROR('%s', 10, 1, @msg) WITH NOWAIT;
                END
            END TRY
            BEGIN CATCH
                DECLARE @errMsg NVARCHAR(MAX) =
                    N'ERROR: Failed to KILL ' + CAST(@sid AS NVARCHAR(12)) + N'. ' +
                    ERROR_MESSAGE() + N' (State ' + CAST(ERROR_STATE() AS NVARCHAR(10)) +
                    N', Severity ' + CAST(ERROR_SEVERITY() AS NVARCHAR(10)) + N')';
                RAISERROR('%s', 10, 1, @errMsg) WITH NOWAIT;
            END CATCH;

            FETCH NEXT FROM kill_cur INTO @sid, @idx;
        END

        CLOSE kill_cur;
        DEALLOCATE kill_cur;
    END

    -- === Re-run your rebuild proc with accumulated skip list ===
    IF @InvokeRebuildAfterKill = 1 AND @AddedSkipsThisLoop > 0
    BEGIN
        DECLARE @SkipCsv NVARCHAR(MAX);
        SELECT @SkipCsv = STRING_AGG(index_name, N',') WITHIN GROUP (ORDER BY index_name)
        FROM #skip_master;

        IF @SkipCsv IS NULL SET @SkipCsv = N'';

        SET @msg = N'Re-executing ' + @RebuildProcSysName + N' with @SkipIndexesCsv = ' + @SkipCsv;
        RAISERROR('%s', 10, 1, @msg) WITH NOWAIT;

        DECLARE @execSql NVARCHAR(MAX) =
            N'EXEC ' + QUOTENAME(PARSENAME(@RebuildProcSysName, 2)) + N'.' + QUOTENAME(PARSENAME(@RebuildProcSysName, 1)) +
            N' @SkipIndexesCsv = @p1;';

        EXEC sp_executesql @execSql, N'@p1 NVARCHAR(MAX)', @p1 = @SkipCsv;
    END

    -- === Refresh previous snapshot ===
    UPDATE p
       SET p.command            = c.command,
           p.sql_text           = c.sql_text,
           p.reads              = c.reads,
           p.writes             = c.writes,
           p.logical_reads      = c.logical_reads,
           p.percent_complete   = c.percent_complete,
           p.total_elapsed_time = c.total_elapsed_time,
           p.sample_time        = @sample_time
      FROM #prev AS p
      JOIN #curr AS c ON c.session_id = p.session_id;

    INSERT INTO #prev (session_id, command, sql_text, reads, writes, logical_reads, percent_complete, total_elapsed_time, sample_time)
    SELECT c.session_id, c.command, c.sql_text, c.reads, c.writes, c.logical_reads, c.percent_complete, c.total_elapsed_time, @sample_time
    FROM #curr AS c
    WHERE NOT EXISTS (SELECT 1 FROM #prev AS p WHERE p.session_id = c.session_id);

    DELETE p
      FROM #prev AS p
     WHERE NOT EXISTS (SELECT 1 FROM #curr AS c WHERE c.session_id = p.session_id);

    -- === Cleanup and sleep ===
    DROP TABLE #curr;
    DROP TABLE #result;
    IF OBJECT_ID('tempdb..#to_kill') IS NOT NULL DROP TABLE #to_kill;

    SET @msg = N'Sleeping for ' + @SleepDelay + N' ...';
    RAISERROR('%s', 10, 1, @msg) WITH NOWAIT;

    WAITFOR DELAY @SleepDelay;

    SET @first = 0;
END;
-- (No GO here; let the loop run in a single batch)
