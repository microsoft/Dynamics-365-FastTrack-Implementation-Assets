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

DECLARE @Tables NVARCHAR(MAX) = 'INVENTTRANS,LEDGERJOURNALTRANS,SALESLINE,TAXTRANS,RETAILTRANSACTIONPAYMENTTRANS,CUSTTRANS,RETAILTRANSACTIONSALESTRANS,CUSTINVOICETRANS,RETAILTRANSACTIONTABLE' -- Replace with your list of tables (comma separated)
DECLARE @MaxArchivingDate DATE = '2025-01-01' -- Replace with your max archiving date
DECLARE @Simulation BIT = 1 -- Set to 1 for simulation mode, 0 for actual deletion

DECLARE @LE NVARCHAR(10)
DECLARE @StartDate DATE
DECLARE @EndDate DATE

-- Declare the @EligibleDates table variable
DECLARE @EligibleDates TABLE (DataAreaID NVARCHAR(10), FiscalYearStartDate DATE, FiscalYearEndDate DATE)

-- Populate the EligibleDates table
INSERT INTO @EligibleDates
EXEC PopulateEligibleDates @MaxArchivingDate

-- Split the list of tables
DECLARE @TableList TABLE (TableName NVARCHAR(255))
INSERT INTO @TableList (TableName)
SELECT value FROM STRING_SPLIT(@Tables, ',')

-- Loop through each eligible LE and fiscal year
DECLARE LE_CURSOR CURSOR FOR
SELECT DataAreaID, FiscalYearStartDate, FiscalYearEndDate FROM @EligibleDates

OPEN LE_CURSOR
FETCH NEXT FROM LE_CURSOR INTO @LE, @StartDate, @EndDate

WHILE @@FETCH_STATUS = 0
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
        EXEC DeleteRecords @Table, @LE, @StartDate, @EndDate, @Simulation
        FETCH NEXT FROM TABLE_CURSOR INTO @Table
    END

    CLOSE TABLE_CURSOR
    DEALLOCATE TABLE_CURSOR

    FETCH NEXT FROM LE_CURSOR INTO @LE, @StartDate, @EndDate
END

CLOSE LE_CURSOR
DEALLOCATE LE_CURSOR

DROP PROCEDURE dbo.PopulateEligibleDates;
DROP PROCEDURE dbo.DeleteRecords;