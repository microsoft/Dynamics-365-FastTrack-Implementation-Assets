/****** Object:  Table [dbo].[CU_PriceList]    Script Date: 7/12/2022 2:49:28 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[CU_PriceList](
	[Name] [nvarchar](100) NULL,
	[Currency] [nvarchar](100) NULL,
	[Context] [nvarchar](20) NULL,
	[StartDate] [date] NULL,
	[EndDate] [date] NULL
) ON [PRIMARY]
GO

