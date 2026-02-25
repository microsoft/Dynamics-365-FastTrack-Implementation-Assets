/****** Object:  Table [dbo].[UL_Project]    Script Date: 6/9/2022 5:45:21 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

IF OBJECT_ID (N'UL_Project') IS NOT NULL DROP TABLE UL_Project

CREATE TABLE [dbo].[UL_Project](
	[id] [uniqueidentifier] NULL,
	[msdyn_subject] [nvarchar](255) NULL,
	[msdyn_description] [nvarchar](255) NULL,
	[msdyn_customer] [uniqueidentifier] NULL,
	[msdyn_workhourtemplate] [uniqueidentifier] NULL,
	[msdyn_owningcompany] [uniqueidentifier] NULL,
	[msdyn_projectmanager] [uniqueidentifier] NULL,
	[msdyn_scheduledstart] [date] NULL,
        [msdyn_finish] [date] null,
        [msdyn_effort] [float] null,
        [msdyn_scheduler] [int] NULL,
        [msdyn_schedulemode] [int] NULL
) ON [PRIMARY]
GO

