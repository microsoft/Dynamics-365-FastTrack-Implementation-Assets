-- Create a stored procedure to populate the EligibleDates table
IF OBJECT_ID('dbo.PopulateEligibleDates', 'P') IS NOT NULL
    DROP PROCEDURE dbo.PopulateEligibleDates;
GO
CREATE PROCEDURE PopulateEligibleDates
    @MaxArchivingDate DATE
AS
BEGIN
    DECLARE @EligibleDates TABLE (DataAreaID NVARCHAR(10), FiscalYearStartDate DATE, FiscalYearEndDate DATE)

    INSERT INTO @EligibleDates
    SELECT 
        da.ID AS DataAreaID,
        fcy.STARTDATE AS FiscalYearStartDate,
        fcy.ENDDATE AS FiscalYearEndDate
    FROM 
        dbo.DATAAREA da
    INNER JOIN 
        dbo.LEDGER l ON da.ID = l.NAME
    INNER JOIN 
        dbo.LEDGERFISCALCALENDARPERIOD lfp ON l.RECID = lfp.LEDGER
    INNER JOIN 
        dbo.FISCALCALENDARPERIOD fcp ON lfp.FISCALCALENDARPERIOD = fcp.RECID
    INNER JOIN 
        dbo.FISCALCALENDARYEAR fcy ON fcp.FISCALCALENDARYEAR = fcy.RECID
    INNER JOIN
        (SELECT 
            fcp.FISCALCALENDARYEAR, fc.RECID, l.PARTITION, da.ID, COUNT(*) AS NBOCCURENCES
        FROM
            dbo.DATAAREA da
        JOIN 
            dbo.LEDGER l ON da.ID = l.NAME
        JOIN 
            dbo.LEDGERFISCALCALENDARPERIOD lfp ON l.RECID = lfp.LEDGER
        JOIN 
            dbo.FISCALCALENDARPERIOD fcp ON lfp.FISCALCALENDARPERIOD = fcp.RECID
        JOIN 
            dbo.FISCALCALENDAR fc ON fcp.FISCALCALENDAR = fc.RECID AND fc.RECID = l.FISCALCALENDAR
        WHERE 
            lfp.STATUS IN (0, 2) AND lfp.PARTITION = fcp.PARTITION
        GROUP BY 
            fcp.FISCALCALENDARYEAR, fc.RECID, l.PARTITION, da.ID
        HAVING 
            COUNT(*) = (
                SELECT 
                    COUNT(*)
                FROM 
                    dbo.FISCALCALENDARPERIOD fcp2
                WHERE 
                    fcp2.FISCALCALENDARYEAR = fcp.FISCALCALENDARYEAR
                    AND fcp2.PARTITION = l.PARTITION
                    AND fcp2.FISCALCALENDAR = fc.RECID
            )
        ) Allperiods ON Allperiods.FISCALCALENDARYEAR = fcp.FISCALCALENDARYEAR 
        AND Allperiods.ID = da.ID 
        AND Allperiods.PARTITION = da.PARTITION 
        AND Allperiods.RECID = l.RECID
    WHERE 
        fcy.ENDDATE <= @MaxArchivingDate
    GROUP BY 
        da.ID, fcy.STARTDATE, fcy.ENDDATE

    SELECT * FROM @EligibleDates
END
