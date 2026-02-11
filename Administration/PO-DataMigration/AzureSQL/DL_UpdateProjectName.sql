/****** Object:  StoredProcedure [dbo].[DL_UpdateProjectName]    Script Date: 3/8/2022 3:08:08 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

-- =============================================
-- Author:      <Author, , Name>
-- Create Date: <Create Date, , >
-- Description: <Description, , >
-- =============================================
CREATE PROCEDURE [dbo].[DL_UpdateProjectName]

AS
BEGIN

    SET NOCOUNT ON

    UPDATE DL_ProjectTask
	SET 
	   ProjectName = pr.ProjectName
	FROM
	   DL_ProjectTask pt
	JOIN
       DL_Project pr
	ON
	   pt.ProjectId = pr.ProjectId
END
GO

