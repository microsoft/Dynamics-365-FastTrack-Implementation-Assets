
/* ===========================================
   Index Rebuild Log Table - Create/Upgrade
   =========================================== */

-- Create base table if it does not exist
IF OBJECT_ID('dbo.IndexRebuildLog') IS NULL
BEGIN
    CREATE TABLE dbo.IndexRebuildLog
    (
        log_id      BIGINT IDENTITY(1,1) PRIMARY KEY,
        run_ts      DATETIME2(2) NOT NULL DEFAULT SYSUTCDATETIME(),
        schema_name SYSNAME,
        table_name  SYSNAME,
        index_name  SYSNAME,
        status      VARCHAR(30),
        attempt     INT,
        err_number  INT NULL,
        err_message NVARCHAR(4000) NULL
    );
END;

-- Add optional columns if missing (idempotent upgrades)
IF COL_LENGTH('dbo.IndexRebuildLog', 'start_time') IS NULL
    ALTER TABLE dbo.IndexRebuildLog ADD start_time DATETIME2(2) NULL;

IF COL_LENGTH('dbo.IndexRebuildLog', 'end_time') IS NULL
    ALTER TABLE dbo.IndexRebuildLog ADD end_time DATETIME2(2) NULL;

IF COL_LENGTH('dbo.IndexRebuildLog', 'duration_ms') IS NULL
    ALTER TABLE dbo.IndexRebuildLog ADD duration_ms BIGINT NULL;

IF COL_LENGTH('dbo.IndexRebuildLog', 'sql_text') IS NULL
    ALTER TABLE dbo.IndexRebuildLog ADD sql_text NVARCHAR(MAX) NULL;

-- Helpful filtered index for quick lookups by status/time (optional)
IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'IX_IndexRebuildLog_status_run_ts'
      AND object_id = OBJECT_ID('dbo.IndexRebuildLog')
)
BEGIN
    CREATE INDEX IX_IndexRebuildLog_status_run_ts
    ON dbo.IndexRebuildLog (status, run_ts);
END;
