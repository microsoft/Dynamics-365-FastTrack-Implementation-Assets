declare @tableNames varchar(max) = 'GeneralJournalEntry,GeneralJournalAccountEntry,Ledger,DimensionFinancialTag,DimensionAttributeValueCombination,DirPartyTable,OMOperatingUnit,MainAccount,DimensionAttribute,DimensionAttributeDirCategory';

Select 
X.Table_Name,
X.Data_Path,
X.Manifest_Path,
X.Manifest_Name,
'NO_PARTITION' as Partition_Strategy,
'CREATEDDATETIME' as Partition_DateColumn
from (
SELECT 
'Tables/' + r.filepath(1) + '/'+ r.filepath(2) + '/' + r.filepath(3) + '/'+ r.filepath(4) + '/' + r.filepath(5)  as [Data_Path],
'Tables/' + r.filepath(1) + '/'+ r.filepath(2) + '/' + r.filepath(3) + '/'+ r.filepath(4)    as [Manifest_Path],
r.filepath(4)    as [Manifest_Name],
r.filepath(5) as [Table_Name]
FROM OPENROWSET(BULK 'Tables/*/*/*/*/*/index.json', FORMAT = 'CSV', fieldterminator ='0x0b',fieldquote = '0x0b'
, DATA_SOURCE ='dynamics365_financeandoperations_finance_sandbox_EDS') 
with (firstCol nvarchar(1000)) as r group by r.filepath(1) , r.filepath(2), r.filepath(3) , r.filepath(4), r.filepath(5)
union 
SELECT 
'Tables/' + r.filepath(1) + '/'+ r.filepath(2) + '/' + r.filepath(3) + '/'+ r.filepath(4)  as [Data_Path],
'Tables/' + r.filepath(1) + '/'+ r.filepath(2) + '/' + r.filepath(3)     as [Manifest_Path],
r.filepath(3)    as [Manifest_Name],
r.filepath(4) as [Table_Name]

FROM OPENROWSET(BULK 'Tables/*/*/*/*/index.json', FORMAT = 'CSV', fieldterminator ='0x0b',fieldquote = '0x0b'
, DATA_SOURCE ='dynamics365_financeandoperations_finance_sandbox_EDS') 
with (firstCol nvarchar(1000)) as r group by r.filepath(1) , r.filepath(2), r.filepath(3) , r.filepath(4)
union 
SELECT 
'Tables/' + r.filepath(1) + '/'+ r.filepath(2) + '/' + r.filepath(3)   as [Data_Path],
 r.filepath(3) as [Table_Name],
'Tables/' + r.filepath(1) + '/'+ r.filepath(2)      as [Manifest_Path],
r.filepath(2)    as [Manifest_Name]
FROM OPENROWSET(BULK 'Tables/*/*/*/index.json', FORMAT = 'CSV', fieldterminator ='0x0b',fieldquote = '0x0b'
, DATA_SOURCE ='dynamics365_financeandoperations_finance_sandbox_EDS') 
with (firstCol nvarchar(1000)) as r group by r.filepath(1) , r.filepath(2), r.filepath(3) 
) X 
where X.[Table_Name] not in  (select value from string_split(@tableNames, ',') )
for  JSON  PATH