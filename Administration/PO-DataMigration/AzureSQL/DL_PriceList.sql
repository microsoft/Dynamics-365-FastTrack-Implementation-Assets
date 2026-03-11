/****** Object:  Table [dbo].[DL_PriceList]    Script Date: 3/8/2022 3:46:56 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[DL_PriceList](
	[Name] [nvarchar](100) NULL,
	[PriceLevelId] [uniqueidentifier] NULL,
	[Currency] [nvarchar](100) NULL
) ON [PRIMARY]
GO

