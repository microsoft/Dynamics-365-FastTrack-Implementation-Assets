IF NOT EXISTS ( SELECT  *
                FROM    sys.schemas
                WHERE   name = N'datamodel' )
    EXEC('CREATE SCHEMA [datamodel]');
GO

Create or Alter View  [datamodel].[BusinessUnit] AS
SELECT 
[RECID] as _Key
,[VALUE] as Id
,[NAME] as Description
FROM [dbo].[DIMATTRIBUTEOMBUSINESSUNITENTITY]
GO



Create or Alter View  [datamodel].[CostCenter] AS
SELECT 
[RECID] as _Key
,[VALUE] as Id
,[NAME] as Description
FROM [dbo].[DIMATTRIBUTEOMCOSTCENTERENTITY]
GO

/****** Object:  View [datamodel].[Department]    Script Date: 4/27/2022 5:52:33 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


Create or Alter View  [datamodel].[Department] AS
SELECT 
[RECID] as _Key
,[VALUE] as Id
,[NAME] as Description
FROM [dbo].[DIMATTRIBUTEOMDEPARTMENTENTITY]
GO

/****** Object:  View [datamodel].[GeneralJournalTransactions]    Script Date: 4/27/2022 5:52:33 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO



Create or Alter VIEW [datamodel].[GeneralJournalTransactions] AS
select
    GeneralJournalEntry.AccountingDate as AccountingDate,
    GeneralJournalEntry.DocumentDate as DocumentDate,
    GeneralJournalEntry.DocumentNumber as DocumentNumber,
	GENERALJOURNALENTRY.JOURNALNUMBER as JournalNumber,
	DIMENSIONATTRIBUTEVALUECOMBINATION.DISPLAYVALUE as LedgerDimension,
	GENERALJOURNALACCOUNTENTRY.MAINACCOUNT as MainAccount_FK,
    DIMENSIONATTRIBUTEVALUECOMBINATION.COSTCENTER as CostCenter_FK,
    DIMENSIONATTRIBUTEVALUECOMBINATION.DEPARTMENT as Department_FK,
    DIMENSIONATTRIBUTEVALUECOMBINATION.BUSINESSUNIT as BusinessUnit_FK,
    DIMENSIONATTRIBUTEVALUECOMBINATION.ITEMGROUP as ItemGroup_FK,
	LEDGER.RECID as LegalEntity_FK,
    GeneralJournalAccountEntry.ACCOUNTINGCURRENCYAMOUNT as [Amount(AccountingCurrency)],
    Ledger.ACCOUNTINGCURRENCY as AccountingCurrency,
	GENERALJOURNALACCOUNTENTRY.REPORTINGCURRENCYAMOUNT as [Amount(ReportingCurrency)],
	ledger.REPORTINGCURRENCY as ReportingCurrency,
	GENERALJOURNALACCOUNTENTRY.TRANSACTIONCURRENCYAMOUNT as [Amount(TransactionCurrency)],
	GENERALJOURNALACCOUNTENTRY.TRANSACTIONCURRENCYCODE as TransactionCurrency,
	GENERALJOURNALENTRY.SUBLEDGERVOUCHER as SubLedgerVoucher
from GENERALJOURNALACCOUNTENTRY
join GENERALJOURNALENTRY on GeneralJournalAccountEntry.GENERALJOURNALENTRY = GeneralJournalEntry.RECID
join Ledger on GENERALJOURNALENTRY.Ledger = Ledger.RECID
join DIMENSIONATTRIBUTEVALUECOMBINATION on GENERALJOURNALACCOUNTENTRY.LEDGERDIMENSION = DIMENSIONATTRIBUTEVALUECOMBINATION.RECID;

GO

Create or alter View [datamodel].[LegalEntity] AS
select 
L.RecId as Ledger_Key
, Le.DATAAREA as ID
, LE.Name as CompanyName   
from Ledger L
join DirPartyTable LE 
on L.PrimaryForLegalEntity = LE.RECID
GO

CREATE or alter VIEW [datamodel].[MainAccountDim] AS 
SELECT
	M.RECID as ID,
	M.MAINACCOUNTID as MainAccount,
	M.NAME as Description,
	M.LEDGERCHARTOFACCOUNTS as COA_FK,
	L.NAME as COA_Name
FROM dbo.MAINACCOUNT M
JOIN dbo.LEDGERCHARTOFACCOUNTS L on LEDGERCHARTOFACCOUNTS = L.RECID
GO


