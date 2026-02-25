/****** Object:  StoredProcedure [dbo].[UL_CreateRolePrice]    Script Date: 7/12/2022 9:04:03 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

/****** Object:  StoredProcedure [dbo].[UL_CreatePriceList]    Script Date: 7/12/2022 8:22:01 PM ******/

CREATE PROCEDURE [dbo].[UL_CreateRolePrice]
AS

TRUNCATE TABLE UL_RolePrice
INSERT INTO
   UL_RolePrice
SELECT 
   COALESCE (drp.ResourceCategoryPrice,CAST (NULL as uniqueidentifier)) as ResourceCategoryPrice,
   dpl.PriceLevelId as PriceLevelId,
   brc.ResourceCategoryId as RoleId,
   dou.OrganizationUnit as ResourcingUnitId,
   dun.UoMId, 
   crp.Price,
   dc.TransactionCurrencyId
FROM
   CU_RolePrice crp
LEFT JOIN
   DL_RolePrice drp
ON
   crp.PriceList = drp.PriceList and
   crp.[Role] = drp.[Role] and
   crp.ResourcingUnit = drp.ResourcingUnit
JOIN
   DL_PriceList dpl
ON
   crp.PriceList = dpl.[Name]
JOIN
   DL_BookableResourceCategory brc
ON
   crp.[Role] = brc.[Name]
JOIN
   DL_OrganizationalUnit dou
ON
   crp.ResourcingUnit = dou.[Name]
JOIN
   DL_Currency dc
ON
   crp.Currency = dc.ISOCurrencyCode
JOIN
	DL_Unit dun
ON
   crp.Unit = dun.[Name]

GO

