/****** Object:  Table [dbo].[CO_TimeEntryType]    Script Date: 3/8/2022 3:34:15 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[CO_TimeEntryType](
	[Label] [nvarchar](50) NULL,
	[Value] [int] NULL
) ON [PRIMARY]
GO

INSERT INTO CO_TimeEntryType
VALUES
	( 'Overtime', 192354320 ),
	( 'Work', 192350000 ),
	( 'Absence', 192350001 ),
	( 'Vacation', 192350002 )