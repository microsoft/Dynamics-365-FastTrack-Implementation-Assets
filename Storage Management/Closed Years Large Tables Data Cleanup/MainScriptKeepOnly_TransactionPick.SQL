/*
This script takes three parameters:

A list of tables (comma-separated).
A maximum archiving date.
A simulation boolean.

Determines the list of fiscal years that are properly closed for each legal entity.

Filters the list to exclude fiscal years with an end date greater than the maximum archiving date.

Loops through the list of eligible legal entities and fiscal years, and deletes records from the specified tables.

Disables Change Data Capture or Change Tracking before deleting records and re-enables them afterward.

If simulation mode is enabled, it counts the records and estimates the duration instead of deleting them.
*/

DECLARE @Tables NVARCHAR(MAX) = 'INVENTTRANS,LEDGERJOURNALTRANS,SALESLINE,TAXTRANS,RETAILTRANSACTIONPAYMENTTRANS,CUSTTRANS,RETAILTRANSACTIONSALESTRANS,CUSTINVOICETRANS,RETAILTRANSACTIONTABLE,MCRRETURNSALESTABLE,MCRSALESLINE,MCRSALESTABLE,RETAILSALESLINE,RETAILSALESTABLE,SALESLINE,SALESLINE_BR,SALESLINE_IN,SALESLINE_W,SALESTABLE,SALESTABLE_BR,SALESTABLE_RU,SALESTABLE_W,INVENTTRANSARCHIVE,INVENTTRANS,INVENTJOURNALTABLE,INVENTJOURNALTABLE_IN,INVENTJOURNALTRANS,INVENTJOURNALTRANS_IN,TAXTRANS,TAXTRANS_BR,TAXTRANSGENERALJOURNALACCOUNTENTRY,TAXTRANS_IN,TAXTRANS_IT,TAXTRANS_REPORTING,TAXTRANS_RU,TAXTRANSSUBLEDGERJOURNALACCOUNTENTRY,TAXTRANS_TH,TAXTRANS_W' -- Replace with your list of tables (comma separated)
DECLARE @MaxArchivingDate DATE = '2025-01-01' -- Replace with your max archiving date
DECLARE @Simulation BIT = 1 -- Set to 1 for simulation mode, 0 for actual deletion

DECLARE @LE NVARCHAR(10) = 'USMF,BRMF'
DECLARE @StartDate DATE
DECLARE @EndDate DATE

-- Split the list of tables
DECLARE @TableList TABLE (TableName NVARCHAR(255))
INSERT INTO @TableList (TableName)
SELECT value FROM STRING_SPLIT(@Tables, ',')

BEGIN
    PRINT 'LE :' + @LE + ' StartDate :' + CONVERT(NVARCHAR, @StartDate, 120) + ' EndDate :' + CONVERT(NVARCHAR, @EndDate, 120)
    
    -- Declare the @Table variable
    DECLARE @Table NVARCHAR(255)

    DECLARE TABLE_CURSOR CURSOR FOR
    SELECT TableName FROM @TableList

    OPEN TABLE_CURSOR
    FETCH NEXT FROM TABLE_CURSOR INTO @Table

    WHILE @@FETCH_STATUS = 0
    BEGIN
        EXEC KeepOnlyRecordsSp @Table, @LE, @MaxArchivingDate, @Simulation
        FETCH NEXT FROM TABLE_CURSOR INTO @Table
    END

    CLOSE TABLE_CURSOR
    DEALLOCATE TABLE_CURSOR

END

DROP PROCEDURE dbo.KeepOnlyRecordsSp;
