IF NOT EXISTS (SELECT * FROM sys.external_file_formats WHERE [name] = N'CSV')
CREATE EXTERNAL FILE FORMAT [CSV] WITH (FORMAT_TYPE = DELIMITEDTEXT, FORMAT_OPTIONS (FIELD_TERMINATOR = N',', STRING_DELIMITER = N'"', USE_TYPE_DEFAULT = False))

IF  EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[DataLakeToSynapse_ControlTableForCopy]') AND type in (N'U'))
DROP TABLE [dbo].[DataLakeToSynapse_ControlTableForCopy]
GO

CREATE TABLE [dbo].[DataLakeToSynapse_ControlTableForCopy]
(
	[TableName] [varchar](255) NULL,
	[DataLocation] [varchar](255) NULL,
	[FileFormat]   [varchar](100) NULL,
	[CDCDataLocation] [varchar](255) NULL,
	[MetadataLocation] [varchar](255) NULL,
	[LastCopyDateTime] [datetime2](7) NULL,
	[LastCopyMarker] [varchar](255) NULL,
	[LastCopyStatus] [int] NULL
)
WITH
(
	DISTRIBUTION = ROUND_ROBIN,
	CLUSTERED COLUMNSTORE INDEX
)
GO

IF  EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'dbo.DataLakeToSynapse_CopyIntoTable') AND type in (N'P'))
DROP Procedure dbo.DataLakeToSynapse_CopyIntoTable
GO
CREATE  PROCEDURE dbo.DataLakeToSynapse_CopyIntoTable
(
  @TableName varchar(255),
  @FilePath varchar(500),
  @FileFormat varchar(100)
)
AS
BEGIN
 
 declare @CopyIntoSQL nvarchar(4000) = 'delete from '+ @TableName + '; COPY INTO ' + @TableName +
 ' FROM ''' + @FilePath + ''' 
 WITH (
     FILE_TYPE = ''' + @FileFormat +',
     CREDENTIAL = (IDENTITY = ''Managed Identity'')
 )'

 Begin Tran;
 Execute sp_executesql @CopyIntoSQL;

 update [dbo].[DataLakeToSynapse_ControlTableForCopy]
 set [LastCopyDateTime] = getUTCdate(), [LastCopyStatus] = 0
 where [TableName] = ''+ @TableName + '';

 Commit Tran;

END
GO

IF  EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'dbo.DataLakeToSynapse_InsertIntoControlTableForCopy') AND type in (N'P'))
DROP Procedure dbo.DataLakeToSynapse_InsertIntoControlTableForCopy;
GO

CREATE PROCEDURE dbo.DataLakeToSynapse_InsertIntoControlTableForCopy
(
  @TableName varchar(255),
  @DataLocation varchar(500),
  @FileFormat varchar(100),
  @CDCDataLocation varchar(500),
  @MetadataLocation varchar(500)
)
AS
BEGIN
INSERT INTO [dbo].[DataLakeToSynapse_ControlTableForCopy](TableName, DataLocation,FileFormat, CDCDataLocation, MetadataLocation)
SELECT * FROM
(SELECT @TableName, @DataLocation, @FileFormat, @CDCDataLocation, @MetadataLocation) as i (TableName, DataLocation,  FileFormat, CDCDataLocation, MetadataLocation) 
WHERE NOT EXISTS (SELECT DISTINCT TableName FROM [dbo].[DataLakeToSynapse_ControlTableForCopy] WHERE TableName =i.TableName)
END
GO


IF  EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'dbo.DataLakeToSynapse_GetControlTableForCopy') AND type in (N'P'))
DROP Procedure dbo.DataLakeToSynapse_GetControlTableForCopy;
GO

CREATE PROC [dbo].[DataLakeToSynapse_GetControlTableForCopy] (@TableList [varchar](8000), @schema varchar(50)) AS 
BEGIN
SELECT * FROM [dbo].[DataLakeToSynapse_ControlTableForCopy] where 
@TableList is null OR TableName in (select @schema + '.' + value from STRING_SPLIT(@TableList, ','));
END
GO


--CREATE DATABASE SCOPED CREDENTIAL msi_cred WITH IDENTITY = 'Managed Service Identity';