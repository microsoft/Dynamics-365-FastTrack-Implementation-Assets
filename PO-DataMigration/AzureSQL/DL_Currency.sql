/****** Object:  Table [dbo].[DL_Currency]    Script Date: 3/12/2022 10:15:45 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[DL_Currency](
	[CurrencyName] [nvarchar](100) NULL,
	[ISOCurrencyCode] [nvarchar](5) NULL,
	[TransactionCurrencyId] [uniqueidentifier] NULL,
	[CurrencySymbol] [nvarchar](13) NULL,
	[ExchangeRate] [decimal](38, 10) NULL,
	[CurrencyPrecision] [int] NULL
) ON [PRIMARY]
GO

