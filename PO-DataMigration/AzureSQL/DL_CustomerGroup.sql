/****** Object:  Table [dbo].[DL_CustomerGroup]    Script Date: 3/8/2022 3:46:38 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[DL_CustomerGroup](
	[CustomerGroup] [uniqueidentifier] NOT NULL,
	[CustomerGroupId] [nvarchar](20) NULL,
	[CompanyId] [uniqueidentifier] NULL,
	[Company] [nvarchar](20) NULL
) ON [PRIMARY]
GO

