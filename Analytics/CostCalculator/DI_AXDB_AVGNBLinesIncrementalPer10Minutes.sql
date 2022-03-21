
Select avgrowsper10min = AVG(nbRecordsperhour/6)
from
(
	select 
		CAST(FORMAT(DDGEH.ENDDATETIME,'yyyy-MM-dd HH:0') AS datetime) as formatedHours, 
		Sum(NOOFRECORDS) nbRecordsperhour, 
		DDGE.ENTITY  
	from 
		DMFDEFINITIONGROUPEXECUTION DDGEH
		inner join
		DMFDEFINITIONGROUPENTITY DDGE on DDGEH.DEFINITIONGROUP = DDGE.DEFINITIONGROUP
		inner join 
		DMFDATASOURCE DDS on DDS.PARTITION = DDGE.PARTITION and DDGE.DEFAULTREFRESHTYPE = 0 -- refreshtype 0 is incremental 
		and DDS.SOURCENAME = DDGE.SOURCE 
	where 
		TYPE = 4 --AX DB Type = 4
	group by CAST(FORMAT(DDGEH.ENDDATETIME,'yyyy-MM-dd HH:0') AS datetime), DDGE.ENTITY
) recordsperhour
