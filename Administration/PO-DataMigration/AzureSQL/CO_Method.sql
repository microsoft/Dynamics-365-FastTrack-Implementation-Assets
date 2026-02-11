/****** Object:  Table [dbo].[CO_BillingMethod]    Script Date: 7/12/2022 1:24:40 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[CO_Method](
	[Label] [nvarchar](20) NULL,
	[Value] [int] NULL
) ON [PRIMARY]
GO

INSERT INTO CO_Method
VALUES 
  ('Cost',192350000),
  ('Purchase',192350001),
  ('Sales',192350002)

