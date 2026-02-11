/****** Object:  Table [dbo].[CU_Account]    Script Date: 3/8/2022 3:40:02 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[CU_Account](
	[Name] [nvarchar](255) NULL,
	[Company] [nvarchar](20) NULL,
	[CustomerGroupId] [nvarchar](20) NULL,
	[AccountNumber] [nvarchar](20) NULL,
	[PriceList] [nvarchar](100) NULL,
	[Currency] [nvarchar](100) NULL
) ON [PRIMARY]
GO

