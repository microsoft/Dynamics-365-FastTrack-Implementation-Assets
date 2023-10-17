/****** Object:  StoredProcedure [dbo].[UL_CreateProjectOrder]    Script Date: 8/25/2023 3:53:59 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


CREATE PROCEDURE [dbo].[UL_CreateProjectOrder]
AS

TRUNCATE TABLE UL_ProjectOrder
INSERT INTO
   UL_ProjectOrder
SELECT
   CAST (NULL as uniqueidentifier) as Id,
   po.Name,
   AccountId,
   CompanyId,
   'account'  as CustomerEntity,
   192350001 as OrderType --Work based
FROM
   CU_ProjectOrder po
LEFT JOIN 
   DL_Account ac
ON
   po.Customer = ac.Name

GO

