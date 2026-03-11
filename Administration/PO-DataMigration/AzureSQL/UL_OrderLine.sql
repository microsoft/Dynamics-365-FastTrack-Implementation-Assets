/****** Object:  Table [dbo].[UL_OrderLine]    Script Date: 3/14/2022 4:42:37 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[UL_OrderLine](
	[Id] [uniqueidentifier] NULL,
	[Name] [nvarchar](500) NULL,
	[ProductDescription] [nvarchar](500) NULL,
	[Order] [uniqueidentifier] NULL,
	[Quantity] [Decimal] NULL,
	[PricePerUnit] [money] NULL,
	[BillingMethod] [int] NULL,
	[IncludeTime] [bit] NULL,
	[IncludeExpense] [bit] NULL,
	[IncludeMaterial] [bit] NULL,
	[IncludeFee] [bit] NULL,
	[LineType] [int] NULL,
	[ProductType] [int] NULL
) ON [PRIMARY]
GO

