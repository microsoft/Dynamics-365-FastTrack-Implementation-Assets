/****** Object:  Table [dbo].[CU_Actual]    Script Date: 2/20/2023 10:27:01 AM ******/
IF  EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[CU_Actual]') AND type in (N'U'))
DROP TABLE [dbo].[CU_Actual]
GO

/****** Object:  Table [dbo].[CU_Actual]    Script Date: 2/20/2023 10:27:01 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[CU_Actual](
	[ProjectName] [nvarchar](255) NOT NULL
) ON [PRIMARY]
GO

INSERT INTO CU_ACTUAL Values ('MDD-DMProject-0001')
