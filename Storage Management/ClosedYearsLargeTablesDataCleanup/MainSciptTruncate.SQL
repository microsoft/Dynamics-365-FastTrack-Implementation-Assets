-- Main script truncate
-- Transaction (4), WorksheetHeader (5), WorksheetLine (6), Worksheet (9), TransactionHeader (10), TransactionLine (11), Staging (12)
DECLARE @TableGroups NVARCHAR(MAX) = '12'
DECLARE @TableNames NVARCHAR(MAX) = 'BATCHHISTORY,DOCUHISTORY,SYSDATABASELOG,BATCHJOBHISTORY,SYSEMAILHISTORY,SECURITYOBJECTHISTORY'
DECLARE @SimulationMode BIT = 1 -- Set to 1 for simulation mode, 0 for actual execution

EXEC dbo.TruncateTables @TableGroups, @TableNames, @SimulationMode

DROP PROCEDURE dbo.TruncateTables;