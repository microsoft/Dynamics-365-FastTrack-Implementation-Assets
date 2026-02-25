/****** Object:  Table [dbo].[UL_TimeEntry]    Script Date: 3/15/2022 8:08:33 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[UL_TimeEntry](
	[TimeEntryId] [uniqueidentifier] NULL,
	[Duration] [int] NULL,
	[Description] [nvarchar](100) NULL,
	[ExternalDescription] [nvarchar](100) NULL,
	[EntryStatus] [int] NOT NULL,
	[TimeSource] [uniqueidentifier] NULL,
	[ProjectId] [uniqueidentifier] NULL,
	[TaskId] [uniqueidentifier] NULL,
	[ResourceCategoryId] [uniqueidentifier] NULL,
	[Type] [int] NULL,
	[Date] [date] NULL,
	[ResourcingCompany] [uniqueidentifier] NULL,
	[TargetStatus] [nvarchar](50) NULL
) ON [PRIMARY]
GO

