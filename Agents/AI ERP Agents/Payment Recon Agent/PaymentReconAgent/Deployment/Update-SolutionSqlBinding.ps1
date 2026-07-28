<#
.SYNOPSIS
    Rewrites the SQL Server/database binding inside the Payment Recon Power
    Platform solution zip so the canvas app and Copilot agents point at the
    SQL server/database created by the Azure deployment.

.DESCRIPTION
    The canvas app stores its SQL data source as a fixed dataset string
    ("<server>.database.windows.net,<database>") baked into the .msapp and the
    canvas app meta.xml. The Copilot agents use placeholder tokens
    (<Reconserver>, <ReconDatabase>, <ReconDBName>, <ReconDB>). Neither is an
    environment variable, so a normal solution import does NOT update them.

    This script produces a NEW deployment-specific solution zip in which every
    occurrence of the old dataset string and every agent placeholder is replaced
    with the real server/database for this deployment. The original zip is left
    untouched.

    If -DeploymentSettingsFile is provided, the script also rewrites the Cloud
    Flow parameter defaults and environment variable definition/value artifacts
    from Settings.EnvironmentVariables, adding missing environment variable
    artifacts when needed, so deployment-specific ADF/SQL values are embedded in
    the deployment zip.

    No Power Platform sign-in is required; this is a pure file transform.

.PARAMETER SolutionZip
    Path to the source (template) solution zip, e.g.
    PaymentReconSolutionV5.zip

.PARAMETER SqlServerFqdn
    Target Azure SQL server. Accepts either the short name (myserver) or the
    fully qualified name (myserver.database.windows.net).

.PARAMETER SqlDatabaseName
    Target Azure SQL database name.

.PARAMETER OutputZip
    Path for the rewritten solution zip. Defaults to the source name with a
    "-deploy" suffix next to the source.

.PARAMETER DeploymentSettingsFile
    Optional path to PaymentReconSolutionV5.deployment-settings.json. When
    provided, EnvironmentVariables from this file are injected into Cloud Flow
    defaults and environment variable artifacts inside the output solution zip.

.PARAMETER ConnectionReferenceDisplayPrefix
    Enterprise prefix applied to every connection reference display name inside
    customizations.xml (e.g. "Payment Recon - Azure SQL Database (Power App)").
    The connection reference LOGICAL names are never changed, so deployment
    mapping and all solution bindings keep working. Defaults to "Payment Recon".

.PARAMETER SkipConnectionReferenceRename
    Skip the connection reference display-name rename and leave the original
    (auto-generated) display names untouched.

.EXAMPLE
    .\Update-SolutionSqlBinding.ps1 -SolutionZip .\PaymentReconSolutionV5.zip `
        -SqlServerFqdn "paymentreconv6-sqlsrv" -SqlDatabaseName "paymentreconv6-db"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string]$SolutionZip,
    [Parameter(Mandatory)] [string]$SqlServerFqdn,
    [Parameter(Mandatory)] [string]$SqlDatabaseName,
    [string]$OutputZip,
    [string]$DeploymentSettingsFile,
    [string]$ConnectionReferenceDisplayPrefix = "Payment Recon",
    [switch]$SkipConnectionReferenceRename
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

if (-not (Test-Path $SolutionZip)) {
    throw "Solution zip not found: $SolutionZip"
}
if (-not [string]::IsNullOrWhiteSpace($DeploymentSettingsFile) -and -not (Test-Path $DeploymentSettingsFile)) {
    throw "Deployment settings file not found: $DeploymentSettingsFile"
}

# ---- Normalize the target server/database into the strings we need ----
$fqdn = $SqlServerFqdn.Trim().ToLowerInvariant()
if ($fqdn -notmatch '\.database\.windows\.net$') {
    $fqdn = "$fqdn.database.windows.net"
}
$shortName  = ($fqdn -replace '\.database\.windows\.net$', '')
$db         = $SqlDatabaseName.Trim()
$newDataset = "$fqdn,$db"

if (-not $OutputZip) {
    $dir  = Split-Path -Parent (Resolve-Path $SolutionZip)
    $base = [System.IO.Path]::GetFileNameWithoutExtension($SolutionZip)
    $OutputZip = Join-Path $dir "$base-deploy.zip"
}

# ---- Enterprise display names for connection references ----
# Applied to customizations.xml so a normal solution import sets friendly,
# consistently prefixed display names automatically. Keyed by the connection
# reference LOGICAL name (which is immutable and is what deployment mapping and
# every solution component bind to - only the display name is changed here).
$script:RenamedConnectionRefs = 0
$script:AddedLogicFlowConnectionRefs = 0
$script:AddedLogicFlowDatasourceBindings = 0
$script:LogicFlowsConnectionReferenceLogicalName = 'new_sharedlogicflows_paymentreconintegration_v5'
$script:ConnRefRenames = [ordered]@{}
if (-not $SkipConnectionReferenceRename) {
    $prefix = ([string]$ConnectionReferenceDisplayPrefix).Trim()
    $connRefSuffixByLogicalName = [ordered]@{
        'cap_sharedsql_36c34127c7'                                                                          = 'Azure SQL Database (Power App)'
        'copilots_header_fe637.shared_sql.9ea221cbf55f45aea2135ed09ee80b3c'                                 = 'Azure SQL Database (Agent - Reconciliation)'
        'cre7a_agentR61Db3.shared_sql.shared-sql-bf74b048-9772-4554-91ed-69eaa209c782'                      = 'Azure SQL Database (Agent - Rule Admin)'
        'cap_sharedazureblob_36c34fa51a'                                                                    = 'Azure Blob Storage'
        'new_sharedazuredatafactory_98752'                                                                  = 'Azure Data Factory'
        'new_sharedmicrosoftcopilotstudio_dea00'                                                            = 'Microsoft Copilot Studio'
        'cre7a_agentR61Db3.shared_a365mcpservers.shared-a365mcpserver-afbe760a-ab61-4886-bd0d-54db4fe8d46e' = 'Microsoft Outlook Mail MCP'
        $script:LogicFlowsConnectionReferenceLogicalName                                                    = 'Logic Flows (Code App Reconcile)'
    }
    foreach ($logicalName in $connRefSuffixByLogicalName.Keys) {
        $suffix = [string]$connRefSuffixByLogicalName[$logicalName]
        if ([string]::IsNullOrWhiteSpace($prefix)) {
            $script:ConnRefRenames[$logicalName] = $suffix
        } else {
            $script:ConnRefRenames[$logicalName] = "$prefix - $suffix"
        }
    }
}

Write-Host "Rewriting deployment bindings in solution..." -ForegroundColor Cyan
Write-Host "  Source : $SolutionZip" -ForegroundColor Gray
Write-Host "  Server : $fqdn" -ForegroundColor Gray
Write-Host "  Database: $db" -ForegroundColor Gray
Write-Host "  Output : $OutputZip" -ForegroundColor Gray

$script:EnvVarOverrides = @{}
if (-not [string]::IsNullOrWhiteSpace($DeploymentSettingsFile)) {
    try {
        $settings = Get-Content -Path $DeploymentSettingsFile -Raw | ConvertFrom-Json
        if ($settings -and $settings.PSObject.Properties.Name -contains 'EnvironmentVariables') {
            foreach ($ev in $settings.EnvironmentVariables) {
                $schemaName = [string]$ev.SchemaName
                if (-not [string]::IsNullOrWhiteSpace($schemaName)) {
                    $script:EnvVarOverrides[$schemaName] = [string]$ev.Value
                }
            }
        }
    } catch {
        throw "Failed reading environment variables from deployment settings file '$DeploymentSettingsFile': $($_.Exception.Message)"
    }
    Write-Host "  Environment variable overrides: $($script:EnvVarOverrides.Count)" -ForegroundColor Gray
}
$script:AddedEnvVarArtifacts = 0

# Replace any existing 'server.database.windows.net,DB' dataset and the agent
# placeholder tokens. UTF-8 round-trips losslessly; we only touch ASCII tokens.
$script:Replacements = 0
function Convert-SqlText {
    param([string]$Text)
    $before = $Text
    $Text = [regex]::Replace($Text, '[A-Za-z0-9._-]+\.database\.windows\.net,[A-Za-z0-9_.-]+', $newDataset)
    $Text = $Text -replace '<Reconserver>',  $shortName
    $Text = $Text -replace '<ReconDatabase>', $db
    $Text = $Text -replace '<ReconDBName>',   $db
    $Text = $Text -replace '<ReconDB>',       $db
    $Text = $Text -replace '<ReconDb>',       $db
    $Text = $Text -replace 'paymentreconintegration_v5_har', $script:LogicFlowsConnectionReferenceLogicalName
    if ($Text -ne $before) { $script:Replacements++ }
    return $Text
}

function Convert-WorkflowParameterDefaultsText {
    param([string]$Text)

    if ($script:EnvVarOverrides.Count -eq 0) { return $Text }
    $before = $Text
    $changed = $false

    try {
        $json = $Text | ConvertFrom-Json
        $parameters = $json.properties.definition.parameters
        if ($parameters) {
            foreach ($entry in $script:EnvVarOverrides.GetEnumerator()) {
                $schemaName = [string]$entry.Key
                $value = [string]$entry.Value
                $paramProperty = $parameters.PSObject.Properties[$schemaName]
                $paramNode = if ($paramProperty) { $paramProperty.Value } else { $null }
                if ($paramNode -and ($paramNode.PSObject.Properties.Name -contains 'defaultValue')) {
                    if ([string]$paramNode.defaultValue -ne $value) {
                        $paramNode.defaultValue = $value
                        $changed = $true
                    }
                }
            }
        }
        if ($changed) {
            $Text = $json | ConvertTo-Json -Depth 100
        }
    } catch {
        # Not a workflow schema we can parse safely; leave content untouched.
    }

    if ($Text -ne $before) { $script:Replacements++ }
    return $Text
}

function Convert-EnvironmentVariableDefinitionText {
    param(
        [string]$Text,
        [string]$SchemaName
    )

    if ($script:EnvVarOverrides.Count -eq 0) { return $Text }
    if (-not $script:EnvVarOverrides.ContainsKey($SchemaName)) { return $Text }

    $value = [string]$script:EnvVarOverrides[$SchemaName]
    $before = $Text

    if ($Text -match '(?s)<defaultvalue>.*?</defaultvalue>') {
        $Text = [regex]::Replace(
            $Text,
            '(?s)(<defaultvalue>)(.*?)(</defaultvalue>)',
            { param($m) "$($m.Groups[1].Value)$value$($m.Groups[3].Value)" }
        )
    }

    if ($Text -ne $before) { $script:Replacements++ }
    return $Text
}

function Convert-EnvironmentVariableValueText {
    param(
        [string]$Text,
        [string]$SchemaName
    )

    if ($script:EnvVarOverrides.Count -eq 0) { return $Text }
    if (-not $script:EnvVarOverrides.ContainsKey($SchemaName)) { return $Text }

    $before = $Text
    $changed = $false

    try {
        $json = $Text | ConvertFrom-Json
        if ($json.environmentvariablevalues.environmentvariablevalue) {
            $target = [string]$script:EnvVarOverrides[$SchemaName]
            if ([string]$json.environmentvariablevalues.environmentvariablevalue.value -ne $target) {
                $json.environmentvariablevalues.environmentvariablevalue.value = $target
                $changed = $true
            }
        }
        if ($changed) {
            $Text = $json | ConvertTo-Json -Depth 10
        }
    } catch {
        # Leave untouched if shape is unexpected.
    }

    if ($Text -ne $before) { $script:Replacements++ }
    return $Text
}

function ConvertTo-XmlEscapedText {
    param([string]$Text)
    if ($null -eq $Text) { return '' }
    return [System.Security.SecurityElement]::Escape($Text)
}

function Get-EnvironmentVariableMetadata {
    param([string]$SchemaName)

    switch ($SchemaName) {
        'cap_PaymentReconStorageAccountName' {
            return [ordered]@{
                DisplayName = 'Payment Recon Storage Account Name'
                Description = 'Azure Blob Storage account name used by Payment Recon deployment bindings.'
            }
        }
        'cap_PaymentReconSqlServerFqdn' {
            return [ordered]@{
                DisplayName = 'Payment Recon SQL Server FQDN'
                Description = 'Azure SQL server FQDN used by Payment Recon deployment bindings.'
            }
        }
        'cap_PaymentReconSqlDatabaseName' {
            return [ordered]@{
                DisplayName = 'Payment Recon SQL Database Name'
                Description = 'Azure SQL database name used by Payment Recon deployment bindings.'
            }
        }
        default {
            $display = $SchemaName
            if ($display -like 'cap_*') { $display = $display.Substring(4) }
            $display = $display -replace '_', ' '
            $display = [regex]::Replace($display, '([a-z0-9])([A-Z])', '$1 $2')
            return [ordered]@{
                DisplayName = $display
                Description = 'Payment Recon deployment environment variable.'
            }
        }
    }
}

function New-EnvironmentVariableDefinitionXml {
    param(
        [Parameter(Mandatory)] [string]$SchemaName,
        [Parameter(Mandatory)] [string]$Value
    )

    $meta = Get-EnvironmentVariableMetadata -SchemaName $SchemaName
    $schemaEsc = ConvertTo-XmlEscapedText -Text $SchemaName
    $valueEsc = ConvertTo-XmlEscapedText -Text $Value
    $displayEsc = ConvertTo-XmlEscapedText -Text ([string]$meta.DisplayName)
    $descEsc = ConvertTo-XmlEscapedText -Text ([string]$meta.Description)

    return @"
<environmentvariabledefinition schemaname="$schemaEsc">
  <defaultvalue>$valueEsc</defaultvalue>
  <description default="$descEsc">
    <label description="$descEsc" languagecode="1033" />
  </description>
  <displayname default="$displayEsc">
    <label description="$displayEsc" languagecode="1033" />
  </displayname>
  <introducedversion>1.0.0.16</introducedversion>
  <iscustomizable>1</iscustomizable>
  <isrequired>1</isrequired>
  <secretstore>0</secretstore>
  <type>100000000</type>
</environmentvariabledefinition>
"@
}

function New-EnvironmentVariableValueJson {
    param([Parameter(Mandatory)] [string]$Value)

    $obj = [ordered]@{
        environmentvariablevalues = [ordered]@{
            environmentvariablevalue = [ordered]@{
                iscustomizable = '1'
                value = $Value
            }
        }
    }
    return ($obj | ConvertTo-Json -Depth 10)
}

# Decode bytes to text preserving a UTF-8 BOM if present, then re-encode the
# same way so we never change file encoding.
function ConvertTo-XmlText {
    param([string]$Value)
    if ($null -eq $Value) { return '' }
    $Value = $Value -replace '&', '&amp;'
    $Value = $Value -replace '<', '&lt;'
    $Value = $Value -replace '>', '&gt;'
    return $Value
}

# Rewrite <connectionreferencedisplayname> values inside the <connectionreferences>
# block of customizations.xml. Each replace is scoped to a specific (immutable)
# logical name, so connector ids and logical names are never touched and the
# transform is idempotent (re-running yields the same enterprise display name).
function Convert-ConnectionReferenceDisplayNames {
    param([string]$Text)
    if ($script:ConnRefRenames.Count -eq 0) { return $Text }
    $before = $Text
    foreach ($entry in $script:ConnRefRenames.GetEnumerator()) {
        $logical = [string]$entry.Key
        $display = ConvertTo-XmlText ([string]$entry.Value)
        $pattern = '(?s)(<connectionreference\s+connectionreferencelogicalname="' +
                   [regex]::Escape($logical) +
                   '"\s*>\s*<connectionreferencedisplayname>)(.*?)(</connectionreferencedisplayname>)'
        $beforeOne = $Text
        $Text = [regex]::Replace($Text, $pattern, { param($m) "$($m.Groups[1].Value)$display$($m.Groups[3].Value)" })
        if ($Text -ne $beforeOne) { $script:RenamedConnectionRefs++ }
    }
    if ($Text -ne $before) { $script:Replacements++ }
    return $Text
}

function Ensure-LogicFlowsConnectionReferenceInCustomizations {
    param([string]$Text)

    if ($Text -notmatch 'paymentreconintegration_v5_har') { return $Text }

    $targetLogicalName = $script:LogicFlowsConnectionReferenceLogicalName
    if ($Text -match ('<connectionreference\s+connectionreferencelogicalname="' + [regex]::Escape($targetLogicalName) + '"\s*>')) {
        return $Text
    }

    $display = 'Payment Recon - Logic Flows (Code App Reconcile)'
    if ($script:ConnRefRenames.Contains($targetLogicalName)) {
        $display = [string]$script:ConnRefRenames[$targetLogicalName]
    }
    $display = ConvertTo-XmlText -Value $display

    $insert = @"
    <connectionreference connectionreferencelogicalname="$targetLogicalName">
      <connectionreferencedisplayname>$display</connectionreferencedisplayname>
      <connectorid>/providers/Microsoft.PowerApps/apis/shared_logicflows</connectorid>
      <iscustomizable>1</iscustomizable>
      <promptingbehavior>0</promptingbehavior>
      <statecode>0</statecode>
      <statuscode>1</statuscode>
    </connectionreference>
"@

    $before = $Text
    $closeRootConnRefs = [regex]::new('(?s)</connectionreferences>')
    $Text = $closeRootConnRefs.Replace($Text, "$insert`r`n  </connectionreferences>", 1)
    if ($Text -ne $before) {
        $script:Replacements++
        $script:AddedLogicFlowConnectionRefs++
    }
    return $Text
}

function Ensure-CodeAppLogicFlowDatasourceBinding {
    param([string]$Text)

    if ($Text -notmatch 'paymentreconintegration_v5_har') { return $Text }

    $targetLogicalName = $script:LogicFlowsConnectionReferenceLogicalName
    if ($Text -match ('"xrmConnectionReferenceLogicalName"\s*:\s*"' + [regex]::Escape($targetLogicalName) + '"')) { return $Text }

    $Text = $Text -replace '"paymentreconintegration_v5_har"', ('"' + $targetLogicalName + '"')
    $Text = $Text -replace '"xrmConnectionReferenceLogicalName"\s*:\s*"paymentreconintegration_v5_har"', ('"xrmConnectionReferenceLogicalName":"' + $targetLogicalName + '"')
    $pattern = '(?s)("dataSources"\s*:\s*\[[^\]]*"' + [regex]::Escape($targetLogicalName) + '"[^\]]*\]\s*,\s*)(")'
    $before = $Text
    $replacement = '$1"xrmConnectionReferenceLogicalName":"' + $targetLogicalName + '",$2'
    $Text = [regex]::Replace($Text, $pattern, $replacement)
    if ($Text -ne $before) {
        $script:Replacements++
        $script:AddedLogicFlowDatasourceBindings++
    }
    return $Text
}

function Convert-Bytes {
    param(
        [byte[]]$Bytes,
        [string]$EntryName
    )
    $hasBom = ($Bytes.Length -ge 3 -and $Bytes[0] -eq 0xEF -and $Bytes[1] -eq 0xBB -and $Bytes[2] -eq 0xBF)
    $text = [System.Text.Encoding]::UTF8.GetString($Bytes)
    if ($hasBom) { $text = $text.TrimStart([char]0xFEFF) }
    $text = Convert-SqlText -Text $text

    if (-not [string]::IsNullOrWhiteSpace($EntryName) -and $EntryName -match '(^|[\\/])customizations\.xml$') {
        $text = Convert-ConnectionReferenceDisplayNames -Text $text
        $text = Ensure-LogicFlowsConnectionReferenceInCustomizations -Text $text
    }

    $text = Ensure-CodeAppLogicFlowDatasourceBinding -Text $text

    if ($script:EnvVarOverrides.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace($EntryName)) {
        if ($EntryName -match '(^|[\\/])Workflows[\\/].+\.json$') {
            $text = Convert-WorkflowParameterDefaultsText -Text $text
        } elseif ($EntryName -match '(^|[\\/])environmentvariabledefinitions[\\/](?<schema>[^\\/]+)[\\/]environmentvariabledefinition\.xml$') {
            $text = Convert-EnvironmentVariableDefinitionText -Text $text -SchemaName $Matches['schema']
        } elseif ($EntryName -match '(^|[\\/])environmentvariabledefinitions[\\/](?<schema>[^\\/]+)[\\/]environmentvariablevalues\.json$') {
            $text = Convert-EnvironmentVariableValueText -Text $text -SchemaName $Matches['schema']
        }
    }

    $enc  = New-Object System.Text.UTF8Encoding($hasBom)
    return $enc.GetBytes($text)
}

function Read-EntryBytes {
    param([System.IO.Compression.ZipArchiveEntry]$Entry)
    $s = $Entry.Open()
    try {
        $ms = New-Object System.IO.MemoryStream
        $s.CopyTo($ms)
        return $ms.ToArray()
    } finally { $s.Dispose() }
}

function Write-EntryBytes {
    param([System.IO.Compression.ZipArchive]$Zip, [string]$Name, [byte[]]$Bytes)
    $entry = $Zip.CreateEntry($Name, [System.IO.Compression.CompressionLevel]::Optimal)
    $os = $entry.Open()
    try { $os.Write($Bytes, 0, $Bytes.Length) } finally { $os.Dispose() }
}

function Add-MissingEnvironmentVariableArtifacts {
    param(
        [Parameter(Mandatory)] [System.IO.Compression.ZipArchive]$Zip,
        [Parameter(Mandatory)] [System.Collections.Generic.HashSet[string]]$WrittenEntries
    )

    if ($script:EnvVarOverrides.Count -eq 0) { return }

    foreach ($entry in $script:EnvVarOverrides.GetEnumerator()) {
        $schema = [string]$entry.Key
        if ([string]::IsNullOrWhiteSpace($schema) -or $schema -notmatch '^[A-Za-z0-9_]+$') {
            continue
        }

        $value = [string]$entry.Value
        $basePath = "environmentvariabledefinitions/$schema"
        $defPath = "$basePath/environmentvariabledefinition.xml"
        $valPath = "$basePath/environmentvariablevalues.json"

        if (-not $WrittenEntries.Contains($defPath)) {
            $defText = New-EnvironmentVariableDefinitionXml -SchemaName $schema -Value $value
            $defBytes = [System.Text.Encoding]::UTF8.GetBytes($defText)
            Write-EntryBytes -Zip $Zip -Name $defPath -Bytes $defBytes
            [void]$WrittenEntries.Add($defPath)
            $script:AddedEnvVarArtifacts++
        }

        if (-not $WrittenEntries.Contains($valPath)) {
            $valText = New-EnvironmentVariableValueJson -Value $value
            $valBytes = [System.Text.Encoding]::UTF8.GetBytes($valText)
            Write-EntryBytes -Zip $Zip -Name $valPath -Bytes $valBytes
            [void]$WrittenEntries.Add($valPath)
            $script:AddedEnvVarArtifacts++
        }
    }
}

# A text entry we should transform: canvas meta.xml / customizations.xml or any
# Copilot agent (botcomponent) action 'data' file.
function Test-TextTarget {
    param([string]$Name)
    if ($Name -match '\.(xml|json|yaml|yml|js)$') { return $true }
    if ($Name -match '[\\/]data$') { return $true }
    return $false
}

# Rewrite the dataset string inside a nested .msapp (itself a zip).
function Convert-Msapp {
    param([byte[]]$Bytes)
    $inMs = New-Object System.IO.MemoryStream(, $Bytes)
    $outMs = New-Object System.IO.MemoryStream
    $inZip = New-Object System.IO.Compression.ZipArchive($inMs, [System.IO.Compression.ZipArchiveMode]::Read)
    try {
        $outZip = New-Object System.IO.Compression.ZipArchive($outMs, [System.IO.Compression.ZipArchiveMode]::Create, $true)
        try {
            foreach ($e in $inZip.Entries) {
                $b = Read-EntryBytes -Entry $e
                if ($e.FullName -match '(^|[\\/])(Properties\.json|DataSources\.json)$') {
                    $b = Convert-Bytes -Bytes $b -EntryName $e.FullName
                }
                Write-EntryBytes -Zip $outZip -Name $e.FullName -Bytes $b
            }
        } finally { $outZip.Dispose() }
    } finally { $inZip.Dispose(); $inMs.Dispose() }
    return $outMs.ToArray()
}

# ---- Rebuild the outer solution zip, transforming target entries ----
$tmpOut = "$OutputZip.tmp"
if (Test-Path $tmpOut)   { Remove-Item $tmpOut -Force }
if (Test-Path $OutputZip) { Remove-Item $OutputZip -Force }

$srcZip = [System.IO.Compression.ZipFile]::OpenRead((Resolve-Path $SolutionZip))
try {
    $outFs = [System.IO.File]::Open($tmpOut, [System.IO.FileMode]::Create)
    try {
        $outZip = New-Object System.IO.Compression.ZipArchive($outFs, [System.IO.Compression.ZipArchiveMode]::Create)
        try {
            $writtenEntries = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
            foreach ($entry in $srcZip.Entries) {
                if ([string]::IsNullOrEmpty($entry.Name)) { continue }  # skip directory entries
                $bytes = Read-EntryBytes -Entry $entry
                if ($entry.FullName -match '\.msapp$') {
                    $bytes = Convert-Msapp -Bytes $bytes
                } elseif (Test-TextTarget -Name $entry.FullName) {
                    $bytes = Convert-Bytes -Bytes $bytes -EntryName $entry.FullName
                }
                Write-EntryBytes -Zip $outZip -Name $entry.FullName -Bytes $bytes
                [void]$writtenEntries.Add($entry.FullName)
            }
            Add-MissingEnvironmentVariableArtifacts -Zip $outZip -WrittenEntries $writtenEntries
        } finally { $outZip.Dispose() }
    } finally { $outFs.Dispose() }
} finally { $srcZip.Dispose() }

Move-Item -Path $tmpOut -Destination $OutputZip -Force

Write-Host "Done. Updated solution content blocks: $script:Replacements" -ForegroundColor Green
if ($script:RenamedConnectionRefs -gt 0) {
    Write-Host "Renamed connection reference display names: $script:RenamedConnectionRefs (prefix '$ConnectionReferenceDisplayPrefix')" -ForegroundColor Green
}
if ($script:AddedLogicFlowConnectionRefs -gt 0) {
    Write-Host "Added missing Logic flows connection references: $script:AddedLogicFlowConnectionRefs" -ForegroundColor Green
}
if ($script:AddedLogicFlowDatasourceBindings -gt 0) {
    Write-Host "Added code-app Logic flows datasource bindings: $script:AddedLogicFlowDatasourceBindings" -ForegroundColor Green
}
if ($script:AddedEnvVarArtifacts -gt 0) {
    Write-Host "Added missing environment variable artifacts: $script:AddedEnvVarArtifacts" -ForegroundColor Green
}
Write-Host "Deployment-ready solution: $OutputZip" -ForegroundColor Green
return $OutputZip
