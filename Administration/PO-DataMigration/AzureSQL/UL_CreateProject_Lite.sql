/****** Object:  StoredProcedure [dbo].[UL_CreateProject_Lite]    Script Date: 6/9/2022 5:53:45 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [dbo].[UL_CreateProject_Lite]
AS

TRUNCATE TABLE UL_Project
INSERT INTO
   UL_Project
SELECT
   COALESCE (dpr.ProjectId,CAST (NULL as uniqueidentifier)) as Id,
   pr.ProjectName as msdyn_subject,
   pr.ProjectName as msdyn_description,
   msdyn_customer,
   msdyn_workhourtemplate,
   msdyn_owningcompany,
   msdyn_projectmanager,
   StartDate as msdyn_scheduledstart,
   EndDate as msdyn_finish, 
   Effort,   
   192350001 as Scheduler, -- Add-in
   scm.Value as SchedulingMode 
FROM
   CU_Project AS pr
LEFT JOIN (
   SELECT
      ProjectId,ProjectName
   FROM
      DL_Project ) as dpr
ON
   pr.ProjectName = dpr.ProjectName
LEFT JOIN (
   SELECT 
      Id as msdyn_owningcompany,CompanyCode
   FROM
      DL_Company ) AS co
ON
  pr.Company = co.CompanyCode
JOIN (
   SELECT
      Name,AccountId AS msdyn_customer,CompanyId
   FROM
       DL_Account) AS ac
ON
   pr.CustomerName = ac.Name 
JOIN (
   SELECT 
      SystemUserId AS msdyn_projectmanager,FullName
   FROM
      DL_User) AS us
ON
   pr.ProjectManager = us.FullName
JOIN (
   SELECT
      Id AS msdyn_workhourtemplate,Name
   FROM
      DL_WorkTemplate) AS wo
ON
   pr.Calendar = wo.Name
JOIN
   CO_ScheduleMode scm
ON
   pr.ScheduleMode = scm.Label
GO

