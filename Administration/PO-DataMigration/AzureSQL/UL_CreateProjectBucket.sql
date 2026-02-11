/****** Object:  StoredProcedure [dbo].[UL_CreateProjectBucket]    Script Date: 6/9/2022 5:53:45 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [dbo].[UL_CreateProjectBucket]
AS

TRUNCATE TABLE UL_ProjectBucket
INSERT INTO
   UL_ProjectBucket
SELECT
   CAST (NULL as uniqueidentifier) as msdyn_projectbucketid,
   'Bucket 1' as msdyn_name,
   ProjectId as msdyn_projectid
FROM (
   SELECT 
      msdyn_subject
   FROM 
      UL_Project 
   WHERE
      id is NULL) as upr
JOIN (
   SELECT
      ProjectId,ProjectName
   FROM
      DL_Project ) as dpr
ON
   upr.msdyn_subject = dpr.ProjectName


GO

