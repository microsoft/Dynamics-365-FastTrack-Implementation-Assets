/****** Object:  Table [dbo].[CU_Milestone]    Script Date: 2/17/2023 4:37:46 PM ******/
IF  EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[CU_Milestone]') AND type in (N'U'))
DROP TABLE [dbo].[CU_Milestone]
GO

/****** Object:  Table [dbo].[CU_Milestone]    Script Date: 2/17/2023 4:37:46 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[CU_Milestone](
	[Name] [nvarchar](300) NOT NULL,
	[ProjectOrder] [nvarchar](300) NOT NULL,
	[ProjectOrderLine] [nvarchar](300) NOT NULL,
	[Project] [nvarchar](255) NOT NULL,
	[Task] [nvarchar](450) NOT NULL,
	[MilestoneDate] [date] NOT NULL,
	[Amount] [money] NOT NULL,
	[InvoiceStatus] [nvarchar](50) NOT NULL
) ON [PRIMARY]
GO

INSERT INTO CU_Milestone VALUES 
('M1','MDD-DMProjectContract-0001','Software','MDD-DMProject-0001','DM-Task-0001','2023-02-25',250,'Ready for invoicing'),
('M2','MDD-DMProjectContract-0001','Software','MDD-DMProject-0001','DM-Task-0001','2023-03-25',250,'Not Ready for invoicing')

