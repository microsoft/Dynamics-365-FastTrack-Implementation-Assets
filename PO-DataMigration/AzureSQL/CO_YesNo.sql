/****** Object:  Table [dbo].[CO_YesNo]    Script Date: 3/8/2022 3:38:17 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[CO_YesNo](
	[Label] [nvarchar](10) NULL,
	[Value] [int] NULL
) ON [PRIMARY]
GO

INSERT INTO CO_YesNo
VALUES
	( 'Yes' , 1 ),
	( 'No' , 0 )