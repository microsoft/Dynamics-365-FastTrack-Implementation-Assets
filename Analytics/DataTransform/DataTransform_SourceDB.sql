create or alter proc [dbo].[GetMetadata](@TargetTableName nvarchar(100))
AS
Begin
--declare @TargetTableName nvarchar(100)= 'Sales.Customer_Dim';    

Declare @Schema nvarchar(100) ;
Declare @TableName nvarchar(100) ;

set @Schema = left(@TargetTableName,CHARINDEX('.', @TargetTableName)-1)
set @TableName = right(@TargetTableName,len(@TargetTableName) - CHARINDEX('.',@TargetTableName))

SELECT  TABLE_NAME
       ,STUFF((SELECT ', ' + CAST(COLUMN_NAME AS VARCHAR(100)) [text()]
         FROM INFORMATION_SCHEMA.COLUMNS 
         WHERE TABLE_NAME = t.TABLE_NAME and TABLE_SCHEMA = t.TABLE_SCHEMA
		 and COLUMN_NAME not in ('IsDeleted','UpdateDateTime')
		 order by Ordinal_position Asc
         FOR XML PATH(''), TYPE)
        .value('.','NVARCHAR(MAX)'),1,2,' ') COLUMN_NAME
FROM INFORMATION_SCHEMA.COLUMNS t
WHERE TABLE_NAME = @TableName
and  TABLE_SCHEMA = @Schema
GROUP BY TABLE_NAME, TABLE_SCHEMA
End 
GO






