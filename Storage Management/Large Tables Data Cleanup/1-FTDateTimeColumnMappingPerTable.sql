Create or Alter view FTDateTimeColumnMappingPerTable as 
-- 1) Identify tables that have CREATEDDATETIME as the chosen cleanup column
SELECT 
    FIC.TABLE_NAME,
    'CreatedDateTime' AS CleanupColumn,
    'Preferred: CreatedDateTime indicates when record was originally created.' AS Reason
FROM FTInformationcolums FIC
WHERE FIC.COLUMN_NAME = 'CreatedDateTime'
union
-- 2) Identify tables that do NOT have CREATEDDATETIME but do have MODIFIEDDATETIME
SELECT 
    FIC.Table_Name,
    'ModifiedDateTime' AS CleanupColumn,
    'Fallback: ModifiedDateTime is used if CreatedDateTime does not exist.' AS Reason
FROM FTInformationcolums FIC
WHERE FIC.Column_Name = 'ModifiedDateTime'
    AND FIC.Table_Name NOT IN (
        SELECT FTIC.Table_Name 
        FROM FTInformationcolums FTIC
        WHERE FTIC.Column_Name = 'CreatedDateTime'
    )
union
-- 3) Identify tables that do NOT have CREATEDDATETIME or MODIFIEDDATETIME but do have ACCOUNTINGDATE
SELECT 
    FIC.Table_Name,
    'AccountingDate' AS CleanupColumn,
    'Fallback: AccountingDate is used if neither CreatedDateTime nor ModifiedDateTime exist.' AS Reason
FROM FTInformationcolums FIC
WHERE FIC.COLUMN_NAME = 'AccountingDate'
    AND FIC.TABLE_NAME NOT IN (
        SELECT TABLE_NAME 
        FROM FTInformationcolums 
        WHERE COLUMN_NAME IN ('CreatedDateTime', 'ModifiedDateTime')
    )
union
-- 3) Identify tables that do NOT have CREATEDDATETIME or MODIFIEDDATETIME but do have ACCOUNTINGDATE
SELECT 
    FIC.Table_Name,
    'TransDate' AS CleanupColumn,
    'Fallback: TransDate is used if neither CreatedDateTime nor ModifiedDateTime nor AccountingDate exist.' AS Reason
FROM FTInformationcolums FIC
WHERE FIC.COLUMN_NAME = 'TransDate'
    AND FIC.TABLE_NAME NOT IN (
        SELECT TABLE_NAME 
        FROM FTInformationcolums 
        WHERE COLUMN_NAME IN ('CreatedDateTime', 'ModifiedDateTime', 'AccountingDate')
    )
union
-- 4) Identify tables with none of the three columns, choosing the “best alternative”
--    (this part requires domain knowledge—below uses an example heuristic)
SELECT
    FIC.TABLE_NAME,
    -- Example heuristic: pick the first date/datetime-like column as fallback
    MAX(FIC.COLUMN_NAME) AS CleanupColumn,
    'None of CreatedDateTime/ModifiedDateTime/AccountingDate exist; choose best date-like column.' AS Reason
FROM FTInformationcolums FIC
WHERE FIC.TABLE_NAME NOT IN (
    SELECT TABLE_NAME 
    FROM FTInformationcolums 
    WHERE COLUMN_NAME IN ('CreatedDateTime', 'ModifiedDateTime', 'AccountingDate', 'TransDate')
)
    -- If you have a way to identify date-like columns (e.g. data type checks), filter them:
    -- AND (FIC.DataType IN ('datetime', 'date'))
GROUP BY FIC.TABLE_NAME;