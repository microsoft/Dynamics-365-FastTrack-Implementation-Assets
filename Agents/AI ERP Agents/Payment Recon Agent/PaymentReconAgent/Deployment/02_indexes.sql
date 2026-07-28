-- =============================================
-- INDEX CREATION SCRIPTS
-- Generated: 2026-02-24
-- Total Indexes: 20
-- =============================================

-- =============================================
-- CLEAN-INSTALL GUARD
-- Drop existing indexes first so the latest definitions are
-- deployed every time, even on a standalone re-run.
-- =============================================
DROP INDEX IF EXISTS [IX_PaymentProcessorStaging_PaymentRef] ON [dbo].[PaymentProcessorTransactionsStaging];
DROP INDEX IF EXISTS [IX_PaymentProcessorStaging_Status] ON [dbo].[PaymentProcessorTransactionsStaging];
DROP INDEX IF EXISTS [IX_PaymentProcessorStaging_ValidData] ON [dbo].[PaymentProcessorTransactionsStaging];
DROP INDEX IF EXISTS [IX_CommerceStaging_Dedup] ON [dbo].[CommercePaymentTransactionsStaging];
DROP INDEX IF EXISTS [IX_CommerceStaging_ValidData] ON [dbo].[CommercePaymentTransactionsStaging];
DROP INDEX IF EXISTS [CIX_CommercePaymentTransactions_TransactionId] ON [dbo].[CommercePaymentTransactions];
DROP INDEX IF EXISTS [IX_CommercePayment_Matching] ON [dbo].[CommercePaymentTransactions];
DROP INDEX IF EXISTS [IX_CommercePayment_ReconciliationId] ON [dbo].[CommercePaymentTransactions];
DROP INDEX IF EXISTS [IX_CommercePayment_Tendered_Filter] ON [dbo].[CommercePaymentTransactions];
DROP INDEX IF EXISTS [CIX_PaymentProcessorTransactions_PaymentReferenceId] ON [dbo].[PaymentProcessorTransactions];
DROP INDEX IF EXISTS [IX_PaymentProcessor_Matching] ON [dbo].[PaymentProcessorTransactions];
DROP INDEX IF EXISTS [IX_PaymentProcessor_ReconciliationId] ON [dbo].[PaymentProcessorTransactions];
DROP INDEX IF EXISTS [IX_PaymentProcessor_Status_Filter] ON [dbo].[PaymentProcessorTransactions];
DROP INDEX IF EXISTS [IX_PaymentProcessorTransactions_ReconciliationId_Status] ON [dbo].[PaymentProcessorTransactions];
DROP INDEX IF EXISTS [IX_PaymentProcessorHistory_PaymentRef] ON [dbo].[PaymentProcessorTransactionsHistory];
DROP INDEX IF EXISTS [IX_PaymentProcessorTransactionsHistory_ReconciliationId] ON [dbo].[PaymentProcessorTransactionsHistory];
DROP INDEX IF EXISTS [IX_CommerceHistory_Dedup] ON [dbo].[CommercePaymentTransactionsHistory];
DROP INDEX IF EXISTS [IX_CommercePaymentTransactionsHistory_ReconciliationId] ON [dbo].[CommercePaymentTransactionsHistory];

-- =============================================
-- STAGING TABLES
-- =============================================

-- PaymentProcessorTransactionsStaging Indexes
CREATE NONCLUSTERED INDEX [IX_PaymentProcessorStaging_PaymentRef]
ON [dbo].[PaymentProcessorTransactionsStaging] ([PaymentReferenceId] ASC, [Status] ASC)
INCLUDE ([Captured], [Currency], [PaymentMethod]);

CREATE NONCLUSTERED INDEX [IX_PaymentProcessorStaging_Status]
ON [dbo].[PaymentProcessorTransactionsStaging] ([Status] ASC)
INCLUDE ([PaymentReferenceId]);

CREATE NONCLUSTERED INDEX [IX_PaymentProcessorStaging_ValidData]
ON [dbo].[PaymentProcessorTransactionsStaging] ([PaymentReferenceId] ASC);

-- CommercePaymentTransactionsStaging Indexes
CREATE NONCLUSTERED INDEX [IX_CommerceStaging_Dedup]
ON [dbo].[CommercePaymentTransactionsStaging] ([TransactionId] ASC, [PaymentReferenceId] ASC)
INCLUDE ([Tendered], [Currency]);

CREATE NONCLUSTERED INDEX [IX_CommerceStaging_ValidData]
ON [dbo].[CommercePaymentTransactionsStaging] ([PaymentReferenceId] ASC);

-- =============================================
-- TRANSACTION TABLES (Active)
-- =============================================

-- CommercePaymentTransactions Indexes
CREATE CLUSTERED INDEX [CIX_CommercePaymentTransactions_TransactionId]
ON [dbo].[CommercePaymentTransactions] ([TransactionId] ASC);

CREATE NONCLUSTERED INDEX [IX_CommercePayment_Matching]
ON [dbo].[CommercePaymentTransactions] ([PaymentReferenceId] ASC, [ReconciliationId] ASC)
INCLUDE ([Tendered], [TransactionId], [Currency], [PaymentMethod], [TransactionDate]);

CREATE NONCLUSTERED INDEX [IX_CommercePayment_ReconciliationId]
ON [dbo].[CommercePaymentTransactions] ([ReconciliationId] ASC)
INCLUDE ([TransactionId], [PaymentReferenceId], [Tendered], [Currency], [TransactionDate]);

CREATE NONCLUSTERED INDEX [IX_CommercePayment_Tendered_Filter]
ON [dbo].[CommercePaymentTransactions] ([Tendered] ASC, [ReconciliationId] ASC)
INCLUDE ([PaymentReferenceId], [TransactionId], [Currency]);

-- PaymentProcessorTransactions Indexes
CREATE CLUSTERED INDEX [CIX_PaymentProcessorTransactions_PaymentReferenceId]
ON [dbo].[PaymentProcessorTransactions] ([PaymentReferenceId] ASC);

CREATE NONCLUSTERED INDEX [IX_PaymentProcessor_Matching]
ON [dbo].[PaymentProcessorTransactions] ([PaymentReferenceId] ASC, [Status] ASC, [ReconciliationId] ASC)
INCLUDE ([Captured], [Currency], [PaymentMethod]);

CREATE NONCLUSTERED INDEX [IX_PaymentProcessor_ReconciliationId]
ON [dbo].[PaymentProcessorTransactions] ([ReconciliationId] ASC)
INCLUDE ([PaymentReferenceId], [Status], [Captured], [Currency]);

CREATE NONCLUSTERED INDEX [IX_PaymentProcessor_Status_Filter]
ON [dbo].[PaymentProcessorTransactions] ([Status] ASC, [ReconciliationId] ASC)
INCLUDE ([PaymentReferenceId], [Captured]);

CREATE NONCLUSTERED INDEX [IX_PaymentProcessorTransactions_ReconciliationId_Status]
ON [dbo].[PaymentProcessorTransactions] ([ReconciliationId] ASC)
INCLUDE ([PaymentReferenceId], [Status]);

-- =============================================
-- HISTORY TABLES
-- =============================================

-- PaymentProcessorTransactionsHistory Indexes
CREATE NONCLUSTERED INDEX [IX_PaymentProcessorHistory_PaymentRef]
ON [dbo].[PaymentProcessorTransactionsHistory] ([PaymentReferenceId] ASC)
INCLUDE ([Status], [Captured], [ReconciliationId]);

CREATE NONCLUSTERED INDEX [IX_PaymentProcessorTransactionsHistory_ReconciliationId]
ON [dbo].[PaymentProcessorTransactionsHistory] ([ReconciliationId] ASC);

-- CommercePaymentTransactionsHistory Indexes
CREATE NONCLUSTERED INDEX [IX_CommerceHistory_Dedup]
ON [dbo].[CommercePaymentTransactionsHistory] ([TransactionId] ASC, [PaymentReferenceId] ASC)
INCLUDE ([Tendered], [ReconciliationId]);

CREATE NONCLUSTERED INDEX [IX_CommercePaymentTransactionsHistory_ReconciliationId]
ON [dbo].[CommercePaymentTransactionsHistory] ([ReconciliationId] ASC);


