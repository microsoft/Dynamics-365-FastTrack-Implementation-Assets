/****** Object:  StoredProcedure [dbo].[UL_CreateAccount]    Script Date: 7/12/2022 4:55:50 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


CREATE PROCEDURE [dbo].[UL_CreatePriceList]
AS

TRUNCATE TABLE UL_PriceList
INSERT INTO
   UL_PriceList
SELECT 
   COALESCE (dl.PriceLevelId,CAST (NULL as uniqueidentifier)) as PriceLevelId,
   pl.Name,cu.TransactionCurrencyId,StartDate,EndDate,
   me.Value as Context
FROM
    CU_PriceList pl 
LEFT JOIN
   DL_PriceList dl 
ON
   pl.Name = dl.Name
JOIN 
   DL_Currency cu
ON
   pl.Currency = cu.ISOCurrencyCode
JOIN
   CO_Method me
ON
   pl.Context = me.Label
GO


