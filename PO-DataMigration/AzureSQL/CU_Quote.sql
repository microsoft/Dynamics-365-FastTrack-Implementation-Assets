/****** Object:  Table [dbo].[CU_Quote]    Script Date: 3/8/2022 3:40:47 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[CU_Quote](
	[Name] [nvarchar](300) NULL,
	[Customer] [nvarchar](160) NULL,
	[Company] [nvarchar](20) NULL,
	[PriceList] [nvarchar](100) NULL
) ON [PRIMARY]
GO

