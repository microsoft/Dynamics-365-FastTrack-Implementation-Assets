-- Drop the table FTInformationcolums if it exists
DROP TABLE IF EXISTS dbo.FTInformationcolums;

-- Create a new table FTInformationcolums and insert data into it
SELECT * INTO FTInformationcolums FROM (
    -- Select all columns from INFORMATION_SCHEMA.COLUMNS
    SELECT isc.*, sdf.TABLEID 
    FROM [INFORMATION_SCHEMA].[COLUMNS] isc
    -- Inner join with SQLDICTIONARY to get TABLEID where FIELDID = 0 and ARRAY = 0
    INNER JOIN (
        SELECT SQLName, TABLEID 
        FROM SQLDICTIONARY sd 
        WHERE sd.FIELDID = 0 AND sd.ARRAY = 0
    ) sdf ON isc.Table_Name = sdf.SQLNAME
    -- Inner join with TABLEMETADATATABLE to get metadata information
    INNER JOIN TABLEMETADATATABLE TMT ON TMT.TABLEID = sdf.TABLEID
    -- Filter the results based on TABLEGROUP and SQLNAME, and data_type = 'datetime'
    WHERE (TMT.TABLEGROUP IN (4, 5, 6, 9, 10, 11) OR SDF.SQLNAME IN ('WHSASNITEM', 'WHSASNITEMRECEIPT', 'WHSUOMSTRUCTURE')) 
    AND data_type = 'datetime'
) selection;
