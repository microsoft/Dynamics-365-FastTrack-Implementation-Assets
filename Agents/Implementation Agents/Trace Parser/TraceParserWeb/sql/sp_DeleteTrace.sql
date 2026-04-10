CREATE OR ALTER PROCEDURE dbo.sp_DeleteTrace
    @TraceId INT
AS
BEGIN
    SET NOCOUNT ON;

    -- Delete in FK-safe order (children first)

    -- 0a. Pre-computed aggregation tables
    DELETE FROM dbo.SessionMetrics WHERE TraceId = @TraceId;
    DELETE FROM dbo.TopMethodsBySession WHERE TraceId = @TraceId;

    -- 0b. TopMethods (FK → UserSessionProcessThreads)
    DELETE tm FROM dbo.TopMethods tm
    INNER JOIN dbo.UserSessionProcessThreads uspt ON tm.BeginUspId = uspt.UserSessionProcessThreadId
    WHERE uspt.TraceId = @TraceId;

    -- 1. QueryBindParameters (FK → TraceLines.TraceLineId)
    DELETE qbp
    FROM QueryBindParameters qbp
    INNER JOIN TraceLines tl ON qbp.TraceLineId = tl.TraceLineId
    INNER JOIN UserSessionProcessThreads uspt ON tl.UserSessionProcessThreadId = uspt.UserSessionProcessThreadId
    WHERE uspt.TraceId = @TraceId;

    -- 2. TraceLines (FK → UserSessionProcessThreads) — batch delete to avoid transaction log overflow
    DECLARE @deleted INT = 1;
    WHILE @deleted > 0
    BEGIN
        DELETE TOP (500000) tl
        FROM TraceLines tl
        INNER JOIN UserSessionProcessThreads uspt ON tl.UserSessionProcessThreadId = uspt.UserSessionProcessThreadId
        WHERE uspt.TraceId = @TraceId;
        SET @deleted = @@ROWCOUNT;
    END

    -- 3. StageTraceLines (staging table, joins via UserSessionProcessThreadId)
    DELETE stl
    FROM StageTraceLines stl
    INNER JOIN UserSessionProcessThreads uspt ON stl.UserSessionProcessThreadId = uspt.UserSessionProcessThreadId
    WHERE uspt.TraceId = @TraceId;

    -- 4. UserSessionProcessThreads (FK → UserSessions)
    DELETE FROM UserSessionProcessThreads WHERE TraceId = @TraceId;

    -- 5. UserSessions (FK → Traces)
    DELETE FROM UserSessions WHERE TraceId = @TraceId;

    -- 6. Traces (root)
    DELETE FROM Traces WHERE TraceId = @TraceId;
END;
