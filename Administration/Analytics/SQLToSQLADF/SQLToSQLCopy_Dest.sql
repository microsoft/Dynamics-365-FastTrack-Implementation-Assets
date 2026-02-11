
/***** Creating schema sqltosql *****/
IF NOT EXISTS ( SELECT  *
                FROM    sys.schemas
                WHERE   name = N'sqltosql' )
    EXEC('CREATE SCHEMA [sqltosql]');
GO

/****** Object:  StoredProcedure [sqltosql].[MERGECT]    Script Date: 4/6/2021 12:41:33 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

-- prepare merge stateement and execute to merge cdc data to main table
CREATE OR ALTER  PROC [sqltosql].[MERGECT]
(
    -- Add the parameters for the stored procedure here
    @TargetTable nvarchar(100),
    @CDCTable nvarchar(100)
)
AS
BEGIN
    -- SET NOCOUNT ON added to prevent extra result sets from
    -- interfering with SELECT statements.
    SET NOCOUNT ON

--Declare @TargetTable nvarchar(100) = 'AXDB.CUSTGROUP';
--Declare @CDCTable nvarchar(100) ='CDC.CUSTGROUP'

declare @UpdateColumns nvarchar(max);
declare @Columns nvarchar(max);
Select @UpdateColumns = COALESCE(@UpdateColumns + ', ', '') + 'T.' + x.COLUMN_NAME + ' = S.'  + x.COLUMN_NAME,
  @Columns = COALESCE(@Columns + ', ', '')  + x.COLUMN_NAME 
 from INFORMATION_SCHEMA.COLUMNS x 
WHERE TABLE_NAME = right(@TargetTable,Len(@TargetTable) -charindex('.',@TargetTable)  )
and  TABLE_SCHEMA = Left(@TargetTable,charindex('.',@TargetTable)-1)

select @UpdateColumns, @Columns

Declare @MergeStatement nvarchar(max);

set @MergeStatement 
=  ' MERGE ' + @TargetTable + ' T USING '+ @CDCTable + ' S' + 
' ON ' +   sqltosql.SQLToSQL_GetJoinStatement(@TargetTable, 'T', 'S') +
' WHEN MATCHED and S.SYS_CHANGE_OPERATION = ''U''' +
'    THEN UPDATE SET ' +
 @UpdateColumns +
' WHEN NOT MATCHED BY TARGET THEN INSERT (' + 
@Columns +
')	Values (' +
@Columns + 
')' +
' WHEN MATCHED and S.SYS_CHANGE_OPERATION = ''D''' +
' THEN DELETE;' +
'Drop TABLE ' + @CDCTable; 
--select @MergeStatement
Execute sp_executesql  @MergeStatement;
 
END
GO

/****** Object:  StoredProcedure [sqltosql].[SQLToSQL_CreatePrimaryIndex]    Script Date: 4/6/2021 12:42:05 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER  PROCEDURE [sqltosql].[SQLToSQL_CreatePrimaryIndex] @TableName NVARCHAR(100), @Schema NVARCHAR(10), @primaryIndexColumns NVARCHAR(200)
AS

DECLARE @IndexColumns table(ColumnName NVARCHAR(40) NOT NULL);
INSERT INTO @IndexColumns 
SELECT value FROM string_split(@primaryIndexColumns, ',')
SELECT * FROM @IndexColumns;

DECLARE @AlterScript VARCHAR(MAX) 
SELECT  @AlterScript = COALESCE( @AlterScript + + ';', '')+ 'ALTER TABLE ' + @schema +'.' + @TableName + '  ALTER COLUMN  ' +  C.COLUMN_NAME  + ' ' 
+ C.data_type 
+ CASE data_type
            WHEN 'sql_variant' THEN ''
            WHEN 'text' THEN ''
            WHEN 'ntext' THEN ''
            WHEN 'xml' THEN ''
            WHEN 'decimal' THEN '(' + CAST(numeric_precision AS VARCHAR) + ', ' + CAST(numeric_scale AS VARCHAR) + ')'
            ELSE coalesce('('+ CASE WHEN character_maximum_length = -1 THEN 'MAX' ELSE CAST(character_maximum_length AS VARCHAR) END +')','') END 
+ '  NOT NULL'
       FROM INFORMATION_SCHEMA.COLUMNS c
       JOIN @IndexColumns on ColumnName = C.COLUMN_NAME 
              WHERE c.TABLE_NAME = @TableName
                     AND c.TABLE_SCHEMA = @Schema

					 select @AlterScript

EXEC (@AlterScript)

Declare @SQLIdx nvarchar(300)=  FORMATMESSAGE('ALTER TABLE %s  ADD CONSTRAINT PK_%s_Idx PRIMARY KEY CLUSTERED (%s);', @Schema+ '.' +@TableName, @TableName, @primaryIndexColumns );

EXEC (@SQLIdx)

GO

/****** Object:  UserDefinedFunction [sqltosql].[SQLToSQL_GetJoinStatement]    Script Date: 4/6/2021 12:48:52 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER  FUNCTION [sqltosql].[SQLToSQL_GetJoinStatement]
(
	@SOURCETABLENAME VARCHAR(50),
	@SOURCEALIAS varchar(20) = 'SOURCE', 
	@CTALIAS varchar(20) = 'CT'
)
RETURNS VARCHAR(MAX)
AS
BEGIN

declare @ONSTATEMENT varchar(8000);

Declare @Schema nvarchar(100) ;
Declare @TableName nvarchar(100) ;

set @Schema = left(@SOURCETABLENAME,CHARINDEX('.', @SOURCETABLENAME)-1)
set @TableName = right(@SOURCETABLENAME,len(@SOURCETABLENAME) - CHARINDEX('.',@SOURCETABLENAME))

select  @ONSTATEMENT = COALESCE(@ONSTATEMENT + ' AND ', '') +  @SOURCEALIAS + '.' + C.Name + ' = ' + @CTALIAS + '.' + C.name 
from sys.columns c
join sys.objects o
on c.object_id = o.object_id and o.schema_id = SCHEMA_ID(@Schema) 
Inner JOIN 
    sys.index_columns ic ON ic.object_id = c.object_id AND ic.column_id = c.column_id
Inner JOIN 
    sys.indexes i ON ic.object_id = i.object_id AND ic.index_id = i.index_id and i.is_primary_key = 1
where o.name = @TableName and o.schema_id = SCHEMA_ID(@Schema)

return @ONSTATEMENT
End

GO