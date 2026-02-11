/****** Object:  Table [dbo].[CO_AccountRelationshipType]    Script Date: 3/14/2022 10:12:55 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[CO_TransactionClassification](
	[Label] [nvarchar](50) NULL,
	[Value] [int] NULL
) ON [PRIMARY]
GO

INSERT INTO CO_TransactionClassification
VALUES
   ( 'Time',192350000),
   ( 'Expense',192350001),
   ( 'Material',192350002),
   ( 'Milestone', 192350003),
   ( 'Fee',192350004 ),
   ( 'Retainer', 192350005),
   ( 'Tax',690970002 )