# Trace Parser Agent - Setup Guide

# For Testing Environment Configuration

---

# Overview

This guide helps you set up the **D365 Trace Parser Analyzer** agent on your local machine. Since you already have the AxTrace database installed, this guide focuses on:

1. Installing Data API Builder (DAB)
2. Running the required SQL scripts
3. Configuring the MCP server
4. Setting up VS Code port forwarding (so Copilot Studio can reach your local server)
5. Importing and configuring the Copilot Studio agent

**Estimated Setup Time:** 30-45 minutes

---

# Prerequisites Checklist

Before starting, verify you have:

| Requirement | How to Check | Status |
| --- | --- | --- |
| AxTrace DB installed | Open SSMS, connect to LocalDB | ☐ |
| .NET 9.0 or higher | Run `dotnet --version` in PowerShell | ☐ |
| SQL Server LocalDB running | Run `sqllocaldb info MSSQLLocalDB` | ☐ |
| Copilot Studio access | Login to make.powerva.microsoft.com | ☐ |
| Internet connection | For Microsoft Learn MCP | ☐ |

## Check .NET Version

```powershell
dotnet --version

```

**Required:** 9.0.0 or higher

If not installed, download from: https://dotnet.microsoft.com/download/dotnet/9.0

## Check LocalDB

```powershell
sqllocaldb info MSSQLLocalDB

```

**Expected Output:**

```
Name:               MSSQLLocalDB
Version:            15.0.x.x or higher
State:              Running

```

If not running:

```powershell
sqllocaldb start MSSQLLocalDB

```

## Verify AxTrace Database

Open **SQL Server Management Studio (SSMS)** and connect to:

```
Server: (LocalDB)\MSSQLLocalDB
Authentication: Windows Authentication

```

Verify the `AxTrace` database exists and contains tables like:

- Traces
- UserSessions
- TraceLines
- MethodNames
- QueryStatements

---

# Step 1: Create Working Directory

Create a folder for the DAB configuration:

```powershell
# Create directory
mkdir C:\TraceParserMCP

# Navigate to it
cd C:\TraceParserMCP

```

---

# Step 2: Install Data API Builder CLI

```powershell
# Create tool manifest (required for local tool installation)
dotnet new tool-manifest

# Install DAB CLI with prerelease flag (required for MCP support)
dotnet tool install microsoft.dataapibuilder --prerelease

# Restore tools
dotnet tool restore

# Verify installation
dotnet tool list

```

**Expected Output:**

```
Package Id                       Version      Commands
------------------------------------------------------------
microsoft.dataapibuilder         1.x.x-rc     dab

```

**Verify DAB works:**

```powershell
dotnet dab --version

```

---

# Step 3: Run SQL Scripts

You need to run **2 SQL scripts** to create the views and stored procedures the agent uses.

**Option A: Use the standalone SQL files (Recommended)**

The project includes ready-to-run SQL script files. Open **SSMS**, connect to your database server, and execute them in order:

1. `Create Views.sql` - Creates the 6 analytical views
2. `Create Keyword Search SPs.sql` - Creates the 4 keyword search stored procedures

Skip to [Step 4](#step-4-create-dab-configuration-files) after running both scripts.

**Option B: Copy and run the scripts below**

Alternatively, you can copy and run the SQL directly from this guide.

## Script 1: Create Analysis Views

Open **SSMS**, connect to `(LocalDB)\MSSQLLocalDB`, and run this script:

```sql
-- =============================================
-- TraceParser Analysis Views
-- Run this in AxTrace database
-- =============================================

USE AxTrace;
GO

-- View 1: Session Summary
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

-- View 2: Session Metrics
CREATE OR ALTER VIEW dbo.vw_SessionMetrics AS
SELECT
    us.SessionId,
    us.SessionName,
    u.UserName,
    t.TraceName,
    t.TraceId,
    COUNT(tl.TraceLineId) AS TotalTraceLines,
    SUM(CASE WHEN tl.ParentSequence IS NULL THEN 1 ELSE 0 END) AS RootCalls,
    CAST(SUM(CASE WHEN tl.ParentSequence IS NULL
         THEN tl.InclusiveDurationNano ELSE 0 END) / 1000000.0 AS DECIMAL(18,2)) AS TotalDurationMs,
    CAST(SUM(tl.DatabaseDurationNano) / 1000000.0 AS DECIMAL(18,2)) AS TotalDatabaseMs,
    SUM(tl.DatabaseCalls) AS TotalDatabaseCalls,
    SUM(tl.InclusiveRpc) AS TotalRpcCalls,
    SUM(tl.RowFetchCount) AS TotalRowsFetched
FROM dbo.UserSessions us
INNER JOIN dbo.Users u ON us.UserId = u.UserId
INNER JOIN dbo.Traces t ON us.TraceId = t.TraceId
INNER JOIN dbo.UserSessionProcessThreads uspt ON us.SessionId = uspt.SessionId
LEFT JOIN dbo.TraceLines tl ON uspt.UserSessionProcessThreadId = tl.UserSessionProcessThreadId
GROUP BY us.SessionId, us.SessionName, u.UserName, t.TraceName, t.TraceId;
GO

-- View 3: Trace Line Details
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
        ELSE 0
    END AS AvgDbCallMs,
    tl.RowFetchCount,
    tl.QueryStatementHash,
    qs.Statement AS SqlStatement,
    tl.QueryTableHash,
    qt.TableNames,
    tl.HasChildren,
    tl.EventType,
    tl.EventName
FROM dbo.TraceLines tl
INNER JOIN dbo.UserSessionProcessThreads uspt
    ON tl.UserSessionProcessThreadId = uspt.UserSessionProcessThreadId
LEFT JOIN dbo.MethodNames mn ON tl.MethodHash = mn.MethodHash
LEFT JOIN dbo.QueryStatements qs ON tl.QueryStatementHash = qs.QueryStatementHash
LEFT JOIN dbo.QueryTables qt ON tl.QueryTableHash = qt.QueryTableHash;
GO

-- View 4: N+1 Patterns Detection
CREATE OR ALTER VIEW dbo.vw_NPlusOnePatterns AS
SELECT
    tl.TraceLineId,
    uspt.SessionId,
    uspt.TraceId,
    mn.Name AS MethodName,
    tl.DatabaseCalls,
    CAST(tl.DatabaseDurationNano / 1000000.0 AS DECIMAL(18,2)) AS DatabaseMs,
    CAST(tl.DatabaseDurationNano / 1000000.0 / NULLIF(tl.DatabaseCalls, 0) AS DECIMAL(18,4)) AS AvgMsPerCall,
    CAST(tl.InclusiveDurationNano / 1000000.0 AS DECIMAL(18,2)) AS InclusiveMs,
    'N+1 PATTERN: High DB calls with low avg time' AS PatternDescription
FROM dbo.TraceLines tl
INNER JOIN dbo.UserSessionProcessThreads uspt
    ON tl.UserSessionProcessThreadId = uspt.UserSessionProcessThreadId
LEFT JOIN dbo.MethodNames mn ON tl.MethodHash = mn.MethodHash
WHERE tl.DatabaseCalls > 100
  AND (tl.DatabaseDurationNano / 1000000.0 / NULLIF(tl.DatabaseCalls, 0)) < 5;
GO

-- View 5: Slow SQL Statements
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
    'SLOW SQL: Execution > 5 seconds' AS PatternDescription
FROM dbo.TraceLines tl
INNER JOIN dbo.UserSessionProcessThreads uspt
    ON tl.UserSessionProcessThreadId = uspt.UserSessionProcessThreadId
LEFT JOIN dbo.MethodNames mn ON tl.MethodHash = mn.MethodHash
LEFT JOIN dbo.QueryStatements qs ON tl.QueryStatementHash = qs.QueryStatementHash
LEFT JOIN dbo.QueryTables qt ON tl.QueryTableHash = qt.QueryTableHash
WHERE tl.QueryStatementHash IS NOT NULL
  AND tl.DatabaseDurationNano > 5000000000;
GO

-- View 6: Top Methods by Session
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
    CAST(SUM(tl.DatabaseDurationNano) / 1000000.0 AS DECIMAL(18,2)) AS TotalDbMs
FROM dbo.TraceLines tl
INNER JOIN dbo.UserSessionProcessThreads uspt
    ON tl.UserSessionProcessThreadId = uspt.UserSessionProcessThreadId
LEFT JOIN dbo.MethodNames mn ON tl.MethodHash = mn.MethodHash
WHERE mn.Name IS NOT NULL
GROUP BY uspt.SessionId, uspt.TraceId, mn.Name;
GO

PRINT 'All 6 views created successfully!';

```

**Verify views created:**

```sql
SELECT TABLE_NAME FROM INFORMATION_SCHEMA.VIEWS WHERE TABLE_SCHEMA = 'dbo';

```

---

## Script 2: Create Keyword Search Stored Procedures

Run this script in SSMS:

```sql
-- =============================================
-- TraceParser Keyword Search Stored Procedures
-- Run this in AxTrace database
-- =============================================

USE AxTrace;
GO

-- Procedure 1: Search All Fields
CREATE OR ALTER PROCEDURE dbo.sp_SearchTracesByKeyword
    @TraceId INT,
    @Keyword NVARCHAR(500),
    @SearchIn NVARCHAR(20) = 'ALL',
    @MaxResults INT = 100
AS
BEGIN
    SET NOCOUNT ON;

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
        CASE
            WHEN qs.Statement LIKE @Pattern THEN 'SQL'
            WHEN mn.Name LIKE @Pattern THEN 'METHOD'
            WHEN m.MessageText LIKE @Pattern THEN 'MESSAGE'
            WHEN qt.TableNames LIKE @Pattern THEN 'TABLE'
            ELSE 'MULTIPLE'
        END AS MatchedIn
    FROM dbo.TraceLines tl
    INNER JOIN dbo.UserSessionProcessThreads uspt
        ON tl.UserSessionProcessThreadId = uspt.UserSessionProcessThreadId
    INNER JOIN dbo.UserSessions us
        ON uspt.SessionId = us.SessionId AND us.TraceId = uspt.TraceId
    INNER JOIN dbo.Traces t
        ON t.TraceId = uspt.TraceId
    LEFT JOIN dbo.MethodNames mn ON mn.MethodHash = tl.MethodHash
    LEFT JOIN dbo.QueryStatements qs ON tl.QueryStatementHash = qs.QueryStatementHash
    LEFT JOIN dbo.QueryTables qt ON tl.QueryTableHash = qt.QueryTableHash
    LEFT JOIN dbo.Messages m ON m.MessageHash = tl.MessageHash
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

-- Procedure 2: Search SQL Statements
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
        ON uspt.SessionId = us.SessionId AND us.TraceId = uspt.TraceId
    INNER JOIN dbo.Traces t ON t.TraceId = uspt.TraceId
    LEFT JOIN dbo.MethodNames mn ON mn.MethodHash = tl.MethodHash
    LEFT JOIN dbo.QueryStatements qs ON tl.QueryStatementHash = qs.QueryStatementHash
    LEFT JOIN dbo.QueryTables qt ON tl.QueryTableHash = qt.QueryTableHash
    WHERE
        t.TraceId = @TraceId
        AND qs.Statement LIKE @Pattern
    ORDER BY tl.TimeStamp ASC;
END;
GO

-- Procedure 3: Search Methods
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
        ON uspt.SessionId = us.SessionId AND us.TraceId = uspt.TraceId
    INNER JOIN dbo.Traces t ON t.TraceId = uspt.TraceId
    LEFT JOIN dbo.MethodNames mn ON mn.MethodHash = tl.MethodHash
    WHERE
        t.TraceId = @TraceId
        AND mn.Name LIKE @Pattern
    ORDER BY tl.TimeStamp ASC;
END;
GO

-- Procedure 4: Search Messages
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
        ON uspt.SessionId = us.SessionId AND us.TraceId = uspt.TraceId
    INNER JOIN dbo.Traces t ON t.TraceId = uspt.TraceId
    LEFT JOIN dbo.MethodNames mn ON mn.MethodHash = tl.MethodHash
    LEFT JOIN dbo.Messages m ON m.MessageHash = tl.MessageHash
    WHERE
        t.TraceId = @TraceId
        AND m.MessageText LIKE @Pattern
    ORDER BY tl.TimeStamp ASC;
END;
GO

PRINT 'All 4 stored procedures created successfully!';

```

**Verify stored procedures created:**

```sql
SELECT ROUTINE_NAME FROM INFORMATION_SCHEMA.ROUTINES WHERE ROUTINE_TYPE = 'PROCEDURE' AND ROUTINE_NAME LIKE 'sp_Search%';

```

---

# Step 4: Create DAB Configuration Files

## 4.1 Create Environment File

Create a file named `.env` in `C:\TraceParserMCP`:

```powershell
cd C:\TraceParserMCP

# Create .env file
@"
MSSQL_CONNECTION_STRING=Server=(LocalDB)\MSSQLLocalDB;Database=AxTrace;Trusted_Connection=True;TrustServerCertificate=True;Encrypt=Optional
"@ | Out-File -FilePath ".env" -Encoding UTF8

```

Or manually create `.env` with this content:

```
MSSQL_CONNECTION_STRING=Server=(LocalDB)\MSSQLLocalDB;Database=AxTrace;Trusted_Connection=True;TrustServerCertificate=True;Encrypt=Optional

```

## 4.2 Create DAB Configuration File

Create a file named `dab-config.json` in `C:\TraceParserMCP`:

```json
{
  "$schema": "https://github.com/Azure/data-api-builder/releases/latest/download/dab.draft.schema.json",
  "data-source": {
    "database-type": "mssql",
    "connection-string": "@env('MSSQL_CONNECTION_STRING')"
  },
  "runtime": {
    "rest": {
      "enabled": true,
      "path": "/api"
    },
    "graphql": {
      "enabled": true,
      "path": "/graphql"
    },
    "host": {
      "mode": "Development",
      "cors": {
        "origins": ["*"],
        "allow-credentials": false
      }
    },
    "mcp": {
      "enabled": true,
      "path": "/mcp",
      "dml-tools": {
        "describe-entities": true,
        "create-record": false,
        "read-records": true,
        "update-record": false,
        "delete-record": false,
        "execute-entity": true
      }
    }
  },
  "entities": {
    "Traces": {
      "source": "dbo.Traces",
      "permissions": [{ "role": "anonymous", "actions": ["read"] }]
    },
    "UserSessions": {
      "source": "dbo.UserSessions",
      "permissions": [{ "role": "anonymous", "actions": ["read"] }]
    },
    "Users": {
      "source": "dbo.Users",
      "permissions": [{ "role": "anonymous", "actions": ["read"] }]
    },
    "UserSessionProcessThreads": {
      "source": "dbo.UserSessionProcessThreads",
      "permissions": [{ "role": "anonymous", "actions": ["read"] }]
    },
    "TraceLines": {
      "source": "dbo.TraceLines",
      "permissions": [{ "role": "anonymous", "actions": ["read"] }]
    },
    "MethodNames": {
      "source": "dbo.MethodNames",
      "permissions": [{ "role": "anonymous", "actions": ["read"] }]
    },
    "QueryStatements": {
      "source": "dbo.QueryStatements",
      "permissions": [{ "role": "anonymous", "actions": ["read"] }]
    },
    "QueryTables": {
      "source": "dbo.QueryTables",
      "permissions": [{ "role": "anonymous", "actions": ["read"] }]
    },
    "SessionSummary": {
      "source": {
        "object": "dbo.vw_SessionSummary",
        "type": "view",
        "key-fields": ["SessionId"]
      },
      "permissions": [{ "role": "anonymous", "actions": ["read"] }]
    },
    "SessionMetrics": {
      "source": {
        "object": "dbo.vw_SessionMetrics",
        "type": "view",
        "key-fields": ["SessionId"]
      },
      "permissions": [{ "role": "anonymous", "actions": ["read"] }]
    },
    "TraceLineDetails": {
      "source": {
        "object": "dbo.vw_TraceLineDetails",
        "type": "view",
        "key-fields": ["TraceLineId"]
      },
      "permissions": [{ "role": "anonymous", "actions": ["read"] }]
    },
    "NPlusOnePatterns": {
      "source": {
        "object": "dbo.vw_NPlusOnePatterns",
        "type": "view",
        "key-fields": ["TraceLineId"]
      },
      "permissions": [{ "role": "anonymous", "actions": ["read"] }]
    },
    "SlowSqlStatements": {
      "source": {
        "object": "dbo.vw_SlowSqlStatements",
        "type": "view",
        "key-fields": ["TraceLineId"]
      },
      "permissions": [{ "role": "anonymous", "actions": ["read"] }]
    },
    "TopMethodsBySession": {
      "source": {
        "object": "dbo.vw_TopMethodsBySession",
        "type": "view",
        "key-fields": ["SessionId", "MethodName"]
      },
      "permissions": [{ "role": "anonymous", "actions": ["read"] }]
    },
    "SearchTracesByKeyword": {
      "source": {
        "object": "dbo.sp_SearchTracesByKeyword",
        "type": "stored-procedure",
        "parameters": {
          "TraceId": 0,
          "Keyword": "",
          "SearchIn": "ALL",
          "MaxResults": 100
        }
      },
      "permissions": [{ "role": "anonymous", "actions": ["execute"] }],
      "rest": { "methods": ["post"] }
    },
    "SearchSqlStatements": {
      "source": {
        "object": "dbo.sp_SearchSqlStatements",
        "type": "stored-procedure",
        "parameters": {
          "TraceId": 0,
          "Keyword": "",
          "MaxResults": 100
        }
      },
      "permissions": [{ "role": "anonymous", "actions": ["execute"] }],
      "rest": { "methods": ["post"] }
    },
    "SearchMethods": {
      "source": {
        "object": "dbo.sp_SearchMethods",
        "type": "stored-procedure",
        "parameters": {
          "TraceId": 0,
          "Keyword": "",
          "MaxResults": 100
        }
      },
      "permissions": [{ "role": "anonymous", "actions": ["execute"] }],
      "rest": { "methods": ["post"] }
    },
    "SearchMessages": {
      "source": {
        "object": "dbo.sp_SearchMessages",
        "type": "stored-procedure",
        "parameters": {
          "TraceId": 0,
          "Keyword": "",
          "MaxResults": 100
        }
      },
      "permissions": [{ "role": "anonymous", "actions": ["execute"] }],
      "rest": { "methods": ["post"] }
    }
  }
}

```

---

# Step 5: Start the MCP Server

## 5.1 Start DAB

Open PowerShell and run:

```powershell
cd C:\TraceParserMCP
dotnet dab start --config dab-config.json

```

**Expected Output:**

```
info: Azure.DataApiBuilder.Service.Startup[0]
      Successfully loaded configuration file.
info: Azure.DataApiBuilder.Service.Startup[0]
      Starting Data API Builder...
info: Microsoft.Hosting.Lifetime[14]
      Now listening on: http://localhost:5000

```

⚠️ **Keep this PowerShell window open** - the server must be running for the agent to work.

## 5.2 Test the Server

Open a **new PowerShell window** and run:

```powershell
# Test health endpoint
Invoke-RestMethod -Uri "http://localhost:5000/health"

# Test traces endpoint
Invoke-RestMethod -Uri "http://localhost:5000/api/Traces"

# Test session metrics (replace TraceId with your actual trace ID)
Invoke-RestMethod -Uri "http://localhost:5000/api/SessionMetrics"

```

## 5.3 Test Stored Procedures

```powershell
# Test keyword search (replace TraceId with your actual trace ID)
$body = @{
    TraceId = 2
    Keyword = "find"
    SearchIn = "ALL"
    MaxResults = 10
} | ConvertTo-Json

Invoke-RestMethod -Uri "http://localhost:5000/api/SearchTracesByKeyword" -Method Post -Body $body -ContentType "application/json"

```

---

# Step 6: Import the Agent Solution

## 6.1 Receive the Solution File

You will receive a solution file (`.zip`) from your colleague. This contains the Copilot Studio agent.

## 6.2 Import to Power Platform

1. Go to [Power Apps Maker Portal](https://make.powerapps.com/)
2. Select your **Environment** (top right)
3. Click **Solutions** in the left navigation
4. Click **Import solution**
5. Browse and select the `.zip` file
6. Click **Next** and follow the prompts
7. Wait for import to complete

## 6.3 Open Copilot Studio

1. Go to [Copilot Studio](https://copilotstudio.microsoft.com/)
2. Select the same **Environment**
3. Find the **D365 Trace Parser Analyzer** agent
4. Click to open it

---

# Step 7: Set Up Port Forwarding (Required for Copilot Studio)

Copilot Studio is a cloud service and **cannot access `localhost:5000`** on your machine. You need to create a public tunnel URL using VS Code's built-in port forwarding feature.

## 7.1 Forward Port 5000 in VS Code

1. Make sure the **DAB server is running** (from Step 5)
2. Open **VS Code**
3. Open the **Ports** panel:
    - Go to **View** > **Terminal**, then click the **Ports** tab
    - Or press `Ctrl+Shift+P` and type **"Ports: Focus on Ports View"**
4. Click **Forward a Port** (or the `+` button)
5. Enter port: `5000`
6. VS Code will create a forwarded URL like:
    ```
    https://abcdef12-5000.uks1.devtunnels.ms
    ```

## 7.2 Set Port Visibility to Public

By default, forwarded ports are **private** (require Microsoft authentication). Copilot Studio needs **public** access:

1. In the **Ports** panel, right-click on the forwarded port `5000`
2. Select **Port Visibility** > **Public**
3. Confirm the change

> **Important:** The port must be set to **Public** for Copilot Studio to reach it. Private visibility will cause connection errors.

## 7.3 Verify the Tunnel

Test the forwarded URL in your browser:

```
https://<your-tunnel-url>/api/Traces
```

You should see JSON data from your local database. If this works, the tunnel is ready.

## 7.4 Copy Your MCP URL

Your MCP URL for Copilot Studio will be:

```
https://<your-tunnel-url>/mcp
```

For example: `https://abcdef12-5000.uks1.devtunnels.ms/mcp`

> **Note:** The tunnel URL changes each time you restart VS Code port forwarding. You will need to update the connector URL in Copilot Studio if this happens.

---

# Step 8: Configure MCP Connectors

## 8.1 Configure TraceParser MCP Connector

1. In Copilot Studio, open the agent
2. Go to **Tools** (left navigation)
3. Find the **TraceParser MCP** connector
4. Click **Edit** or **Configure**
5. Update the URL to your **forwarded tunnel URL** from Step 7:

    ```
    https://<your-tunnel-url>/mcp
    ```

    > **Do NOT use `http://localhost:5000/mcp`** - Copilot Studio cannot reach localhost.

6. **Save** the connector

## 8.2 Verify Microsoft Learn MCP Connector

1. In **Tools**, find **Microsoft Learn MCP** connector
2. Verify the URL is:

    ```
    https://learn.microsoft.com/api/mcp

    ```

3. This connector should work without changes (public endpoint)

---

# Step 9: Test the Agent

## 9.1 Open Test Panel

1. In Copilot Studio, click **Test** (bottom right)
2. The test chat panel will open

## 9.2 Test Queries

Try these queries to verify everything works:

### Test 1: Basic Connection

```
Show me all available traces

```

**Expected:** List of traces from your AxTrace database

### Test 2: Session Discovery

```
Show me all sessions in trace 2

```

(Replace `2` with an actual TraceId from your database)

**Expected:** Table of sessions with duration, DB calls, and status indicators

### Test 3: Keyword Search

```
Find all references to "find" in trace 2

```

**Expected:** Search results from the stored procedure

### Test 4: Microsoft Learn Integration

```
What is an N+1 query pattern and how do I fix it?

```

**Expected:** Response pulling from Microsoft Learn documentation

### Test 5: Full Analysis

```
Analyze the slowest session for performance issues

```

**Expected:** Detailed analysis with issues detected and Microsoft Learn recommendations

---

# Troubleshooting

## Issue: DAB Server Won't Start

**Error:** `Connection string not found`

**Solution:**

1. Verify `.env` file exists in `C:\TraceParserMCP`
2. Check the connection string is correct
3. Try running with explicit connection string:

```powershell
$env:MSSQL_CONNECTION_STRING="Server=(LocalDB)\MSSQLLocalDB;Database=AxTrace;Trusted_Connection=True;TrustServerCertificate=True;Encrypt=Optional"
dab start --config dab-config.json

```

---

## Issue: "execute_entity tool is disabled"

**Error in Agent:**

```
The execute_entity tool is disabled in the configuration.

```

**Solution:**

1. Open `dab-config.json`
2. Find the `mcp` section
3. Ensure `execute-entity` is `true`:

```json
"mcp": {
    "dml-tools": {
        "execute-entity": true
    }
}

```

1. Restart DAB server

---

## Issue: SSL Certificate Error

**Error:**

```
certificate chain was issued by an authority that is not trusted

```

**Solution:** Add `Encrypt=Optional` to connection string in `.env`:

```
MSSQL_CONNECTION_STRING=Server=(LocalDB)\MSSQLLocalDB;Database=AxTrace;Trusted_Connection=True;TrustServerCertificate=True;Encrypt=Optional

```

---

## Issue: Views Not Found

**Error:**

```
Could not find entity: SessionMetrics

```

**Solution:** Run the SQL view creation script from Step 3.

---

## Issue: Agent Can't Connect to MCP

**Symptoms:** Agent says it can't access trace data or "get connected first" error

**Checklist:**

1. ☐ Is DAB server running? (Check PowerShell window)
2. ☐ Is VS Code port forwarding active? (Check Ports panel)
3. ☐ Is port visibility set to **Public**? (Right-click port > Port Visibility > Public)
4. ☐ Is the connector URL using the **tunnel URL** (not `localhost`)?
5. ☐ Can you reach `https://<your-tunnel-url>/api/Traces` in browser?
6. ☐ Did the tunnel URL change? (Update connector if VS Code restarted)

---

## Issue: No Data Returned

**Symptoms:** Queries return empty results

**Checklist:**

1. ☐ Do you have trace data in the database?
2. ☐ Is the TraceId correct?
3. ☐ Test directly via REST API:

```powershell
Invoke-RestMethod -Uri "http://localhost:5000/api/Traces"

```

---

# Quick Reference Card

## File Locations

| File | Location |
| --- | --- |
| DAB Config | `C:\TraceParserMCP\dab-config.json` |
| Environment | `C:\TraceParserMCP\.env` |
| DAB CLI | `C:\TraceParserMCP\.config\dotnet-tools.json` |

## Commands

| Action | Command |
| --- | --- |
| Start MCP Server | `cd C:\TraceParserMCP; dab start --config dab-config.json` |
| Stop MCP Server | Press `Ctrl+C` in PowerShell window |
| Test Health | `Invoke-RestMethod -Uri "http://localhost:5000/health"` |
| Check DAB Version | `dab --version` |

## URLs

| Endpoint | URL |
| --- | --- |
| MCP Server (local) | `http://localhost:5000/mcp` |
| MCP Server (for Copilot Studio) | `https://<your-tunnel-url>/mcp` (via VS Code port forwarding) |
| REST API | `http://localhost:5000/api/` |
| Health Check | `http://localhost:5000/health` |
| Microsoft Learn MCP | `https://learn.microsoft.com/api/mcp` |

## Support

For questions or issues, please open an issue in the [Dynamics 365 FastTrack Implementation Assets](https://github.com/microsoft/Dynamics-365-FastTrack-Implementation-Assets/issues) GitHub repository.

---

# Setup Verification Checklist

Before testing the agent, verify:

- [ ]  .NET 9+ installed
- [ ]  LocalDB running
- [ ]  AxTrace database accessible
- [ ]  6 views created (vw_SessionSummary, vw_SessionMetrics, etc.)
- [ ]  4 stored procedures created (sp_SearchTracesByKeyword, etc.)
- [ ]  DAB CLI installed
- [ ]  `.env` file created with connection string
- [ ]  `dab-config.json` file created
- [ ]  DAB server starts without errors
- [ ]  Health endpoint responds
- [ ]  REST API returns data
- [ ]  VS Code port forwarding active (port 5000, visibility: Public)
- [ ]  Tunnel URL accessible from browser
- [ ]  Agent solution imported
- [ ]  TraceParser MCP connector configured (using tunnel URL, not localhost)
- [ ]  Microsoft Learn MCP connector verified
- [ ]  Test queries work in agent

**Setup Complete! ✅**