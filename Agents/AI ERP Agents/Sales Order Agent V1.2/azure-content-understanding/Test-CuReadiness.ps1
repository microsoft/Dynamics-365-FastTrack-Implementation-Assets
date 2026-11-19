<#
.SYNOPSIS
    Readiness check for the Content Understanding sales-order pipeline.

.DESCRIPTION
    Replaces the MarkItDown-era Test-Readiness.ps1 for the CU route. Drops every
    Azure Function, custom connector, application-user and security-role check,
    because none of those components exist any more.

    Includes the checks that were learned the hard way and are invisible to
    inspection:

      * Two intake flows pointed at the SAME mailbox folder. Both active means
        every email is processed twice.
      * Dataverse search off - the agent cannot read the staging table, which
        surfaces much later as StagingDocumentUnavailable.
      * An analyzer ID that exists in an environment variable but not on the
        resource.
      * Numeric fields silently typed as string, which lets "USD2999.00" reach
        Dataverse unparsed.

.EXAMPLE
    .\Test-CuReadiness.ps1 -OrgUrl https://contoso.crm.dynamics.com `
                           -Endpoint https://contoso.services.ai.azure.com
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$OrgUrl,
    [Parameter(Mandatory = $true)][string]$Endpoint,
    [string]$AnalyzerId = 'sales_order_extraction_v2_0_7',
    [string]$ApiVersion = '2025-11-01'
)

$ErrorActionPreference = 'Stop'
$OrgUrl = $OrgUrl.TrimEnd('/')
$Endpoint = $Endpoint.TrimEnd('/')
$script:Results = @()

function Add-Result {
    param($Area, $Check, $Status, $Detail, $Fix)
    $script:Results += [pscustomobject]@{
        Area = $Area; Check = $Check; Status = $Status; Detail = $Detail; Fix = $Fix
    }
}

function Get-Token {
    param($Resource)
    $t = az account get-access-token --resource $Resource --query accessToken -o tsv 2>$null |
        Select-Object -Last 1
    if (-not $t -or $t -notmatch '^ey') { throw "Could not get a token for $Resource. Run 'az login'." }
    return $t.Trim()
}

$dvToken = Get-Token -Resource $OrgUrl
$dv = @{ Authorization = "Bearer $dvToken"; Accept = 'application/json' }

function Invoke-Dv {
    # The environment is intermittently slow. A release gate must not report
    # FAIL because of a transient timeout, so retry before giving up.
    param($Path)
    for ($i = 1; $i -le 3; $i++) {
        try {
            return Invoke-RestMethod -Uri "$OrgUrl/api/data/v9.2/$Path" -Headers $dv -TimeoutSec 300
        }
        catch {
            if ($i -eq 3) { throw }
            Start-Sleep -Seconds 10
        }
    }
}

Write-Host "`nContent Understanding readiness" -ForegroundColor Cyan
Write-Host ("=" * 70)
Write-Host "  org      : $OrgUrl"
Write-Host "  endpoint : $Endpoint`n"

# --- Dataverse reachability -------------------------------------------------
try {
    $who = Invoke-Dv 'WhoAmI'
    Add-Result 'Platform' 'Dataverse reachable' 'PASS' "org $($who.OrganizationId)"
}
catch {
    Add-Result 'Platform' 'Dataverse reachable' 'FAIL' $_.Exception.Message 'Check the org URL and that you are signed in.'
    $script:Results | Format-Table -AutoSize
    exit 1
}

# --- Dataverse search -------------------------------------------------------
# The agent reads the staging table through search. With search off, extraction
# succeeds and the agent still fails, which looks like a packaging defect.
try {
    $org = Invoke-Dv 'organizations?$select=isexternalsearchindexenabled'
    $searchOn = [bool]$org.value[0].isexternalsearchindexenabled
    Add-Result 'Platform' 'Dataverse search enabled' $(if ($searchOn) { 'PASS' } else { 'FAIL' }) `
        "isexternalsearchindexenabled = $searchOn" `
        'Power Platform admin centre > Environment > Settings > Product > Features > Dataverse search.'
}
catch {
    Add-Result 'Platform' 'Dataverse search enabled' 'UNKNOWN' $_.Exception.Message
}

# --- Staging table contract -------------------------------------------------
$requiredColumns = @(
    'aipod_extracteddata', 'aipod_sourcehash', 'aipod_sourceorderedrowcount',
    'aipod_processingstatus', 'aipod_processingphase', 'aipod_converterversion',
    'aipod_hasattachment', 'aipod_contenttype', 'aipod_inputdocument',
    'aipod_analyzerid', 'aipod_operationid', 'aipod_schemaversion',
    'aipod_sourcekind', 'aipod_linecountverification'
)
try {
    $attrs = Invoke-Dv "EntityDefinitions(LogicalName='aipod_stagingdocument')/Attributes?`$select=LogicalName"
    $have = $attrs.value.LogicalName
    $missing = $requiredColumns | Where-Object { $_ -notin $have }
    Add-Result 'Schema' 'staging document columns present' $(if ($missing) { 'FAIL' } else { 'PASS' }) `
        $(if ($missing) { "missing: $($missing -join ', ')" } else { "all $($requiredColumns.Count) present" }) `
        'Import the solution that defines the staging document table.'
}
catch {
    Add-Result 'Schema' 'staging document columns present' 'FAIL' $_.Exception.Message
}

# --- Intake flows: one per mailbox, never two on the same mailbox ------------
# Detection is by TRIGGER, not by name. An earlier name-based check missed
# "When a new email with attachment arrives in a shared mailbox (V2)" entirely.
#
# Counting active flows is also wrong: personal and shared intakes legitimately
# run together because they watch DIFFERENT mailboxes. What must never happen is
# two active flows resolving to the SAME mailbox and folder, which double-
# processes every email.
try {
    $flows = Invoke-Dv "workflows?`$select=name,workflowid,statecode&`$filter=category eq 5 and statecode eq 1"
    $emailTriggered = @()
    foreach ($f in $flows.value) {
        $def = Invoke-Dv "workflows($($f.workflowid))?`$select=clientdata"
        if (-not $def.clientdata -or $def.clientdata -notmatch 'OnNewEmail') { continue }
        $parsed = $def.clientdata | ConvertFrom-Json
        $trigger = ($parsed.properties.definition.triggers.PSObject.Properties | Select-Object -First 1).Value
        $p = $trigger.inputs.parameters
        $emailTriggered += [pscustomobject]@{
            Name    = $f.name
            Mailbox = "$($p.to)$($p.mailboxAddress)"
            Folder  = "$($p.folderPath)$($p.folderId)"
        }
    }

    $cu = $emailTriggered | Where-Object { $_.Name -like '*Content Understanding*' }
    Add-Result 'Flows' 'a Content Understanding intake flow is active' $(if ($cu) { 'PASS' } else { 'FAIL' }) `
        $(if ($cu) { ($cu.Name -join ' | ') } else { 'none active' }) `
        'Turn on the Content Understanding intake flow.'

    $clash = $emailTriggered | Group-Object { "$($_.Mailbox)|$($_.Folder)" } | Where-Object { $_.Count -gt 1 }
    Add-Result 'Flows' 'no two intake flows share a mailbox and folder' $(if ($clash) { 'FAIL' } else { 'PASS' }) `
        "$($emailTriggered.Count) active: $(($emailTriggered.Name) -join ' | ')" `
        'Two active flows on the same mailbox process every email twice. Deactivate one.'

    $legacy = $emailTriggered | Where-Object { $_.Name -notlike '*Content Understanding*' }
    Add-Result 'Flows' 'no MarkItDown-era intake flow is active' $(if ($legacy) { 'FAIL' } else { 'PASS' }) `
        $(if ($legacy) { ($legacy.Name -join ' | ') } else { 'none' }) `
        'The MarkItDown route is retired and its Azure Function has been deleted.'
}
catch {
    Add-Result 'Flows' 'intake flow state' 'UNKNOWN' $_.Exception.Message
}

# --- Connection references --------------------------------------------------
try {
    $refs = Invoke-Dv "connectionreferences?`$select=connectionreferencelogicalname,connectionid,connectorid"
    $cuRef = $refs.value | Where-Object { $_.connectorid -like '*contentunderstanding*' }
    if (-not $cuRef) {
        Add-Result 'Connections' 'CU connection reference present' 'FAIL' 'none found' `
            'Create or select a Content Understanding connection before import, not after - an unbound reference greys out Next.'
    }
    else {
        $bound = [bool]$cuRef[0].connectionid
        Add-Result 'Connections' 'CU connection reference bound' $(if ($bound) { 'PASS' } else { 'FAIL' }) `
            "$($cuRef[0].connectionreferencelogicalname) -> $($cuRef[0].connectionid)" `
            'Bind the connection reference to a Content Understanding connection.'

            # The connection stores an API KEY (keyBasedAuth: api_key + siteUrl).
            # It is NOT OAuth. Rotating the Azure key breaks it, and the connection
            # still reports "Connected" while failing - observed 2026-10-10.
            Add-Result 'Connections' 'CU connection auth mode understood' 'WARN' `
                'connector parameter set is keyBasedAuth (api_key + siteUrl)' `
                'Connection status is NOT evidence. After any key rotation, update the connection api_key and prove it by processing a document. An Entra token test does not exercise this connection.'
    }

    $markitdown = $refs.value | Where-Object { $_.connectorid -like '*markitdown*' }
    Add-Result 'Connections' 'no MarkItDown connection required' $(if ($markitdown) { 'WARN' } else { 'PASS' }) `
        $(if ($markitdown) { "still present: $($markitdown.connectionreferencelogicalname)" } else { 'none - CU route needs no custom connector' }) `
        'Harmless, but the CU release does not use it.'
}
catch {
    Add-Result 'Connections' 'connection references' 'UNKNOWN' $_.Exception.Message
}

# --- Environment variables --------------------------------------------------
try {
    $defs = Invoke-Dv "environmentvariabledefinitions?`$select=schemaname,defaultvalue"
    $vals = Invoke-Dv "environmentvariablevalues?`$select=value,_environmentvariabledefinitionid_value"
    $byId = @{}
    foreach ($v in $vals.value) { $byId[$v._environmentvariabledefinitionid_value] = $v.value }

    foreach ($name in 'aipod_MailboxToMonitor', 'aipod_MailboxFolderToMonitor',
        'aipod_SharedMailboxToMonitor', 'aipod_SharedMailboxFolderToMonitor') {
        $d = $defs.value | Where-Object { $_.schemaname -eq $name }
        if (-not $d) {
            Add-Result 'Env vars' "$name defined" 'FAIL' 'not found'
            continue
        }
        $current = $byId[$d.environmentvariabledefinitionid]
        $effective = if ($current) { $current } else { $d.defaultvalue }
        # Shared-mailbox variables only matter when the shared intake is on.
        $severity = if ($name -like '*Shared*') { 'WARN' } else { 'FAIL' }
        Add-Result 'Env vars' "$name has a value" $(if ($effective) { 'PASS' } else { $severity }) `
            "effective = '$effective'" `
            'Set a current value for this environment before enabling the matching intake flow.'
    }

    # The flow DOES read this variable - analyzerId is @parameters(...), not a
    # literal. A wrong value here points the flow at a non-existent analyzer.
    $d = $defs.value | Where-Object { $_.schemaname -eq 'aipod_AzureContentUnderstandingAnalyzerId' }
    if ($d) {
        $current = $byId[$d.environmentvariabledefinitionid]
        $effective = if ($current) { $current } else { $d.defaultvalue }
        Add-Result 'Env vars' 'analyzer ID variable matches the deployed analyzer' `
            $(if ($effective -eq $AnalyzerId) { 'PASS' } else { 'FAIL' }) `
            "effective = '$effective', expected '$AnalyzerId'" `
            'The intake flow reads this variable to choose the analyzer. A wrong value fails every analyze call.'
    }

    $key = $defs.value | Where-Object { $_.schemaname -eq 'aipod_AzureContentUnderstandingApiKey' }
    if ($key -and $key.defaultvalue) {
        Add-Result 'Security' 'no secret stored as an env-var default' 'FAIL' `
            'aipod_AzureContentUnderstandingApiKey has a non-empty default' `
            'Defaults travel inside solutions. Rotate the key and clear the default.'
    }
    else {
        Add-Result 'Security' 'no secret stored as an env-var default' 'PASS' 'none set'
    }
}
catch {
    Add-Result 'Env vars' 'environment variables' 'UNKNOWN' $_.Exception.Message
}

# --- Analyzer ---------------------------------------------------------------
try {
    $cuToken = Get-Token -Resource 'https://cognitiveservices.azure.com'
    $analyzer = Invoke-RestMethod -Uri "$Endpoint/contentunderstanding/analyzers/$AnalyzerId`?api-version=$ApiVersion" `
        -Headers @{ Authorization = "Bearer $cuToken" } -TimeoutSec 300

    Add-Result 'Analyzer' 'analyzer exists' 'PASS' "$AnalyzerId"
    Add-Result 'Analyzer' "status is ready" $(if ($analyzer.status -eq 'ready') { 'PASS' } else { 'FAIL' }) `
        "status = $($analyzer.status)" 'Re-run Deploy-Analyzer.ps1.'

    $itemProps = $analyzer.fieldSchema.fields.items.items.properties
    foreach ($numeric in 'productquantity', 'productprice', 'productlinetotal') {
        $type = $itemProps.$numeric.type
        Add-Result 'Analyzer' "$numeric is typed 'number'" $(if ($type -eq 'number') { 'PASS' } else { 'FAIL' }) `
            "type = $type" `
            'There is no number parsing on the CU path. A string here puts values like USD2999.00 into Dataverse unparsed.'
    }
    $dateType = $analyzer.fieldSchema.fields.deliverydate.type
    Add-Result 'Analyzer' "deliverydate is typed 'date'" $(if ($dateType -eq 'date') { 'PASS' } else { 'FAIL' }) "type = $dateType"
}
catch {
    Add-Result 'Analyzer' 'analyzer exists' 'FAIL' $_.Exception.Message `
        "Run Deploy-Analyzer.ps1 -Endpoint $Endpoint -AnalyzerId $AnalyzerId"
}

# --- Report -----------------------------------------------------------------
Write-Host ""
foreach ($area in $script:Results.Area | Select-Object -Unique) {
    Write-Host $area -ForegroundColor Cyan
    foreach ($r in $script:Results | Where-Object { $_.Area -eq $area }) {
        $colour = switch ($r.Status) {
            'PASS' { 'Green' } 'FAIL' { 'Red' } 'WARN' { 'Yellow' } default { 'DarkGray' }
        }
        Write-Host ("  {0,-6} {1}" -f $r.Status, $r.Check) -ForegroundColor $colour
        if ($r.Detail) { Write-Host ("         {0}" -f $r.Detail) -ForegroundColor DarkGray }
        if ($r.Status -in 'FAIL', 'WARN' -and $r.Fix) {
            Write-Host ("         fix: {0}" -f $r.Fix) -ForegroundColor DarkYellow
        }
    }
}

$pass = @($script:Results | Where-Object Status -eq 'PASS').Count
$fail = @($script:Results | Where-Object Status -eq 'FAIL').Count
$warn = @($script:Results | Where-Object Status -eq 'WARN').Count

Write-Host ("`n" + ("=" * 70))
Write-Host ("RESULT: PASS={0} FAIL={1} WARN={2}" -f $pass, $fail, $warn) `
    -ForegroundColor $(if ($fail -eq 0) { 'Green' } else { 'Red' })
if ($fail -gt 0) { exit 1 }
