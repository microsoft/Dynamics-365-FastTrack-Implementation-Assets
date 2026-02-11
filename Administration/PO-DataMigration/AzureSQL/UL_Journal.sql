/****** Object:  Table [dbo].[UL_Journal]    Script Date: 3/14/2022 9:55:27 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[UL_Journal](
	[Description] [nvarchar](100) NULL,
	[JournalType] [int] NULL,
	[Id] [uniqueidentifier] NULL
) ON [PRIMARY]
GO

