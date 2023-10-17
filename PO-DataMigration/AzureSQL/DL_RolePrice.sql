/****** Object:  Table [dbo].[DL_RolePrice]    Script Date: 7/12/2022 7:40:42 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[DL_RolePrice](
	[ResourceCategoryPrice] [uniqueidentifier] NULL,
	[PriceListId] [uniqueidentifier] NULL,
	[ResourcingUnitId] [uniqueidentifier] NULL,
	[RoleId] [uniqueidentifier] NULL,
	[PriceList] [nvarchar](100) NULL,
	[ResourcingUnit] [nvarchar](100) NULL,
	[Role] [nvarchar](100) NULL
) ON [PRIMARY]
GO

