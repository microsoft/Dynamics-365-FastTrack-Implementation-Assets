
CREATE OR ALTER PROCEDURE load_customers 
AS 
BEGIN

DROP TABLE IF EXISTS dbo.customers
CREATE TABLE dbo.customers AS
	select 
		'D365' as SourceSystem
		,'D365_'+ cast(customerid as varchar(80))as customerid 
		,[Customer Account Number]
		, [Customer Group]
		, partyid
		, Name
		, [Short Name]
		, [Country]
		, [State]
		, [City]
		, [District]
		, [Street]
		, [Zip Code]
		, [Phone Number]
		, [Email]
		, [Business Unit]
	from [dataverse_jjd365unodev_d365analyticsfabriclake_unqd3fc845080daee1190486045bd016_1].dbo.customers
union
select 
	'AX2012' as SourceSystem
	,'AX2012_'+ cast(c.customerid as varchar(80))as customerid 
	,c.[Customer Account Number]
	, c.[Customer Group]
	, c.partyid
	, c.Name
	, c.[Short Name]
	, c.[Country]
	, c.[State]
	, c.[City]
	, c.[District]
	, c.[Street]
	, c.[Zip Code]
	, c.[Phone Number]
	, c.[Email]
	, c.[Business Unit]
from Legacy_AX_2012_Data.dbo.customers c
LEFT JOIN [dataverse_jjd365unodev_d365analyticsfabriclake_unqd3fc845080daee1190486045bd016_1].dbo.customers n
ON c.[Customer Account Number] = n.[Customer Account Number] AND c.[Legal Entity] = n.[Legal Entity]
WHERE n.[Customer Account Number] IS NULL

END 

GO 

CREATE OR ALTER PROCEDURE load_legalentity 
AS 

BEGIN
DROP TABLE IF EXISTS dbo.legalentity
CREATE TABLE dbo.legalentity AS
SELECT 
	'D365' as SourceSystem
	,'D365_'+ cast(legalentityid as varchar(80))as legalentityid
	, Name
	,[Legal Entity]
	, [Short Name]
	, [Country]
	, [State]
	, [City]
	, [District]
	, [Street]
	, [Zip Code]
	from [dataverse_jjd365unodev_d365analyticsfabriclake_unqd3fc845080daee1190486045bd016_1].dbo.legalentity
UNION
SELECT 
	'AX2012' as SourceSystem
	,'AX2012_'+ cast(c.legalentityid as varchar(80))as legalentityid
	, c.[Legal Entity]
	, c.Name
	, c.[Short Name]
	, c.[Country]
	, c.[State]
	, c.[City]
	, c.[District]
	, c.[Street]
	, c.[Zip Code]
from Legacy_AX_2012_Data.dbo.legalentity c
LEFT JOIN [dataverse_jjd365unodev_d365analyticsfabriclake_unqd3fc845080daee1190486045bd016_1].dbo.legalentity n
ON lower(c.[Legal Entity]) = lower(n.[Legal Entity])
WHERE n.[Legal Entity] IS NULL
END

GO


CREATE OR ALTER PROCEDURE load_products 
AS 

BEGIN

DROP TABLE IF EXISTS dbo.products
CREATE TABLE dbo.products AS
SELECT 
	'D365' as SourceSystem
	,newid() as Id
	,'D365_'+ cast(productid as varchar(80))as productid
	,[Product Number]
	,[Product Name]
	,[Item Number]
	,[Item Short Name]
	,[Legal Entity]
from [dataverse_jjd365unodev_d365analyticsfabriclake_unqd3fc845080daee1190486045bd016_1].dbo.products
UNION 
SELECT 
	'AX2012' as SourceSystem
	,newid() as ID
	,'AX2012_'+ cast(c.productid as varchar(80))as productid
	,c.[Product Number]
	,c.[Product Name]
	,c.[Item Number]
	,c.[Item Short Name]
	,c.[Legal Entity]
from Legacy_AX_2012_Data.dbo.products  c
LEFT JOIN [dataverse_jjd365unodev_d365analyticsfabriclake_unqd3fc845080daee1190486045bd016_1].dbo.products n
ON c.[Product Number] = n.[Product Number] and lower(c.[Legal Entity]) = lower(n.[Legal Entity])
WHERE n.[Product Number] IS NULL

END

GO

CREATE OR ALTER PROCEDURE load_salesorderdetails 
AS 

BEGIN

DROP TABLE IF EXISTS dbo.salesorderdetails
CREATE TABLE dbo.salesorderdetails AS
SELECT 
'D365' as SourceSystem
, newid() as ID
, [Order Date]
, [Order Line Id]
, [Order Id]
, [Product]
, [Sales Qty]
, [Sales Unit]
, [Unit Price]
, [Line Amount]
, [Currency Code]
, [Order Status]
, legalentity
,'D365_'+ cast(customerid as varchar(80))as customerid 
,'D365_'+ cast(legalentityid as varchar(80))as legalentityid
,'D365_'+ cast(productid as varchar(80))as productid	
from [dataverse_jjd365unodev_d365analyticsfabriclake_unqd3fc845080daee1190486045bd016_1].dbo.salesorderdetails
UNION 
SELECT 
'AX2012' as SourceSystem
, newid() as ID
, case 
	when c.[Order Date] = '1900-01-01' then '2015-01-01' 
	else c.[Order Date] end as [Order Date]
, c.[Order Id]
, c.[Order Line Id]
, c.[Product]
, c.[Sales Qty]
, c.[Sales Unit]
, c.[Unit Price]
, c.[Line Amount]
, c.[Currency Code]
, c.[Order Status]
, c.legalentity
,'AX2012_'+ cast(c.customerid as varchar(80))as customerid 
,case when le.legalentityid is not null then 'D365_' else 'AX2012_' end + cast(c.legalentityid as varchar(80))  as legalentityid
,'AX2012_'+ cast(c.productid as varchar(80))as productid	
from Legacy_AX_2012_Data.dbo.salesorderdetails c
left join  [dataverse_jjd365unodev_d365analyticsfabriclake_unqd3fc845080daee1190486045bd016_1].dbo.legalentity le
on lower(c.legalentity) = lower(le.[Legal Entity]) 
LEFT JOIN [dataverse_jjd365unodev_d365analyticsfabriclake_unqd3fc845080daee1190486045bd016_1].dbo.salesorderdetails n
ON c.[Order Id] = n.[Order Id] and  lower(c.[legalentity]) = lower(n.[legalentity])
WHERE n.[Order Id] IS NULL

END