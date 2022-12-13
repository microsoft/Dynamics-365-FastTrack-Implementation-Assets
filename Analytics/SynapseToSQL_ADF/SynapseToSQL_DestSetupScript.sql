
/*
Scripts to execute on the target SQL database. 
Objects 
    Tables 
    1. SynapseToSQLTables - Store
    Stored procedures:
    1. publishTable
    2. Create_RecId_Index
    3. MERGECDC
    4. SetTableStatus
These objects are used in the data factory to store setup data and  

*/
DROP TABLE If EXISTS [dbo].[SynapseToSQLTables]
GO
-- Create Table
CREATE TABLE [dbo].[SynapseToSQLTables](
	[TableName] [varchar](100) NOT NULL,
	[CDCTableName] [varchar](100) NULL,
	[ColumnNames] [varchar](8000) NULL,
	[Status] [int] NULL,
	[CreatedDateTime] [datetime] NULL,
	[ModifiedDateTime] [datetime] NULL,
	[PrimaryTableName] [varchar](100) NULL,
	[LastProcessedFile] [nvarchar](200) NULL,
 CONSTRAINT [PK_TABLENAME] PRIMARY KEY CLUSTERED 
(
	[TableName] ASC
)WITH (STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]
GO

Create or ALTER PROC [dbo].[Create_RecId_Index] @TableName nvarchar(100), @Schema nvarchar(10) 
as 
begin 
--declare @Schema nvarchar(10) = 'DBO';
--declare @TableName nvarchar(100) = 'CUSTGROUP';
Declare @SQLNull nvarchar(300)=  FORMATMESSAGE('ALTER TABLE  %s ALTER COLUMN  RECID BIGINT NOT NULL;', @Schema+ '.' +@TableName );

EXECUTE  sp_executesql  @SQLNull;

Declare @SQLIdx nvarchar(300)=  FORMATMESSAGE('ALTER TABLE %s  ADD CONSTRAINT PK_%s_RECID PRIMARY KEY CLUSTERED (RECID);', @Schema+ '.' +@TableName, @TableName );

EXECUTE  sp_executesql  @SQLIdx;
end 
GO

-- prepare merge stateement and execute to merge cdc data to main table
CREATE OR ALTER  PROC [dbo].[MERGECDC]
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

--Declare  nvarchar(100) = 'CUSTGROUP';
--Declare @CDCTable nvarchar(100) ='CDC.CUSTGROUP'

declare @UpdateColumns nvarchar(max);
declare @Columns nvarchar(max);
Select @UpdateColumns = COALESCE(@UpdateColumns + ', ', '') + 'T.' + x.COLUMN_NAME + ' = S.'  + x.COLUMN_NAME,
  @Columns = COALESCE(@Columns + ', ', '')  + x.COLUMN_NAME 
 from INFORMATION_SCHEMA.COLUMNS x 
WHERE TABLE_NAME = @TargetTable
and  TABLE_SCHEMA = 'dbo'

select @UpdateColumns, @Columns

Declare @MergeStatement nvarchar(max);

set @MergeStatement 
=  ' MERGE ' + @TargetTable + ' T USING '+ @CDCTable + ' S' + 
' ON T.RECID = S.RECID' +
' WHEN MATCHED and S.DML_Action = ''AFTER_UPDATE''' +
'    THEN UPDATE SET ' +
 @UpdateColumns +
' WHEN NOT MATCHED BY TARGET THEN INSERT (' + 
@Columns +
')	Values (' +
@Columns + 
')' +
' WHEN MATCHED and S.DML_Action = ''DELETE''' +
' THEN DELETE;'; 

Execute sp_executesql  @MergeStatement;
 
END
GO

/****** Object:  StoredProcedure [dbo].[publishTable]   create update record in setup table*/
CREATE OR ALTER PROC [dbo].[publishTable]  
@TableName nvarchar(100), 
@CDCTableName nvarchar(100),
@PrimaryTableName nvarchar(100),
@ColumnNames nvarchar(8000)
as 
begin
	
	IF EXISTS (SELECT 1 FROM SynapseToSQLTables where TableName = @TableName)
	BEGIN
		update SynapseToSQLTables set PrimaryTableName = @PrimaryTableName ,ColumnNames = @ColumnNames, Status= 0 , LastProcessedFile = '' , CreatedDateTime = getdate(), ModifiedDateTime = GETDATE()
		where TableName = @TableName
	END 
ELSE 
	BEGIN
		Insert into SynapseToSQLTables (TableName, CDCTableName, PrimaryTableName, LastProcessedFile, ColumnNames, [Status], CreatedDateTime, ModifiedDateTime)
		values (@TableName, @CDCTableName, @PrimaryTableName, '', @ColumnNames, 0,   getdate(), getdate() )
	END
end
GO

/****** Object:  StoredProcedure [dbo].[SetTableStatus]    Update status******/

CREATE OR ALTER  PROC [dbo].[SetTableStatus] @TableName varchar(100), @Status int, @LAST_FILENAME nvarchar(100) null
as 
begin 

update SynapseToSQLTables set Status = @Status, LastProcessedFile = ISNULL(@LAST_FILENAME, '')
where TableName = @TableName

end
GO
