/****** Object:  StoredProcedure [dbo].[UL_CreateQuote]    Script Date: 3/8/2022 3:10:30 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [dbo].[UL_CreateQuote]
AS 

TRUNCATE TABLE UL_Quote

INSERT INTO
   UL_Quote
SELECT 
   NEWID() as Id,
   qu.Name,
   co.id as CompanyId,
   PriceLevelId,
   AccountId as CustomerId,
   'account' as CustomerEntity,
   192350001 as OrderType --Work based
FROM
   CU_Quote qu
JOIN
	DL_Company co
ON
   qu.Company = co.CompanyCode
JOIN
   DL_PriceList pl
ON
   qu.PriceList = pl.Name
JOIN
   DL_Account ac
ON
   qu.Customer = ac.Name and
   co.Id = ac.CompanyId
GO

