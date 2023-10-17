CREATE PROCEDURE UL_CreateJournalLine
AS

TRUNCATE TABLE UL_JournalLine
INSERT INTO UL_JournalLine
SELECT
   CAST (NULL as uniqueIdentifier) as Id,
   jo.Id as Journal,
   ttc.Value as TransactionTypeCode,
   tc.Value as TransactionClass,
   DocumentDate,
   DocumentDate as StartDate,
   DocumentDate as EndDate,
   ProjectId as Project,
   ResourceCategoryId as ResourceCategory,
   Quantity,
   Price, 
   (SELECT value FROM CO_BillingType where Label = 'Chargeable') as BillingType
FROM
   CU_JournalLine jl
JOIN
   DL_Journal jo
ON
   jl.JournalName = jo.Description and
   jo.Posted = 0
JOIN
   CO_TransactionTypeCode ttc
ON
  jl.TransactionType = ttc.Label
JOIN
   CO_TransactionClassification tc
ON
  jl.TransactionClass = tc.Label
JOIN
   DL_Project pr
ON
   jl.Project = pr.ProjectName
JOIN
   DL_BookableResourceCategory brc
ON
   jl.Role = brc.Name
GO