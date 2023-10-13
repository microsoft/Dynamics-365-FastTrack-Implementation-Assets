/****** Object:  Table [dbo].[CU_Project]    Script Date: 3/12/2022 10:34:06 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

IF (EXISTS(SELECT object_id FROM sys.tables where name = 'CU_PROJECT'))
BEGIN
  DROP TABLE CU_PROJECT
END

CREATE TABLE [dbo].[CU_Project](
	[ProjectName] [nvarchar](255) NULL,
	[CustomerName] [nvarchar](160) NULL,
	[Calendar] [nvarchar](100) NULL,
	[Company] [nvarchar](20) NULL,
	[ProjectManager] [nvarchar](200) NULL,
	[StartDate] [date] NULL,
	[EndDate] [date] NULL,
	[Effort] [float] NULL,
        [ScheduleMode] [nvarchar](50) NULL
) ON [PRIMARY]
GO

