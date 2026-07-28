<#
.SYNOPSIS
    Signs in to Power Platform (browser pop-up) and imports the Payment Recon
    environment-variable-aware solution.

.DESCRIPTION
    This is a standalone, re-runnable Power Platform deployment step. It can be
    launched on its own (for example, to retry just the Power Platform import
    after the Azure deployment has already completed) or called by
    Install-PaymentRecon.ps1.

    Sign-in supports both interactive browser pop-up and device code. By default
    the script prompts for sign-in mode so operators can use browser when it
    works and switch to device code when browser sign-in is blocked/confusing.

.PARAMETER EnvironmentUrl
    Target Power Platform environment URL, e.g. https://org.crm.dynamics.com
    If omitted, you will be prompted.

.PARAMETER SolutionZip
    Path to the solution zip. Defaults to PaymentReconSolutionV5.zip
    next to this script (the merged solution containing the Power App and all
    Copilot Studio agents).

.PARAMETER AdditionalSolutionZip
    Optional path to a second solution zip to import in the SAME signed-in
    session, immediately after the primary solution. Left empty by default (the
    product now ships a single merged solution). When supplied, the second
    solution reuses the connection IDs resolved for the primary solution and
    discovers its own connection reference logical names from its package.

.PARAMETER SettingsFile
    Path to the pac import settings JSON. Defaults to
    PaymentReconSolutionV5.deployment-settings.json next to this script.

.PARAMETER SqlServerFqdn
    Azure SQL server (short name or FQDN) the app/agents should point at. If
    omitted, it is read from the SqlBinding section of the settings file, or
    prompted for.

.PARAMETER SqlDatabaseName
    Azure SQL database name. If omitted, read from the settings file's
    SqlBinding section, or prompted for.

.PARAMETER SqlConnectionId
    The Connection Id (GUID) of an existing SQL Server connection in the target
    environment to bind the canvas app and Copilot agents to. If omitted, the
    script uses Settings.Connections.SqlConnectionId when present; otherwise it
    continues without SQL pre-mapping (no interactive prompt).

.PARAMETER BlobConnectionId
    The Connection Id (GUID) of an existing Azure Blob Storage connection to bind
    to Blob connection references in the solution (for example, app file upload
    and any Cloud Flow Blob actions). Optional. If omitted, the script attempts
    auto-selection from existing Blob connections in the target environment and
    proceeds without Blob pre-mapping when ambiguous (no interactive prompt).

.PARAMETER AzureDataFactoryConnectionId
    Optional Connection Id (GUID) for Azure Data Factory connector references
    used by the imported flow.

.PARAMETER MicrosoftCopilotStudioConnectionId
    Optional Connection Id (GUID) for Microsoft Copilot Studio connector
    references used by the imported flow.

.PARAMETER A365McpServersConnectionId
    Optional Connection Id (GUID) for A365 MCP Servers connector references used
    by the imported agent.

.PARAMETER DataverseConnectionId
    Optional Connection Id (GUID) for Microsoft Dataverse connector references
    used by the code app (the Reconcile button writes a Dataverse row that
    triggers the reconciliation cloud flow). If omitted, the script auto-selects
    the environment's Dataverse connection when exactly one is available.

.PARAMETER LogFile
    Optional log file path for this Power Platform deployment run. If omitted,
    a timestamped deploy-powerplatform-*.log file is created next to this script.

.PARAMETER SignInMode
    Power Platform sign-in mode:
      - Prompt       : Legacy alias of AutoFallback (no prompt shown)
      - Browser      : Browser pop-up sign-in only
      - DeviceCode   : Device-code sign-in only
      - AutoFallback : Default. Try Browser first, then DeviceCode if browser sign-in
                       fails OR does not produce a verified active session.

.PARAMETER SkipConnectionMapping
    If set, the solution is imported WITHOUT pre-mapping the SQL/Blob connection
    references. You will then have to wire the connections manually after import.

.PARAMETER BootstrapConnectionSetup
    If set and any required connection IDs are missing, the script performs a
    first import, then pauses with connector-setup instructions and runs a
    second import in the same terminal session after confirmation.

.PARAMETER KeepSignIn
    If set, the temporary Power Platform auth profile is NOT deleted at the end.
    By default the profile is removed so no refresh token is left on disk.

.EXAMPLE
    .\Deploy-PowerPlatform.ps1

.EXAMPLE
    .\Deploy-PowerPlatform.ps1 -EnvironmentUrl "https://contoso.crm.dynamics.com"
#>

[CmdletBinding()]
param(
    [string]$EnvironmentUrl,
    [string]$SolutionZip,
    [string]$AdditionalSolutionZip,
    [string]$SettingsFile,
    [string]$SqlServerFqdn,
    [string]$SqlDatabaseName,
    [string]$SqlConnectionId,
    [string]$BlobConnectionId,
    [string]$AzureDataFactoryConnectionId,
    [string]$MicrosoftCopilotStudioConnectionId,
    [string]$A365McpServersConnectionId,
    [string]$DataverseConnectionId,
    [string]$LogFile,
    [ValidateSet('Prompt','Browser','DeviceCode','AutoFallback')]
    [string]$SignInMode = 'AutoFallback',
    [switch]$SkipConnectionMapping,
    [switch]$BootstrapConnectionSetup,
    [switch]$KeepSignIn
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Force a neutral console palette for this import session so inherited shell
# themes/colors do not produce a full-screen blue background.
if ($Host -and $Host.UI -and $Host.UI.RawUI) {
    $Host.UI.RawUI.BackgroundColor = "Black"
    $Host.UI.RawUI.ForegroundColor = "Gray"
    Clear-Host
}
$esc = [char]27
Write-Host "$esc[0m$esc[37;40m$esc[2J$esc[H" -NoNewline

trap {
    if ($script:LogPath) {
        Write-Log "ERROR : $($_.Exception.Message)"
    }
    throw
}

# Connection-reference logical names baked into the shipped solution. The three
# SQL references (canvas app + two Copilot agents) all bind to one SQL Server
# connection. Blob references are discovered from the deployment solution zip;
# this default list is only a fallback.
$script:SqlConnectionRefLogicalNames = @(
    'cap_sharedsql_36c34127c7',
    'copilots_header_fe637.shared_sql.9ea221cbf55f45aea2135ed09ee80b3c',
    'cre7a_agentR61Db3.shared_sql.shared-sql-bf74b048-9772-4554-91ed-69eaa209c782'
)
$script:SqlConnectorId  = '/providers/Microsoft.PowerApps/apis/shared_sql'
$script:BlobConnectionRefLogicalNames = @(
    'cap_sharedazureblob_36c34fa51a'
)
$script:BlobConnectorId = '/providers/Microsoft.PowerApps/apis/shared_azureblob'
$script:AzureDataFactoryConnectionRefLogicalNames = @(
    'new_sharedazuredatafactory_98752'
)
$script:AzureDataFactoryConnectorId = '/providers/Microsoft.PowerApps/apis/shared_azuredatafactory'
$script:MicrosoftCopilotStudioConnectionRefLogicalNames = @(
    'new_sharedmicrosoftcopilotstudio_dea00'
)
$script:MicrosoftCopilotStudioConnectorId = '/providers/Microsoft.PowerApps/apis/shared_microsoftcopilotstudio'
$script:A365McpServersConnectionRefLogicalNames = @(
    'cre7a_agentR61Db3.shared_a365mcpservers.shared-a365mcpserver-afbe760a-ab61-4886-bd0d-54db4fe8d46e'
)
$script:A365McpServersConnectorId = '/providers/Microsoft.PowerApps/apis/shared_a365mcpservers'
# Dataverse: the CODE APP resolves its own Dataverse connection at RUNTIME (no
# connection reference, so it never blocks startup). This connection reference is
# for the reconciliation FLOW's "When a row is added" trigger on
# payrecon_reconciliationrequests. It is discovered from the solution package;
# this list is only a fallback.
$script:DataverseConnectionRefLogicalNames = @(
    'new_sharedcommondataserviceforapps_d0a7e'
)
$script:DataverseConnectorId = '/providers/Microsoft.PowerApps/apis/shared_commondataserviceforapps'
$script:LogPath = $null

function Initialize-DeploymentLog {
    param(
        [Parameter(Mandatory)] [string]$ScriptDirectory,
        [string]$RequestedPath
    )

    if ([string]::IsNullOrWhiteSpace($RequestedPath)) {
        $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
        $RequestedPath = Join-Path $ScriptDirectory "deploy-powerplatform-$stamp.log"
    }

    $script:LogPath = $RequestedPath
    "[$([DateTime]::Now.ToString('s'))] Log started: $script:LogPath" | Out-File -FilePath $script:LogPath -Encoding utf8
}

function Write-Log {
    param([string]$Line)
    if ($script:LogPath) {
        "[$([DateTime]::Now.ToString('s'))] $Line" | Out-File -FilePath $script:LogPath -Append -Encoding utf8
    }
}

function Invoke-PacCommand {
    param(
        [Parameter(Mandatory)] [string]$Pac,
        [Parameter(Mandatory)] [string[]]$Arguments,
        [string]$Description
    )

    if ($Description) { Write-Log "STEP  : $Description" }
    Write-Log "CMD   : pac $($Arguments -join ' ')"

    $output = @(& $Pac @Arguments 2>&1)
    $hasErrorMarker = $false
    foreach ($line in $output) {
        $text = [string]$line
        Write-Host $text
        Write-Log "PAC   : $text"
        if ($text -match '^\s*Error:') {
            $hasErrorMarker = $true
        }
    }
    $exit = $LASTEXITCODE
    Write-Log "EXIT  : $exit"
    return [pscustomobject]@{
        ExitCode       = $exit
        Output         = @($output)
        HasErrorMarker = $hasErrorMarker
    }
}

function Get-PacCommand {
    $pac = Get-Command pac -ErrorAction SilentlyContinue
    if (-not $pac) {
        throw "Power Platform CLI (pac) was not found. Install it first, then rerun: https://aka.ms/PowerAppsCLI"
    }
    return $pac.Source
}

function Read-RequiredValue {
    param([Parameter(Mandatory)] [string]$Prompt)
    while ($true) {
        $value = Read-Host $Prompt
        if (-not [string]::IsNullOrWhiteSpace($value)) { return $value.Trim() }
        Write-Host "Value is required." -ForegroundColor Yellow
    }
}

function Resolve-SignInMode {
    param([string]$RequestedMode)

    if (-not $RequestedMode -or $RequestedMode -eq 'Prompt') { return 'AutoFallback' }
    return $RequestedMode
}

function Invoke-PacAuthCreate {
    param(
        [Parameter(Mandatory)] [string]$Pac,
        [Parameter(Mandatory)] [string]$AuthName,
        [Parameter(Mandatory)] [string]$EnvironmentUrl,
        [Parameter(Mandatory)] [ValidateSet('Browser','DeviceCode')] [string]$Mode
    )

    Write-Host "`n==> Power Platform sign-in ($Mode)" -ForegroundColor Cyan
    Write-Host "------------------------------------------------------------" -ForegroundColor DarkGray
    $args = @('auth','create','--name',$AuthName,'--environment',$EnvironmentUrl)
    if ($Mode -eq 'Browser') {
        Write-Host "A browser window will open for sign-in." -ForegroundColor Yellow
        Write-Host "  * Complete sign-in in the browser, then return here." -ForegroundColor Gray
        Write-Host "  * If no browser appears, check for blocked pop-ups/windows." -ForegroundColor Gray
    } else {
        Write-Host "Device-code sign-in selected." -ForegroundColor Yellow
        Write-Host "  * Copy the shown code, open the URL, sign in, then return here." -ForegroundColor Gray
        $args += '--deviceCode'
    }
    $result = Invoke-PacCommand -Pac $Pac -Arguments $args -Description "Power Platform auth create ($Mode)"
    Write-Host "------------------------------------------------------------" -ForegroundColor DarkGray

    return ($result.ExitCode -eq 0)
}

function Test-GuidValue {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return $false }
    return ($Value.Trim() -match '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')
}

function Get-UnresolvedConnectionTargets {
    param(
        [string]$SqlConnectionId,
        [string]$BlobConnectionId,
        [string]$AzureDataFactoryConnectionId,
        [string]$MicrosoftCopilotStudioConnectionId,
        [string]$A365McpServersConnectionId,
        [string]$DataverseConnectionId,
        [string[]]$AzureDataFactoryConnectionRefLogicalNames = @(),
        [string[]]$MicrosoftCopilotStudioConnectionRefLogicalNames = @(),
        [string[]]$A365McpServersConnectionRefLogicalNames = @(),
        [string[]]$DataverseConnectionRefLogicalNames = @()
    )

    $missing = New-Object System.Collections.Generic.List[string]
    if ([string]::IsNullOrWhiteSpace($SqlConnectionId)) { $missing.Add("SqlConnectionId (SQL Server)") }
    if ([string]::IsNullOrWhiteSpace($BlobConnectionId)) { $missing.Add("BlobConnectionId (Azure Blob Storage)") }

    $adfRefs = @($AzureDataFactoryConnectionRefLogicalNames | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($adfRefs.Count -gt 0 -and [string]::IsNullOrWhiteSpace($AzureDataFactoryConnectionId)) {
        $missing.Add("AzureDataFactoryConnectionId (Azure Data Factory)")
    }

    $copilotRefs = @($MicrosoftCopilotStudioConnectionRefLogicalNames | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($copilotRefs.Count -gt 0 -and [string]::IsNullOrWhiteSpace($MicrosoftCopilotStudioConnectionId)) {
        $missing.Add("MicrosoftCopilotStudioConnectionId (Microsoft Copilot Studio)")
    }

    $mcpRefs = @($A365McpServersConnectionRefLogicalNames | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($mcpRefs.Count -gt 0 -and [string]::IsNullOrWhiteSpace($A365McpServersConnectionId)) {
        $missing.Add("A365McpServersConnectionId (A365 MCP Servers)")
    }

    $dataverseRefs = @($DataverseConnectionRefLogicalNames | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($dataverseRefs.Count -gt 0 -and [string]::IsNullOrWhiteSpace($DataverseConnectionId)) {
        $missing.Add("DataverseConnectionId (Microsoft Dataverse)")
    }

    return @($missing)
}

function Normalize-ConnectionId {
    param(
        [string]$Value,
        [Parameter(Mandatory)] [string]$Name
    )

    if ([string]::IsNullOrWhiteSpace($Value)) { return $null }
    if (Test-GuidValue -Value $Value) { return $Value.Trim() }
    Write-Host "Ignoring invalid $Name (must be GUID): $Value" -ForegroundColor Yellow
    Write-Log "WARN  : Invalid $Name provided: $Value"
    return $null
}

function Get-EnvironmentVariableValue {
    param(
        [object]$SettingsJson,
        [Parameter(Mandatory)] [string]$SchemaName
    )

    if ($null -eq $SettingsJson) { return $null }
    if (-not ($SettingsJson.PSObject.Properties.Name -contains 'EnvironmentVariables')) { return $null }

    foreach ($ev in $SettingsJson.EnvironmentVariables) {
        if ([string]$ev.SchemaName -eq $SchemaName) {
            return [string]$ev.Value
        }
    }
    return $null
}

function Get-BlobConnectionCandidates {
    param(
        [Parameter(Mandatory)] [string]$Pac,
        [Parameter(Mandatory)] [string]$EnvironmentUrl
    )

    $result = Invoke-PacCommand -Pac $Pac -Arguments @('connection','list','--environment',$EnvironmentUrl) -Description "Listing Power Platform connections"
    if ($result.ExitCode -ne 0) {
        Write-Host "Could not list Power Platform connections to auto-resolve blob mapping." -ForegroundColor Yellow
        return @()
    }

    $rows = @()
    $pattern = '^\s*(?<id>[0-9a-fA-F-]{36})\s+(?<name>.+?)\s+(?<apiid>/providers/Microsoft\.PowerApps/apis/[^\s]+)\s+(?<status>[^\s]+)\s*$'
    foreach ($line in $result.Output) {
        $text = [string]$line
        if ($text -match $pattern) {
            $apiId = [string]$Matches['apiid']
            if ($apiId -eq $script:BlobConnectorId) {
                $rows += [pscustomobject]@{
                    Id     = ([string]$Matches['id']).ToLowerInvariant()
                    Name   = [string]$Matches['name']
                    ApiId  = $apiId
                    Status = [string]$Matches['status']
                }
            }
        }
    }
    return @($rows)
}

function Get-SqlConnectionCandidates {
    param(
        [Parameter(Mandatory)] [string]$Pac,
        [Parameter(Mandatory)] [string]$EnvironmentUrl
    )

    $result = Invoke-PacCommand -Pac $Pac -Arguments @('connection','list','--environment',$EnvironmentUrl) -Description "Listing Power Platform connections"
    if ($result.ExitCode -ne 0) {
        Write-Host "Could not list Power Platform connections to auto-resolve SQL mapping." -ForegroundColor Yellow
        return @()
    }

    $rows = @()
    $pattern = '^\s*(?<id>[0-9a-fA-F-]{36})\s+(?<name>.+?)\s+(?<apiid>/providers/Microsoft\.PowerApps/apis/[^\s]+)\s+(?<status>[^\s]+)\s*$'
    foreach ($line in $result.Output) {
        $text = [string]$line
        if ($text -match $pattern) {
            $apiId = [string]$Matches['apiid']
            if ($apiId -eq $script:SqlConnectorId) {
                $rows += [pscustomobject]@{
                    Id     = ([string]$Matches['id']).ToLowerInvariant()
                    Name   = [string]$Matches['name']
                    ApiId  = $apiId
                    Status = [string]$Matches['status']
                }
            }
        }
    }
    return @($rows)
}

function Resolve-SqlConnectionIdAuto {
    param(
        [Parameter(Mandatory)] [string]$Pac,
        [Parameter(Mandatory)] [string]$EnvironmentUrl,
        [string]$SqlServerFqdn,
        [string]$SqlDatabaseName
    )

    if ([string]::IsNullOrWhiteSpace($SqlServerFqdn) -or [string]::IsNullOrWhiteSpace($SqlDatabaseName)) {
        return $null
    }

    $fqdn = $SqlServerFqdn.Trim().ToLowerInvariant()
    if ($fqdn -notmatch '\.database\.windows\.net$') {
        $fqdn = "$fqdn.database.windows.net"
    }
    $shortServer = ($fqdn -replace '\.database\.windows\.net$', '')
    $db = $SqlDatabaseName.Trim().ToLowerInvariant()

    $candidates = @(Get-SqlConnectionCandidates -Pac $Pac -EnvironmentUrl $EnvironmentUrl)
    if ($candidates.Count -eq 0) { return $null }

    $active = @($candidates | Where-Object { $_.Status -eq 'Connected' })
    if ($active.Count -eq 0) { $active = @($candidates) }

    $exact = @($active | Where-Object {
        $n = ([string]$_.Name).ToLowerInvariant()
        $n -like "*$db*" -and $n -like "*$fqdn*"
    })
    if ($exact.Count -eq 1) {
        Write-Log "INFO  : Auto-resolved SQL connection from environment (exact fqdn/db match): $($exact[0].Id)"
        return [string]$exact[0].Id
    }

    $fallback = @($active | Where-Object {
        $n = ([string]$_.Name).ToLowerInvariant()
        $n -like "*$db*" -and $n -like "*$shortServer*"
    })
    if ($fallback.Count -eq 1) {
        Write-Log "INFO  : Auto-resolved SQL connection from environment (short-server/db match): $($fallback[0].Id)"
        return [string]$fallback[0].Id
    }

    if ($exact.Count -gt 1 -or $fallback.Count -gt 1) {
        Write-Log "WARN  : Multiple SQL connection candidates matched target server/database; skipping auto-selection."
    }
    return $null
}

function Get-DataverseConnectionCandidates {
    param(
        [Parameter(Mandatory)] [string]$Pac,
        [Parameter(Mandatory)] [string]$EnvironmentUrl
    )

    $result = Invoke-PacCommand -Pac $Pac -Arguments @('connection','list','--environment',$EnvironmentUrl) -Description "Listing Power Platform connections"
    if ($result.ExitCode -ne 0) {
        Write-Host "Could not list Power Platform connections to auto-resolve Dataverse mapping." -ForegroundColor Yellow
        return @()
    }

    $rows = @()
    $pattern = '^\s*(?<id>[0-9a-fA-F-]{36})\s+(?<name>.+?)\s+(?<apiid>/providers/Microsoft\.PowerApps/apis/[^\s]+)\s+(?<status>[^\s]+)\s*$'
    foreach ($line in $result.Output) {
        $text = [string]$line
        if ($text -match $pattern) {
            $apiId = [string]$Matches['apiid']
            if ($apiId -eq $script:DataverseConnectorId) {
                $rows += [pscustomobject]@{
                    Id     = ([string]$Matches['id']).ToLowerInvariant()
                    Name   = [string]$Matches['name']
                    ApiId  = $apiId
                    Status = [string]$Matches['status']
                }
            }
        }
    }
    return @($rows)
}

function Resolve-DataverseConnectionIdAuto {
    param(
        [Parameter(Mandatory)] [string]$Pac,
        [Parameter(Mandatory)] [string]$EnvironmentUrl
    )

    $candidates = @(Get-DataverseConnectionCandidates -Pac $Pac -EnvironmentUrl $EnvironmentUrl)
    if ($candidates.Count -eq 0) { return $null }

    $active = @($candidates | Where-Object { $_.Status -eq 'Connected' })
    if ($active.Count -eq 0) { $active = @($candidates) }

    if ($active.Count -eq 1) {
        Write-Log "INFO  : Auto-resolved Dataverse connection from environment: $($active[0].Id)"
        return [string]$active[0].Id
    }
    if ($active.Count -gt 1) {
        Write-Log "WARN  : Multiple Dataverse connection candidates found; skipping auto-selection."
    }
    return $null
}

function Get-SolutionConnectionRefLogicalNames {
    param(
        [Parameter(Mandatory)] [string]$SolutionZip,
        [Parameter(Mandatory)] [string]$ConnectorId,
        [string[]]$FallbackLogicalNames = @()
    )

    $fallback = @($FallbackLogicalNames | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
    if (-not (Test-Path $SolutionZip)) {
        return $fallback
    }

    try {
        Add-Type -AssemblyName System.IO.Compression
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $zip = [System.IO.Compression.ZipFile]::OpenRead((Resolve-Path $SolutionZip))
        try {
            $entry = $zip.Entries | Where-Object { $_.FullName -match '(?i)(^|[\\/])customizations\.xml$' } | Select-Object -First 1
            if (-not $entry) { return $fallback }

            $sr = New-Object System.IO.StreamReader($entry.Open())
            try {
                $xmlText = $sr.ReadToEnd()
            } finally {
                $sr.Dispose()
            }

            [xml]$xml = $xmlText
            $refs = @()
            if ($xml.ImportExportXml -and $xml.ImportExportXml.connectionreferences) {
                foreach ($refNode in $xml.ImportExportXml.connectionreferences.connectionreference) {
                    $logicalName = [string]$refNode.connectionreferencelogicalname
                    $connector = [string]$refNode.connectorid
                    if ($connector -eq $ConnectorId -and -not [string]::IsNullOrWhiteSpace($logicalName)) {
                        $refs += $logicalName
                    }
                }
            }

            $resolved = @($refs | Select-Object -Unique)
            if ($resolved.Count -gt 0) { return $resolved }
            return $fallback
        } finally {
            $zip.Dispose()
        }
    } catch {
        Write-Host "Could not discover connector references from solution package: $($_.Exception.Message)" -ForegroundColor Yellow
        return $fallback
    }
}

function Resolve-SqlConnectionId {
    <#
        Resolves the SQL Server Connection Id to map. This prompt is intentionally
        scoped to the solution connection references only; it does not scan or
        auto-select from other environment connections.
    #>
    $printedBootstrapHelp = $false
    while ($true) {
        Write-Host "`n==> SQL connection mapping for this solution" -ForegroundColor Cyan
        Write-Host "Paste the SQL Connection Id (GUID) to map the solution's SQL connection references." -ForegroundColor Gray
        Write-Host "Press Enter to skip SQL connection mapping for now." -ForegroundColor Gray
        if (-not $printedBootstrapHelp) {
            Write-Host "If this is your first install and no SQL connection exists yet:" -ForegroundColor Yellow
            Write-Host "  1) Press Enter to continue import without SQL mapping." -ForegroundColor Gray
            Write-Host "  2) Create SQL connection in make.powerapps.com > Data > Connections." -ForegroundColor Gray
            Write-Host "  3) Re-run this script and paste the SQL Connection Id (GUID)." -ForegroundColor Gray
            Write-Host "  Tip: list connections with: pac connection list --environment $EnvironmentUrl" -ForegroundColor Gray
            $printedBootstrapHelp = $true
        }
        $answer = Read-Host "SQL Connection Id"
        if ([string]::IsNullOrWhiteSpace($answer)) {
            Write-Log "INFO  : SQL connection mapping skipped by user."
            return $null
        }
        if (Test-GuidValue -Value $answer) {
            $id = $answer.Trim().ToLowerInvariant()
            Write-Log "INFO  : SQL connection selected for solution mapping: $id"
            return $id
        }
        Write-Host "Invalid Connection Id format. Enter a GUID like xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx." -ForegroundColor Yellow
    }
}

function Resolve-BlobConnectionId {
    param(
        [Parameter(Mandatory)] [string]$Pac,
        [Parameter(Mandatory)] [string]$EnvironmentUrl,
        [string]$StorageAccountName,
        [switch]$AllowPrompt
    )

    Write-Host "`n==> Azure Blob connection mapping for this solution" -ForegroundColor Cyan
    if (-not [string]::IsNullOrWhiteSpace($StorageAccountName)) {
        Write-Host "Target storage account from step 1: $StorageAccountName" -ForegroundColor Gray
    }

    $candidates = @(Get-BlobConnectionCandidates -Pac $Pac -EnvironmentUrl $EnvironmentUrl)
    if ($candidates.Count -gt 0) {
        $preferred = @()
        if (-not [string]::IsNullOrWhiteSpace($StorageAccountName)) {
            $preferred = @($candidates | Where-Object { $_.Name -like "*$StorageAccountName*" })
        }
        if ($preferred.Count -eq 1) {
            $id = [string]$preferred[0].Id
            Write-Host "Auto-selected Azure Blob connection: $id ($($preferred[0].Name))" -ForegroundColor Green
            Write-Log "INFO  : Blob connection auto-selected by storage account name '$StorageAccountName': $id"
            return $id
        }
        if ($candidates.Count -eq 1) {
            $id = [string]$candidates[0].Id
            Write-Host "Auto-selected Azure Blob connection: $id ($($candidates[0].Name))" -ForegroundColor Green
            Write-Log "INFO  : Blob connection auto-selected (single candidate): $id"
            return $id
        }

        if ($AllowPrompt) {
            Write-Host "Multiple Azure Blob connections were found in this environment:" -ForegroundColor Yellow
            for ($i = 0; $i -lt $candidates.Count; $i++) {
                $c = $candidates[$i]
                Write-Host ("  [{0}] {1} | {2} | {3}" -f ($i + 1), $c.Id, $c.Name, $c.Status) -ForegroundColor Gray
            }
            Write-Host "Paste a Blob Connection Id (GUID) or choose by number. Press Enter to skip." -ForegroundColor Gray
        }
    } else {
        if ($AllowPrompt) {
            Write-Host "No Azure Blob connections were found automatically in this environment." -ForegroundColor Yellow
            Write-Host "Create one in make.powerapps.com > Data > Connections (Azure Blob Storage), then re-run or paste its Connection Id now." -ForegroundColor Gray
        }
    }

    if (-not $AllowPrompt) {
        if ($candidates.Count -gt 1) {
            Write-Host "Multiple Azure Blob connections were found; skipping Blob pre-mapping to avoid interactive prompts." -ForegroundColor Yellow
            Write-Log "INFO  : Blob connection unresolved due to multiple candidates in non-interactive mode."
        } else {
            Write-Host "No Azure Blob connection could be auto-resolved; skipping Blob pre-mapping." -ForegroundColor Yellow
            Write-Log "INFO  : Blob connection unresolved in non-interactive mode."
        }
        return $null
    }

    while ($true) {
        $answer = Read-Host "Blob Connection Id"
        if ([string]::IsNullOrWhiteSpace($answer)) {
            Write-Log "INFO  : Blob connection mapping skipped by user."
            return $null
        }

        $indexValue = 0
        if ($candidates.Count -gt 0 -and [int]::TryParse($answer.Trim(), [ref]$indexValue)) {
            if ($indexValue -ge 1 -and $indexValue -le $candidates.Count) {
                $picked = [string]$candidates[$indexValue - 1].Id
                Write-Log "INFO  : Blob connection selected by list index: $picked"
                return $picked
            }
            Write-Host "Invalid selection index. Choose a number between 1 and $($candidates.Count)." -ForegroundColor Yellow
            continue
        }

        if (Test-GuidValue -Value $answer) {
            $id = $answer.Trim().ToLowerInvariant()
            Write-Log "INFO  : Blob connection selected for solution mapping: $id"
            return $id
        }
        Write-Host "Invalid Connection Id format. Enter a GUID like xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx." -ForegroundColor Yellow
    }
}

function New-ImportSettingsFile {
    <#
        Builds a pac-schema import settings file (EnvironmentVariables +
        ConnectionReferences) from our deployment metadata settings file. The
        custom SqlBinding section is intentionally excluded (pac does not
        understand it). Connection references are only emitted for connections we
        actually resolved, so unresolved references are left for the importer to
        handle. Returns the path to the generated temp file.
    #>
    param(
        [Parameter(Mandatory)] [string]$MetadataSettingsFile,
        [string]$SqlConnectionId,
        [string]$BlobConnectionId,
        [string]$AzureDataFactoryConnectionId,
        [string]$MicrosoftCopilotStudioConnectionId,
        [string]$A365McpServersConnectionId,
        [string]$DataverseConnectionId,
        [string[]]$SqlConnectionRefLogicalNames = @(),
        [string[]]$BlobConnectionRefLogicalNames = @(),
        [string[]]$AzureDataFactoryConnectionRefLogicalNames = @(),
        [string[]]$MicrosoftCopilotStudioConnectionRefLogicalNames = @(),
        [string[]]$A365McpServersConnectionRefLogicalNames = @(),
        [string[]]$DataverseConnectionRefLogicalNames = @()
    )

    if (-not [string]::IsNullOrWhiteSpace($SqlConnectionId) -and -not (Test-GuidValue -Value $SqlConnectionId)) {
        throw "SqlConnectionId must be a GUID."
    }
    if (-not [string]::IsNullOrWhiteSpace($BlobConnectionId) -and -not (Test-GuidValue -Value $BlobConnectionId)) {
        throw "BlobConnectionId must be a GUID."
    }
    if (-not [string]::IsNullOrWhiteSpace($AzureDataFactoryConnectionId) -and -not (Test-GuidValue -Value $AzureDataFactoryConnectionId)) {
        throw "AzureDataFactoryConnectionId must be a GUID."
    }
    if (-not [string]::IsNullOrWhiteSpace($MicrosoftCopilotStudioConnectionId) -and -not (Test-GuidValue -Value $MicrosoftCopilotStudioConnectionId)) {
        throw "MicrosoftCopilotStudioConnectionId must be a GUID."
    }
    if (-not [string]::IsNullOrWhiteSpace($A365McpServersConnectionId) -and -not (Test-GuidValue -Value $A365McpServersConnectionId)) {
        throw "A365McpServersConnectionId must be a GUID."
    }
    if (-not [string]::IsNullOrWhiteSpace($DataverseConnectionId) -and -not (Test-GuidValue -Value $DataverseConnectionId)) {
        throw "DataverseConnectionId must be a GUID."
    }

    $meta = Get-Content -Path $MetadataSettingsFile -Raw | ConvertFrom-Json

    $envVars = @()
    if ($meta.PSObject.Properties.Name -contains 'EnvironmentVariables') {
        foreach ($ev in $meta.EnvironmentVariables) {
            $envVars += [ordered]@{ SchemaName = $ev.SchemaName; Value = [string]$ev.Value }
        }
    }

    $connRefs = @()
    if (-not [string]::IsNullOrWhiteSpace($SqlConnectionId)) {
        $sqlRefNames = @($SqlConnectionRefLogicalNames | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
        if ($sqlRefNames.Count -eq 0) {
            $sqlRefNames = @($script:SqlConnectionRefLogicalNames)
        }
        foreach ($ln in $sqlRefNames) {
            $connRefs += [ordered]@{
                LogicalName  = $ln
                ConnectionId = $SqlConnectionId
                ConnectorId  = $script:SqlConnectorId
            }
        }
    }
    if (-not [string]::IsNullOrWhiteSpace($BlobConnectionId)) {
        $blobRefNames = @($BlobConnectionRefLogicalNames | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
        if ($blobRefNames.Count -eq 0) {
            $blobRefNames = @($script:BlobConnectionRefLogicalNames)
        }
        foreach ($ln in $blobRefNames) {
            $connRefs += [ordered]@{
                LogicalName  = $ln
                ConnectionId = $BlobConnectionId
                ConnectorId  = $script:BlobConnectorId
            }
        }
    }
    if (-not [string]::IsNullOrWhiteSpace($AzureDataFactoryConnectionId)) {
        $adfRefNames = @($AzureDataFactoryConnectionRefLogicalNames | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
        if ($adfRefNames.Count -eq 0) {
            $adfRefNames = @($script:AzureDataFactoryConnectionRefLogicalNames)
        }
        foreach ($ln in $adfRefNames) {
            $connRefs += [ordered]@{
                LogicalName  = $ln
                ConnectionId = $AzureDataFactoryConnectionId
                ConnectorId  = $script:AzureDataFactoryConnectorId
            }
        }
    }
    if (-not [string]::IsNullOrWhiteSpace($MicrosoftCopilotStudioConnectionId)) {
        $copilotRefNames = @($MicrosoftCopilotStudioConnectionRefLogicalNames | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
        if ($copilotRefNames.Count -eq 0) {
            $copilotRefNames = @($script:MicrosoftCopilotStudioConnectionRefLogicalNames)
        }
        foreach ($ln in $copilotRefNames) {
            $connRefs += [ordered]@{
                LogicalName  = $ln
                ConnectionId = $MicrosoftCopilotStudioConnectionId
                ConnectorId  = $script:MicrosoftCopilotStudioConnectorId
            }
        }
    }
    if (-not [string]::IsNullOrWhiteSpace($A365McpServersConnectionId)) {
        $mcpRefNames = @($A365McpServersConnectionRefLogicalNames | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
        if ($mcpRefNames.Count -eq 0) {
            $mcpRefNames = @($script:A365McpServersConnectionRefLogicalNames)
        }
        foreach ($ln in $mcpRefNames) {
            $connRefs += [ordered]@{
                LogicalName  = $ln
                ConnectionId = $A365McpServersConnectionId
                ConnectorId  = $script:A365McpServersConnectorId
            }
        }
    }
    if (-not [string]::IsNullOrWhiteSpace($DataverseConnectionId)) {
        $dataverseRefNames = @($DataverseConnectionRefLogicalNames | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
        if ($dataverseRefNames.Count -eq 0) {
            $dataverseRefNames = @($script:DataverseConnectionRefLogicalNames)
        }
        foreach ($ln in $dataverseRefNames) {
            $connRefs += [ordered]@{
                LogicalName  = $ln
                ConnectionId = $DataverseConnectionId
                ConnectorId  = $script:DataverseConnectorId
            }
        }
    }

    $obj = [ordered]@{ EnvironmentVariables = @($envVars) }
    if ($connRefs.Count -gt 0) { $obj['ConnectionReferences'] = @($connRefs) }

    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("payrecon-import-settings-{0}.json" -f ([guid]::NewGuid().ToString('N')))
    ($obj | ConvertTo-Json -Depth 10) | Out-File -FilePath $tmp -Encoding utf8
    return $tmp
}

$scriptDir = $PSScriptRoot
if (-not $scriptDir) { $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path }

# Two independent solutions ship in Solutions\ (source repo) or Deployment\Solutions\
# (delivered package). Code App is imported first (primary), then Agent V5.
function Resolve-SolutionZipPath {
    param([string]$Dir, [string]$Name)
    $candidate = Join-Path $Dir (Join-Path 'Solutions' $Name)
    if (Test-Path $candidate) { return $candidate }
    return (Join-Path $Dir $Name)
}
if (-not $SolutionZip)  { $SolutionZip  = Resolve-SolutionZipPath -Dir $scriptDir -Name "PaymentReconAgentV5_unmanaged.zip" }
if (-not $SettingsFile) { $SettingsFile = Join-Path $scriptDir "PaymentReconSolutionV5.deployment-settings.json" }

Initialize-DeploymentLog -ScriptDirectory $scriptDir -RequestedPath $LogFile
Write-Host "Log file: $script:LogPath" -ForegroundColor Gray
Write-Log "INFO  : Script directory: $scriptDir"
Write-Log "INFO  : Solution zip: $SolutionZip"
if (-not [string]::IsNullOrWhiteSpace($AdditionalSolutionZip)) {
    Write-Log "INFO  : Additional solution zip: $AdditionalSolutionZip"
}
Write-Log "INFO  : Settings file: $SettingsFile"
Write-Log "INFO  : SignInMode: $SignInMode"

$pac = Get-PacCommand

if (-not (Test-Path $SolutionZip)) {
    throw "Power Platform solution zip not found: $SolutionZip"
}
if (-not (Test-Path $SettingsFile)) {
    throw "Power Platform deployment settings file not found: $SettingsFile`nRun the Azure deployment first so it generates this file, or pass -SettingsFile."
}

if (-not $EnvironmentUrl) {
    $EnvironmentUrl = Read-RequiredValue -Prompt "Enter target Power Platform environment URL (for example, https://org.crm.dynamics.com)"
}

# ---------------------------------------------------------------------------
# Rewrite deployment-specific bindings inside the solution:
#   1) SQL server/database for the canvas app and Copilot agents.
#   2) Cloud Flow/environment variable defaults from Settings.EnvironmentVariables
#      so ADF subscription/resource-group/factory/pipeline values align with
#      the Azure deployment step.
# SQL values come from -SqlServerFqdn/-SqlDatabaseName, else SqlBinding in the
# settings file, else SQL EnvironmentVariables in the settings file, else an
# interactive prompt.
# ---------------------------------------------------------------------------
if (-not $SqlServerFqdn -or -not $SqlDatabaseName) {
    try {
        $settingsJson = Get-Content -Path $SettingsFile -Raw | ConvertFrom-Json
        if ($settingsJson.PSObject.Properties.Name -contains 'SqlBinding') {
            if (-not $SqlServerFqdn)   { $SqlServerFqdn   = $settingsJson.SqlBinding.ServerFqdn }
            if (-not $SqlDatabaseName)  { $SqlDatabaseName = $settingsJson.SqlBinding.Database }
        }
        if ((-not $SqlServerFqdn -or -not $SqlDatabaseName) -and $settingsJson.PSObject.Properties.Name -contains 'EnvironmentVariables') {
            foreach ($ev in $settingsJson.EnvironmentVariables) {
                $schemaName = [string]$ev.SchemaName
                if ($schemaName -eq 'cap_PaymentReconSqlServerFqdn' -and -not $SqlServerFqdn) {
                    $SqlServerFqdn = [string]$ev.Value
                }
                if ($schemaName -eq 'cap_PaymentReconSqlDatabaseName' -and -not $SqlDatabaseName) {
                    $SqlDatabaseName = [string]$ev.Value
                }
            }
        }
    } catch {
        Write-Host "Could not read SQL values from settings file: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}
if (-not $SqlServerFqdn)  { $SqlServerFqdn  = Read-RequiredValue -Prompt "Enter the Azure SQL server (e.g. myserver or myserver.database.windows.net)" }
if (-not $SqlDatabaseName) { $SqlDatabaseName = Read-RequiredValue -Prompt "Enter the Azure SQL database name" }

$rewriteScript = Join-Path $scriptDir "Update-SolutionSqlBinding.ps1"
if (Test-Path $rewriteScript) {
    Write-Host "`n==> Updating solution bindings for this deployment" -ForegroundColor Cyan
    $sourceSolutionZip = $SolutionZip
    $deployStamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $solutionDir = Split-Path -Parent $sourceSolutionZip
    $solutionBase = [System.IO.Path]::GetFileNameWithoutExtension($sourceSolutionZip)
    $solutionBase = [regex]::Replace($solutionBase, '-deploy(?:-\d{8}-\d{6})?$', '')
    $deployOutputZip = Join-Path $solutionDir ("{0}-deploy-{1}.zip" -f $solutionBase, $deployStamp)
    $deployZip = & $rewriteScript `
        -SolutionZip $sourceSolutionZip `
        -SqlServerFqdn $SqlServerFqdn `
        -SqlDatabaseName $SqlDatabaseName `
        -OutputZip $deployOutputZip `
        -DeploymentSettingsFile $SettingsFile
    if (-not $deployZip -or -not (Test-Path $deployZip)) {
        throw "Solution binding rewrite did not produce a deployment solution zip."
    }
    $SolutionZip = $deployZip
    Write-Host "Using deployment-specific solution zip: $SolutionZip" -ForegroundColor Green
    Write-Log "INFO  : Deployment-specific solution zip: $SolutionZip"

    if (-not [string]::IsNullOrWhiteSpace($AdditionalSolutionZip)) {
        if (Test-Path $AdditionalSolutionZip) {
            $sourceAdditionalZip = $AdditionalSolutionZip
            $additionalBase = [System.IO.Path]::GetFileNameWithoutExtension($sourceAdditionalZip)
            $additionalBase = [regex]::Replace($additionalBase, '-deploy(?:-\d{8}-\d{6})?$', '')
            $additionalOutputZip = Join-Path (Split-Path -Parent $sourceAdditionalZip) ("{0}-deploy-{1}.zip" -f $additionalBase, $deployStamp)
            $additionalDeployZip = & $rewriteScript `
                -SolutionZip $sourceAdditionalZip `
                -SqlServerFqdn $SqlServerFqdn `
                -SqlDatabaseName $SqlDatabaseName `
                -OutputZip $additionalOutputZip `
                -DeploymentSettingsFile $SettingsFile
            if (-not $additionalDeployZip -or -not (Test-Path $additionalDeployZip)) {
                throw "Solution binding rewrite did not produce a deployment solution zip for the additional solution."
            }
            $AdditionalSolutionZip = $additionalDeployZip
            Write-Host "Using deployment-specific additional solution zip: $AdditionalSolutionZip" -ForegroundColor Green
            Write-Log "INFO  : Deployment-specific additional solution zip: $AdditionalSolutionZip"
        } else {
            Write-Host "Additional solution zip not found; skipping its import: $AdditionalSolutionZip" -ForegroundColor Yellow
            Write-Log "WARN  : Additional solution zip not found; skipping: $AdditionalSolutionZip"
            $AdditionalSolutionZip = $null
        }
    }
} else {
    Write-Host "WARNING: Update-SolutionSqlBinding.ps1 not found; importing the solution WITHOUT repointing SQL. The app may target the wrong server." -ForegroundColor Yellow
}

$authName = "payrecon-$((Get-Date).ToString('MMddHHmmss'))"
if ($authName.Length -gt 30) { $authName = $authName.Substring(0, 30) }

$signedIn = $false
$importSettingsFile = $null

try {
    $resolvedSignInMode = Resolve-SignInMode -RequestedMode $SignInMode
    Write-Log "INFO  : Resolved sign-in mode: $resolvedSignInMode"
    $authOk = $false
    switch ($resolvedSignInMode) {
        'Browser' {
            $authOk = Invoke-PacAuthCreate -Pac $pac -AuthName $authName -EnvironmentUrl $EnvironmentUrl -Mode 'Browser'
            if (-not $authOk) {
                throw "Power Platform browser sign-in failed. Re-run and choose device code if browser sign-in does not work."
            }
        }
        'DeviceCode' {
            $authOk = Invoke-PacAuthCreate -Pac $pac -AuthName $authName -EnvironmentUrl $EnvironmentUrl -Mode 'DeviceCode'
            if (-not $authOk) {
                throw "Power Platform device-code sign-in failed."
            }
        }
        'AutoFallback' {
            $authOk = Invoke-PacAuthCreate -Pac $pac -AuthName $authName -EnvironmentUrl $EnvironmentUrl -Mode 'Browser'
            if (-not $authOk) {
                Write-Host "Browser sign-in failed. Retrying with device code..." -ForegroundColor Yellow
                $authOk = Invoke-PacAuthCreate -Pac $pac -AuthName $authName -EnvironmentUrl $EnvironmentUrl -Mode 'DeviceCode'
            }
            if (-not $authOk) {
                throw "Power Platform sign-in failed in both browser and device-code modes."
            }
        }
        default {
            throw "Unsupported SignInMode: $resolvedSignInMode"
        }
    }

    # Verify the sign-in actually produced an active, connected profile before
    # we attempt the import. This turns a silent hang/failure into a clear error.
    # For AutoFallback mode, retry via device code if browser auth did not produce
    # a usable session even when the browser command itself returned success.
    Write-Host "`n==> Verifying Power Platform sign-in..." -ForegroundColor Cyan
    $whoResult = Invoke-PacCommand -Pac $pac -Arguments @('org','who') -Description "Power Platform auth verification"
    if ($whoResult.ExitCode -ne 0 -and $resolvedSignInMode -eq 'AutoFallback') {
        Write-Host "Browser sign-in did not establish an active session. Retrying with device code..." -ForegroundColor Yellow
        Write-Log "WARN  : Browser auth command completed but session verification failed; retrying with device code."
        $null = Invoke-PacCommand -Pac $pac -Arguments @('auth','delete','--name',$authName) -Description "Removing incomplete Power Platform auth profile before device-code fallback"
        $authOk = Invoke-PacAuthCreate -Pac $pac -AuthName $authName -EnvironmentUrl $EnvironmentUrl -Mode 'DeviceCode'
        if ($authOk) {
            Write-Host "`n==> Verifying Power Platform sign-in (device code fallback)..." -ForegroundColor Cyan
            $whoResult = Invoke-PacCommand -Pac $pac -Arguments @('org','who') -Description "Power Platform auth verification (device-code fallback)"
        } else {
            $whoResult = [pscustomobject]@{ ExitCode = 1; Output = @() }
        }
    }
    if ($whoResult.ExitCode -ne 0) {
        throw "Could not confirm an active Power Platform connection to '$EnvironmentUrl'. Sign-in may not have completed. Re-run this script and choose device code."
    }
    $signedIn = $true
    Write-Host "Sign-in verified." -ForegroundColor Green

    $solutionsToImport = @($SolutionZip)
    if (-not [string]::IsNullOrWhiteSpace($AdditionalSolutionZip) -and (Test-Path $AdditionalSolutionZip)) {
        $solutionsToImport += $AdditionalSolutionZip
    }

    $solutionIndex = 0
    foreach ($currentSolutionZip in $solutionsToImport) {
        $solutionIndex++
        $isPrimarySolution = ($solutionIndex -eq 1)
        $solutionDisplayName = [System.IO.Path]::GetFileNameWithoutExtension($currentSolutionZip)
        $solutionDisplayName = [regex]::Replace($solutionDisplayName, '-deploy(?:-\d{8}-\d{6})?$', '')
        if ($solutionsToImport.Count -gt 1) {
            Write-Host "`n============================================================" -ForegroundColor Cyan
            Write-Host "  Solution $solutionIndex of $($solutionsToImport.Count): $solutionDisplayName" -ForegroundColor Cyan
            Write-Host "============================================================" -ForegroundColor Cyan
        }

    # -----------------------------------------------------------------------
    # Resolve and pre-map SQL/Blob/ADF/Copilot/MCP connections so the canvas app,
    # flow, and agents are wired at import time instead of being left unbound.
    # Blob mapping can auto-select from existing Blob connections (with a
    # storage-account name hint from EnvironmentVariables) when possible.
    # The settings file passed to pac is generated fresh in the schema pac
    # expects (EnvironmentVariables + ConnectionReferences); our custom
    # SqlBinding metadata is not passed to pac.
    # -----------------------------------------------------------------------
    $blobConnectionRefLogicalNames = @($script:BlobConnectionRefLogicalNames)
    $azureDataFactoryConnectionRefLogicalNames = @($script:AzureDataFactoryConnectionRefLogicalNames)
    $microsoftCopilotStudioConnectionRefLogicalNames = @($script:MicrosoftCopilotStudioConnectionRefLogicalNames)
    $a365McpServersConnectionRefLogicalNames = @($script:A365McpServersConnectionRefLogicalNames)
    $dataverseConnectionRefLogicalNames = @($script:DataverseConnectionRefLogicalNames)
    # SQL reference logical names are discovered from the solution package (like
    # blob/ADF/Copilot/MCP) so every SQL connection reference in the solution -
    # Power App plus each Copilot Studio agent - is mapped. The hard-coded
    # $script:SqlConnectionRefLogicalNames list is only a fallback when discovery
    # finds nothing.
    $sqlConnectionRefLogicalNames = @()
    if (-not $SkipConnectionMapping) {
        $sqlConnectionRefLogicalNames = @(Get-SolutionConnectionRefLogicalNames `
            -SolutionZip $currentSolutionZip `
            -ConnectorId $script:SqlConnectorId `
            -FallbackLogicalNames $script:SqlConnectionRefLogicalNames)
        if ($sqlConnectionRefLogicalNames.Count -gt 0) {
            Write-Log "INFO  : SQL connection reference logical names in solution: $($sqlConnectionRefLogicalNames -join ', ')"
        }
        $blobConnectionRefLogicalNames = @(Get-SolutionConnectionRefLogicalNames `
            -SolutionZip $currentSolutionZip `
            -ConnectorId $script:BlobConnectorId `
            -FallbackLogicalNames $script:BlobConnectionRefLogicalNames)
        if ($blobConnectionRefLogicalNames.Count -gt 0) {
            Write-Log "INFO  : Blob connection reference logical names in solution: $($blobConnectionRefLogicalNames -join ', ')"
        }
        $azureDataFactoryConnectionRefLogicalNames = @(Get-SolutionConnectionRefLogicalNames `
            -SolutionZip $currentSolutionZip `
            -ConnectorId $script:AzureDataFactoryConnectorId `
            -FallbackLogicalNames $script:AzureDataFactoryConnectionRefLogicalNames)
        if ($azureDataFactoryConnectionRefLogicalNames.Count -gt 0) {
            Write-Log "INFO  : Azure Data Factory connection reference logical names in solution: $($azureDataFactoryConnectionRefLogicalNames -join ', ')"
        }
        $microsoftCopilotStudioConnectionRefLogicalNames = @(Get-SolutionConnectionRefLogicalNames `
            -SolutionZip $currentSolutionZip `
            -ConnectorId $script:MicrosoftCopilotStudioConnectorId `
            -FallbackLogicalNames $script:MicrosoftCopilotStudioConnectionRefLogicalNames)
        if ($microsoftCopilotStudioConnectionRefLogicalNames.Count -gt 0) {
            Write-Log "INFO  : Microsoft Copilot Studio connection reference logical names in solution: $($microsoftCopilotStudioConnectionRefLogicalNames -join ', ')"
        }
        $a365McpServersConnectionRefLogicalNames = @(Get-SolutionConnectionRefLogicalNames `
            -SolutionZip $currentSolutionZip `
            -ConnectorId $script:A365McpServersConnectorId `
            -FallbackLogicalNames $script:A365McpServersConnectionRefLogicalNames)
        if ($a365McpServersConnectionRefLogicalNames.Count -gt 0) {
            Write-Log "INFO  : A365 MCP Servers connection reference logical names in solution: $($a365McpServersConnectionRefLogicalNames -join ', ')"
        }
        $dataverseConnectionRefLogicalNames = @(Get-SolutionConnectionRefLogicalNames `
            -SolutionZip $currentSolutionZip `
            -ConnectorId $script:DataverseConnectorId `
            -FallbackLogicalNames $script:DataverseConnectionRefLogicalNames)
        if ($dataverseConnectionRefLogicalNames.Count -gt 0) {
            Write-Log "INFO  : Dataverse connection reference logical names in solution: $($dataverseConnectionRefLogicalNames -join ', ')"
        }

        $settingsJson = $null
        $storageAccountName = $null
        if ([string]::IsNullOrWhiteSpace($SqlConnectionId) -or
            [string]::IsNullOrWhiteSpace($BlobConnectionId) -or
            [string]::IsNullOrWhiteSpace($AzureDataFactoryConnectionId) -or
            [string]::IsNullOrWhiteSpace($MicrosoftCopilotStudioConnectionId) -or
            [string]::IsNullOrWhiteSpace($A365McpServersConnectionId) -or
            [string]::IsNullOrWhiteSpace($DataverseConnectionId)) {
            try {
                $settingsJson = Get-Content -Path $SettingsFile -Raw | ConvertFrom-Json
                if ($settingsJson.PSObject.Properties.Name -contains 'Connections') {
                    if ([string]::IsNullOrWhiteSpace($SqlConnectionId)  -and $settingsJson.Connections.PSObject.Properties.Name -contains 'SqlConnectionId') {
                        $SqlConnectionId = [string]$settingsJson.Connections.SqlConnectionId
                    }
                    if ([string]::IsNullOrWhiteSpace($BlobConnectionId) -and $settingsJson.Connections.PSObject.Properties.Name -contains 'BlobConnectionId') {
                        $BlobConnectionId = [string]$settingsJson.Connections.BlobConnectionId
                    }
                    if ([string]::IsNullOrWhiteSpace($AzureDataFactoryConnectionId) -and $settingsJson.Connections.PSObject.Properties.Name -contains 'AzureDataFactoryConnectionId') {
                        $AzureDataFactoryConnectionId = [string]$settingsJson.Connections.AzureDataFactoryConnectionId
                    }
                    if ([string]::IsNullOrWhiteSpace($MicrosoftCopilotStudioConnectionId) -and $settingsJson.Connections.PSObject.Properties.Name -contains 'MicrosoftCopilotStudioConnectionId') {
                        $MicrosoftCopilotStudioConnectionId = [string]$settingsJson.Connections.MicrosoftCopilotStudioConnectionId
                    }
                    if ([string]::IsNullOrWhiteSpace($A365McpServersConnectionId) -and $settingsJson.Connections.PSObject.Properties.Name -contains 'A365McpServersConnectionId') {
                        $A365McpServersConnectionId = [string]$settingsJson.Connections.A365McpServersConnectionId
                    }
                    if ([string]::IsNullOrWhiteSpace($DataverseConnectionId) -and $settingsJson.Connections.PSObject.Properties.Name -contains 'DataverseConnectionId') {
                        $DataverseConnectionId = [string]$settingsJson.Connections.DataverseConnectionId
                    }
                }
                $storageAccountName = Get-EnvironmentVariableValue -SettingsJson $settingsJson -SchemaName 'cap_PaymentReconStorageAccountName'
            } catch {
                Write-Host "Could not read Connections from settings file: $($_.Exception.Message)" -ForegroundColor Yellow
            }
        }
        if (-not [string]::IsNullOrWhiteSpace($SqlConnectionId)) {
            if (Test-GuidValue -Value $SqlConnectionId) {
                $SqlConnectionId = $SqlConnectionId.Trim()
            } else {
                Write-Host "Ignoring invalid SqlConnectionId (must be GUID): $SqlConnectionId" -ForegroundColor Yellow
                $SqlConnectionId = $null
            }
        }
        if (-not [string]::IsNullOrWhiteSpace($BlobConnectionId)) {
            if (Test-GuidValue -Value $BlobConnectionId) {
                $BlobConnectionId = $BlobConnectionId.Trim()
            } else {
                Write-Host "Ignoring invalid BlobConnectionId (must be GUID): $BlobConnectionId" -ForegroundColor Yellow
                $BlobConnectionId = $null
            }
        }
        if (-not [string]::IsNullOrWhiteSpace($AzureDataFactoryConnectionId)) {
            if (Test-GuidValue -Value $AzureDataFactoryConnectionId) {
                $AzureDataFactoryConnectionId = $AzureDataFactoryConnectionId.Trim()
            } else {
                Write-Host "Ignoring invalid AzureDataFactoryConnectionId (must be GUID): $AzureDataFactoryConnectionId" -ForegroundColor Yellow
                $AzureDataFactoryConnectionId = $null
            }
        }
        if (-not [string]::IsNullOrWhiteSpace($MicrosoftCopilotStudioConnectionId)) {
            if (Test-GuidValue -Value $MicrosoftCopilotStudioConnectionId) {
                $MicrosoftCopilotStudioConnectionId = $MicrosoftCopilotStudioConnectionId.Trim()
            } else {
                Write-Host "Ignoring invalid MicrosoftCopilotStudioConnectionId (must be GUID): $MicrosoftCopilotStudioConnectionId" -ForegroundColor Yellow
                $MicrosoftCopilotStudioConnectionId = $null
            }
        }
        if (-not [string]::IsNullOrWhiteSpace($A365McpServersConnectionId)) {
            if (Test-GuidValue -Value $A365McpServersConnectionId) {
                $A365McpServersConnectionId = $A365McpServersConnectionId.Trim()
            } else {
                Write-Host "Ignoring invalid A365McpServersConnectionId (must be GUID): $A365McpServersConnectionId" -ForegroundColor Yellow
                $A365McpServersConnectionId = $null
            }
        }
        if (-not [string]::IsNullOrWhiteSpace($DataverseConnectionId)) {
            if (Test-GuidValue -Value $DataverseConnectionId) {
                $DataverseConnectionId = $DataverseConnectionId.Trim()
            } else {
                Write-Host "Ignoring invalid DataverseConnectionId (must be GUID): $DataverseConnectionId" -ForegroundColor Yellow
                $DataverseConnectionId = $null
            }
        }
        if ([string]::IsNullOrWhiteSpace($SqlConnectionId)) {
            $SqlConnectionId = Resolve-SqlConnectionIdAuto `
                -Pac $pac `
                -EnvironmentUrl $EnvironmentUrl `
                -SqlServerFqdn $SqlServerFqdn `
                -SqlDatabaseName $SqlDatabaseName
        }
        if ([string]::IsNullOrWhiteSpace($SqlConnectionId)) {
            Write-Host "Proceeding without pre-mapping the SQL connection; wire it manually after import." -ForegroundColor Yellow
            Write-Log "INFO  : SQL connection unresolved in non-interactive mode; continuing without SQL pre-mapping."
        } else {
            Write-Host "SQL connection will be mapped to the app and both agents: $SqlConnectionId" -ForegroundColor Green
        }

        if ([string]::IsNullOrWhiteSpace($BlobConnectionId)) {
            $BlobConnectionId = Resolve-BlobConnectionId -Pac $pac -EnvironmentUrl $EnvironmentUrl -StorageAccountName $storageAccountName -AllowPrompt:$false
        }
        if ([string]::IsNullOrWhiteSpace($BlobConnectionId)) {
            Write-Host "Proceeding without pre-mapping the Blob connection; wire app file upload manually after import." -ForegroundColor Yellow
        } else {
            Write-Host "Blob connection will be mapped across Blob references in this solution: $BlobConnectionId" -ForegroundColor Green
        }
        if ([string]::IsNullOrWhiteSpace($AzureDataFactoryConnectionId) -and $azureDataFactoryConnectionRefLogicalNames.Count -gt 0) {
            Write-Host "Proceeding without pre-mapping Azure Data Factory connection references; flow actions may fail until wired." -ForegroundColor Yellow
        } elseif (-not [string]::IsNullOrWhiteSpace($AzureDataFactoryConnectionId)) {
            Write-Host "Azure Data Factory connection will be mapped across flow references: $AzureDataFactoryConnectionId" -ForegroundColor Green
        }
        if ([string]::IsNullOrWhiteSpace($MicrosoftCopilotStudioConnectionId) -and $microsoftCopilotStudioConnectionRefLogicalNames.Count -gt 0) {
            Write-Host "Proceeding without pre-mapping Microsoft Copilot Studio connection references; flow actions may fail until wired." -ForegroundColor Yellow
        } elseif (-not [string]::IsNullOrWhiteSpace($MicrosoftCopilotStudioConnectionId)) {
            Write-Host "Microsoft Copilot Studio connection will be mapped across flow references: $MicrosoftCopilotStudioConnectionId" -ForegroundColor Green
        }
        if ([string]::IsNullOrWhiteSpace($A365McpServersConnectionId) -and $a365McpServersConnectionRefLogicalNames.Count -gt 0) {
            Write-Host "Proceeding without pre-mapping A365 MCP Servers connection references; agent actions may fail until wired." -ForegroundColor Yellow
        } elseif (-not [string]::IsNullOrWhiteSpace($A365McpServersConnectionId)) {
            Write-Host "A365 MCP Servers connection will be mapped across agent references: $A365McpServersConnectionId" -ForegroundColor Green
        }
        if ([string]::IsNullOrWhiteSpace($DataverseConnectionId) -and $dataverseConnectionRefLogicalNames.Count -gt 0) {
            $DataverseConnectionId = Resolve-DataverseConnectionIdAuto -Pac $pac -EnvironmentUrl $EnvironmentUrl
        }
        if ([string]::IsNullOrWhiteSpace($DataverseConnectionId) -and $dataverseConnectionRefLogicalNames.Count -gt 0) {
            Write-Host "Proceeding without pre-mapping the Dataverse connection references; the code app Reconcile button may fail until wired." -ForegroundColor Yellow
        } elseif (-not [string]::IsNullOrWhiteSpace($DataverseConnectionId)) {
            Write-Host "Dataverse connection will be mapped across code app references: $DataverseConnectionId" -ForegroundColor Green
        }
    } else {
        Write-Host "Connection mapping skipped (-SkipConnectionMapping)." -ForegroundColor Yellow
        $SqlConnectionId = $null
        $BlobConnectionId = $null
        $AzureDataFactoryConnectionId = $null
        $MicrosoftCopilotStudioConnectionId = $null
        $A365McpServersConnectionId = $null
        $DataverseConnectionId = $null
    }

    $initialUnresolvedConnections = @(Get-UnresolvedConnectionTargets `
        -SqlConnectionId $SqlConnectionId `
        -BlobConnectionId $BlobConnectionId `
        -AzureDataFactoryConnectionId $AzureDataFactoryConnectionId `
        -MicrosoftCopilotStudioConnectionId $MicrosoftCopilotStudioConnectionId `
        -A365McpServersConnectionId $A365McpServersConnectionId `
        -DataverseConnectionId $DataverseConnectionId `
        -AzureDataFactoryConnectionRefLogicalNames $azureDataFactoryConnectionRefLogicalNames `
        -MicrosoftCopilotStudioConnectionRefLogicalNames $microsoftCopilotStudioConnectionRefLogicalNames `
        -A365McpServersConnectionRefLogicalNames $a365McpServersConnectionRefLogicalNames `
        -DataverseConnectionRefLogicalNames $dataverseConnectionRefLogicalNames)

    $importSettingsFile = New-ImportSettingsFile `
        -MetadataSettingsFile $SettingsFile `
        -SqlConnectionId $SqlConnectionId `
        -BlobConnectionId $BlobConnectionId `
        -AzureDataFactoryConnectionId $AzureDataFactoryConnectionId `
        -MicrosoftCopilotStudioConnectionId $MicrosoftCopilotStudioConnectionId `
        -A365McpServersConnectionId $A365McpServersConnectionId `
        -DataverseConnectionId $DataverseConnectionId `
        -SqlConnectionRefLogicalNames $sqlConnectionRefLogicalNames `
        -BlobConnectionRefLogicalNames $blobConnectionRefLogicalNames `
        -AzureDataFactoryConnectionRefLogicalNames $azureDataFactoryConnectionRefLogicalNames `
        -MicrosoftCopilotStudioConnectionRefLogicalNames $microsoftCopilotStudioConnectionRefLogicalNames `
        -A365McpServersConnectionRefLogicalNames $a365McpServersConnectionRefLogicalNames `
        -DataverseConnectionRefLogicalNames $dataverseConnectionRefLogicalNames

    Write-Host "`n==> Importing solution (pass 1)" -ForegroundColor Cyan
    Write-Host "Solution: $currentSolutionZip" -ForegroundColor Gray
    Write-Host "Settings: $importSettingsFile" -ForegroundColor Gray
    Write-Host "This can take several minutes; progress is shown below." -ForegroundColor Gray

    $importArgs = @(
        'solution','import',
        '--environment',$EnvironmentUrl,
        '--path',$currentSolutionZip,
        '--settings-file',$importSettingsFile,
        '--publish-changes',
        '--force-overwrite'
    )
    $importResult = Invoke-PacCommand -Pac $pac -Arguments $importArgs -Description "Solution import (pass 1)"
    if ($importResult.ExitCode -ne 0 -or $importResult.HasErrorMarker) {
        throw "Power Platform solution import failed (exit code $($importResult.ExitCode))."
    }

    if ($BootstrapConnectionSetup -and $isPrimarySolution -and -not $SkipConnectionMapping -and $initialUnresolvedConnections.Count -gt 0) {
        Write-Host "`n==> Quick connector setup (one-time per environment)" -ForegroundColor Cyan
        Write-Host "Good news: pass 1 is complete. Now do these quick steps, then this script will redeploy pass 2 automatically." -ForegroundColor Gray
        Write-Host "Missing connection IDs detected:" -ForegroundColor Yellow
        foreach ($m in $initialUnresolvedConnections) {
            Write-Host "  - $m" -ForegroundColor Yellow
        }
        Write-Host ""
        Write-Host "1. Open: $EnvironmentUrl" -ForegroundColor Gray
        Write-Host "2. Go to Solutions > $solutionDisplayName > Connection references." -ForegroundColor Gray
        Write-Host "3. Create or update the connection for each reference listed above - in particular these data connections:" -ForegroundColor Gray
        Write-Host "     - SQL Server         -> SqlConnectionId" -ForegroundColor Gray
        Write-Host "     - Azure Data Factory -> AzureDataFactoryConnectionId" -ForegroundColor Gray
        Write-Host "     - Azure Blob Storage -> BlobConnectionId" -ForegroundColor Gray
        Write-Host "4. (Recommended) Paste those GUIDs into:" -ForegroundColor Gray
        Write-Host "   $SettingsFile" -ForegroundColor Gray
        Write-Host ""
        $choice = Read-Host "Press Enter to run pass 2 now, or type SKIP to finish"

        if ($choice.Trim().ToUpperInvariant() -ne 'SKIP') {
            try {
                $retrySettingsJson = Get-Content -Path $SettingsFile -Raw | ConvertFrom-Json
                if ($retrySettingsJson.PSObject.Properties.Name -contains 'Connections') {
                    if ($retrySettingsJson.Connections.PSObject.Properties.Name -contains 'SqlConnectionId') {
                        $SqlConnectionId = [string]$retrySettingsJson.Connections.SqlConnectionId
                    }
                    if ($retrySettingsJson.Connections.PSObject.Properties.Name -contains 'BlobConnectionId') {
                        $BlobConnectionId = [string]$retrySettingsJson.Connections.BlobConnectionId
                    }
                    if ($retrySettingsJson.Connections.PSObject.Properties.Name -contains 'AzureDataFactoryConnectionId') {
                        $AzureDataFactoryConnectionId = [string]$retrySettingsJson.Connections.AzureDataFactoryConnectionId
                    }
                    if ($retrySettingsJson.Connections.PSObject.Properties.Name -contains 'MicrosoftCopilotStudioConnectionId') {
                        $MicrosoftCopilotStudioConnectionId = [string]$retrySettingsJson.Connections.MicrosoftCopilotStudioConnectionId
                    }
                    if ($retrySettingsJson.Connections.PSObject.Properties.Name -contains 'A365McpServersConnectionId') {
                        $A365McpServersConnectionId = [string]$retrySettingsJson.Connections.A365McpServersConnectionId
                    }
                    if ($retrySettingsJson.Connections.PSObject.Properties.Name -contains 'DataverseConnectionId') {
                        $DataverseConnectionId = [string]$retrySettingsJson.Connections.DataverseConnectionId
                    }
                }
            } catch {
                Write-Host "Could not reload updated Connections from settings file: $($_.Exception.Message)" -ForegroundColor Yellow
                Write-Log "WARN  : Could not reload settings before pass 2: $($_.Exception.Message)"
            }

            $SqlConnectionId = Normalize-ConnectionId -Value $SqlConnectionId -Name "SqlConnectionId"
            $BlobConnectionId = Normalize-ConnectionId -Value $BlobConnectionId -Name "BlobConnectionId"
            $AzureDataFactoryConnectionId = Normalize-ConnectionId -Value $AzureDataFactoryConnectionId -Name "AzureDataFactoryConnectionId"
            $MicrosoftCopilotStudioConnectionId = Normalize-ConnectionId -Value $MicrosoftCopilotStudioConnectionId -Name "MicrosoftCopilotStudioConnectionId"
            $A365McpServersConnectionId = Normalize-ConnectionId -Value $A365McpServersConnectionId -Name "A365McpServersConnectionId"
            $DataverseConnectionId = Normalize-ConnectionId -Value $DataverseConnectionId -Name "DataverseConnectionId"
            if ([string]::IsNullOrWhiteSpace($DataverseConnectionId) -and $dataverseConnectionRefLogicalNames.Count -gt 0) {
                $DataverseConnectionId = Resolve-DataverseConnectionIdAuto -Pac $pac -EnvironmentUrl $EnvironmentUrl
            }

            $remainingUnresolved = @(Get-UnresolvedConnectionTargets `
                -SqlConnectionId $SqlConnectionId `
                -BlobConnectionId $BlobConnectionId `
                -AzureDataFactoryConnectionId $AzureDataFactoryConnectionId `
                -MicrosoftCopilotStudioConnectionId $MicrosoftCopilotStudioConnectionId `
                -A365McpServersConnectionId $A365McpServersConnectionId `
                -DataverseConnectionId $DataverseConnectionId `
                -AzureDataFactoryConnectionRefLogicalNames $azureDataFactoryConnectionRefLogicalNames `
                -MicrosoftCopilotStudioConnectionRefLogicalNames $microsoftCopilotStudioConnectionRefLogicalNames `
                -A365McpServersConnectionRefLogicalNames $a365McpServersConnectionRefLogicalNames `
                -DataverseConnectionRefLogicalNames $dataverseConnectionRefLogicalNames)
            if ($remainingUnresolved.Count -gt 0) {
                Write-Host "Pass 2 will continue, but some connection IDs are still missing:" -ForegroundColor Yellow
                foreach ($m in $remainingUnresolved) {
                    Write-Host "  - $m" -ForegroundColor Yellow
                }
            }

            if ($importSettingsFile -and (Test-Path $importSettingsFile)) {
                Remove-Item -Path $importSettingsFile -Force -ErrorAction SilentlyContinue
            }
            $importSettingsFile = New-ImportSettingsFile `
                -MetadataSettingsFile $SettingsFile `
                -SqlConnectionId $SqlConnectionId `
                -BlobConnectionId $BlobConnectionId `
                -AzureDataFactoryConnectionId $AzureDataFactoryConnectionId `
                -MicrosoftCopilotStudioConnectionId $MicrosoftCopilotStudioConnectionId `
                -A365McpServersConnectionId $A365McpServersConnectionId `
                -DataverseConnectionId $DataverseConnectionId `
                -SqlConnectionRefLogicalNames $sqlConnectionRefLogicalNames `
                -BlobConnectionRefLogicalNames $blobConnectionRefLogicalNames `
                -AzureDataFactoryConnectionRefLogicalNames $azureDataFactoryConnectionRefLogicalNames `
                -MicrosoftCopilotStudioConnectionRefLogicalNames $microsoftCopilotStudioConnectionRefLogicalNames `
                -A365McpServersConnectionRefLogicalNames $a365McpServersConnectionRefLogicalNames `
                -DataverseConnectionRefLogicalNames $dataverseConnectionRefLogicalNames

            Write-Host "`n==> Re-importing solution (pass 2)" -ForegroundColor Cyan
            Write-Host "Solution: $currentSolutionZip" -ForegroundColor Gray
            Write-Host "Settings: $importSettingsFile" -ForegroundColor Gray
            $importArgs = @(
                'solution','import',
                '--environment',$EnvironmentUrl,
                '--path',$currentSolutionZip,
                '--settings-file',$importSettingsFile,
                '--publish-changes',
                '--force-overwrite'
            )
            $importResult = Invoke-PacCommand -Pac $pac -Arguments $importArgs -Description "Solution import (pass 2)"
            if ($importResult.ExitCode -ne 0 -or $importResult.HasErrorMarker) {
                throw "Power Platform solution import pass 2 failed (exit code $($importResult.ExitCode))."
            }
        } else {
            Write-Host "Skipping pass 2." -ForegroundColor Yellow
        }
    }

    Write-Host "`n============================================================" -ForegroundColor Magenta
    Write-Host "  Power Platform solution imported successfully" -ForegroundColor Magenta
    Write-Host "============================================================" -ForegroundColor Magenta
    Write-Host "Environment: $EnvironmentUrl" -ForegroundColor Gray

        if ($importSettingsFile -and (Test-Path $importSettingsFile)) {
            Remove-Item -Path $importSettingsFile -Force -ErrorAction SilentlyContinue
            $importSettingsFile = $null
        }
    }
}
finally {
    if ($importSettingsFile -and (Test-Path $importSettingsFile)) {
        Remove-Item -Path $importSettingsFile -Force -ErrorAction SilentlyContinue
    }
    if ($signedIn -and -not $KeepSignIn) {
        Write-Host "`n==> Removing temporary Power Platform sign-in..." -ForegroundColor Cyan
        $deleteResult = Invoke-PacCommand -Pac $pac -Arguments @('auth','delete','--name',$authName) -Description "Power Platform auth delete"
        if ($deleteResult.ExitCode -eq 0) {
            Write-Host "Removed Power Platform auth profile '$authName'." -ForegroundColor Gray
        }
    }
    if ($script:LogPath) {
        Write-Host "Power Platform log file: $script:LogPath" -ForegroundColor Gray
    }
}
