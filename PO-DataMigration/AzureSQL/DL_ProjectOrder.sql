/****** Object:  Table [dbo].[DL_ProjectOrder]    Script Date: 5/13/2022 9:21:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[DL_ProjectOrder](
	[Name] [nvarchar](300) NULL,
	[Id] [uniqueidentifier] NULL,
	[Currency] [uniqueidentifier] NULL,
	[PriceList] [uniqueidentifier] NULL
) ON [PRIMARY]
GO

