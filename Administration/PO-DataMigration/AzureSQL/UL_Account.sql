/****** Object:  Table [dbo].[UL_Account]    Script Date: 3/8/2022 3:49:53 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[UL_Account](
	[AccountId] [uniqueidentifier] NULL,
	[Name] [nvarchar](255) NULL,
	[CurrencyId] [uniqueidentifier] NULL,
	[CompanyId] [uniqueidentifier] NULL,
	[AccountNumber] [nvarchar](20) NULL,
	[Relationship] [int] NULL,
	[CustomerGroup] [uniqueidentifier] NULL,
	[PriceList] [uniqueidentifier] NULL
) ON [PRIMARY]
GO

