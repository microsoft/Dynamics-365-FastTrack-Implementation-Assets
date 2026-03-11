/****** Object:  Table [dbo].[DL_Journal]    Script Date: 3/14/2022 12:52:46 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[DL_Journal](
	[Id] [uniqueidentifier] NULL,
	[Description] [nvarchar](100) NULL,
	[JournalType] [int] NULL,
	[Posted] [bit] NULL
) ON [PRIMARY]
GO

