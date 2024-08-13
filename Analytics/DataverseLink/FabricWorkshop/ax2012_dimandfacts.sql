/* 
This script is to help create a simple dimentional data model similar to Dynamics 365 schema on MicrosoftDynamics AX Data copied to Fabric Lakehouse 
Script creates following views that are intended to be used in the final Symantic data model and Power BI report.

1.[dbo].[customers]
2.[dbo].[legalentity]
3.[dbo].[products]
4.[dbo].[legalentity] 
5.[dbo].[vendors]
6.[dbo].[salesorderdetails]

Two additonal views and function are created by script as generic template and used in the views above   
[dbo].[defaultfinancialdimension_view]
[dbo].[dirpartyprimary_view]


Pre-requisites: You must have a AX 2012 data copied to Microsoft OneLake
Following tables are enabled 
1. dirpartytable
3. logisticspostaladdress
4. logisticselectronicaddress
5. dimensionattributevaluesetitem
6. dimensionattributevalue
7. dimensionattribute
8. custtable
9. custgroup
10. hcmworker
11. vendtable
12. inventtable
13. ecoresproduct
14. ecoresproducttranslation
15. salesline
*/

--Script starts here-- 
/*
Party and Global address book 
https://learn.microsoft.com/en-us/dynamics365/fin-ops-core/dev-itpro/data-entities/dual-write/party-gab
"Party" in AX 2012 represents any entity or individual that can enter into a business relationship. Party can be customer, vendor, employee
"Global address book" stores party records and physical address and electronic address in central tables.  
 Following view provides common and simple representation of the party to include the key fields 
 partyid, name, primary address, primary phone number and email    
*/
CREATE OR ALTER VIEW dirpartyprimary_view
As
SELECT 
	PARTY.RECID AS [partyid]
	,PARTY.NAME AS [Name]
	,ISNULL(PARTY.NAMEALIAS, '') AS [Short Name]
	,ISNULL(POSTAL.COUNTRYREGIONID, '') AS [Country]
	,ISNULL(POSTAL.STATE, '') AS [State]
	,ISNULL(POSTAL.CITY, '') AS City
	,ISNULL(POSTAL.DISTRICTNAME, '') AS District
	,ISNULL(POSTAL.STREET, '') AS Street
	,ISNULL(POSTAL.ZIPCODE, '') AS [Zip Code]
	,ISNULL(PHONE.LOCATOR, '') AS [Phone Number]
	,ISNULL(EMAIL.LOCATOR, '') AS [Email]
FROM dbo.DIRPARTYTABLE PARTY 
LEFT OUTER JOIN dbo.LOGISTICSPOSTALADDRESS POSTAL ON POSTAL.LOCATION = PARTY.PRIMARYADDRESSLOCATION
AND POSTAL.VALIDTO > GETUTCDATE() -- FILTERS ONLY VALID(EFFECTIVE) ADDRESSES
LEFT OUTER JOIN dbo.LOGISTICSELECTRONICADDRESS PHONE ON PHONE.RECID = PARTY.PRIMARYCONTACTPHONE
LEFT OUTER JOIN dbo.LOGISTICSELECTRONICADDRESS EMAIL ON EMAIL.RECID = PARTY.PRIMARYCONTACTEMAIL

GO

/* 
Financial dimension such as business unit, cost center, department etc are use to represent segments 
master data/dimension such as customers, products,vendors etc. 
This concept is refered as Default Financial Dimension in Finance and Operations and in the backend is stored in normalized  
defaultfinancialdimension_view is simple representation of default financial dimension to extract such as business unit, cost center, department etc, 
*/
create or alter view defaultfinancialdimension_view
as 
	SELECT 
		T1.DISPLAYVALUE AS dimensionvalue, 
		T1.DIMENSIONATTRIBUTEVALUESET AS defaultdimensionid, 
		T3.NAME AS dimensionname
		FROM DIMENSIONATTRIBUTEVALUESETITEM T1 
	JOIN DIMENSIONATTRIBUTEVALUE T2 ON T1.DIMENSIONATTRIBUTEVALUE  =  T2.RECID
	JOIN DIMENSIONATTRIBUTE T3 ON T2.DIMENSIONATTRIBUTE  =  T3.RECID

GO

/* Get Enum translation from [SRSANALYSISENUMS]
*/
CREATE or ALTER FUNCTION GetEnumTranslations (@ENUMNAME varchar(200), @ENUMITEMVALUE int,  @LANGUAGEID varchar(10)='en-us')
RETURNS TABLE
AS
RETURN (
    SELECT 
	[ENUMITEMLABEL] as EnumLabel
    FROM [dbo].[SRSANALYSISENUMS]
	WHERE ENUMNAME = @ENUMNAME
    AND LANGUAGEID = @LANGUAGEID
    AND ENUMITEMVALUE = @ENUMITEMVALUE
);
GO

-- customers view to provides, basic customer account details, name, primary address and segmentation
CREATE OR ALTER VIEW dbo.customers 
AS
SELECT 
	customer.RECID AS customerid
	,customer.ACCOUNTNUM AS [Customer Account Number]
	,customer.DATAAREAID AS [Legal Entity]
	,custgroup.NAME as [Customer Group]
	,party.*
	,isnull(bu.dimensionvalue,'')  as [Business Unit]
FROM dbo.CUSTTABLE customer -- customer table
join dbo.dirpartyprimary_view as party on customer.PARTY = party.partyid
left outer join dbo.CUSTGROUP custgroup on custgroup.CUSTGROUP = customer.CUSTGROUP and custgroup.DATAAREAID = customer.DATAAREAID
left outer join dbo.defaultfinancialdimension_view bu on bu.defaultdimensionid = customer.DEFAULTDIMENSION and bu.dimensionname = 'BusinessUnit'
GO

-- employee view provides, employee number, name, primary address
CREATE OR ALTER VIEW dbo.employee
AS
SELECT 
	worker.RECID AS employeeid
	,worker.PERSONNELNUMBER AS [Employee Number]
	,party.*
FROM HCMWORKER worker
join dbo.dirpartyprimary_view as party on worker.PERSON = party.partyid
GO


-- vendor view provides, basic vendor/supplier details, name, primary address
CREATE OR ALTER VIEW dbo.vendors
AS
SELECT 
	vendor.RECID AS vendorid
	,vendor.ACCOUNTNUM as [Vendor Account]
	,vendor.DATAAREAID as [Legal Entity]
	,party.*
FROM VENDTABLE vendor
join dbo.dirpartyprimary_view as party on vendor.PARTY = party.partyid

GO 

-- product view to provides, product number, short name and detail product description
CREATE OR ALTER VIEW dbo.products
AS
SELECT it.RECID AS productid
	,p.DISPLAYPRODUCTNUMBER AS [Product Number]
	,pt.NAME [Product Name]
	,it.ITEMID AS [Item Number]
	,it.NAMEALIAS [Item Short Name]
	,it.DATAAREAID [Legal Entity]
FROM dbo.INVENTTABLE AS it
LEFT OUTER JOIN dbo.ECORESPRODUCT p ON p.RECID = it.PRODUCT
LEFT OUTER JOIN dbo.ECORESPRODUCTTRANSLATION pt ON it.PRODUCT = pt.PRODUCT
	AND pt.LANGUAGEID = 'en-us'
	
GO

-- legal entity view to provides, id, code and name and primary address details
CREATE OR ALTER VIEW dbo.legalentity
AS	
SELECT 
	company.RECID AS legalentityid
	,company.DATAAREA AS [Legal Entity]
	,party.*
FROM dbo.DIRPARTYTABLE company
join dbo.dirpartyprimary_view as party on company.RECID = party.partyid
WHERE company.DATAAREA NOT IN ('dat', 'DAT', '') -- dat is default company that typically not represent the actual legal entity structure and hence filtered out here

GO

-- sales order details is the fact table, to provide detail sales order lines including order date, qty, amount and associated dimension keys
CREATE OR ALTER VIEW dbo.salesorderdetails
AS
select 
	cast(salesline.CREATEDDATETIME as date)  as [Order Date],
	cast(salesline.SALESID as varchar(40))  as [Order Id],
	cast(salesline.INVENTTRANSID + '_' + salesline.DATAAREAID as varchar(100)) as [Order Line Id],
	cast(salesline.ITEMID as varchar(40)) as [Product],
	salesline.SALESQTY as [Sales Qty], 
	cast(salesline.SALESUNIT as varchar(10)) as [Sales Unit],  
	salesline.SALESPRICE as [Unit Price], 
	salesline.LINEAMOUNT as [Line Amount], 
	cast(salesline.CURRENCYCODE as varchar(40)) as [Currency Code], 
    --(select top 1 EnumLabel from GetEnumTranslations('SalesStatus', salesline.SALESSTATUS, 'en-us')) as [Order Status], 
	case  salesline.SALESSTATUS 
		when 1 then 'Open Order'
		when 2 then 'Delivered'
		when 3 then 'Invoiced'
		when 4 then 'Canceled'
		end 
	as [Order Status],
	salesline.DATAAREAID as legalentity,
	customer.RECID as customerid,
	company.RECID as legalentityid,
	inventtable.RECID as productid
from SALESLINE as salesline
left outer join CUSTTABLE customer
	on customer.ACCOUNTNUM = salesline.CUSTACCOUNT and customer.DATAAREAID = salesline.DATAAREAID
left outer join DIRPARTYTABLE company
	on  lower(salesline.DATAAREAID) = lower(company.DATAAREA)
left outer join  INVENTTABLE inventtable
	on  salesline.ITEMID = inventtable.ITEMID and salesline.DATAAREAID = inventtable.DATAAREAID

