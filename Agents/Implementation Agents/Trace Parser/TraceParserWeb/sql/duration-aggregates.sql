-- Additive schema only: no historical aggregate backfill.
-- Run after Duration units.sql inside the guarded analysis installation transaction.
IF COL_LENGTH('dbo.SessionMetrics','AggregationVersion') IS NOT NULL
 OR COL_LENGTH('dbo.TopMethodsBySession','AggregationVersion') IS NOT NULL
    THROW 51128,'Aggregate unit migration already installed or schema differs.',1;
ALTER TABLE dbo.SessionMetrics ADD AggregationVersion varchar(24) NULL, DurationValuesKnown bit NULL;
ALTER TABLE dbo.TopMethodsBySession ADD AggregationVersion varchar(24) NULL, DurationValuesKnown bit NULL;
GO
CREATE OR ALTER PROCEDURE dbo.sp_PopulateSessionAggregations @TraceId int
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF NOT EXISTS(SELECT 1 FROM dbo.vw_TraceDurationUnits
        WHERE TraceId=@TraceId AND NanosecondsPerStoredUnit IS NOT NULL)
      OR EXISTS(SELECT 1 FROM dbo.TPImportReceipts WHERE TraceId=@TraceId AND Phase IN ('Complete','Deleted'))
        THROW 51129,'Unclassified or completed historical trace: aggregate rewrite is not permitted.',1;
    -- Called in the importer's atomic Complete transaction. Direct PS imports get
    -- the same all-or-nothing aggregate publication.
    BEGIN TRY
        BEGIN TRAN;
        DELETE dbo.SessionMetrics WHERE TraceId=@TraceId;
        DELETE dbo.TopMethodsBySession WHERE TraceId=@TraceId;
        INSERT dbo.SessionMetrics(SessionId,TraceId,SessionName,UserName,TraceName,
            TotalTraceLines,RootCalls,TotalDurationMs,TotalDatabaseMs,TotalDatabaseCalls,
            TotalRpcCalls,TotalRowsFetched,AggregationVersion,DurationValuesKnown)
        SELECT us.SessionId,us.TraceId,us.SessionName,u.UserName,t.TraceName,
            COUNT(tl.TraceLineId),
            SUM(CASE WHEN tl.TraceLineId IS NOT NULL AND (tl.ParentSequence IS NULL OR tl.ParentSequence=0) THEN 1 ELSE 0 END),
            COALESCE(SUM(CASE WHEN tl.ParentSequence IS NULL OR tl.ParentSequence=0
                THEN CASE WHEN tl.InclusiveDurationNano>=0 THEN tl.InclusiveDurationNano ELSE 0 END ELSE 0 END)/1000000.0,0),
            COALESCE(SUM(CASE WHEN tl.CallTypeId=64 AND tl.DatabaseDurationNano>=0 THEN tl.DatabaseDurationNano ELSE 0 END)/1000000.0,0),
            COALESCE(SUM(CASE WHEN tl.CallTypeId=64 THEN tl.DatabaseCalls ELSE 0 END),0),
            COALESCE(SUM(CONVERT(bigint,tl.InclusiveRpc)),0),COALESCE(SUM(tl.RowFetchCount),0),'sql-execution-v2',
            MIN(CASE WHEN tl.TraceLineId IS NULL OR (tl.IsComplete=1 AND tl.InclusiveDurationNano>=0 AND tl.ExclusiveDurationNano>=0
                AND tl.DatabaseDurationNano>=0 AND tl.PrepDurationNano>=0 AND tl.BindDurationNano>=0 AND tl.RowFetchDurationNano>=0) THEN 1 ELSE 0 END)
        FROM dbo.UserSessions us
        JOIN dbo.Users u ON u.UserId=us.UserId
        JOIN dbo.Traces t ON t.TraceId=us.TraceId
        LEFT JOIN dbo.UserSessionProcessThreads uspt ON uspt.SessionId=us.SessionId AND uspt.TraceId=us.TraceId
        LEFT JOIN dbo.vw_UnitAwareTraceLines tl ON tl.UserSessionProcessThreadId=uspt.UserSessionProcessThreadId
        WHERE us.TraceId=@TraceId
        GROUP BY us.SessionId,us.TraceId,us.SessionName,u.UserName,t.TraceName;

        INSERT dbo.TopMethodsBySession(SessionId,TraceId,MethodName,CallCount,
            TotalInclusiveMs,TotalExclusiveMs,AvgInclusiveMs,TotalDbCalls,TotalDbMs,AggregationVersion,DurationValuesKnown)
        SELECT uspt.SessionId,uspt.TraceId,mn.Name,COUNT(*),
            SUM(CASE WHEN tl.InclusiveDurationNano>=0 THEN tl.InclusiveDurationNano ELSE 0 END)/1000000.0,
            SUM(CASE WHEN tl.ExclusiveDurationNano>=0 THEN tl.ExclusiveDurationNano ELSE 0 END)/1000000.0,
            AVG(CASE WHEN tl.InclusiveDurationNano>=0 THEN tl.InclusiveDurationNano ELSE 0 END)/1000000.0,
            SUM(tl.DatabaseCalls),
            SUM(CASE WHEN tl.DatabaseDurationNano>=0 THEN tl.DatabaseDurationNano ELSE 0 END)/1000000.0,
            'sql-execution-v2',
            MIN(CASE WHEN tl.IsComplete=1 AND tl.InclusiveDurationNano>=0 AND tl.ExclusiveDurationNano>=0
                AND tl.DatabaseDurationNano>=0 AND tl.PrepDurationNano>=0 AND tl.BindDurationNano>=0 AND tl.RowFetchDurationNano>=0 THEN 1 ELSE 0 END)
        FROM dbo.vw_UnitAwareTraceLines tl
        JOIN dbo.UserSessionProcessThreads uspt ON uspt.UserSessionProcessThreadId=tl.UserSessionProcessThreadId
        JOIN dbo.MethodNames mn ON mn.MethodHash=tl.MethodHash
        WHERE uspt.TraceId=@TraceId
        GROUP BY uspt.SessionId,uspt.TraceId,mn.Name;
        COMMIT;
    END TRY
    BEGIN CATCH
        IF XACT_STATE()<>0 ROLLBACK;
        THROW;
    END CATCH;
END;
GO
-- Read the existing physical tables, never scan the trace lines for the homepage.
-- Legacy session counters mix inclusive contexts; normalizing their unit cannot
-- repair their grain or root/session joins. Withhold those totals, retain counts.
CREATE OR ALTER VIEW dbo.vw_SessionMetrics AS
SELECT m.SessionId,m.SessionName,m.UserName,m.TraceName,m.TraceId,m.TotalTraceLines,
    CASE WHEN m.AggregationVersion='sql-execution-v2' THEN m.RootCalls END AS RootCalls,
    CASE WHEN m.AggregationVersion='sql-execution-v2' AND m.DurationValuesKnown=1 AND u.NanosecondsPerStoredUnit IS NOT NULL
        THEN m.TotalDurationMs END AS TotalDurationMs,
    CASE WHEN m.AggregationVersion='sql-execution-v2' AND m.DurationValuesKnown=1 AND u.NanosecondsPerStoredUnit IS NOT NULL
        THEN m.TotalDatabaseMs END AS TotalDatabaseMs,
    CASE WHEN m.AggregationVersion='sql-execution-v2' THEN m.TotalDatabaseCalls END AS TotalDatabaseCalls,
    m.TotalRpcCalls,m.TotalRowsFetched,u.StoredDurationUnit,
    COALESCE(m.AggregationVersion,'legacy-unverified') AS AggregationVersion,
    CASE WHEN m.DurationValuesKnown=0 THEN 'unknown-values'
        WHEN u.NanosecondsPerStoredUnit IS NULL THEN 'unclassified-units'
        WHEN m.AggregationVersion IS NULL THEN 'legacy-unverified' ELSE 'known' END AS DurationStatus
FROM dbo.SessionMetrics m JOIN dbo.vw_TraceDurationUnits u ON u.TraceId=m.TraceId;
GO
-- Method groups retain inclusive semantics. Old rounded values can be normalized
-- but not made more precise: 0.01 old milliseconds = 1ms for v1.
CREATE OR ALTER VIEW dbo.vw_TopMethodsBySession AS
SELECT m.SessionId,m.TraceId,m.MethodName,m.CallCount,
    CONVERT(decimal(28,4),m.TotalInclusiveMs)*s.Scale AS TotalInclusiveMs,
    CONVERT(decimal(28,4),m.TotalExclusiveMs)*s.Scale AS TotalExclusiveMs,
    CONVERT(decimal(28,6),m.AvgInclusiveMs)*s.Scale AS AvgInclusiveMs,
    m.TotalDbCalls,CONVERT(decimal(28,4),m.TotalDbMs)*s.Scale AS TotalDbMs,
    u.StoredDurationUnit,COALESCE(m.AggregationVersion,'legacy-rounded') AS AggregationVersion,
    CONVERT(decimal(10,4),0.01)*s.Scale AS TotalPrecisionMs
FROM dbo.TopMethodsBySession m JOIN dbo.vw_TraceDurationUnits u ON u.TraceId=m.TraceId
CROSS APPLY(SELECT CASE WHEN u.NanosecondsPerStoredUnit IS NULL THEN NULL
    WHEN m.DurationValuesKnown=0 THEN NULL
    WHEN m.AggregationVersion='sql-execution-v2' THEN 1
    WHEN m.AggregationVersion IS NULL THEN u.NanosecondsPerStoredUnit END AS Scale) s;
GO
