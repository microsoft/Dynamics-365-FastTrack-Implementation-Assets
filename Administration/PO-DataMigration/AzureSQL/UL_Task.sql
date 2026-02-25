/****** Object:  Table [dbo].[UL_TASK]    Script Date: 6/12/2023 1:52:42 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

IF OBJECT_ID('UL_TASK','U') is not null
   DROP TABLE UL_TASK

CREATE TABLE [dbo].[UL_TASK](
	[Nr] [int] NULL,
	[Id] [uniqueidentifier] NULL,
	[TaskName] [nvarchar](450) NULL,
	[ProjectId] [uniqueidentifier] NULL,
        [ProjectBucketId] [uniqueidentifier] NULL,
	[Effort] [float] NULL,
	[EffortRemaining] [float] NULL,
        [EffortCompleted] [float] NULL,
	[ScheduledStart] [date] NULL,
	[ScheduledEnd] [date] NULL,
	[LinkStatus] [int] NOT NULL,
	[ParentTask] [int] NULL,
	[ParentId] [uniqueidentifier] NULL,
	[WBSNr] [numeric](38, 9) NULL,
        [msdyn_duration] [float] NULL,
        [msdyn_finish] [date] NULL,
        [msdyn_outlinelevel] [int] null,
        [msdyn_scheduledduration] [int] null,
        [msdyn_start] [date] null
) ON [PRIMARY]
GO


