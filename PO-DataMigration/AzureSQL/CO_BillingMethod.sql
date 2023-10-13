/****** Object:  Table [dbo].[CO_BillingMethod]    Script Date: 3/8/2022 3:31:21 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[CO_BillingMethod](
	[Label] [nvarchar](20) NULL,
	[Value] [int] NULL
) ON [PRIMARY]
GO

INSERT INTO CO_BillingMethod
VALUES 
    ( 'Time and Material', 192350000),
    ( 'Fixed Price', 192350001)
 