/****** Object:  Table [dbo].[UL_ProjectOrder]    Script Date: 5/13/2022 9:35:35 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[UL_ProjectOrder](
	[Id] [uniqueidentifier] NULL,
	[Name] [nvarchar](300) NULL,
	[AccountId] [uniqueidentifier] NULL,
	[CustomerEntity] [varchar](20) NULL,
	[OrderType] [int] NULL,
	[CurrencyId] [uniqueidentifier] NULL,
	[PriceListId] [uniqueidentifier] NULL
) ON [PRIMARY]
GO

