/****** Object:  Table [dbo].[DL_ProjectTask]    Script Date: 3/8/2022 3:47:55 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[DL_ProjectTask](
	[ProjectId] [uniqueidentifier] NULL,
	[ProjectName] [nvarchar](255) NULL,
	[TaskName] [nvarchar](450) NULL,
	[TaskId] [uniqueidentifier] NULL
) ON [PRIMARY]
GO

