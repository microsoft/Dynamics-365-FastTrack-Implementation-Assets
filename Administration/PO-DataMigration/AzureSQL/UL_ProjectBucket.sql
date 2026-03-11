/****** Object:  Table [dbo].[UL_ProjectBucket]    Script Date: 9/1/2023 5:45:21 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[UL_ProjectBucket](
	[msdyn_projetbucketid] [uniqueidentifier] NULL,
	[msdyn_name] [nvarchar](255) NULL,
        [msdyn_project] [uniqueidentifier] NULL
) ON [PRIMARY]
GO

