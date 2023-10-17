/****** Object:  StoredProcedure [dbo].[UL_CreateTimeEntry]    Script Date: 3/15/2022 8:30:07 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [dbo].[UL_CreateTimeEntry]
AS

TRUNCATE TABLE UL_TimeEntry
INSERT INTO
   UL_TimeEntry
SELECT
   newid() as TimeEntryId,
   Duration, Description,ExternalDescription,
   (SELECT Value FROM CO_TimeEntryStatus WHERE Label = 'Draft') as EntryStatus, 
   (SELECT TimeSource FROM DL_TimeSource WHERE Name = 'Project Service') as TimeSource,
   ProjectId,TaskId,br.ResourceCategoryId,
   et.Value as Type,
   [Date], co.Id,
   EntryStatus as TargetStatus
FROM
   CU_TimeEntry te
JOIN
   DL_BookableResourceCategory br
ON
   te.Role = br.Name
JOIN
   DL_ProjectTask pt
ON
   te.ProjectName = pt.ProjectName and
   te.TaskName = pt.TaskName
JOIN
	CO_TimeEntryType as et
ON
   te.Type = et.Label
JOIN
   DL_Company co
ON
   'USPM' = co.CompanyCode
GO

