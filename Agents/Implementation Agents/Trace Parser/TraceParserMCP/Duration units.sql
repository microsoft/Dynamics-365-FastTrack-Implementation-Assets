-- Read-only provenance. No inference from filenames, observed timings or native versions.
CREATE OR ALTER VIEW dbo.vw_TraceDurationUnits AS
SELECT TraceId, TraceParserVersion,
    CAST(CASE (TraceParserVersion+N'|') COLLATE Latin1_General_100_BIN2
        WHEN 'safe-import-v1|' THEN '100ns ticks'
        WHEN 'safe-import-v2|' THEN 'nanoseconds'
        WHEN 'ps-import-v2|' THEN 'nanoseconds'
        ELSE 'unknown' END AS varchar(16)) AS StoredDurationUnit,
    CASE (TraceParserVersion+N'|') COLLATE Latin1_General_100_BIN2
        WHEN 'safe-import-v1|' THEN 100
        WHEN 'safe-import-v2|' THEN 1
        WHEN 'ps-import-v2|' THEN 1 END AS NanosecondsPerStoredUnit
FROM dbo.Traces;
GO
-- All six *Nano columns here are normalized nanoseconds, NULL when unclassified.
-- Original values remain exposed as Stored*; negative sentinel codes stay negative.
-- FILETIME, counts, sequences and identities are NEVER converted.
CREATE OR ALTER VIEW dbo.vw_UnitAwareTraceLines AS
SELECT tl.TraceLineId, tl.UserSessionProcessThreadId, tl.CallTypeId,
    tl.Sequence, tl.SequenceEnd, tl.TimeStamp, tl.TimeStampEnd,
    CASE WHEN u.NanosecondsPerStoredUnit IS NULL THEN NULL WHEN tl.InclusiveDurationNano<0 THEN tl.InclusiveDurationNano
        ELSE CONVERT(decimal(28,0),tl.InclusiveDurationNano)*u.NanosecondsPerStoredUnit END AS InclusiveDurationNano,
    CASE WHEN u.NanosecondsPerStoredUnit IS NULL THEN NULL WHEN tl.ExclusiveDurationNano<0 THEN tl.ExclusiveDurationNano
        ELSE CONVERT(decimal(28,0),tl.ExclusiveDurationNano)*u.NanosecondsPerStoredUnit END AS ExclusiveDurationNano,
    CASE WHEN u.NanosecondsPerStoredUnit IS NULL THEN NULL WHEN tl.DatabaseDurationNano<0 THEN tl.DatabaseDurationNano
        ELSE CONVERT(decimal(28,0),tl.DatabaseDurationNano)*u.NanosecondsPerStoredUnit END AS DatabaseDurationNano,
    tl.ParentSequence, tl.InclusiveRpc, tl.DatabaseCalls, tl.QueryStatementHash, tl.QueryTableHash,
    CASE WHEN u.NanosecondsPerStoredUnit IS NULL THEN NULL WHEN tl.PrepDurationNano<0 THEN tl.PrepDurationNano
        ELSE CONVERT(decimal(28,0),tl.PrepDurationNano)*u.NanosecondsPerStoredUnit END AS PrepDurationNano,
    CASE WHEN u.NanosecondsPerStoredUnit IS NULL THEN NULL WHEN tl.BindDurationNano<0 THEN tl.BindDurationNano
        ELSE CONVERT(decimal(28,0),tl.BindDurationNano)*u.NanosecondsPerStoredUnit END AS BindDurationNano,
    CASE WHEN u.NanosecondsPerStoredUnit IS NULL THEN NULL WHEN tl.RowFetchDurationNano<0 THEN tl.RowFetchDurationNano
        ELSE CONVERT(decimal(28,0),tl.RowFetchDurationNano)*u.NanosecondsPerStoredUnit END AS RowFetchDurationNano,
    tl.RowFetchCount, tl.MethodHash, tl.MessageHash, tl.CallstackHash, tl.HasChildren,
    tl.IsComplete, tl.TransactionParentSequence, tl.IsRecursive, tl.FileName,
    tl.RoleRoleId, tl.RoleInstanceRoleInstanceId, tl.EventLevel, tl.EventId,
    tl.AzureTenantAzureTenantId, tl.EventType, tl.PropertiesXml, tl.LineNumber, tl.EventName,
    tl.InclusiveDurationNano AS StoredInclusiveDuration,
    tl.ExclusiveDurationNano AS StoredExclusiveDuration,
    tl.DatabaseDurationNano AS StoredDatabaseDuration,
    tl.PrepDurationNano AS StoredPrepDuration,
    tl.BindDurationNano AS StoredBindDuration,
    tl.RowFetchDurationNano AS StoredRowFetchDuration,
    u.StoredDurationUnit, u.TraceParserVersion, u.TraceId
FROM dbo.TraceLines tl
JOIN dbo.UserSessionProcessThreads uspt ON uspt.UserSessionProcessThreadId=tl.UserSessionProcessThreadId
JOIN dbo.vw_TraceDurationUnits u ON u.TraceId=uspt.TraceId;
GO
-- Only this versioned PS importer creates TopMethods. The Function does not.
-- Both interval endpoints must belong to that same proven trace.
CREATE OR ALTER VIEW dbo.vw_TopMethodsWithUnits AS
SELECT tm.Id,tm.BeginUspId,tm.EndUspId,tm.Name,tm.Count,tm.RpcTotal,tm.DatabaseCallTotal,tm.Type,
    CASE WHEN (t.TraceParserVersion+N'|') COLLATE Latin1_General_100_BIN2='ps-import-v2|' THEN tm.InclusiveTotal END AS InclusiveTotal,
    CASE WHEN (t.TraceParserVersion+N'|') COLLATE Latin1_General_100_BIN2='ps-import-v2|' THEN tm.ExclusiveTotal END AS ExclusiveTotal,
    tm.InclusiveTotal AS StoredInclusiveTotal,tm.ExclusiveTotal AS StoredExclusiveTotal,
    CAST(CASE WHEN (t.TraceParserVersion+N'|') COLLATE Latin1_General_100_BIN2='ps-import-v2|'
        THEN 'nanoseconds' ELSE 'unknown' END AS varchar(16)) AS StoredDurationUnit
FROM dbo.TopMethods tm
LEFT JOIN dbo.UserSessionProcessThreads b ON b.UserSessionProcessThreadId=tm.BeginUspId
LEFT JOIN dbo.UserSessionProcessThreads e ON e.UserSessionProcessThreadId=tm.EndUspId AND e.TraceId=b.TraceId
LEFT JOIN dbo.Traces t ON t.TraceId=e.TraceId;
GO
