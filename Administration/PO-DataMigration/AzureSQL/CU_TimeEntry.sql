/****** Object:  Table [dbo].[CU_TimeEntry]    Script Date: 3/8/2022 3:41:34 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[CU_TimeEntry](
	[Duration] [int] NULL,
	[Description] [nvarchar](100) NULL,
	[ExternalDescription] [nvarchar](100) NULL,
	[EntryStatus] [nvarchar](50) NULL,
	[ProjectName] [nvarchar](255) NULL,
	[TaskName] [nvarchar](450) NULL,
	[Role] [nvarchar](100) NULL,
	[Type] [nvarchar](20) NULL,
	[Date] [date] NULL
) ON [PRIMARY]
GO

