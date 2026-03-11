/***** Enabling change tracking on Source database ******/
IF NOT EXISTS (SELECT * 
	FROM sys.change_tracking_databases 
	WHERE database_id=DB_ID('AXDB_Source'))
BEGIN
	ALTER DATABASE AXDB_Source  
	SET CHANGE_TRACKING = ON  
	(CHANGE_RETENTION = 2 DAYS, AUTO_CLEANUP = ON)
END

/***** Creating schema sqltosql *****/
IF NOT EXISTS ( SELECT  *
                FROM    sys.schemas
                WHERE   name = N'sqltosql' )
    EXEC('CREATE SCHEMA [sqltosql]');
GO

/****** Object:  Table [sqltosql].[SQLToSQLDATASYNCSETUP]    Script Date: 4/6/2021 12:37:59 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

IF NOT EXISTS (SELECT * FROM SYSOBJECTS WHERE NAME='SQLToSQLDATASYNCSETUP' AND XTYPE='U')
CREATE TABLE [sqltosql].[SQLToSQLDATASYNCSETUP](
	[TABLENAME] [varchar](200) NOT NULL,
	[TARGETTABLENAME] [varchar](200) NOT NULL,
	[CHANGEVERSION] [bigint] NOT NULL,
	[PUBLISHED] [int] NULL,
	[STATUS] [int] NULL,
	[CREATEDDATETIME] [datetime] NULL,
	[MODIFIEDDATETIME] [datetime] NULL,
	[FULLEXPORTSCRIPT] [nvarchar](max) NULL,
	[INCREMENTALEXPORTSCRIPT] [nvarchar](max) NULL,
	[PRIMARYINDEXCOLUMNS] [nvarchar](max) NULL,
 CONSTRAINT [PK_SQLToSQLDATASYNCSETUP_TABLENAME] PRIMARY KEY CLUSTERED 
(
	[TABLENAME] ASC
)WITH (STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY],
 CONSTRAINT [AK_SQLToSQLDATASYNCSETUP_TARGETTABLENAME] UNIQUE NONCLUSTERED 
(
	[TARGETTABLENAME] ASC
)WITH (STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]
GO

/****** Object:  UserDefinedFunction [sqltosql].[SQLToSQL_GenerateFieldList]    Script Date: 4/6/2021 12:47:26 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER  FUNCTION [sqltosql].[SQLToSQL_GenerateFieldList]
(
	@SOURCETABLENAME VARCHAR(200)
)
RETURNS VARCHAR(MAX)
AS
BEGIN

Declare @Schema nvarchar(100) ;
Declare @TableName nvarchar(100) ;

set @Schema = left(@SOURCETABLENAME,CHARINDEX('.', @SOURCETABLENAME)-1)
set @TableName = right(@SOURCETABLENAME,len(@SOURCETABLENAME) - CHARINDEX('.',@SOURCETABLENAME))


DECLARE @Columns VARCHAR(max) 
select  @Columns = COALESCE(@Columns + ', ', '') + C.COLUMN_NAME  
	FROM INFORMATION_SCHEMA.COLUMNS c
			where c.TABLE_NAME = @TableName
			and c.TABLE_SCHEMA = @Schema
			and DATA_TYPE not in ('xml', 'varbinary', 'binary')
	order by C.COLUMN_NAME ASC

return @Columns
End

GO

/****** Object:  UserDefinedFunction [sqltosql].[SQLToSQL_GetCTFieldList]    Script Date: 4/6/2021 12:47:53 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


CREATE OR ALTER  FUNCTION [sqltosql].[SQLToSQL_GetCTFieldList]
(
	@SOURCETABLENAME VARCHAR(50),
	@SOURCEALIAS varchar(20) = 'SOURCE',
	@CTALIAS varchar(20) = 'CT'
)
RETURNS VARCHAR(MAX)
AS
BEGIN
Declare @Schema nvarchar(100) ;
Declare @TableName nvarchar(100) ;

set @Schema = left(@SOURCETABLENAME,CHARINDEX('.', @SOURCETABLENAME)-1)
set @TableName = right(@SOURCETABLENAME,len(@SOURCETABLENAME) - CHARINDEX('.',@SOURCETABLENAME))

declare @SelectList varchar(max) = @CTALIAS + '.SYS_CHANGE_OPERATION ' ;

select  @SelectList = COALESCE(@SelectList + ', ', '') + 
case ISNULL(i.is_primary_key, 0) 
	when 0 then @SOURCEALIAS + '.' + C.Name  
	when 1 then @CTALIAS + '.' + C.name
	end 
from sys.columns c
join sys.objects o
on c.object_id = o.object_id
and o.schema_id = SCHEMA_ID(@Schema)

outer Apply
( SELECT top 1 i.is_primary_key from sys.index_columns ic 
	LEFT OUTER JOIN 
    sys.indexes i ON ic.object_id = i.object_id AND ic.index_id = i.index_id  and i.is_primary_key =1
	where  ic.object_id = c.object_id AND ic.column_id = c.column_id) as i
where o.name = @TableName and o.schema_id = SCHEMA_ID(@Schema) 
and c.system_type_id not in ( select distinct xtype from Sys.systypes t where t.name  in ('xml', 'varbinary', 'binary') )
order by c.name ASC

return @SelectList
End

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

/****** Object:  UserDefinedFunction [sqltosql].[SQLToSQL_GetPrimaryIndexColumns]    Script Date: 4/6/2021 12:49:25 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO



CREATE OR ALTER  FUNCTION [sqltosql].[SQLToSQL_GetPrimaryIndexColumns]
(
	@SOURCETABLENAME VARCHAR(100)
)
RETURNS VARCHAR(MAX)
AS
BEGIN
Declare @Schema nvarchar(100) ;
Declare @TableName nvarchar(100) ;

set @Schema = left(@SOURCETABLENAME,CHARINDEX('.', @SOURCETABLENAME)-1)
set @TableName = right(@SOURCETABLENAME,len(@SOURCETABLENAME) - CHARINDEX('.',@SOURCETABLENAME))

declare @IndexColumns varchar(max)
select  @IndexColumns = COALESCE(@IndexColumns + ',', '') + C.Name 
from sys.columns c
join sys.objects o
on c.object_id = o.object_id and o.schema_id = SCHEMA_ID(@Schema) 
Inner JOIN 
    sys.index_columns ic ON ic.object_id = c.object_id AND ic.column_id = c.column_id
Inner JOIN 
    sys.indexes i ON ic.object_id = i.object_id AND ic.index_id = i.index_id and i.is_primary_key = 1
where o.name = @TableName and o.schema_id = SCHEMA_ID(@Schema)
return @IndexColumns
End

GO

/****** Object:  UserDefinedFunction [sqltosql].[SQLToSQL_INCREMENTALSCRIPT]    Script Date: 4/6/2021 12:49:43 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


CREATE OR ALTER  FUNCTION [sqltosql].[SQLToSQL_INCREMENTALSCRIPT]
(
	@SOURCETABLENAME VARCHAR(50),
	@SOURCEALIAS varchar(20) = 'SOURCE',
	@CTALIAS varchar(20) = 'CT'
)
RETURNS VARCHAR(MAX)
AS
BEGIN

DECLARE @Statement VARCHAR(max);

Set @Statement =  
' SELECT ' + 
sqltosql.SQLToSQL_GetCTFieldList(@SOURCETABLENAME, @SOURCEALIAS, @CTALIAS) +
' FROM  CHANGETABLE(CHANGES ' +
@SOURCETABLENAME  +
', {LASTSYNCVERSION}) '  +
@CTALIAS +
' LEFT JOIN ' +
@SOURCETABLENAME +
' ' +
@SOURCEALIAS+
' ON  ' +
sqltosql.SQLToSQL_GetJoinStatement(@SOURCETABLENAME, @SOURCEALIAS, @CTALIAS) +
' WHERE CT.Sys_Change_Version <= {CURRENTSYNCVERSION}'	;							  


return  @Statement
End

GO

/****** Object:  StoredProcedure [dbo].[SetTableStatus]    Script Date: 4/6/2021 12:40:32 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

/****** Object:  StoredProcedure [dbo].[SetTableStatus]    Update status******/

CREATE OR ALTER  PROC [sqltosql].[SetTableStatus] @TableName nvarchar(100), @TargetTableName nvarchar(100), @Status int, @LAST_FILENAME nvarchar(100) null
as 
begin 

update SynapseToSQLTables set Status = @Status, LastProcessedFile = ISNULL(@LAST_FILENAME, '')
where TableName = @TableName and TargetTableName = @TargetTableName

end
GO

/****** Object:  StoredProcedure [sqltosql].[GetUpdatedTables]    Script Date: 4/6/2021 12:41:10 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

	CREATE OR ALTER  Procedure [sqltosql].[GetUpdatedTables]
	AS
	SET NOCOUNT ON; 
	DECLARE @currentSyncVersion TABLE (TableName nvarchar(200), currentSyncVersion bigint)          
	DECLARE @SetupTableCursor as CURSOR;     
	DECLARE @TABLENAME as nvarchar(200);   
	DECLARE @LastSyncVersion as bigint;        
	SET @SetupTableCursor = CURSOR FOR  SELECT A.TABLENAME FROM sqlToSQL.SQLToSQLDataSyncSetup A where A.Published = 1 and A.Status = 0      
	OPEN @SetupTableCursor;       
	FETCH NEXT FROM @SetupTableCursor INTO @TABLENAME;         
	WHILE @@FETCH_STATUS = 0    
	BEGIN        
	select top 1 @LastSyncVersion = X.ChangeVersion from sqlToSQL.SQLToSQLDataSyncSetup X         
	WHERE X.TableName = @TABLENAME;          
	insert into @currentSyncVersion(TableName, currentSyncVersion)       
	exec [sqlToSQL].SQLToSQL_GetCurrentSyncVersion @TABLENAME, @LastSyncVersion          
	FETCH NEXT FROM @SetupTableCursor INTO @TABLENAME;       
	END          

	Select  
	 A.TableName AS TABLENAME
	 ,SUBSTRING(A.TargetTableName, 0, CHARINDEX('.', A.TargetTableName)) AS [TARGET_SCHEMA]
    ,SUBSTRING(A.TargetTableName, CHARINDEX('.', A.TargetTableName)  + 1, LEN(A.TargetTableName)) AS [TARGET_TABLENAME]
	,A.ChangeVersion AS LAST_SYNC_VERSION
	,b.CURRENTSYNCVERSION as CURRENT_SYNC_VERSION,            
	replace(replace(A.INCREMENTALEXPORTSCRIPT, '{LASTSYNCVERSION}',  A.ChangeVersion) ,   '{CURRENTSYNCVERSION}', b.CURRENTSYNCVERSION) AS INCREMENTAL_EXPORT_SCRIPT  				   
	from sqlToSQL.SQLToSQLDataSyncSetup A         
	join @currentSyncVersion as b              
	on A.TableName = b.TABLENAME      
	where  
	A.PUBLISHED = 1 and
	A.Status = 0     
	and  b.currentSyncVersion > a.ChangeVersion
GO



/****** Object:  StoredProcedure [sqltosql].[SQLToSQL_GetCurrentSyncVersion]    Script Date: 4/6/2021 12:42:27 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

Create Or Alter  PROC [sqltosql].[SQLToSQL_GetCurrentSyncVersion]
    @TableName nvarchar(200),
    @LastSyncVersion bigInt
AS
SET NOCOUNT ON;
declare @ctStatement nvarchar(1000);
 IF EXISTS (SELECT 1 FROM sys.change_tracking_tables 
               WHERE object_id = OBJECT_ID(@TableName)) 
Begin 
set @ctStatement = FORMATMESSAGE('select ''%s'' as TableName, max(CT.SYS_CHANGE_VERSION) CurrentSyncVersion from  CHANGETABLE(CHANGES %s, %I64d) CT', @TableName, @TableName, @LastSyncVersion);
END
EXECUTE sp_executesql    @ctStatement
GO

/****** Object:  StoredProcedure [sqltosql].[SQLToSQL_PublishTable]    Script Date: 4/6/2021 12:43:47 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROCEDURE [sqltosql].[SQLToSQL_PublishTable]
@SourceTableName  nvarchar(200),
@TargetTableName  nvarchar(200)
AS
BEGIN
	SET NOCOUNT ON;
	
	Declare @Schema nvarchar(100) ;
	Declare @TableName nvarchar(100) ;	
	set @Schema = left(@SOURCETABLENAME,CHARINDEX('.', @SOURCETABLENAME)-1)
	set @TableName = right(@SOURCETABLENAME,len(@SOURCETABLENAME) - CHARINDEX('.',@SOURCETABLENAME))
	
	-- enable change tracking 

    declare @ChangeTrackingStatement [nvarchar] (max)
    set @ChangeTrackingStatement = FORMATMESSAGE(
							'declare @ChangeTrackingEnabled bit; 
						     set @ChangeTrackingEnabled =
							 (select top 1 1 as Exist from sys.change_tracking_tables where object_id = object_id(''%s''))
							 if  @ChangeTrackingEnabled  is null
							 begin
								ALTER TABLE %s
								ENABLE CHANGE_TRACKING
							 end'
							,@SourceTableName, @SourceTableName) ;

	Exec (@ChangeTrackingStatement)

	-- calculate script 
	Declare @FULLEXPORTSCRIPT [nvarchar](max)
	Declare @INCREMENTALEXPORTSCRIPT [nvarchar](max)
	Declare @PUBLISHEDSCHEMAJSON [nvarchar](max)
	Declare @PrimaryIndexColumns [nvarchar](max)

	set @FULLEXPORTSCRIPT = 'select ''I'' as SYS_CHANGE_OPERATION, ' + sqltosql.SQLToSQL_GenerateFieldList(@SourceTableName) + ' From ' + @SourceTableName;

	set @INCREMENTALEXPORTSCRIPT = sqltosql.SQLToSQL_INCREMENTALSCRIPT(@SourceTableName, 'SOURCE', 'CT');

	set @PrimaryIndexColumns =  sqltosql.SQLToSQL_GetPrimaryIndexColumns(@SourceTableName);
	DECLARE @next_baseline bigint;  
	SET @next_baseline = CHANGE_TRACKING_CURRENT_VERSION();  

	
	update [SQLToSQLDataSyncSetup]
			set 
				ChangeVersion = @next_baseline
				, Published = 0
				,Status = 1
				,ModifiedDateTime = getDate(), 
				FULLEXPORTSCRIPT = @FULLEXPORTSCRIPT,
				INCREMENTALEXPORTSCRIPT = @INCREMENTALEXPORTSCRIPT,
				PRIMARYINDEXCOLUMNS = @PrimaryIndexColumns
			where TableName = @SourceTableName;
	
	if @@rowcount =0 
	begin
		insert into [SQLToSQLDataSyncSetup] (TableName, TargetTableName, ChangeVersion,  CreatedDateTime, ModifiedDateTime,  
		FULLEXPORTSCRIPT, INCREMENTALEXPORTSCRIPT,   PRIMARYINDEXCOLUMNS, Published, Status)
		values (@SourceTableName, @TargetTableName, 0,  getDate(), getDate(),  
		@FULLEXPORTSCRIPT, @INCREMENTALEXPORTSCRIPT,   @PrimaryIndexColumns, 0, 1);
	end
	
END

GO

/****** Object:  StoredProcedure [sqltosql].[SQLToSQL_UpdateLastSyncVersion]    Script Date: 4/6/2021 12:44:14 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROC [sqltosql].[SQLToSQL_UpdateLastSyncVersion]
    @TableName varchar(200),
    @LastSyncVersion bigInt
AS
SET NOCOUNT ON;
 
UPDATE SQLToSQLDataSyncSetup
SET ChangeVersion = @LastSyncVersion, Status = 0, ModifiedDateTime = GetDate()
WHERE TableName = @TableName; 
 
GO

/****** Object:  StoredProcedure [sqltosql].[SQLToSQL_UpdatePublished]    Script Date: 4/6/2021 12:44:33 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER  PROC [sqltosql].[SQLToSQL_UpdatePublished]
    @TableName varchar(200)
AS
SET NOCOUNT ON;
 
UPDATE [SQLToSQLDataSyncSetup]
SET Published = 1, Status = 0, ModifiedDateTime = getDate()
WHERE TableName = @TableName;

GO

/****** Object:  StoredProcedure [sqltosql].[SQLToSQL_UpdateStatusInProcess]    Script Date: 4/6/2021 12:44:50 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER  PROC [sqltosql].[SQLToSQL_UpdateStatusInProcess]
    @TableName varchar(200)
AS
SET NOCOUNT ON;
 
UPDATE SQLToSQLDataSyncSetup
SET [Status] = 1, ModifiedDateTime = getDate()
WHERE TableName = @TableName; 
 
GO

