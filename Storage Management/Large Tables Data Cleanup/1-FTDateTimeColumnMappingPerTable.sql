-- Create or Alter view FTDateTimeColumnMappingPerTable
CREATE OR ALTER VIEW FTDateTimeColumnMappingPerTable AS 

-- 1) Identify tables that have ACCOUNTINGDATE
SELECT 
    FIC.Table_Name,
    'AccountingDate' AS CleanupColumn,
    'Preferred: AccountingDate indicates when record was originally created.' AS Reason
FROM FTInformationcolums FIC
WHERE FIC.COLUMN_NAME = 'AccountingDate'

UNION

-- 2) Identify tables that do NOT have ACCOUNTINGDATE but  have TRANSDATE
SELECT 
    FIC.Table_Name,
    'TransDate' AS CleanupColumn,
    'Preferred: TranDate if AccountingDate does not exist.' AS Reason
FROM FTInformationcolums FIC
WHERE FIC.COLUMN_NAME = 'TransDate'
    AND FIC.TABLE_NAME NOT IN (
        SELECT TABLE_NAME 
        FROM FTInformationcolums 
        WHERE COLUMN_NAME IN ('AccountingDate')
    )

UNION

-- 3) Identify tables that have CREATEDDATETIME as the chosen cleanup column
SELECT 
    FIC.TABLE_NAME,
    'CreatedDateTime' AS CleanupColumn,
    'Preferred: CreatedDateTime indicates when record was originally created.' AS Reason
FROM FTInformationcolums FIC
WHERE FIC.COLUMN_NAME = 'CreatedDateTime'
    AND FIC.TABLE_NAME NOT IN (
        SELECT TABLE_NAME 
        FROM FTInformationcolums 
        WHERE COLUMN_NAME IN ('AccountingDate','TransDate')
    )


UNION

-- 4) Identify tables that do NOT have CREATEDDATETIME but do have MODIFIEDDATETIME
SELECT 
    FIC.Table_Name,
    'ModifiedDateTime' AS CleanupColumn,
    'Fallback: ModifiedDateTime is used if CreatedDateTime does not exist.' AS Reason
FROM FTInformationcolums FIC
WHERE FIC.Column_Name = 'ModifiedDateTime'
    AND FIC.Table_Name NOT IN (
        SELECT FTIC.Table_Name 
        FROM FTInformationcolums FTIC
        WHERE COLUMN_NAME IN ('AccountingDate','TransDate','CreatedDateTime')
    )

UNION

/*    
-- 5) Identify tables with none of the above columns, choosing the “best alternative”
--    (this part requires domain knowledge—below uses an example heuristic)
SELECT
    FIC.TABLE_NAME,
    -- Example heuristic: pick the first date/datetime-like column as fallback
    MAX(FIC.COLUMN_NAME) AS CleanupColumn,
    'None of CreatedDateTime/ModifiedDateTime/AccountingDate/TransDate exist; choose best date-like column.' AS Reason
FROM FTInformationcolums FIC
WHERE FIC.TABLE_NAME NOT IN (
    SELECT TABLE_NAME 
    FROM FTInformationcolums 
    WHERE COLUMN_NAME IN ('CreatedDateTime', 'ModifiedDateTime', 'AccountingDate', 'TransDate')
)
    -- If you have a way to identify date-like columns (e.g. data type checks), filter them:
    -- AND (FIC.DataType IN ('datetime', 'date'))
GROUP BY FIC.TABLE_NAME;
*/
