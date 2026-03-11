/****** Object:  Table [dbo].[UL_RolePrice]    Script Date: 7/12/2022 8:57:58 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[UL_RolePrice](
	[ResourceCategoryPrice] [uniqueidentifier] NULL,
	[PriceLevelId] [uniqueidentifier] NULL,
	[RoleId] [uniqueidentifier] NULL,
	[ResourcingUnitId] [uniqueidentifier] NULL,
	[UnitId] [uniqueidentifier] NULL,
	[Price] [money] NULL,
	[TransactionCurrencyId] [uniqueidentifier] NULL
) ON [PRIMARY]
GO

