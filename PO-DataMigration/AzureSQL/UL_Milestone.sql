/****** Object:  Table [dbo].[UL_Milestone]    Script Date: 4/4/2022 8:16:52 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[UL_Milestone](
	[Id] [uniqueidentifier] NULL,
	[Name] [nvarchar](100) NULL,
	[Amount] [money] NULL,
	[ContractLineId] [uniqueidentifier] NULL,
	[InvoiceDate] [date] NULL,
	[InvoiceStatus] [int] NOT NULL
) ON [PRIMARY]
GO

