DECLARE @json NVARCHAR(MAX);
Declare @DataSource nvarchar(50);
SET @json = N'{
  "application": "Dynamics 365 for Finance and Operations",
  "name": "CUSTGROUP",
  "entities": [
    {
      "$type": "LocalEntity",
	   "name": "CUSTGROUP",
      "description": "CUSTGROUP",
      "attributes": [
        {
          "name": "RECID",
          "description": "RECID",
          "dataType": "int64"
        }],
		 "partitions": [
        {
          "name": "CUSTGROUP",
          "location": "https://adls.dfs.core.windows.net/DynamicsAX/TABLEs/CUSTGROUP.csv"
        }]
	  }]
	  }';
set @DataSource  = N'SqlOnDemandDemo'; -- replace this with the name of datasource to connect storage account 

declare @ViewDefinition varchar(max)

select  @ViewDefinition = COALESCE(@ViewDefinition + ',', '') + fieldName 
+ ' ' + 
case  dataType
when 'int64'  then 'bigint'
when 'int32' then  'int'
when 'dateTime'  then  'varchar(100)'
when 'decimal' then 'decimal'
when 'double' then 'float'
when 'boolean'  then 'bit'
when 'string' then 'varchar(800)'
end + ' '
FROM OPENJSON(@json)
  WITH (
     entities NVARCHAR(MAX) '$.entities' AS JSON
  )
  OUTER APPLY OPENJSON(entities)
  WITH 
  ( attributes NVARCHAR(MAX) '$.attributes' AS JSON,
  partitions NVARCHAR(MAX) '$.partitions' AS JSON
  )
   OUTER APPLY OPENJSON(attributes)
  WITH (fieldName nvarchar(100) '$.name',
        dataType nvarchar(50) '$.dataType')

 
select 
@ViewDefinition = 'CREATE or ALTER VIEW ' + entityName 
+' AS SELECT * FROM OPENROWSET(BULK '''+ location + ''',  DATA_SOURCE = '''+ @DataSource + ''', FORMAT = ''CSV'', Parser_Version= ''2.0'') 
WITH (' + @ViewDefinition + ') as r'
FROM OPENJSON(@json)
  WITH (
     entities NVARCHAR(MAX) '$.entities' AS JSON
  )
  OUTER APPLY OPENJSON(entities)
  WITH 
  ( 
    entityName nvarchar(100) '$.name',
    partitions NVARCHAR(MAX) '$.partitions' AS JSON
  )
  OUTER APPLY OPENJSON(partitions)
  WITH (location nvarchar(1000) '$.location') ;

   select @ViewDefinition as ViewDefinition