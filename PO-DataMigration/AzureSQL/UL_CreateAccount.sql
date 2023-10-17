/****** Object:  StoredProcedure [dbo].[UL_CreateAccount]    Script Date: 3/8/2022 3:09:37 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [dbo].[UL_CreateAccount]
AS

TRUNCATE TABLE UL_Account
INSERT INTO
   UL_Account
SELECT 
   COALESCE (dl.AccountId,CAST (NULL as uniqueidentifier)) as AccountId,
   ac.Name,
   cu.TransactionCurrencyId as CurrencyId,  
   cg.CompanyId,ac.AccountNumber,
   (SELECT value FROM CO_AccountRelationshipType WHERE label = 'Customer') as Relationship,
   CustomerGroup,
   pl.PriceLevelId as PriceList
FROM
    CU_Account ac 
LEFT JOIN
   DL_Account dl 
on
   ac.AccountNumber = dl.AccountNumber
JOIN
	DL_CustomerGroup cg
ON
   ac.Company = cg.Company and
   ac.CustomerGroupId = cg.CustomerGroupId
JOIN
    DL_PriceList pl
ON
   ac.PriceList = pl.Name
JOIN
   DL_Currency cu
ON
   ac.Currency = cu.IsoCurrencyCode
GO

