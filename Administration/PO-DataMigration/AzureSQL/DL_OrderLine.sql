/****** Object:  Table [dbo].[DL_OrderLine]    Script Date: 3/8/2022 7:39:52 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[DL_OrderLine](
	[Id] [uniqueidentifier] NULL,
	[Name] [nvarchar](500) NULL,
	[Order] [uniqueidentifier] NULL
) ON [PRIMARY]
GO

