/* 
This script is to help create a simple dimentional data model on Dynamics 365 for Finance and Operations tables enabled via Fabric link 
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
Table-Valued Functions: [dbo].[GetEnumTranslations]


Pre-requisites: You must have a Fabrik link/Synapse link setup with D365FO environment 
Following tables are enabled 
1. dirpartytable
2. companyinfo
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
"Party" in D365 FnO represents any entity or individual that can enter into a business relationship. Party can be customer, vendor, employee
"Global address book" stores party records and physical address and electronic address in central tables.  
 Following view provides common and simple representation of the party to include the key fields 
 partyid, name, primary address, primary phone number and email    
*/
CREATE OR ALTER VIEW dirpartyprimary_view
As
SELECT 
	party.recid as [partyid]
	,party.name AS [Name]
	,isnull(party.namealias, '') AS [Short Name]
	,isnull(postal.countryregionid, '') AS [Country]
	,isnull(postal.state, '') AS [State]
	,isnull(postal.city, '') AS City
	,isnull(postal.districtname, '') AS District
	,isnull(postal.street, '') AS Street
	,isnull(postal.zipcode, '') AS [Zip Code]
	,isnull(phone.locator, '') AS [Phone Number]
	,isnull(email.locator, '') AS [Email]
FROM dbo.dirpartytable party 
LEFT OUTER JOIN dbo.logisticspostaladdress postal ON postal.location = party.primaryaddresslocation
AND postal.validto > getutcdate() -- filters only valid(effective) addresses
LEFT OUTER JOIN dbo.logisticselectronicaddress phone ON phone.recid = party.primarycontactphone
LEFT OUTER JOIN dbo.logisticselectronicaddress email ON email.recid = party.primarycontactemail

GO

/* 
Many times  financial dimension such as business unit, cost center, department etc are use to represent segments 
master data/dimension such as customers, products,vendors etc. 
This concept is refered as Default Financial Dimension in Finance and Operations and in the backend is stored in normalized  
defaultfinancialdimension_view is simple representation of default financial dimension to extract such as business unit, cost center, department etc, 
*/
create or alter view defaultfinancialdimension_view
as 
	select 
		t1.displayvalue as dimensionvalue, 
		t1.dimensionattributevalueset as defaultdimensionid, 
		t3.name as dimensionname
		from dimensionattributevaluesetitem t1 
	join dimensionattributevalue t2 on t1.dimensionattributevalue  =  t2.recid
	join dimensionattribute t3 on t2.dimensionattribute  =  t3.recid

GO

/* One of the important reporting task when dealing with reporting is BI to decode the concept of the FnO is Enums.
The primary purpose of using an enum is to define collections of constants that are logically related to each other. 
Example of enum could be SalesStatus = (1-OpenOrder,2-Delivered,3-Invoiced,4-Canceled etc)
In the backend system enums are stored in the integer value, however in the front end they are represent as more meaningfull text value 
In Fabric link and Synapse link tables stores in integer representation of the enum. 
You can fined the mapping enum to string in the GlobalOptionsetMetadata table. 

This generic implementation of a table value function can return all the enum translation for a given table that can be further 
used to get translalted string value as column value for given table.

Code is 

A simple example use of this 

select 
salesline.salesstatus,
JSON_VALUE(enum.enumtranslation, CONCAT('$.salesstatus."', salesline.salesstatus,'"'))  as [Order Status]
from salesline salesline
cross apply GetEnumTranslations('salesline', '1033') as enum
group by salesline.salesstatus, enum.enumtranslation
salesstatus	Order Status
1	Open order
2	Delivered
3	Invoiced
4	Canceled
*/
CREATE or ALTER FUNCTION GetEnumTranslations (@tablename varchar(200), @langcode varchar(10)='1033')
RETURNS TABLE
AS
RETURN (
    SELECT 
        CONCAT('{' , STRING_AGG(CONVERT(NVARCHAR(MAX), idvalue),',') , '}') AS enumtranslation
    FROM 
    (
        SELECT 
            CONCAT('"', OptionSetName, '":{'
            , STRING_AGG(CONVERT(NVARCHAR(MAX), CONCAT('"', [Option], '":"', [LocalizedLabel], '"')), ',') 
            , '}') AS idvalue
        FROM GlobalOptionsetMetadata 
        WHERE EntityName = @tablename
        AND LocalizedLabelLanguageCode = @langcode
        GROUP BY OptionSetName
    ) x
);

GO

-- customers view to provides, basic customer account details, name, primary address and segmentation
CREATE OR ALTER VIEW dbo.customers 
AS
SELECT 
	customer.recid AS customerid
	,customer.accountnum AS [Customer Account Number]
	,customer.dataareaid AS [Legal Entity]
	,custgroup.name as [Customer Group]
	,party.*
	,isnull(bu.dimensionvalue,'')  as [Business Unit]
FROM dbo.custtable customer -- customer table
join dbo.dirpartyprimary_view as party on customer.party = party.partyid
left outer join dbo.custgroup custgroup on custgroup.custgroup = customer.custgroup and custgroup.dataareaid = customer.dataareaid
left outer join dbo.defaultfinancialdimension_view bu on bu.defaultdimensionid = customer.defaultdimension and bu.dimensionname = 'BusinessUnit'
GO

-- employee view provides, employee number, name, primary address
CREATE OR ALTER VIEW dbo.employee
AS
SELECT 
	worker.recid AS employeeid
	,worker.personnelnumber AS [Employee Number]
	,party.*
FROM hcmworker worker
join dbo.dirpartyprimary_view as party on worker.person = party.partyid
GO


-- vendor view provides, basic vendor/supplier details, name, primary address
CREATE OR ALTER VIEW dbo.vendors
AS
SELECT 
	vendor.recid AS vendorid
	,vendor.accountnum as [Vendor Account]
	,vendor.dataareaid as [Legal Entity]
	,party.*
FROM vendtable vendor
join dbo.dirpartyprimary_view as party on vendor.party = party.partyid

GO 

-- product view to provides, product number, short name and detail product description
CREATE OR ALTER VIEW dbo.products
AS
SELECT it.recid AS productid
	,p.displayproductnumber AS [Product Number]
	,pt.name [Product Name]
	,it.itemid AS [Item Number]
	,it.namealias [Item Short Name]
	,it.dataareaid [Legal Entity]
FROM dbo.inventtable AS it
LEFT OUTER JOIN dbo.ecoresproduct p ON p.recid = it.product
LEFT OUTER JOIN dbo.ecoresproducttranslation pt ON it.product = pt.product
	AND pt.languageid = 'en-us'
	
GO

-- legal entity view to provides, id, code and name and primary address details
CREATE OR ALTER VIEW dbo.legalentity
AS	
SELECT 
	company.recid AS legalentityid
	,company.dataarea AS [Legal Entity]
	,party.*
FROM dbo.companyinfo company
join dbo.dirpartyprimary_view as party on company.recid = party.partyid
WHERE company.dataarea NOT IN ('dat') -- dat is default company that typically not represent the actual legal entity structure and hence filtered out here

GO

-- sales order details is the fact table, to provide detail sales order lines including order date, qty, amount and associated dimension keys
CREATE OR ALTER VIEW dbo.salesorderdetails
AS
select 
	cast(salesline.createddatetime as date)  as [Order Date],
	cast(salesline.salesid as varchar(40))  as [Order Id],
	cast(salesline.inventtransid + '_' + salesline.dataareaid as varchar(100)) as [Order Line Id],
	cast(salesline.itemid as varchar(40)) as [Product],
	salesline.salesqty as [Sales Qty], 
	cast(salesline.salesunit as varchar(10)) as [Sales Unit],  
	salesline.salesprice as [Unit Price], 
	salesline.lineamount as [Line Amount], 
	cast(salesline.currencycode as varchar(40)) as [Currency Code], 
    --cast(JSON_VALUE(enum.enumtranslation, CONCAT('$.salesstatus."', salesline.salesstatus,'"'))  as varchar(40))  
	case  salesline.salesstatus 
		when 1 then 'Open Order'
		when 2 then 'Delivered'
		when 3 then 'Invoiced'
		when 4 then 'Canceled'
		end 
	as [Order Status],
	salesline.dataareaid as legalentity,
	customer.recid as customerid,
	company.recid as legalentityid,
	inventtable.recid as productid
from salesline as salesline
left outer join custtable customer
	on customer.accountnum = salesline.custaccount and customer.dataareaid = salesline.dataareaid
left outer join companyinfo company
	on  lower(salesline.dataareaid) = lower(company.dataarea)
left outer join  inventtable
	on  salesline.itemid = inventtable.itemid and salesline.dataareaid = inventtable.dataareaid
--left outer join GetEnumTranslations('salesline', '1033') as enum on 1=1





