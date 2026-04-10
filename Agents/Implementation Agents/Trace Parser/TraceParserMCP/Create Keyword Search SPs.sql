-- ============================================================
-- TraceParser Keyword Search via Stored Procedure
-- ============================================================
-- Purpose: DAB doesn't support OData contains() function,
--          so we use a stored procedure instead
--
-- This stored procedure can be called via DAB's REST API
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

PRINT 'Creating Keyword Search Stored Procedure for DAB...';
PRINT '';

-- ============================================================
-- Stored Procedure: sp_SearchTracesByKeyword
-- ============================================================
-- Parameters:
--   @TraceId    - Filter by specific trace (required)
--   @Keyword    - Keyword to search (required)
--   @SearchIn   - Where to search: 'ALL', 'SQL', 'METHOD', 'MESSAGE', 'TABLE'
--   @MaxResults - Limit results (default 100)
--
-- Usage via DAB REST API:
--   POST /api/SearchTracesByKeyword
--   Body: { "TraceId": 2, "Keyword": "INVENTTABLE", "SearchIn": "ALL", "MaxResults": 100 }
-- ============================================================

CREATE OR ALTER PROCEDURE dbo.sp_SearchTracesByKeyword
    @TraceId INT,
    @Keyword NVARCHAR(500),
    @SearchIn NVARCHAR(20) = 'ALL',
    @MaxResults INT = 100
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Build the search pattern
    DECLARE @Pattern NVARCHAR(502) = '%' + @Keyword + '%';
    
    SELECT TOP (@MaxResults)
        tl.TraceLineId,
        t.TraceId,
        t.TraceName,
        us.SessionId,
        us.SessionName,
        tl.TimeStamp,
        CAST(tl.InclusiveDurationNano / 1000000.0 AS DECIMAL(18,2)) AS InclusiveMs,
        CAST(tl.ExclusiveDurationNano / 1000000.0 AS DECIMAL(18,2)) AS ExclusiveMs,
        CAST(tl.DatabaseDurationNano / 1000000.0 AS DECIMAL(18,2)) AS DatabaseMs,
        mn.Name AS MethodName,
        qs.Statement AS SqlStatement,
        qt.TableNames,
        m.MessageText,
        tl.FileName,
        tl.EventType,
        tl.DatabaseCalls,
        tl.RowFetchCount,
        -- Indicate which field matched
        CASE 
            WHEN @SearchIn = 'SQL' OR (@SearchIn = 'ALL' AND qs.Statement LIKE @Pattern) THEN 
                CASE WHEN qs.Statement LIKE @Pattern THEN 'SQL' ELSE NULL END
            WHEN @SearchIn = 'METHOD' OR (@SearchIn = 'ALL' AND mn.Name LIKE @Pattern) THEN 
                CASE WHEN mn.Name LIKE @Pattern THEN 'METHOD' ELSE NULL END
            WHEN @SearchIn = 'MESSAGE' OR (@SearchIn = 'ALL' AND m.MessageText LIKE @Pattern) THEN 
                CASE WHEN m.MessageText LIKE @Pattern THEN 'MESSAGE' ELSE NULL END
            WHEN @SearchIn = 'TABLE' OR (@SearchIn = 'ALL' AND qt.TableNames LIKE @Pattern) THEN 
                CASE WHEN qt.TableNames LIKE @Pattern THEN 'TABLE' ELSE NULL END
            ELSE 'MULTIPLE'
        END AS MatchedIn
    FROM dbo.TraceLines tl
    INNER JOIN dbo.UserSessionProcessThreads uspt 
        ON tl.UserSessionProcessThreadId = uspt.UserSessionProcessThreadId
    INNER JOIN dbo.UserSessions us 
        ON uspt.SessionId = us.SessionId 
        AND us.TraceId = uspt.TraceId
    INNER JOIN dbo.Traces t 
        ON t.TraceId = uspt.TraceId
    LEFT JOIN dbo.MethodNames mn 
        ON mn.MethodHash = tl.MethodHash
    LEFT JOIN dbo.QueryStatements qs 
        ON tl.QueryStatementHash = qs.QueryStatementHash
    LEFT JOIN dbo.QueryTables qt 
        ON tl.QueryTableHash = qt.QueryTableHash
    LEFT JOIN dbo.Messages m 
        ON m.MessageHash = tl.MessageHash
    WHERE 
        t.TraceId = @TraceId
        AND (
            (@SearchIn = 'ALL' AND (
                qs.Statement LIKE @Pattern
                OR mn.Name LIKE @Pattern
                OR m.MessageText LIKE @Pattern
                OR qt.TableNames LIKE @Pattern
            ))
            OR (@SearchIn = 'SQL' AND qs.Statement LIKE @Pattern)
            OR (@SearchIn = 'METHOD' AND mn.Name LIKE @Pattern)
            OR (@SearchIn = 'MESSAGE' AND m.MessageText LIKE @Pattern)
            OR (@SearchIn = 'TABLE' AND qt.TableNames LIKE @Pattern)
        )
    ORDER BY tl.TimeStamp ASC;
END;
GO

PRINT '  ✓ sp_SearchTracesByKeyword created';
PRINT '';

-- ============================================================
-- Simplified version: Search SQL only
-- ============================================================

CREATE OR ALTER PROCEDURE dbo.sp_SearchSqlStatements
    @TraceId INT,
    @Keyword NVARCHAR(500),
    @MaxResults INT = 100
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @Pattern NVARCHAR(502) = '%' + @Keyword + '%';
    
    SELECT TOP (@MaxResults)
        tl.TraceLineId,
        t.TraceId,
        us.SessionId,
        us.SessionName,
        tl.TimeStamp,
        CAST(tl.DatabaseDurationNano / 1000000.0 AS DECIMAL(18,2)) AS ExecutionMs,
        mn.Name AS MethodName,
        qs.Statement AS SqlStatement,
        qt.TableNames,
        tl.RowFetchCount
    FROM dbo.TraceLines tl
    INNER JOIN dbo.UserSessionProcessThreads uspt 
        ON tl.UserSessionProcessThreadId = uspt.UserSessionProcessThreadId
    INNER JOIN dbo.UserSessions us 
        ON uspt.SessionId = us.SessionId 
        AND us.TraceId = uspt.TraceId
    INNER JOIN dbo.Traces t 
        ON t.TraceId = uspt.TraceId
    LEFT JOIN dbo.MethodNames mn 
        ON mn.MethodHash = tl.MethodHash
    LEFT JOIN dbo.QueryStatements qs 
        ON tl.QueryStatementHash = qs.QueryStatementHash
    LEFT JOIN dbo.QueryTables qt 
        ON tl.QueryTableHash = qt.QueryTableHash
    WHERE 
        t.TraceId = @TraceId
        AND qs.Statement LIKE @Pattern
    ORDER BY tl.TimeStamp ASC;
END;
GO

PRINT '  ✓ sp_SearchSqlStatements created';
PRINT '';

-- ============================================================
-- Simplified version: Search Methods only
-- ============================================================

CREATE OR ALTER PROCEDURE dbo.sp_SearchMethods
    @TraceId INT,
    @Keyword NVARCHAR(500),
    @MaxResults INT = 100
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @Pattern NVARCHAR(502) = '%' + @Keyword + '%';
    
    SELECT TOP (@MaxResults)
        tl.TraceLineId,
        t.TraceId,
        us.SessionId,
        us.SessionName,
        tl.TimeStamp,
        CAST(tl.InclusiveDurationNano / 1000000.0 AS DECIMAL(18,2)) AS InclusiveMs,
        CAST(tl.ExclusiveDurationNano / 1000000.0 AS DECIMAL(18,2)) AS ExclusiveMs,
        mn.Name AS MethodName,
        tl.DatabaseCalls,
        CAST(tl.DatabaseDurationNano / 1000000.0 AS DECIMAL(18,2)) AS DatabaseMs
    FROM dbo.TraceLines tl
    INNER JOIN dbo.UserSessionProcessThreads uspt 
        ON tl.UserSessionProcessThreadId = uspt.UserSessionProcessThreadId
    INNER JOIN dbo.UserSessions us 
        ON uspt.SessionId = us.SessionId 
        AND us.TraceId = uspt.TraceId
    INNER JOIN dbo.Traces t 
        ON t.TraceId = uspt.TraceId
    LEFT JOIN dbo.MethodNames mn 
        ON mn.MethodHash = tl.MethodHash
    WHERE 
        t.TraceId = @TraceId
        AND mn.Name LIKE @Pattern
    ORDER BY tl.TimeStamp ASC;
END;
GO

PRINT '  ✓ sp_SearchMethods created';
PRINT '';

-- ============================================================
-- Simplified version: Search Messages only
-- ============================================================

CREATE OR ALTER PROCEDURE dbo.sp_SearchMessages
    @TraceId INT,
    @Keyword NVARCHAR(500),
    @MaxResults INT = 100
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @Pattern NVARCHAR(502) = '%' + @Keyword + '%';
    
    SELECT TOP (@MaxResults)
        tl.TraceLineId,
        t.TraceId,
        us.SessionId,
        us.SessionName,
        tl.TimeStamp,
        mn.Name AS MethodName,
        m.MessageText,
        tl.EventType,
        tl.EventName
    FROM dbo.TraceLines tl
    INNER JOIN dbo.UserSessionProcessThreads uspt 
        ON tl.UserSessionProcessThreadId = uspt.UserSessionProcessThreadId
    INNER JOIN dbo.UserSessions us 
        ON uspt.SessionId = us.SessionId 
        AND us.TraceId = uspt.TraceId
    INNER JOIN dbo.Traces t 
        ON t.TraceId = uspt.TraceId
    LEFT JOIN dbo.MethodNames mn 
        ON mn.MethodHash = tl.MethodHash
    LEFT JOIN dbo.Messages m 
        ON m.MessageHash = tl.MessageHash
    WHERE 
        t.TraceId = @TraceId
        AND m.MessageText LIKE @Pattern
    ORDER BY tl.TimeStamp ASC;
END;
GO

PRINT '  ✓ sp_SearchMessages created';
PRINT '';

-- ============================================================
-- Verification
-- ============================================================

PRINT '============================================================';
PRINT 'Stored Procedures Created Successfully!';
PRINT '============================================================';
PRINT '';

SELECT 
    name AS ProcedureName,
    type_desc AS ObjectType,
    create_date AS CreatedDate
FROM sys.objects 
WHERE type = 'P' 
AND name IN ('sp_SearchTracesByKeyword', 'sp_SearchSqlStatements', 'sp_SearchMethods', 'sp_SearchMessages')
ORDER BY name;

PRINT '';
PRINT '============================================================';
PRINT 'TEST EXAMPLES (run in SSMS)';
PRINT '============================================================';
PRINT '';
PRINT '-- Search all fields for INVENTTABLE in trace 2';
PRINT 'EXEC dbo.sp_SearchTracesByKeyword @TraceId = 2, @Keyword = ''INVENTTABLE'';';
PRINT '';
PRINT '-- Search only SQL statements';
PRINT 'EXEC dbo.sp_SearchSqlStatements @TraceId = 2, @Keyword = ''INVENTTABLE'';';
PRINT '';
PRINT '-- Search only method names';
PRINT 'EXEC dbo.sp_SearchMethods @TraceId = 2, @Keyword = ''find'';';
PRINT '';
PRINT '-- Search only messages for errors';
PRINT 'EXEC dbo.sp_SearchMessages @TraceId = 2, @Keyword = ''error'';';
PRINT '';
GO