/****** Object:  Table [dbo].[CO_ScheduleMode]    Script Date: 9/4/2023 10:12:55 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[CO_ScheduleMode](
	[Label] [nvarchar](50) NULL,
	[Value] [int] NULL
) ON [PRIMARY]
GO

INSERT INTO CO_ScheduleMode
VALUES
   ( 'Fixed effort',  192350000 ),
   ( 'Fixed duration',192350001 ),
   ( 'Fixed units',   192350002 )
