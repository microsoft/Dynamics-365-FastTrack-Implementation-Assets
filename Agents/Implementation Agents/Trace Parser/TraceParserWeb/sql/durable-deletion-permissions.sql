-- REVIEWED PROVISIONING TEMPLATE ONLY. Do not run without separate rollout approval.
-- Create dedicated contained users through your approved identity provisioning process.
-- No credentials, database roles, table access or importer privilege is granted here.
SET XACT_ABORT ON;
IF USER_ID('TraceParserDeletionWeb') IS NULL OR USER_ID('TraceParserDeletionWorker') IS NULL
    THROW 51200,'Provision distinct least-privilege contained identities before applying this template.',1;
IF IS_ROLEMEMBER('db_owner','TraceParserDeletionWeb')=1
    OR IS_ROLEMEMBER('db_owner','TraceParserDeletionWorker')=1
    OR IS_ROLEMEMBER('db_datawriter','TraceParserDeletionWeb')=1
    OR IS_ROLEMEMBER('db_datawriter','TraceParserDeletionWorker')=1
    THROW 51200,'Deletion identities must not inherit owner or table-writer roles.',1;
BEGIN TRAN;
GRANT EXECUTE ON OBJECT::dbo.dj_Enqueue TO TraceParserDeletionWeb;
GRANT EXECUTE ON OBJECT::dbo.dj_Read TO TraceParserDeletionWeb;
GRANT EXECUTE ON OBJECT::dbo.dj_Control TO TraceParserDeletionWeb;
GRANT EXECUTE ON OBJECT::dbo.dj_Claim TO TraceParserDeletionWorker;
GRANT EXECUTE ON OBJECT::dbo.dj_Step TO TraceParserDeletionWorker;
GRANT EXECUTE ON OBJECT::dbo.dj_Inspect TO TraceParserDeletionWorker;
GRANT EXECUTE ON OBJECT::dbo.dj_Renew TO TraceParserDeletionWorker;
GRANT EXECUTE ON OBJECT::dbo.dj_Release TO TraceParserDeletionWorker;
COMMIT;
-- dj_AssertProtocol is a fixed metadata-only owner module, reached by ownership chain.
-- Do not grant it directly; do not grant sp_DeleteTrace, SELECT Traces, schema EXECUTE,
-- table DML, VIEW DEFINITION, db_owner or importer tp_* access to the worker.
-- Separately audit effective permissions (including nested roles/Entra groups).
-- Existing legacy deletion grants can remain for disabled-mode compatibility:
-- sp_DeleteTrace explicitly refuses every active durable job, including held jobs.
