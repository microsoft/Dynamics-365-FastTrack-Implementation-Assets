
CREATE TABLE UL_TransactionCategory (
   TransactionCategory uniqueidentifier null,
   Name nvarchar(100),
   CategoryId nvarchar(100),
   BillingType int
)

INSERT INTO 
   UL_TransactionCategory 
SELECT
   NULL,
   'Test New',
   'Test New',
   (SELECT Value FROM CO_BillingType where Label = 'Chargeable')