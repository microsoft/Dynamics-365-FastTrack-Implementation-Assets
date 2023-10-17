/****** Object:  Table [dbo].[CU_JournalLine]    Script Date: 3/13/2022 6:13:02 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[CU_JournalLine](
	[JournalName] [nvarchar](255) NULL,
	[TransactionType] [nvarchar](20) NULL,
	[TransactionClass] [nvarchar](20) NULL,
	[DocumentDate] [date] NULL,
	[Project] [nvarchar](255) NULL,
	[Role] [nvarchar](100) NULL,
	[Quantity] [int] NULL,
	[Price] [money] NULL
) ON [PRIMARY]
GO

