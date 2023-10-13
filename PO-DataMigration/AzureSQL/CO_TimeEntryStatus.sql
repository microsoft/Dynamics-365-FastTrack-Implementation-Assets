/****** Object:  Table [dbo].[CO_YesNo]    Script Date: 3/15/2022 8:20:45 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[CO_TimeEntryStatus](
	[Label] [nvarchar](20) NULL,
	[Value] [int] NULL
) ON [PRIMARY]
GO

INSERT INTO CO_TimeEntryStatus
VALUES
   ( 'Cancelled', 192354320),
   ( 'Draft', 192350000),
   ( 'Returned', 192350001 ),
   ( 'Approved', 192350002),
   ( 'Submitted', 192350003),
   ( 'Recall Requested', 192350004)