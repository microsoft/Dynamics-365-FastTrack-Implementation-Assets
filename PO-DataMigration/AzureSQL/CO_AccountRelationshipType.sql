/****** Object:  Table [dbo].[CO_AccountRelationshipType]    Script Date: 3/8/2022 3:14:20 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[CO_AccountRelationshipType](
	[Label] [nvarchar](50) NULL,
	[Value] [int] NULL
) ON [PRIMARY]
GO

INSERT INTO CO_AccountRelationshipType
VALUES 
	( 'Competitor', 1 ),
	( 'Consultant', 2 ),
	( 'Customer', 3 ),
	( 'Investor', 4 ),
	( 'Partner', 5 ),
	( 'Influencer', 6 ),
	( 'Press', 7 ),
	( 'Prospect', 8 ),
	( 'Reseller', 9 ),
	( 'Supplier', 10 ),
	( 'Vendor', 11 ),
	( 'Other', 12 )