/****** Object:  Table [dbo].[CO_AccountRelationshipType]    Script Date: 3/14/2022 10:12:55 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[CO_BillingType](
	[Label] [nvarchar](50) NULL,
	[Value] [int] NULL
) ON [PRIMARY]
GO

INSERT INTO CO_BillingType
VALUES
   ( 'Non Chargeable',19235000 ),
   ( 'Chargeable',192350001 ),
   ( 'Complementary',192350002 ),
   ( 'Not Available',192350003 )