/****** Object:  Table [dbo].[UL_ResourceAssignment]    Script Date: 9/1/2023 9:55:27 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

IF OBJECT_ID('UL_ResourceAssignment','U') is not null
   DROP TABLE UL_ResourceAssignment

CREATE TABLE [dbo].[UL_ResourceAssignment](
	[Id] [uniqueidentifier] NULL,
	[ProjectId] [uniqueidentifier] NULL, 
	[TaskId] [uniqueidentifier] NULL,                
	[Name] [nvarchar](100) NULL,
	[BookableResourceId]  [uniqueidentifier] NULL,
        [ProjectTeamId] [uniqueidentifier] NULL,
        [Effort] [float] NULL,
        [EffortRemaining] [float] NULL,
	[ScheduledStart] [date] NULL,
	[ScheduledEnd] [date] NULL
) ON [PRIMARY]
GO

