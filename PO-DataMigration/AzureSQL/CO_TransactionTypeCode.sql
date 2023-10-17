/****** Object:  Table [dbo].[CO_AccountRelationshipType]    Script Date: 3/14/2022 10:12:55 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[CO_TransactionTypeCode](
	[Label] [nvarchar](50) NULL,
	[Value] [int] NULL
) ON [PRIMARY]
GO

INSERT INTO CO_TransactionTypeCode
VALUES
   ( 'Cost',192350000 ),
   ( 'Project Contract',192350004 ),
   ( 'Unbilled Sales', 192350005),
   ( 'Billed Sales', 192350006),
   ( 'Resourcing Unit Cost', 192350007),
   ( 'Inter-Organizational Sales',192350008 )
