SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[CU_Material](
	[Name] [nvarchar](100) NULL,
	[ProjectName] [nvarchar](255) NULL,
	[TaskName] [nvarchar](450) NULL,
	[Quantity] decimal(38,2) null,
	[UnitCost] decimal(38,2) null,
	[UsageStatus] [nvarchar](50) NULL,
	[Date] [date] NULL

) ON [PRIMARY]
GO


