$ErrorActionPreference='Stop'
$path=Join-Path $PSScriptRoot '..\..\TraceParserMCP\DAB_ParseEtl.ps1'
$tokens=$null; $errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Resolve-Path $path),[ref]$tokens,[ref]$errors)
if($errors.Count) { throw "Importer PowerShell parse errors: $errors" }
foreach($name in @('ConvertSecToTicks','Convert-DurationTicksToNanoseconds')) {
    $function=$ast.FindAll({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst]},$true) |
        Where-Object Name -eq $name
    if(@($function).Count -ne 1) { throw "Expected one $name function" }
    # Only these scalar functions run. The importer main/SQL/ETL reader never runs.
    Invoke-Expression $function.Extent.Text
}
$checks=0
foreach($case in @(
    @{Seconds='0.001'; Nanoseconds=1000000L},
    @{Seconds='0.002'; Nanoseconds=2000000L},
    @{Seconds='0.003'; Nanoseconds=3000000L},
    @{Seconds='0'; Nanoseconds=0L},
    @{Seconds=''; Nanoseconds=0L},
    @{Seconds=$null; Nanoseconds=0L}
)) {
    $actual=Convert-DurationTicksToNanoseconds (ConvertSecToTicks $case.Seconds)
    if($actual -ne $case.Nanoseconds) { throw "Seconds known-answer failed: $($case.Seconds)" }
    $checks++
}
foreach($n in @(-1L,-20000L,[long]::MinValue)) {
    if((Convert-DurationTicksToNanoseconds $n) -ne $n) { throw 'Negative sentinel changed' }
    $checks++
}
if((Convert-DurationTicksToNanoseconds 800000L) -ne 80000000L) { throw '80ms conversion failed' }
$checks++
$rejected=$false
try { Convert-DurationTicksToNanoseconds ([long]::MaxValue) | Out-Null } catch { $rejected=$true }
if(!$rejected) { throw 'Overflow silently accepted' }
$checks++
$flush=$ast.FindAll({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Flush-StageBatch'},$true)
if($flush.Extent.Text -notmatch "'DatabaseDurationNano','PrepDurationNano','BindDurationNano','RowFetchDurationNano'" -or
    $flush.Extent.Text -notmatch "'InclusiveDurationNano','ExclusiveDurationNano'") { throw 'Six-field encoding boundary missing' }
$checks++
if($ast.Extent.Text -notmatch "TraceParserVersion\)\s*`r?`n\s*OUTPUT INSERTED.TraceId VALUES\(@n,@f,@ts,@ts,@d,'ps-import-v2'\)" -or
    $ast.Extent.Text -notmatch 'Direct PowerShell import is unsupported in a receipt-managed database') { throw 'Version/coordination metadata contract missing' }
$checks++
[pscustomobject]@{Passed=$checks;Scope='AST scalar functions only; no SQL or ETL import';OuterNanoseconds=80000000;
    FileTimeConversion='Not performed';NegativeSentinels='Preserved';Version='ps-import-v2'} | ConvertTo-Json
