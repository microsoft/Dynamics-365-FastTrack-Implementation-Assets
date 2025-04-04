

-- =============================================
-- Author:        Samy Sid Otmane
-- Create date:   2025-04-04
-- Description:   This stored procedure checks if the DBCleanupResultsLog table exists and if all required fields are present.
--                If any field is missing, it drops the table and recreates it along with the index.
-- =============================================
CREATE OR ALTER PROCEDURE dbo.CreateDBCleanup
AS
BEGIN
    -- Function to check if a column exists in the table
    DECLARE @missing_fields INT = 0
	DECLARE @table_exists INT = 0
    DECLARE @table_name NVARCHAR(100) = 'DBCleanupResultsLog'

    
    -- Check if the table exists
    IF EXISTS (SELECT * FROM sysobjects WHERE name=@table_name AND xtype='U')
    BEGIN
		SET @table_exists = 1
        -- Check if all required fields are present in the table
        IF dbo.ColumnExists(@table_name, 'TableName', 'NVARCHAR', 1000) = 0 SET @missing_fields = @missing_fields + 1
        IF dbo.ColumnExists(@table_name, 'LegalEntity', 'NVARCHAR', 1000) = 0 SET @missing_fields = @missing_fields + 1
		IF dbo.ColumnExists(@table_name, 'KeepFromDate', 'NVARCHAR', 120) = 0 SET @missing_fields = @missing_fields + 1
		IF dbo.ColumnExists(@table_name, 'NbRecordsDeleted', 'INT', NULL) = 0 SET @missing_fields = @missing_fields + 1
		IF dbo.ColumnExists(@table_name, 'NbRecordsSaved', 'INT', NULL) = 0 SET @missing_fields = @missing_fields + 1
		IF dbo.ColumnExists(@table_name, 'EstimatedDuration', 'INT', NULL) = 0 SET @missing_fields = @missing_fields + 1
		IF dbo.ColumnExists(@table_name, 'StartTime', 'DATETIME', NULL) = 0 SET @missing_fields = @missing_fields + 1
		IF dbo.ColumnExists(@table_name, 'EndTime', 'DATETIME', NULL) = 0 SET @missing_fields = @missing_fields + 1
		IF dbo.ColumnExists(@table_name, 'Step', 'INT', NULL) = 0 SET @missing_fields = @missing_fields + 1
        IF dbo.ColumnExists(@table_name, 'CurrentLoopIndex', 'INT', NULL) = 0 SET @missing_fields = @missing_fields + 1
        -- Drop the table if any field is missing
			IF @missing_fields > 0
			BEGIN
					DROP TABLE DBCleanupResultsLog
			END

    END

	IF (@table_exists = 0 or @missing_fields > 0)
	BEGIN
		-- Create DBCleanupResultsLog table
		CREATE TABLE DBCleanupResultsLog(
			TableName NVARCHAR(1000),
			LegalEntity NVARCHAR(1000),
			KeepFromDate NVARCHAR(120),
			NbRecordsDeleted INT,
			NbRecordsSaved INT,
			EstimatedDuration INT,
			StartTime DATETIME,
			EndTime DATETIME,
			Step INT,
			CurrentLoopIndex INT
		)
	END
    -- Drop the index if it exists
    IF EXISTS (SELECT * FROM sys.indexes WHERE name='idx_DBCleanupResultsLog_EndTime_StartTime_TableName_LegalEntity_KeepFromDate') and @missing_fields > 0
    BEGIN
        DROP INDEX idx_DBCleanupResultsLog_EndTime_StartTime_TableName_LegalEntity_KeepFromDate ON DBCleanupResultsLog
    END

	IF (@table_exists = 0 or @missing_fields > 0)
	BEGIN
		-- Create the index
		CREATE INDEX idx_DBCleanupResultsLog_EndTime_StartTime_TableName_LegalEntity_KeepFromDate
		ON DBCleanupResultsLog (EndTime, StartTime, TableName, LegalEntity, KeepFromDate);
	END 
END
