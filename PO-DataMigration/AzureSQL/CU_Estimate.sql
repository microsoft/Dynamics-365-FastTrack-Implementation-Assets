/****** Object:  Table [dbo].[CU_Estimate]    Script Date: 3/25/2022 6:07:59 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[CU_Estimate](
	[ProjectName] [nvarchar](255) NULL,
	[TaskName] [nvarchar](450) NULL,
	[Category] [nvarchar](100) NULL,
	[StartDate] [date] NULL,
	[Quantity] [decimal](38, 2) NULL,
	[CostPrice] [money] NULL,
	[SalesPrice] [money] NULL
) ON [PRIMARY]
GO

