-- ============================================================
-- INSERT SCRIPT: [dbo].[ReconciliationRules]
-- Generated: 2026-03-24
-- ============================================================

INSERT INTO [dbo].[ReconciliationRules] 
    ([ExecutionOrder], [Stage], [RuleCode], [RuleDescription], [CreatedAt], [ModifiedAt], [IsSystemRule], [PolicyDriven])
VALUES

-- -------------------------
-- STAGE: INITIALIZE
-- -------------------------
(2100, 'INITIALIZE', 'FIND_INPROGRESS',
'Query ReconciliationExecution for any run currently in an InProgress state, ordered by oldest first. If a row is found, capture its ReconciliationId as {ActiveExecutionId} and proceed to MOVE_INPROGRESS_TO_HISTORY to clean it up. If no rows are found, skip MOVE_INPROGRESS_TO_HISTORY and COMPLETE_INPROGRESS_EXECUTION and go directly to CREATE_EXECUTION.',
'2026-03-13T03:05:17.933', '2026-03-13T03:05:17.933', 1, 0),

(2200, 'INITIALIZE', 'MOVE_INPROGRESS_TO_HISTORY',
'Safely archive all transactions belonging to the previously unfinished run identified by {ActiveExecutionId}. Runs inside a single transaction across five phases: (1) count Commerce and PSP records stamped with {ActiveExecutionId} and store as expected counts; (2) copy Commerce records to CommercePaymentTransactionsHistory using INSERT WHERE NOT EXISTS; (3) copy PSP records to PaymentProcessorTransactionsHistory using INSERT WHERE NOT EXISTS; (4) re-verify History counts match the expected counts before any deletes — rollback and hard stop if either count does not match; (5) delete the records from the active Commerce and PSP transaction tables only after count confirmation.',
'2026-03-13T03:05:17.933', '2026-03-13T03:05:17.933', 1, 0),

(2300, 'INITIALIZE', 'COMPLETE_INPROGRESS_EXECUTION',
'Mark the previously InProgress execution as Completed. Recalculates the final Commerce and PSP record counts directly from History and writes them to CommerceRecords and PaymentRecords on the execution row. Also updates ReconciliationDate to the current UTC time. If 0 rows are updated the execution record was not found or its status has changed — hard stop and investigate. If 1 row is updated the cleanup is done and CREATE_EXECUTION can proceed.',
'2026-03-13T03:05:17.933', '2026-03-13T03:05:17.933', 1, 0),

(2400, 'INITIALIZE', 'CREATE_EXECUTION',
'Insert a new ReconciliationExecution record with status InProgress and a unique ID in the format RECONyyyyMMddHHmmss + 6 random alphanumeric characters. The insert is guarded by a WHERE NOT EXISTS check — if another InProgress run already exists the insert is skipped and FIND_INPROGRESS must be run to investigate. If 1 row is inserted, immediately capture the generated ReconciliationId by selecting the most recent InProgress row and store it as {ExecutionId} for all subsequent stages.',
'2026-03-13T03:05:17.933', '2026-03-13T03:05:17.933', 1, 0),

-- -------------------------
-- STAGE: PREPROCESS
-- -------------------------
(3100, 'PREPROCESS', 'CHECK_STAGING_EMPTY',
'Count the rows currently waiting in both staging tables — CommercePaymentTransactionsStaging and PaymentProcessorTransactionsStaging. If both counts are zero there is no new data to import; skip all remaining PREPROCESS steps and proceed directly to the CLEANSING stage.',
'2026-03-13T03:05:17.933', '2026-03-13T03:05:17.933', 1, 0),

(3200, 'PREPROCESS', 'PSP_CLEAN_STAGING',
'Delete invalid rows from PaymentProcessorTransactionsStaging. A row is invalid if its PaymentReferenceId is null or blank, or if its Status is anything other than SentForSettle or SentForRefund. Only those two status values are permitted to flow into reconciliation.',
'2026-03-13T03:05:17.933', '2026-03-13T03:05:17.933', 1, 0),

(3300, 'PREPROCESS', 'PSP_DEDUPLICATE',
'Remove PSP staging rows that already exist in either the active PaymentProcessorTransactions table or PaymentProcessorTransactionsHistory, preventing duplicate records from being loaded. Matching is composite: always matches on PaymentReferenceId, and additionally matches on ModificationMerchantReference when the staging row has a non-null value for that field. Runs as two sequential delete blocks inside a single transaction — one against the active table, one against History.',
'2026-03-13T03:05:17.933', '2026-03-13T03:05:17.933', 1, 0),

(3400, 'PREPROCESS', 'PSP_INSERT_TRANSACTIONS',
'Insert all remaining PSP staging rows into PaymentProcessorTransactions, but only if the staging table is not empty. Amount fields are passed exactly as-is and are never defaulted. Status defaults to Unknown if null. ReconciliationId is always forced to an empty string on insert — it must never be copied or inherited from staging. Remarks is always forced to an empty string. All other fields are taken directly from staging.',
'2026-03-13T03:05:17.933', '2026-03-13T03:05:17.933', 1, 0),

(3500, 'PREPROCESS', 'COMMERCE_CLEAN_STAGING',
'Delete invalid rows from CommercePaymentTransactionsStaging. A row is invalid if its PaymentReferenceId is null or blank.',
'2026-03-13T03:05:17.933', '2026-03-13T03:05:17.933', 1, 0),

(3600, 'PREPROCESS', 'COMMERCE_DEDUPLICATE',
'Remove Commerce staging rows that already exist in either the active CommercePaymentTransactions table or CommercePaymentTransactionsHistory, matching on PaymentReferenceId. Runs as two sequential delete blocks inside a single transaction — one against the active table, one against History.',
'2026-03-13T03:05:17.933', '2026-03-13T03:05:17.933', 1, 0),

(3700, 'PREPROCESS', 'COMMERCE_INSERT_TRANSACTIONS',
'Insert all remaining Commerce staging rows into CommercePaymentTransactions, but only if the staging table is not empty. NULL text fields (PaymentMethod, StoreId, TerminalId, Currency) are defaulted to empty string. The Tendered amount is passed as-is including NULL — NULL values are intentionally left for the CLEANSING stage to handle via NULL_NUMERIC_FIELDS. ReconciliationId and Remarks are always forced to empty string. A final WHERE NOT EXISTS guard on both the active table and History prevents any duplicates slipping through.',
'2026-03-13T03:05:17.933', '2026-03-13T03:05:17.933', 1, 0),

(3800, 'PREPROCESS', 'CLEANUP_STAGING',
'Delete all remaining rows from both staging tables now that the data has been loaded into the main transaction tables. Each table is only deleted from if it contains rows — if either is already empty a row count of 0 is returned for that table. Both deletes run inside a single transaction.',
'2026-03-13T03:05:17.933', '2026-03-13T03:05:17.933', 1, 0),

-- -------------------------
-- STAGE: RECONCILIATION
-- -------------------------
(5200, 'RECONCILIATION', 'MATCH_TRANSACTIONS_POLICY1',
'Policy-1 — Settled transactions. Finds all PaymentReferenceIds where the sum of Tendered in CommercePaymentTransactions (positive amounts, not yet reconciled) exactly matches the sum of Captured in PaymentProcessorTransactions (positive amounts, Status = SentForSettle, not yet reconciled). Stamps matching Commerce rows first with {ExecutionId} and the remark Policy-1: Settled Transaction - Amount Match. Then stamps the corresponding PSP rows using the already-stamped Commerce rows as the source of truth. Both updates run inside a single transaction.',
'2026-03-13T03:05:17.933', '2026-03-13T03:05:17.933', 1, 1),

(5300, 'RECONCILIATION', 'MATCH_TRANSACTIONS_POLICY2',
'Policy-2 — Refund transactions. Finds all PaymentReferenceIds where the sum of Tendered in CommercePaymentTransactions (negative amounts, not yet reconciled) exactly matches the sum of Captured in PaymentProcessorTransactions (negative amounts, Status = SentForRefund, not yet reconciled). Stamps matching Commerce rows first with {ExecutionId} and the remark Policy-2: Refund Transaction - Amount Match. Then stamps the corresponding PSP rows using the already-stamped Commerce rows as the source of truth. Both updates run inside a single transaction.',
'2026-03-13T03:05:17.933', '2026-03-13T03:05:17.933', 1, 1),

-- -------------------------
-- STAGE: POSTPROCESSING
-- -------------------------
(6100, 'POSTPROCESSING', 'MOVE_TO_HISTORY',
'Move all transactions stamped with {ExecutionId} from the active transaction tables into their respective History tables, then delete them from the active tables. Commerce records are inserted into CommercePaymentTransactionsHistory first, then deleted from CommercePaymentTransactions. PSP records are inserted into PaymentProcessorTransactionsHistory first, then deleted from PaymentProcessorTransactions. All four operations run inside a single transaction.',
'2026-03-13T03:05:17.933', '2026-03-13T03:05:17.933', 1, 0),

(6200, 'POSTPROCESSING', 'FLAG_UNMATCHED',
'No SQL execution required. Transactions that were not matched by any policy are intentionally left as-is in the active transaction tables. They will be picked up and re-evaluated in a future reconciliation run.',
'2026-03-13T03:05:17.933', '2026-03-13T03:05:17.933', 1, 0),

-- -------------------------
-- STAGE: FINALIZATION
-- -------------------------
(7200, 'FINALIZATION', 'UPDATE_STATUS',
'Update the ReconciliationExecution record for {ExecutionId} to Completed and set ReconciliationDate to the current UTC time. The update is guarded so it only applies if the row is still in an InProgress state. If 0 rows are updated the execution record was not found or was already completed — investigate before proceeding.',
'2026-03-13T03:05:17.933', '2026-03-13T03:05:17.933', 1, 0),

(7300, 'FINALIZATION', 'RECALCULATE_METRICS',
'For the 5 most recently completed reconciliation runs, recalculate the actual Commerce and PSP record counts from the History tables and update CommerceRecords and PaymentRecords on the execution rows where the stored values are missing or out of sync. Only rows where at least one count differs or is null are updated. After the update, return the 5 most recently completed runs as a final summary showing ReconciliationId, ReconciliationDate, Status, CommerceRecords, and PaymentRecords.',
'2026-03-13T03:05:17.933', '2026-03-13T03:05:17.933', 1, 0);