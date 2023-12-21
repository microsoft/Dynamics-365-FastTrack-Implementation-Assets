
-- Create the _sales schema if it does not exist
if not exists (select * from sys.schemas where name = '_sales')
begin
    exec('create schema _sales')
end

go

-- Create or alter the customer dimension table 
create  or alter  view [_sales].[customer_dim] as
(
	select 
		ct.recid as customerid
		,ct.accountnum as [account number]
		,ct.dataareaid as [legal entity]
		,dpt.name as [name]
		,isnull(dpt.namealias, '') as [search name]
		,isnull(lpa.countryregionid, '') as [country]
		,isnull(lpa.state, '')as [state]
		,isnull(lpa.city,'') as city
		,isnull(lpa.district,'') as district
		,isnull(lpa.street, '') as street
		,isnull(lpa.zipcode, '') as zipcode
		,isnull(lea_phone.locator, '') as [phone number]
		,isnull(lea_email.locator, '') as [email]
	from dbo.custtable ct
	join dbo.dirpartytable dpt on ct.party = dpt.recid
	left outer join dbo.dirpartylocation dpl_lpa on dpl_lpa.party =  dpt.recid and dpl_lpa.isprimary = 'Yes' and dpl_lpa.ispostaladdress = 'Yes' 
	left outer join dbo.logisticspostaladdress lpa on dpl_lpa.location = lpa.location and lpa.validto > getutcdate()
	left outer join dbo.dirpartylocation dpl_lea on dpl_lea.party =  dpt.recid and dpl_lea.isprimary = 'Yes' and dpl_lea.ispostaladdress = 'No'
	left outer join dbo.logisticslocation ll_lea on ll_lea.recid = dpl_lea.location
	left outer join dbo.logisticselectronicaddress lea_phone on lea_phone.location = ll_lea.recid and lea_phone.type = 'Phone'
	left outer join dbo.logisticselectronicaddress lea_email on lea_email.location = ll_lea.recid and lea_email.type = 'Email'
)

GO

-- Create or alter the legal entity dimension table 
CREATE OR ALTER   view [_sales].[legalentity_dim] as
with  countryregion as (select 
    countrycode,
    case 
        when countrycode in ('fra', 'gbr', 'deu', 'rus') then 'europe'
        when countrycode in ('ind', 'tha', 'sau', 'mys', 'chn', 'jpn') then 'apac'
        when countrycode in ('usa', 'mex') then 'northamerica'
        when countrycode = 'bra' then 'southamerica'
        else 'unknown'
    end as continent
from (select value as countrycode  from string_split('fra,gbr,ind,tha,deu,sau,mys,chn,bra,rus,usa,jpn,mex', ',')) as x
)
select 
c.recid as legalentityid,
c.dataarea as [legal entity], 
dpt.name as [legal entity name]
,isnull(lpa.countryregionid, '') as [country]
,isnull(cr.continent, '') as [continent]
,isnull(lpa.state, '')as [state]
,isnull(lpa.city,'') as city
,isnull(lpa.street, '') as street
,isnull(lpa.zipcode, '') as zipcode
from 
dbo.companyinfo c
join dbo.dirpartytable as dpt on c.recid = dpt.recid
left outer join dbo.dirpartylocation dpl_lpa on dpl_lpa.party =  dpt.recid and dpl_lpa.isprimary = 'Yes' and dpl_lpa.ispostaladdress = 'Yes'
left outer join dbo.logisticspostaladdress lpa on dpl_lpa.location = lpa.location and lpa.validto > getutcdate()	
left outer join countryregion cr on cr.countrycode = lpa.countryregionid
where c.dataarea not in ('dat', 'us01')


GO

-- Create or alter the prodcut dimension table 
CREATE OR ALTER   view [_sales].[product_dim] as
(
	select  
		it.recid as productid,
		p.displayproductnumber as [product number],
		pt.name [product name],
		it.itemid as [item number],
		it.namealias [item short name],
		it.dataareaid [legal entity]
	from dbo.inventtable as it
	left outer join dbo.ecoresproduct p on p.recid = it.product
	left outer join dbo.ecoresproducttranslation pt on it.product = pt.product and pt.languageid = 'en-us'
)

GO

-- Create or alter the order line fact table 
CREATE OR ALTER     view [_sales].[orderlineitem_fact] as
(
	select 
		cast(dateadd(day, abs(checksum(newid())) % (datediff(day, '2023-01-01', '2023-12-31') + 1), '2023-01-01') as date) as orderdate,
		l.salesid  as [order id],
		l.inventtransid + '_' + l.dataareaid as [order line id],
		salesqty as [sales qty], 
		salesunit as [sales unit],  
		salesprice as [unit price], 
		lineamount as [line amount], 
		--case l.salesstatus  
		-- when 1 then 'open'
		-- when 2 then 'delivered'
		-- when 3 then 'invoiced'
		-- when 4 then 'canceled'
		--end
		l.salesstatus as [sales status],
		cd.customerid as customerid,
		le.legalentityid as legalentityid,
		pd.productid as productid,
		l.itemid
	from salesline as l
	left outer join _sales.customer_dim cd 
		on cd.[account number] = l.custaccount and cd.[legal entity] = l.dataareaid
	left outer join _sales.legalentity_dim le 
		on  le.[legal entity] = l.dataareaid
	left outer join  _sales.product_dim pd 
		on  l.itemid = pd.[item number] and l.dataareaid = pd.[legal entity]
)
GO

