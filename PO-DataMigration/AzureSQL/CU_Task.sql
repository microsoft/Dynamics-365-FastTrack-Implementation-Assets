/****** Object:  Table [dbo].[CU_Task]    Script Date: 11/28/2022 10:53:35 AM ******/
IF  EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[CU_Task]') AND type in (N'U'))
DROP TABLE [dbo].[CU_Task]
GO

/****** Object:  Table [dbo].[CU_Task]    Script Date: 11/28/2022 10:53:35 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[CU_Task](
	[ProjectName] [nvarchar](255) NULL,
	[Nr] [int] NULL,
	[TaskName] [nvarchar](450) NULL,
	[ParentTask] [int] NULL,
	[Effort] [float] NULL,
	[ScheduledStart] [date] NULL,
	[ScheduledEnd] [date] NULL,
	[Resource] [nvarchar](100) NULL,
	[Dependency] [int] NULL,
	[WBSNr] [nvarchar](20) null
) ON [PRIMARY]
GO

INSERT INTO CU_Task
VALUES
   ('MDD-AdventureWorks-001',	1,	'DM-Parent-0001',	NULL,  NULL, getdate(),	getdate()+5,	NULL,	NULL,'1'),
   ('MDD-AdventureWorks-001',	2,	'DM-Task-0001',	    1,	   16,	 getdate(), getdate()+2, 'SA Solutions Architect',	NULL,'1.1'),
   ('MDD-AdventureWorks-001',	3,	'DM-Task-0002',	    1,	   16,	 getdate()+3,getdate()+5,	'SA Solutions Architect',	2, '1.2')
      