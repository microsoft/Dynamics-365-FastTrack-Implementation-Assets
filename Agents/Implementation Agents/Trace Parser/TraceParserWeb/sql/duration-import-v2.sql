-- One-time upgrade from the deployed 9ac6f05 importer. NOT a bootstrap/reset.
-- Quiesce writers first. SQL -> v2-capable worker -> new web registrations.
-- Old web keeps registering v1; old workers explicitly refuse v2.
-- Roll back binaries only after draining/holding v2; never downgrade receipts.
-- This batch changes four modules, not any receipt, row, hash, identity, FK or job.
SET XACT_ABORT ON;
IF @@TRANCOUNT<>0 THROW 51128,'Duration upgrade requires its own transaction.',1;
BEGIN TRY
    BEGIN TRAN;
    DECLARE @rc int;
    EXEC @rc=sys.sp_getapplock @Resource='TraceParser:Importer:v1',
        @LockMode='Exclusive',@LockOwner='Transaction',@LockTimeout=0;
    IF @rc<0 THROW 51128,'Importer must be quiescent for duration upgrade.',1;
    EXEC dbo.tp_AssertDeletionProtocol;
    EXEC dbo.dj_AssertProtocol;

    DECLARE @baseline TABLE(Name sysname PRIMARY KEY, Hash binary(32));
    INSERT @baseline VALUES
    ('tp_RegisterUpload',0x869DF9D36291FE97EC591ED9A3881CA2180A9474D897BD20BE5DA366A703EDF9),
    ('tp_GetImportStatus',0x900C4F64405EEF2068A50FFC16C65D2256F19CFDFEBFD2843DEC51AA217B7F92),
    ('tp_AssertDeletionProtocol',0x3863061C083BBBA36BF1B11215C26EF1E1C5CC3A49D23DF907798A557B7B6C95),
    ('tp_AssertImporterStorage',0xAEA6968AAAF4A9F7AADB9FD2C670C7DBAF31962E0FD4577428CBEF2E129B3E41),
    ('tp_AssertImportOwner',0x1C41B7A6E758FA531FED83B63F756EE448FF067E33202AA8E71C25C6F2F8197F),
    ('tp_ReserveTraceLineIds',0x406701376C5824EEC293D53E19A0AB56D88681C1913E8D060721158391E16CDB),
    ('tp_BeginImport',0x27339027071C9A895728839CC539ECB709445C12438B4DA12227A763FE68F3E8),
    ('tp_SetImportContentHash',0x30465E26320AD6ADD7DCFE93FB2831B4BFC8872B971EB62EE2ECF19617EFC68D),
    ('tp_StageImportBatch',0x2FF5CD47651BAA6F4E7C8755266EC613173C22B498B553D4C1E8CAD022D1CF19),
    ('tp_MapImportThread',0xFC3C12A1B76C34EC18E147D5C042CBCEBD97C5C9ADCEDEDD56EF00274C689991),
    ('tp_MarkImportReady',0x17750416A880A671119BA961CFE783772189DA3B4EBD52BBA416753BDBDE7B3A),
    ('tp_PromoteImportBinds',0xC1DD909CDDF325841811AA49F28CA58990010DCC8E41939E9DD61B279C668304),
    ('tp_PromoteImportBatch',0x577F54AE19E3C2F4D8F90EF666C23813110068E88E498B489ECD8D7BA5593D14),
    ('tp_CompleteImport',0x3E6F6D042EF47C556E1A324AD380264ED71211DD8A6F70E3721B1F20CD6EB218),
    ('tp_CleanupCompletedImport',0xF76B21A9D781B957D950E87EB05AA655A7676C348ADFEE6D9B19EA584EC707BD),
    ('tp_RecordImportFailure',0xDE6677E6779B45AD62B174BA096902BFE58592B3E2AABFBCA492E1385A5B3241);
    IF (SELECT COUNT(*) FROM sys.procedures WHERE schema_id=SCHEMA_ID('dbo') AND name LIKE 'tp[_]%')<>16
       OR EXISTS(SELECT 1 FROM @baseline b WHERE
         ISNULL(HASHBYTES('SHA2_256',OBJECT_DEFINITION(OBJECT_ID('dbo.'+b.Name))),0x)<>b.Hash)
        THROW 51128,'Exact deployed importer module baseline required; no automatic adoption.',1;
    IF HASHBYTES('SHA2_256',OBJECT_DEFINITION(OBJECT_ID('dbo.sp_DeleteTrace')))<>
        0x34027474DD6A7CBFD9885291765DC62A319153E32AEF18D3E82240791091707C
        THROW 51128,'Exact coordinated durable deletion baseline required.',1;

    -- Edits are applied only to the fully fingerprinted definitions above.
    DECLARE @sql nvarchar(max)=OBJECT_DEFINITION(OBJECT_ID('dbo.tp_RegisterUpload'));
    SET @sql=REPLACE(@sql,N'@SessionName nvarchar(500)',N'@SessionName nvarchar(500), @ParserVersion varchar(40)=''safe-import-v1''');
    SET @sql=REPLACE(@sql,N'IF @ImportId IS NULL',N'IF @ParserVersion IS NULL OR DATALENGTH(@ParserVersion)<>14 OR @ParserVersion COLLATE Latin1_General_100_BIN2 NOT IN (''safe-import-v1'',''safe-import-v2'')
       THROW 51107,''Unsupported parser contract.'',1;
    IF @ImportId IS NULL');
    SET @sql=REPLACE(@sql,N'BlobName,SessionName)',N'BlobName,SessionName,ParserVersion)');
    SET @sql=REPLACE(@sql,N'@BlobName,@SessionName)',N'@BlobName,@SessionName,@ParserVersion)');
    SET @sql=STUFF(@sql,CHARINDEX(N'CREATE',@sql),6,N'ALTER');
    EXEC sys.sp_executesql @sql;

    SET @sql=OBJECT_DEFINITION(OBJECT_ID('dbo.tp_BeginImport'));
    SET @sql=REPLACE(@sql,N'@ContentLength bigint',N'@ContentLength bigint, @WorkerVersion varchar(40)=''safe-import-v1''');
    SET @sql=REPLACE(@sql,N'@session nvarchar(500);',N'@session nvarchar(500), @parser varchar(40);');
    SET @sql=REPLACE(@sql,N'@session=SessionName',N'@session=SessionName,@parser=ParserVersion');
    SET @sql=REPLACE(@sql,N'OR EXISTS(SELECT 1 FROM dbo.TPImportReceipts WHERE ImportId=@id AND ParserVersion<>''safe-import-v1'')',
       N'OR @WorkerVersion IS NULL OR DATALENGTH(@WorkerVersion)<>14 OR @WorkerVersion COLLATE Latin1_General_100_BIN2 NOT IN (''safe-import-v1'',''safe-import-v2'')
       OR DATALENGTH(@parser)<>14 OR @parser COLLATE Latin1_General_100_BIN2 NOT IN (''safe-import-v1'',''safe-import-v2'')
       OR (@parser=''safe-import-v2'' AND @WorkerVersion<>''safe-import-v2'')');
    SET @sql=REPLACE(@sql,N'GETUTCDATE(),GETUTCDATE(),''safe-import-v1'')',N'GETUTCDATE(),GETUTCDATE(),@parser)');
    SET @sql=REPLACE(@sql,N'SELECT ImportId,TraceId,Phase,LastPromotedId FROM',
        N'SELECT ImportId,TraceId,Phase,LastPromotedId,ParserVersion FROM');
    SET @sql=STUFF(@sql,CHARINDEX(N'CREATE',@sql),6,N'ALTER');
    EXEC sys.sp_executesql @sql;

    SET @sql=OBJECT_DEFINITION(OBJECT_ID('dbo.tp_SetImportContentHash'));
    SET @sql=REPLACE(@sql,N'ParserVersion<>''safe-import-v1''',
        N'DATALENGTH(ParserVersion)<>14 OR ParserVersion COLLATE Latin1_General_100_BIN2 NOT IN (''safe-import-v1'',''safe-import-v2'')');
    SET @sql=STUFF(@sql,CHARINDEX(N'CREATE',@sql),6,N'ALTER');
    EXEC sys.sp_executesql @sql;

    SET @sql=OBJECT_DEFINITION(OBJECT_ID('dbo.tp_AssertImportOwner'));
    SET @sql=REPLACE(@sql,N'WHERE ImportId=@ImportId)',
        N'WHERE ImportId=@ImportId AND DATALENGTH(ParserVersion)=14 AND ParserVersion COLLATE Latin1_General_100_BIN2 IN (''safe-import-v1'',''safe-import-v2''))');
    SET @sql=STUFF(@sql,CHARINDEX(N'CREATE',@sql),6,N'ALTER');
    EXEC sys.sp_executesql @sql;

    IF (SELECT COUNT(*) FROM @baseline b WHERE b.Name NOT IN
        ('tp_RegisterUpload','tp_BeginImport','tp_SetImportContentHash','tp_AssertImportOwner')
        AND HASHBYTES('SHA2_256',OBJECT_DEFINITION(OBJECT_ID('dbo.'+b.Name)))=b.Hash)<>12
        THROW 51128,'Unrelated importer module changed during upgrade.',1;
    EXEC dbo.tp_AssertDeletionProtocol;
    EXEC dbo.dj_AssertProtocol;
    DECLARE @name sysname,@hash varbinary(32);
    DECLARE changed CURSOR LOCAL FAST_FORWARD FOR SELECT Name FROM @baseline
        WHERE Name IN ('tp_RegisterUpload','tp_BeginImport','tp_SetImportContentHash','tp_AssertImportOwner');
    OPEN changed; FETCH NEXT FROM changed INTO @name;
    WHILE @@FETCH_STATUS=0
    BEGIN
        SET @hash=HASHBYTES('SHA2_256',OBJECT_DEFINITION(OBJECT_ID('dbo.'+@name)));
        EXEC sys.sp_addextendedproperty @name=N'TraceParserDurationV2Hash',@value=@hash,
            @level0type=N'SCHEMA',@level0name=N'dbo',@level1type=N'PROCEDURE',@level1name=@name;
        FETCH NEXT FROM changed INTO @name;
    END;
    CLOSE changed; DEALLOCATE changed;
    COMMIT;
END TRY
BEGIN CATCH
    IF XACT_STATE()<>0 ROLLBACK;
    THROW;
END CATCH;
