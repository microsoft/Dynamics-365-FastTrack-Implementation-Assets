/****** Object:  Table [dbo].[DL_ProjectBucket]    Script Date: 3/8/2022 3:47:16 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[DL_ProjectBucket](
	[ProjectBucket] [uniqueidentifier] NULL,
	[Name] [nvarchar](255) NULL,
        [Project] [uniqueidentifier] NULL
) ON [PRIMARY]
GO

