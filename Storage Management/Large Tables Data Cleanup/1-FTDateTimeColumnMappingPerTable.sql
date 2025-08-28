-- Create or Alter view FTDateTimeColumnMappingPerTable
CREATE OR ALTER VIEW FTDateTimeColumnMappingPerTable AS 

-- 1) Identify tables that have ACCOUNTINGDATE
SELECT 
    FIC.Table_Name,
    'AccountingDate' AS CleanupColumn,
    'Preferred: AccountingDate indicates when record was originally created.' AS Reason
FROM FTInformationcolums FIC
WHERE 
	FIC.COLUMN_NAME = 'AccountingDate'


UNION

-- 2) Identify tables that do NOT have CREATEDDATETIME but do have MODIFIEDDATETIME
SELECT 
    FIC.Table_Name,
    'ModifiedDateTime' AS CleanupColumn,
    'Fallback: ModifiedDateTime is used if AccountingDate does not exist.' AS Reason
FROM FTInformationcolums FIC
WHERE FIC.Column_Name = 'ModifiedDateTime'
    AND FIC.Table_Name NOT IN (
        SELECT FTIC.Table_Name 
        FROM FTInformationcolums FTIC
        WHERE COLUMN_NAME IN ('AccountingDate')
    )

UNION

-- 3) Identify tables that have CREATEDDATETIME as the chosen cleanup column
SELECT 
    FIC.TABLE_NAME,
    'CreatedDateTime' AS CleanupColumn,
    'Fallback: CreatedDateTime is used if ModifiedDateTime does not exist..' AS Reason
FROM FTInformationcolums FIC
WHERE 	
--	FIC.Table_Name not in ('LedgerJournalTrans','CustTrans') and 
	FIC.COLUMN_NAME = 'CreatedDateTime'
    AND FIC.TABLE_NAME NOT IN (
        SELECT TABLE_NAME 
        FROM FTInformationcolums 
        WHERE COLUMN_NAME IN ('AccountingDate','ModifiedDateTime')
    )

UNION
	-- 2) Identify tables that do NOT have ACCOUNTINGDATE but  have TRANSDATE
SELECT 
    FIC.Table_Name,
    'TransDate' AS CleanupColumn,
    'Preferred: TranDate if CreatedDateTime does not exist.' AS Reason
FROM FTInformationcolums FIC
WHERE 
--	FIC.Table_Name not in ('LedgerJournalTrans','CustTrans') and 
	FIC.COLUMN_NAME = 'TransDate'
    AND FIC.TABLE_NAME NOT IN (
        SELECT TABLE_NAME 
        FROM FTInformationcolums 
        WHERE COLUMN_NAME IN ('AccountingDate','ModifiedDateTime','CreatedDateTime')
    )

