-- ============================================================
-- TraceParser Analysis Views
-- ============================================================
-- Purpose: Create simplified views for Copilot Studio agent
--          to analyze D365 F&O trace data
-- 
-- These views:
--   1. Denormalize the hash-based schema
--   2. Convert nanoseconds to milliseconds
--   3. Pre-filter common performance patterns
-- Run Duration units.sql first. Unknown duration provenance produces NULL times,
-- never fabricated threshold matches. No stored trace data is rescaled.
-- Materialized deployments must use the discrete Web/sql duration migration,
-- not replace their aggregate views with this nonmaterialized reference script.
--
-- Run this script in SSMS connected to your TraceParser database
-- .DISCLAIMER
--     This script is provided as sample/reference code only under the MIT License.
--     It is not an official Microsoft product or service. Microsoft makes no warranties,
--     express or implied, and assumes no liability for its use. You are responsible for
--     reviewing, testing, and validating this script before running it in your environment.
--     Use at your own risk.

--  Copyright (c) Microsoft Corporation.
-- ============================================================

-- Run this script in the target Trace Parser database context
-- (e.g., AxTrace or TraceParserDB). Select the correct database
-- in SSMS or your deployment tool before executing.
GO

PRINT 'Creating TraceParser Analysis Views...';
PRINT '';

-- ============================================================
-- View 1: vw_SessionSummary
-- ============================================================
-- Purpose: Denormalized session view with user and trace info
-- Use for: Session discovery, finding sessions by user
-- ============================================================

PRINT 'Creating vw_SessionSummary...';
GO

CREATE OR ALTER VIEW dbo.vw_SessionSummary AS
SELECT 
    us.SessionId,
    us.TraceId,
    us.SessionName,
    u.UserId,
    u.UserName,
    t.TraceName,
    t.TimeStampBegin AS TraceStart,
    t.TimeStampEnd AS TraceEnd,
    t.AxVersion,
    c.CustomerName
FROM dbo.UserSessions us
INNER JOIN dbo.Users u ON us.UserId = u.UserId
INNER JOIN dbo.Traces t ON us.TraceId = t.TraceId
LEFT JOIN dbo.Customers c ON us.CustomerCustomerId = c.CustomerId;
GO

PRINT '  ✓ vw_SessionSummary created';
PRINT '';

-- ============================================================
-- View 2: vw_SessionMetrics
-- ============================================================
-- Purpose: Session with aggregated performance metrics
-- Use for: Quick session performance overview
-- Note: All times are in MILLISECONDS (pre-converted)
-- ============================================================

PRINT 'Creating vw_SessionMetrics...';
GO

CREATE OR ALTER VIEW dbo.vw_SessionMetrics AS
SELECT 
    us.SessionId,
    us.SessionName,
    u.UserName,
    t.TraceName,
    t.TraceId,
    COUNT(tl.TraceLineId) AS TotalTraceLines,
    SUM(CASE WHEN tl.TraceLineId IS NOT NULL AND (tl.ParentSequence IS NULL OR tl.ParentSequence = 0) THEN 1 ELSE 0 END) AS RootCalls,
    CASE WHEN du.NanosecondsPerStoredUnit IS NOT NULL THEN
    CAST(COALESCE(SUM(CASE WHEN tl.ParentSequence IS NULL OR tl.ParentSequence = 0
         THEN tl.InclusiveDurationNano ELSE 0 END), 0) / 1000000.0 AS DECIMAL(18,2)) END AS TotalDurationMs,
    -- Method DB counters include descendant SQL: only execution rows are additive.
    CASE WHEN du.NanosecondsPerStoredUnit IS NOT NULL THEN
    CAST(COALESCE(SUM(CASE WHEN tl.CallTypeId = 64 THEN tl.DatabaseDurationNano ELSE 0 END), 0) / 1000000.0 AS DECIMAL(18,2)) END AS TotalDatabaseMs,
    COALESCE(SUM(CASE WHEN tl.CallTypeId = 64 THEN tl.DatabaseCalls ELSE 0 END), 0) AS TotalDatabaseCalls,
    COALESCE(SUM(tl.InclusiveRpc), 0) AS TotalRpcCalls,
    COALESCE(SUM(tl.RowFetchCount), 0) AS TotalRowsFetched,
    du.StoredDurationUnit,
    CAST('sql-execution-v2' AS varchar(24)) AS AggregationVersion,
    CASE WHEN du.NanosecondsPerStoredUnit IS NULL THEN 'unclassified-units' ELSE 'known' END AS DurationStatus
FROM dbo.UserSessions us
INNER JOIN dbo.Users u ON us.UserId = u.UserId
INNER JOIN dbo.Traces t ON us.TraceId = t.TraceId
INNER JOIN dbo.vw_TraceDurationUnits du ON du.TraceId=t.TraceId
INNER JOIN dbo.UserSessionProcessThreads uspt ON us.SessionId = uspt.SessionId AND us.TraceId = uspt.TraceId
LEFT JOIN dbo.vw_UnitAwareTraceLines tl ON uspt.UserSessionProcessThreadId = tl.UserSessionProcessThreadId
GROUP BY us.SessionId, us.SessionName, u.UserName, t.TraceName, t.TraceId,du.NanosecondsPerStoredUnit,du.StoredDurationUnit;
GO

PRINT '  ✓ vw_SessionMetrics created';
PRINT '';

-- ============================================================
-- View 3: vw_TraceLineDetails
-- ============================================================
-- Purpose: TraceLines with method names and SQL text resolved
-- Use for: Call tree analysis, method investigation
-- Note: All times are in MILLISECONDS (pre-converted)
-- ============================================================

PRINT 'Creating vw_TraceLineDetails...';
GO

CREATE OR ALTER VIEW dbo.vw_TraceLineDetails AS
SELECT 
    tl.TraceLineId,
    tl.UserSessionProcessThreadId,
    uspt.SessionId,
    uspt.TraceId,
    tl.Sequence,
    tl.ParentSequence,
    tl.CallTypeId,
    tl.MethodHash,
    mn.Name AS MethodName,
    CAST(tl.InclusiveDurationNano / 1000000.0 AS DECIMAL(18,2)) AS InclusiveMs,
    CAST(tl.ExclusiveDurationNano / 1000000.0 AS DECIMAL(18,2)) AS ExclusiveMs,
    CAST(tl.DatabaseDurationNano / 1000000.0 AS DECIMAL(18,2)) AS DatabaseMs,
    tl.DatabaseCalls,
    CASE 
        WHEN tl.DatabaseCalls > 0 
        THEN CAST(tl.DatabaseDurationNano / 1000000.0 / tl.DatabaseCalls AS DECIMAL(18,4))
        ELSE CASE WHEN tl.StoredDurationUnit<>'unknown' THEN 0 END
    END AS AvgDbCallMs,
    tl.RowFetchCount,
    tl.QueryStatementHash,
    qs.Statement AS SqlStatement,
    tl.QueryTableHash,
    qt.TableNames,
    tl.HasChildren,
    tl.IsComplete,
    tl.EventType,
    tl.EventName,
    tl.StoredDurationUnit
FROM dbo.vw_UnitAwareTraceLines tl
INNER JOIN dbo.UserSessionProcessThreads uspt 
    ON tl.UserSessionProcessThreadId = uspt.UserSessionProcessThreadId
LEFT JOIN dbo.MethodNames mn ON tl.MethodHash = mn.MethodHash
LEFT JOIN dbo.QueryStatements qs ON tl.QueryStatementHash = qs.QueryStatementHash
LEFT JOIN dbo.QueryTables qt ON tl.QueryTableHash = qt.QueryTableHash;
GO

PRINT '  ✓ vw_TraceLineDetails created';
PRINT '';

-- ============================================================
-- View 4: vw_NPlusOnePatterns
-- ============================================================
-- Purpose: Pre-filtered N+1 query pattern candidates
-- Filter: DatabaseCalls > 100 AND average ms per call < 5
-- Use for: Instant N+1 pattern detection
-- Note: All times are in MILLISECONDS (pre-converted)
-- Grain: one call context, not one method name. Suppress only a caller whose
-- immediate child accounts for exactly the same inclusive DB work. Separate
-- executions/threads/sessions survive even when names and metrics are equal.
-- ============================================================

PRINT 'Creating vw_NPlusOnePatterns...';
GO

CREATE OR ALTER VIEW dbo.vw_NPlusOnePatterns AS
SELECT 
    tl.TraceLineId,
    uspt.SessionId,
    uspt.TraceId,
    tl.UserSessionProcessThreadId,
    tl.Sequence,
    tl.ParentSequence,
    mn.Name AS MethodName,
    tl.DatabaseCalls,
    CAST(tl.DatabaseDurationNano / 1000000.0 AS DECIMAL(18,2)) AS DatabaseMs,
    CAST(tl.DatabaseDurationNano / 1000000.0 / NULLIF(tl.DatabaseCalls, 0) AS DECIMAL(18,4)) AS AvgMsPerCall,
    CAST(tl.InclusiveDurationNano / 1000000.0 AS DECIMAL(18,2)) AS InclusiveMs,
    'N+1 PATTERN: High DB calls with low avg time' AS PatternDescription,
    tl.StoredDurationUnit
FROM dbo.vw_UnitAwareTraceLines tl
INNER JOIN dbo.UserSessionProcessThreads uspt 
    ON tl.UserSessionProcessThreadId = uspt.UserSessionProcessThreadId
LEFT JOIN dbo.MethodNames mn ON tl.MethodHash = mn.MethodHash
WHERE tl.DatabaseCalls > 100
  AND tl.DatabaseDurationNano >= 0
  AND tl.DatabaseDurationNano < CONVERT(decimal(28,0),tl.DatabaseCalls) * 5000000
  AND NOT EXISTS (
      SELECT 1 FROM dbo.vw_UnitAwareTraceLines child
      WHERE child.UserSessionProcessThreadId = tl.UserSessionProcessThreadId
        AND child.ParentSequence = tl.Sequence
        AND child.Sequence > tl.Sequence
        AND child.DatabaseCalls = tl.DatabaseCalls
        AND child.DatabaseDurationNano = tl.DatabaseDurationNano
  );
GO

PRINT '  ✓ vw_NPlusOnePatterns created';
PRINT '';

-- ============================================================
-- View 5: vw_SlowSqlStatements
-- ============================================================
-- Purpose: SQL statements exceeding 5 seconds execution time
-- Filter: DatabaseDurationNano > 5,000,000,000 (5 seconds)
-- Use for: Blocking query identification
-- Note: All times are in MILLISECONDS (pre-converted)
-- ============================================================

PRINT 'Creating vw_SlowSqlStatements...';
GO

CREATE OR ALTER VIEW dbo.vw_SlowSqlStatements AS
SELECT 
    tl.TraceLineId,
    uspt.SessionId,
    uspt.TraceId,
    mn.Name AS MethodName,
    qs.Statement AS SqlStatement,
    qt.TableNames,
    CAST(tl.DatabaseDurationNano / 1000000.0 AS DECIMAL(18,2)) AS ExecutionMs,
    tl.RowFetchCount,
    'SLOW SQL: Execution > 5 seconds' AS PatternDescription,
    tl.StoredDurationUnit
FROM dbo.vw_UnitAwareTraceLines tl
INNER JOIN dbo.UserSessionProcessThreads uspt 
    ON tl.UserSessionProcessThreadId = uspt.UserSessionProcessThreadId
LEFT JOIN dbo.MethodNames mn ON tl.MethodHash = mn.MethodHash
LEFT JOIN dbo.QueryStatements qs ON tl.QueryStatementHash = qs.QueryStatementHash
LEFT JOIN dbo.QueryTables qt ON tl.QueryTableHash = qt.QueryTableHash
WHERE tl.QueryStatementHash IS NOT NULL
  AND tl.DatabaseDurationNano > 5000000000;
GO

PRINT '  ✓ vw_SlowSqlStatements created';
PRINT '';

-- ============================================================
-- View 6: vw_TopMethodsBySession
-- ============================================================
-- Purpose: Aggregated method performance per session
-- Use for: Session-specific method hotspots
-- Note: All times are in MILLISECONDS (pre-converted)
-- ============================================================

PRINT 'Creating vw_TopMethodsBySession...';
GO

CREATE OR ALTER VIEW dbo.vw_TopMethodsBySession AS
SELECT 
    uspt.SessionId,
    uspt.TraceId,
    mn.Name AS MethodName,
    COUNT(*) AS CallCount,
    CAST(SUM(tl.InclusiveDurationNano) / 1000000.0 AS DECIMAL(18,2)) AS TotalInclusiveMs,
    CAST(SUM(tl.ExclusiveDurationNano) / 1000000.0 AS DECIMAL(18,2)) AS TotalExclusiveMs,
    CAST(AVG(tl.InclusiveDurationNano) / 1000000.0 AS DECIMAL(18,4)) AS AvgInclusiveMs,
    SUM(tl.DatabaseCalls) AS TotalDbCalls,
    CAST(SUM(tl.DatabaseDurationNano) / 1000000.0 AS DECIMAL(18,2)) AS TotalDbMs,
    tl.StoredDurationUnit
FROM dbo.vw_UnitAwareTraceLines tl
INNER JOIN dbo.UserSessionProcessThreads uspt 
    ON tl.UserSessionProcessThreadId = uspt.UserSessionProcessThreadId
LEFT JOIN dbo.MethodNames mn ON tl.MethodHash = mn.MethodHash
WHERE mn.Name IS NOT NULL
GROUP BY uspt.SessionId, uspt.TraceId, mn.Name, tl.StoredDurationUnit;
GO

PRINT '  ✓ vw_TopMethodsBySession created';
PRINT '';

-- ============================================================
-- Verification: List all created views
-- ============================================================

PRINT '============================================================';
PRINT 'View Creation Complete!';
PRINT '============================================================';
PRINT '';

SELECT 
    name AS ViewName,
    create_date AS CreatedDate,
    modify_date AS ModifiedDate
FROM sys.views 
WHERE name IN (
    'vw_SessionSummary',
    'vw_SessionMetrics', 
    'vw_TraceLineDetails',
    'vw_NPlusOnePatterns',
    'vw_SlowSqlStatements',
    'vw_TopMethodsBySession'
)
ORDER BY name;

PRINT '';
PRINT '============================================================';
PRINT 'Quick Test Queries:';
PRINT '============================================================';
PRINT '';
PRINT '-- Test SessionSummary';
PRINT 'SELECT TOP 5 * FROM dbo.vw_SessionSummary;';
PRINT '';
PRINT '-- Test SessionMetrics';
PRINT 'SELECT TOP 5 * FROM dbo.vw_SessionMetrics ORDER BY TotalDurationMs DESC;';
PRINT '';
PRINT '-- Test N+1 Patterns';
PRINT 'SELECT TOP 5 * FROM dbo.vw_NPlusOnePatterns ORDER BY DatabaseCalls DESC;';
PRINT '';
PRINT '-- Test Slow SQL';
PRINT 'SELECT TOP 5 * FROM dbo.vw_SlowSqlStatements ORDER BY ExecutionMs DESC;';
PRINT '';
PRINT '============================================================';
GO