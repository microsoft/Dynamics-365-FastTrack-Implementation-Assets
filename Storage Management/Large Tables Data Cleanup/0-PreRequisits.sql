drop table dbo.FTInformationcolums
SELECT * into FTInformationcolums FROM (
select isc.*, sdf.TABLEID from [INFORMATION_SCHEMA].[COLUMNS] isc
inner join
(select SQLName,TABLEID from SQLDICTIONARY sd where sd.FIELDID = 0 and sd.ARRAY = 0) sdf on isc.Table_Name = sdf.SQLNAME
		inner join TABLEMETADATATABLE TMT ON TMT.TABLEID = sdf.TABLEID
		where (TMT.TABLEGROUP IN (4, 5, 6, 9, 10, 11) or SDF.SQLNAME in ('WHSASNITEM', 'WHSASNITEMRECEIPT', 'WHSUOMSTRUCTURE')) 
		and data_type =  'datetime'
  ) selection
