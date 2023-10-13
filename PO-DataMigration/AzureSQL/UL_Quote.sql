/****** Object:  Table [dbo].[UL_Quote]    Script Date: 3/8/2022 3:50:36 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[UL_Quote](
	[Id] [uniqueidentifier] NULL,
	[Name] [nvarchar](300) NULL,
	[CompanyId] [uniqueidentifier] NULL,
	[PriceLevelId] [uniqueidentifier] NULL,
	[CustomerId] [uniqueidentifier] NULL,
	[CustomerEntity] [nvarchar](20) NULL,
	[OrderType] [int] NULL
) ON [PRIMARY]
GO

