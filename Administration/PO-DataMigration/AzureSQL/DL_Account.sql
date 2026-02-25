/****** Object:  Table [dbo].[DL_Account]    Script Date: 3/8/2022 3:44:18 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[DL_Account](
	[AccountId] [uniqueidentifier] NULL,
	[Name] [nvarchar](160) NULL,
	[AccountNumber] [nvarchar](20) NULL,
	[CompanyId] [uniqueidentifier] NULL
) ON [PRIMARY]
GO

