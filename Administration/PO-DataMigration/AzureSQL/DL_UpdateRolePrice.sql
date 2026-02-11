/****** Object:  StoredProcedure [dbo].[DL_UpdateRolePrice]    Script Date: 7/12/2022 9:00:02 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [dbo].[DL_UpdateRolePrice]
AS

UPDATE DL_RolePrice
SET
   PriceList = pl.[Name],
   ResourcingUnit = ou.[Name],
   [Role] = br.[Name]
FROM 
    DL_RolePrice rp 
JOIN 
    DL_PriceList pl
ON
   rp.PriceListId = pl.PriceLevelId
JOIN
   DL_OrganizationalUnit ou
ON
   rp.ResourcingUnitId = ou.OrganizationUnit
JOIN
   DL_BookableResourceCategory br
ON
   rp.RoleId = br.ResourceCategoryId


   select * from DL_RolePrice
GO

