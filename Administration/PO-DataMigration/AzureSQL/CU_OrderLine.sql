/****** Object:  Table [dbo].[CU_OrderLine]    Script Date: 3/8/2022 6:31:03 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[CU_OrderLine](
	[OrderName] [nvarchar](300) NULL,
	[Name] [nvarchar](500) NULL,
	[BillingMethod] [nvarchar](20) NULL,
	[Amount] [money] NULL,
	[ProjectName] [nvarchar](255) NULL,
	[IncludeTime] [nvarchar](3) NULL,
	[IncludeExpense] [nvarchar](3) NULL,
	[IncludeMaterial] [nvarchar](3) NULL,
	[IncludeFee] [nvarchar](3) NULL
) ON [PRIMARY]
GO

