/****** Object:  Table [dbo].[CU_JournalLine]    Script Date: 3/14/2022 10:54:21 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[UL_JournalLine](
	[Id] [nvarchar](20) NULL,
	[Journal] uniqueidentifier NULL,
	TransactionTypeCode int null,
	TransactionClassification int null,
	DocumentDate date null,
	StartDate date null,
	EndDate date null,
	Project uniqueidentifier null,
	ResourceCategory uniqueidentifier null,
	Quantity Decimal, 
	Price Money,
	BillingType int
) ON [PRIMARY]
GO


