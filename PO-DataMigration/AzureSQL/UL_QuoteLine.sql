/****** Object:  Table [dbo].[UL_QuoteLine]    Script Date: 3/8/2022 3:51:07 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[UL_QuoteLine](
	[QuoteId] [uniqueidentifier] NULL,
	[Name] [nvarchar](500) NULL,
	[QuoteDetailId] [uniqueidentifier] NULL,
	[BillingMethod] [int] NULL,
	[IncludeTime] [bit] NULL,
	[IncludeExpense] [bit] NULL,
	[IncludeMaterial] [bit] NULL,
	[IncludeFee] [bit] NULL,
	[PricePerUnit] [money] NULL,
	[ProductType] [int] NULL,
	[Description] [nvarchar](500) NULL
) ON [PRIMARY]
GO

