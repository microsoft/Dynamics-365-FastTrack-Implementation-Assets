-- Customer-free fixture of the importer contracts, including the composite session FK
-- and physical aggregates. No live connection or production data is required.
CREATE TABLE dbo.Traces(TraceId int IDENTITY PRIMARY KEY,TraceName nvarchar(500) NOT NULL,
 TraceFile nvarchar(max) NOT NULL,TimeStampBegin datetime NOT NULL,TimeStampEnd datetime NOT NULL,
 TraceParserVersion nvarchar(50));
CREATE TABLE dbo.Users(UserId int IDENTITY PRIMARY KEY,UserName nvarchar(200) NOT NULL UNIQUE);
CREATE TABLE dbo.Customers(CustomerId int IDENTITY PRIMARY KEY,CustomerName nvarchar(200) NOT NULL UNIQUE);
CREATE TABLE dbo.UserSessions(SessionId int NOT NULL,TraceId int NOT NULL REFERENCES dbo.Traces(TraceId),
 UserId int NOT NULL REFERENCES dbo.Users(UserId),SessionName nvarchar(500) NOT NULL,
 CustomerCustomerId int NOT NULL REFERENCES dbo.Customers(CustomerId),PRIMARY KEY(SessionId,TraceId));
CREATE TABLE dbo.UserSessionProcessThreads(UserSessionProcessThreadId int IDENTITY PRIMARY KEY,
 RequestId uniqueidentifier NOT NULL,ActivityId uniqueidentifier NOT NULL,RelatedActivityId uniqueidentifier NOT NULL,
 SessionId int NOT NULL,TraceId int NOT NULL,
 FOREIGN KEY(SessionId,TraceId) REFERENCES dbo.UserSessions(SessionId,TraceId));
CREATE INDEX IX_USPT_TraceId ON dbo.UserSessionProcessThreads(TraceId) INCLUDE(SessionId);
CREATE TABLE dbo.MethodNames(MethodHash bigint PRIMARY KEY,Name nvarchar(500),TargetType int);
CREATE TABLE dbo.QueryStatements(QueryStatementHash bigint PRIMARY KEY,Statement nvarchar(4000));
CREATE TABLE dbo.QueryTables(QueryTableHash bigint PRIMARY KEY,TableNames nvarchar(1000));
CREATE TABLE dbo.Messages(MessageHash bigint PRIMARY KEY,MessageText nvarchar(4000));
CREATE TABLE dbo.TraceLineIDControls(NextTraceLineId bigint NOT NULL);
INSERT dbo.TraceLineIDControls VALUES(1);
CREATE TABLE dbo.TraceLines(
 TraceLineId bigint IDENTITY NOT NULL PRIMARY KEY NONCLUSTERED,
 UserSessionProcessThreadId int NOT NULL REFERENCES dbo.UserSessionProcessThreads(UserSessionProcessThreadId),
 CallTypeId int NOT NULL,Sequence int NOT NULL,SequenceEnd int NOT NULL,[TimeStamp] bigint NOT NULL,
 TimeStampEnd bigint NOT NULL,InclusiveDurationNano bigint NOT NULL,ExclusiveDurationNano bigint NOT NULL,
 DatabaseDurationNano bigint NOT NULL,ParentSequence int NULL,InclusiveRpc int NOT NULL,DatabaseCalls int NOT NULL,
 QueryStatementHash bigint NULL REFERENCES dbo.QueryStatements(QueryStatementHash),
 QueryTableHash bigint NULL REFERENCES dbo.QueryTables(QueryTableHash),
 PrepDurationNano bigint NOT NULL,BindDurationNano bigint NOT NULL,RowFetchDurationNano bigint NOT NULL,
 RowFetchCount int NOT NULL,MethodHash bigint NULL REFERENCES dbo.MethodNames(MethodHash),
 MessageHash bigint NULL REFERENCES dbo.Messages(MessageHash),CallstackHash bigint NULL,HasChildren bit NOT NULL,
 IsComplete bit NULL,TransactionParentSequence int NULL,IsRecursive bit NULL,FileName nvarchar(max) NOT NULL,
 RoleRoleId int NULL,RoleInstanceRoleInstanceId int NULL,EventLevel smallint NULL,EventId int NOT NULL,
 AzureTenantAzureTenantId int NULL,EventType smallint NOT NULL,PropertiesXml nvarchar(max) NULL,
 LineNumber int NOT NULL,EventName nvarchar(max) NULL,
 CONSTRAINT UQ_SessionUser UNIQUE CLUSTERED(UserSessionProcessThreadId,Sequence));
CREATE INDEX IX_Usp_ParentSequence ON dbo.TraceLines(UserSessionProcessThreadId,ParentSequence);
CREATE INDEX IX_USP_QUERY ON dbo.TraceLines(UserSessionProcessThreadId,QueryStatementHash) INCLUDE(InclusiveDurationNano);
CREATE INDEX IX_USP_METHOD ON dbo.TraceLines(UserSessionProcessThreadId,MethodHash) INCLUDE(InclusiveDurationNano,ExclusiveDurationNano,InclusiveRpc,DatabaseCalls);
CREATE INDEX IX_TL_USPT_Aggregation ON dbo.TraceLines(UserSessionProcessThreadId)
 INCLUDE(ParentSequence,InclusiveDurationNano,ExclusiveDurationNano,DatabaseDurationNano,DatabaseCalls,InclusiveRpc,RowFetchCount,MethodHash);
-- UNION prevents SELECT INTO from propagating the TraceLineId identity property.
SELECT TOP(0) * INTO dbo.StageTraceLines FROM dbo.TraceLines
UNION ALL SELECT TOP(0) * FROM dbo.TraceLines;
ALTER TABLE dbo.StageTraceLines ADD PRIMARY KEY(TraceLineId);
CREATE TABLE dbo.QueryBindParameters(QueryBindParameterId int IDENTITY PRIMARY KEY,TraceLineId bigint NOT NULL
 REFERENCES dbo.TraceLines(TraceLineId),ParameterIndex int NULL,BindValue nvarchar(max));
CREATE TABLE dbo.XppParameters(Id int IDENTITY PRIMARY KEY,TraceLineId bigint REFERENCES dbo.TraceLines(TraceLineId));
CREATE TABLE dbo.TopMethods(Id int PRIMARY KEY,BeginUspId int REFERENCES dbo.UserSessionProcessThreads(UserSessionProcessThreadId),
 EndUspId int REFERENCES dbo.UserSessionProcessThreads(UserSessionProcessThreadId));
CREATE TABLE dbo.MethodAotLayers(Id int PRIMARY KEY,TraceId int REFERENCES dbo.Traces(TraceId));
CREATE TABLE dbo.TraceInformations(InfoId int PRIMARY KEY,TraceId int REFERENCES dbo.Traces(TraceId));
CREATE TABLE dbo.SessionMetrics(TraceId int NOT NULL,SessionId int NOT NULL,
 SessionName nvarchar(500),UserName nvarchar(200),TraceName nvarchar(500),TotalTraceLines int NOT NULL,
 RootCalls int NOT NULL,TotalDurationMs decimal(18,2) NOT NULL,TotalDatabaseMs decimal(18,2) NOT NULL,
 TotalDatabaseCalls int NOT NULL,TotalRpcCalls bigint NOT NULL,TotalRowsFetched int NOT NULL,
 ComputedAtUtc datetime2 NOT NULL DEFAULT SYSUTCDATETIME(),PRIMARY KEY(TraceId,SessionId));
CREATE TABLE dbo.TopMethodsBySession(Id int IDENTITY PRIMARY KEY,SessionId int NOT NULL,TraceId int NOT NULL,
 MethodName nvarchar(500),CallCount int NOT NULL,TotalInclusiveMs decimal(18,2) NOT NULL,
 TotalExclusiveMs decimal(18,2) NOT NULL,AvgInclusiveMs decimal(18,4) NOT NULL,TotalDbCalls int NOT NULL,
 TotalDbMs decimal(18,2) NOT NULL,ComputedAtUtc datetime2 NOT NULL DEFAULT SYSUTCDATETIME());
GO
CREATE PROCEDURE dbo.sp_PopulateSessionAggregations @TraceId int
AS
BEGIN
 SET NOCOUNT ON;
 DELETE dbo.SessionMetrics WHERE TraceId=@TraceId;
 DELETE dbo.TopMethodsBySession WHERE TraceId=@TraceId;
 INSERT dbo.SessionMetrics(SessionId,TraceId,SessionName,UserName,TraceName,TotalTraceLines,RootCalls,
 TotalDurationMs,TotalDatabaseMs,TotalDatabaseCalls,TotalRpcCalls,TotalRowsFetched)
 SELECT us.SessionId,us.TraceId,us.SessionName,u.UserName,t.TraceName,COUNT(tl.TraceLineId),
 ISNULL(SUM(CASE WHEN tl.ParentSequence IS NULL THEN 1 ELSE 0 END),0),
 ISNULL(CAST(SUM(CASE WHEN tl.ParentSequence IS NULL THEN tl.InclusiveDurationNano ELSE 0 END)/1000000.0 AS decimal(18,2)),0),
 ISNULL(CAST(SUM(tl.DatabaseDurationNano)/1000000.0 AS decimal(18,2)),0),
 ISNULL(SUM(tl.DatabaseCalls),0),ISNULL(SUM(tl.InclusiveRpc),0),ISNULL(SUM(tl.RowFetchCount),0)
 FROM dbo.UserSessions us JOIN dbo.Users u ON u.UserId=us.UserId JOIN dbo.Traces t ON t.TraceId=us.TraceId
 JOIN dbo.UserSessionProcessThreads uspt ON uspt.SessionId=us.SessionId
 LEFT JOIN dbo.TraceLines tl ON tl.UserSessionProcessThreadId=uspt.UserSessionProcessThreadId
 WHERE us.TraceId=@TraceId GROUP BY us.SessionId,us.TraceId,us.SessionName,u.UserName,t.TraceName;
 INSERT dbo.TopMethodsBySession(SessionId,TraceId,MethodName,CallCount,TotalInclusiveMs,TotalExclusiveMs,
 AvgInclusiveMs,TotalDbCalls,TotalDbMs)
 SELECT uspt.SessionId,uspt.TraceId,mn.Name,COUNT(*),
 CAST(SUM(tl.InclusiveDurationNano)/1000000.0 AS decimal(18,2)),
 CAST(SUM(tl.ExclusiveDurationNano)/1000000.0 AS decimal(18,2)),
 CAST(AVG(tl.InclusiveDurationNano)/1000000.0 AS decimal(18,4)),SUM(tl.DatabaseCalls),
 CAST(SUM(tl.DatabaseDurationNano)/1000000.0 AS decimal(18,2))
 FROM dbo.TraceLines tl JOIN dbo.UserSessionProcessThreads uspt ON uspt.UserSessionProcessThreadId=tl.UserSessionProcessThreadId
 LEFT JOIN dbo.MethodNames mn ON mn.MethodHash=tl.MethodHash
 WHERE uspt.TraceId=@TraceId AND mn.Name IS NOT NULL GROUP BY uspt.SessionId,uspt.TraceId,mn.Name;
END;
