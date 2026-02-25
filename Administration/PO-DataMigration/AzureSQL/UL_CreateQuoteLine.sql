/****** Object:  StoredProcedure [dbo].[UL_CreateQuoteLine]    Script Date: 3/8/2022 3:10:54 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [dbo].[UL_CreateQuoteLine]
AS

TRUNCATE TABLE UL_QuoteLine
INSERT INTO UL_QuoteLine
SELECT
   QuoteId, ql.Name,
   cast (NULL as uniqueidentifier) as QuoteDetailId,
   Value as BillingMethod,
   CASE upper(IncludeTime)
      WHEN 'YES' THEN 1
	  WHEN 'NO' THEN 0
   END as IncludeTime,
   CASE upper(IncludeExpense)
      WHEN 'YES' THEN 1
	  WHEN 'NO' THEN 0
   END as IncludeExpense,
      CASE upper(IncludeMaterial)
      WHEN 'YES' THEN 1
	  WHEN 'NO' THEN 0
   END as IncludeMaterial,
   CASE upper(IncludeFee)
      WHEN 'YES' THEN 1
	  WHEN 'NO' THEN 0
   END as IncludeFee,
   QuotedAmount as PricePerUnit,
   5 as ProjectType, --Project Service
   ql.Name as Description
FROM
   CU_QuoteLine ql
JOIN 
   DL_Quote qu
ON
  ql.[QuoteName] = qu.Name
JOIN
   CO_BillingMethod bm
ON
   ql.BillingMethod = bm.Label



GO

