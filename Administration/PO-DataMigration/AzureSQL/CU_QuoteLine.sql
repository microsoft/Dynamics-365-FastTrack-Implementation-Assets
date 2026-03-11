/****** Object:  Table [dbo].[CU_QuoteLine]    Script Date: 3/8/2022 3:41:08 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[CU_QuoteLine](
	[QuoteName] [nvarchar](300) NULL,
	[Name] [nvarchar](500) NULL,
	[BillingMethod] [nvarchar](20) NULL,
	[IncludeTime] [nvarchar](3) NULL,
	[IncludeExpense] [nvarchar](3) NULL,
	[IncludeMaterial] [nvarchar](3) NULL,
	[IncludeFee] [nvarchar](3) NULL,
	[QuotedAmount] [money] NULL
) ON [PRIMARY]
GO

