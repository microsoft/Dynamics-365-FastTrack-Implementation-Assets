/****** Object:  Table [dbo].[CU_RolePrice]    Script Date: 7/12/2022 7:41:09 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[CU_RolePrice](
	[PriceList] [nvarchar](100) NULL,
	[Role] [nvarchar](100) NULL,
	[ResourcingUnit] [nvarchar](100) NULL,
	[Unit] [nvarchar](100) NULL,
	[Price] [money] NULL,
	[Currency] [nvarchar](5) NULL
) ON [PRIMARY]
GO

