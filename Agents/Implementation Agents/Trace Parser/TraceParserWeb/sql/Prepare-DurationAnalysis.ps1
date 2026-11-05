<#
Produces an atomic, guarded upgrade artifact; NEVER connects to any database.
The bounded rollout owner must separately approve/apply it after duration-import-v2.sql.
Do not run entire legacy Create Views.sql or safe-importer.sql on an upgraded database.
#>
param([Parameter(Mandatory)][string]$OutputPath)
$ErrorActionPreference='Stop'
$mcp=Join-Path $PSScriptRoot '..\..\TraceParserMCP'
$baseline=[ordered]@{
    sp_PopulateSessionAggregations='3F99099C180C38821A25B37DFC122B95E76DB552ABDD800C40BB0D8EA4772979'
    vw_NPlusOnePatterns='5711697923B8C6C88F551A6AFAC6F55B253E7604B950563959C582A40C8B0444'
    vw_SessionMetrics='654344703778C5584FE4681A512B3A815256788469A9B67F3F3F19DF95FB42AE'
    vw_SessionSummary='6CDDB04B505377370CB7FA0E12CE5D590C5D3EE3362992825844A4A02A3251F9'
    vw_SlowSqlStatements='4E18CA11DC87FF27E8A72B43708395D11AD50386E53493512DBF0691C1F3AB57'
    vw_TopMethodsBySession='4DCEC7B545A9EFCBA1140CB318E53FBAA7C618C2E0D25A53CB4E99D48532B9B7'
    vw_TraceLineDetails='AD0AAF28168BC417EBD3D53019F9E6A344BE9583A5EECB82C75322F117FB20A7'
    sp_SearchTracesByKeyword='4E9E69D62B834ADDF86E53A394BC7B0F5E21C0907E2B265AB7FC0742D3392516'
    sp_SearchSqlStatements='C7422E028F11D2FBD2DF6AD0F6937B94A58D1442F656FDB93C32D202C43A975F'
    sp_SearchMethods='CAC1154C27423B1B362B2766982A1B18962F5A01B666980EA8054A5CD5B33D92'
    sp_SearchMessages='42EB2CBFA4B8383F813E72D1CC0C54776C1641F509B42196F822A8DC43549528'
}
$sql=[Text.StringBuilder]::new()
[void]$sql.AppendLine(@'
-- Generated from reviewed source; contains no historical data UPDATE/backfill.
SET XACT_ABORT ON;
IF @@TRANCOUNT<>0 THROW 51128,'Analysis upgrade requires its own transaction.',1;
BEGIN TRY
BEGIN TRAN;
DECLARE @lock int;
EXEC @lock=sys.sp_getapplock @Resource='TraceParser:Importer:v1',@LockMode='Exclusive',@LockOwner='Transaction',@LockTimeout=0;
IF @lock<0 THROW 51128,'Importer must be quiescent for analysis upgrade.',1;
EXEC dbo.tp_AssertDeletionProtocol;
EXEC dbo.dj_AssertProtocol;
IF (SELECT COUNT(*) FROM sys.procedures WHERE schema_id=SCHEMA_ID('dbo') AND name LIKE 'tp[_]%')<>16
 OR (SELECT COUNT(*) FROM sys.extended_properties p JOIN sys.procedures m ON m.object_id=p.major_id
     WHERE p.class=1 AND p.name='TraceParserDurationV2Hash'
     AND m.name IN ('tp_RegisterUpload','tp_BeginImport','tp_SetImportContentHash','tp_AssertImportOwner')
     AND CONVERT(varbinary(32),p.value)=HASHBYTES('SHA2_256',OBJECT_DEFINITION(m.object_id)))<>4
 OR NOT EXISTS(SELECT 1 FROM sys.parameters WHERE object_id=OBJECT_ID('dbo.tp_BeginImport') AND name='@WorkerVersion')
 THROW 51128,'Coordinated v2 importer and exact version fingerprints required.',1;
IF OBJECT_ID('dbo.vw_TraceDurationUnits') IS NOT NULL OR OBJECT_ID('dbo.vw_UnitAwareTraceLines') IS NOT NULL
 OR OBJECT_ID('dbo.vw_TopMethodsWithUnits') IS NOT NULL
 THROW 51128,'New analysis objects already exist; no automatic adoption.',1;
'@)
foreach($entry in $baseline.GetEnumerator()) {
    [void]$sql.AppendLine("IF ISNULL(HASHBYTES('SHA2_256',OBJECT_DEFINITION(OBJECT_ID('dbo.$($entry.Key)'))),0x)<>0x$($entry.Value) THROW 51128,'Analysis baseline differs: $($entry.Key).',1;")
}
function Add-Batch([string]$Batch) {
    if(![string]::IsNullOrWhiteSpace($Batch)) {
        [void]$sql.AppendLine("EXEC sys.sp_executesql N'"+$Batch.Replace("'","''")+"';")
    }
}
function Read-Batches([string]$Path) {
    [regex]::Split([IO.File]::ReadAllText((Resolve-Path $Path)),'(?im)^\s*GO\s*$')
}
foreach($batch in (Read-Batches (Join-Path $mcp 'Duration units.sql'))) { Add-Batch $batch }
# Never install the two raw full-scan aggregation views in a materialized deployment.
$calls=@(Read-Batches (Join-Path $mcp 'Create Views.sql') | Where-Object {
    $_ -match 'CREATE OR ALTER VIEW dbo\.vw_(TraceLineDetails|NPlusOnePatterns|SlowSqlStatements)\b'
})
if($calls.Count -ne 3) { throw 'Expected exactly three reviewed call-analysis views' }
foreach($batch in $calls) { Add-Batch $batch }
$search=@(Read-Batches (Join-Path $mcp 'Create Keyword Search SPs.sql') | Where-Object {
    $_ -match 'CREATE OR ALTER PROCEDURE dbo\.sp_Search'
})
if($search.Count -ne 4) { throw 'Expected all four keyword-search procedures' }
foreach($batch in $search) { Add-Batch $batch }
foreach($batch in (Read-Batches (Join-Path $PSScriptRoot 'duration-aggregates.sql'))) { Add-Batch $batch }
[void]$sql.AppendLine(@'
EXEC dbo.tp_AssertDeletionProtocol;
EXEC dbo.dj_AssertProtocol;
COMMIT;
END TRY
BEGIN CATCH
IF XACT_STATE()<>0 ROLLBACK;
THROW;
END CATCH;
'@)
[IO.File]::WriteAllText($ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath),$sql.ToString())
Get-FileHash $OutputPath -Algorithm SHA256 | Select-Object Hash,Path
