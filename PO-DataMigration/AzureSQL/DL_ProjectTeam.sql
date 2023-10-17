/****** Object:  Table [dbo].[DL_ProjectTeam]    Script Date: 9/4/2023 3:47:16 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[DL_ProjectTeam](
        [id] [uniqueidentifier] NULL,
	[BookableResourceId] [uniqueidentifier] NULL,
        [Project] [uniqueidentifier] NULL
) ON [PRIMARY]
GO

