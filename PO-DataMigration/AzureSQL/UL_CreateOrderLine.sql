/****** Object:  StoredProcedure [dbo].[UL_CreateOrderLine]    Script Date: 3/14/2022 4:43:24 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [dbo].[UL_CreateOrderLine]
AS

TRUNCATE TABLE UL_OrderLine
INSERT INTO
   UL_OrderLIne
SELECT
   CAST (NULL as uniqueidentifier) as Id,
   ol.Name,
   ol.Name as ProductDescription,
   po.id as [Order],
   1.0 as Quantity,
   Amount as PricePerUnit,
   bm.value as BillingMethod,
   (SELECT value FROM CO_YesNO WHERE Label = ol.IncludeTime) as IncludeTime,
   (SELECT value FROM CO_YesNO WHERE Label = ol.IncludeExpense) as IncludeExpense,
   (SELECT value FROM CO_YesNO WHERE Label = ol.IncludeMaterial) as IncludeMaterial,
   (SELECT value FROM CO_YesNO WHERE Label = ol.IncludeFee) as IncludeFee,
   690970000 as LineType, --Project Service Line
   5 as ProductType --Project-based Service
FROM
   CU_OrderLine ol
JOIN
   DL_ProjectOrder po
ON
   ol.OrderName = po.name
JOIN
   CO_BillingMethod bm
ON
   ol.BillingMethod = bm.Label
GO

