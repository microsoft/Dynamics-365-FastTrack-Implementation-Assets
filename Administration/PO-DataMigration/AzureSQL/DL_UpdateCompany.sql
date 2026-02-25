/****** Object:  StoredProcedure [dbo].[DL_UpdateCompany]    Script Date: 3/8/2022 3:07:48 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [dbo].[DL_UpdateCompany]
AS

UPDATE DL_CustomerGroup
SET
   Company = co.CompanyCode
FROM 
   DL_CustomerGroup cg
JOIN
   DL_Company co
ON
   cg.CompanyId = co.Id
GO

