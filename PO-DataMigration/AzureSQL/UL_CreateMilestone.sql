CREATE PROCEDURE UL_Create_Milestone
AS

TRUNCATE TABLE UL_Milestone
INSERT INTO	
   UL_Milestone
SELECT
   CAST (NULL as uniqueidentifier) as Id,
   ms.Name,Amount,
   ol.Id as ContractLineId,
   MilestoneDate,
   192350000 as InvoiceStatus --not ready for invoicing
FROM 
   CU_Milestone ms
JOIN
   DL_ProjectOrder po
ON
   ms.ProjectOrder = po.Name
JOIN
   DL_OrderLine ol
ON
   ms.ProjectOrderLine = ol.Name and
   po.Id = ol.[Order]


