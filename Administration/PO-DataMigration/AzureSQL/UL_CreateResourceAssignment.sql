/****** Object:  StoredProcedure [dbo].[UL_CreateResourceAssignment]    Script Date: 9/1/2023 9:04:03 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


CREATE PROCEDURE [dbo].[UL_CreateResourceAssignment]
AS

TRUNCATE TABLE UL_ResourceAssignment
INSERT INTO
   UL_ResourceAssignment
SELECT 
   CAST (NULL as uniqueidentifier) as id,
   dpr.ProjectId,TaskId,
   concat('resource',Nr) as [Name],
   bore.BookableResourceId,
   dte.Id as ProjectTeamId,
   task.Effort,
   task.Effort as EffortRemaining,
   task.ScheduledStart,task.ScheduledEnd
FROM
   CU_TASK as task 
JOIN 
   DL_BookableResource bore 
ON 
   task.Resource = bore.Name
JOIN 
   DL_Project dpr 
ON 
   task.ProjectName = dpr.ProjectName
JOIN 
   DL_ProjectTask dpt 
ON 
   dpr.ProjectId = dpt.ProjectId and
   task.TaskName = dpt.TaskName
JOIN
   DL_ProjectTeam dte
ON
   dpr.ProjectId = dte.Project and
   bore.BookableResourceId = dte.BookableResourceId

GO