<#
.SYNOPSIS
    Discovery-driven deploy for Payment Recon that supports BOTH redeployment
    (upgrade the resources already in a resource group) and fresh deployment
    (create new resources). You give it a resource group; it inspects what is
    already there and chooses the right path.

.DESCRIPTION
    Given -ResourceGroupName, the script uses the Azure CLI (read-only) to look
    for the Payment Recon resources (Storage, Data Factory, optional SQL, Key
    Vault). Then:

      * If Storage + Data Factory already exist  -> REDEPLOY (upgrade in place):
          - ARM is re-applied incrementally (safe, idempotent)
          - the base SQL schema is NOT re-run (your data is preserved)
          - the Power Platform solution is re-imported as an UPGRADE
      * If they do not exist                      -> FRESH (create everything):
          - resource group / Storage / Data Factory / (optionally) SQL created
          - base schema applied; the Power Platform solution imported

    The customer prefix (which drives every resource name) is taken from the RG
    name when it follows the "<prefix>-paymentrecon-rg" convention, otherwise
    pass -CustomerPrefix.

    DEFAULT IS A READ-ONLY PLAN. Nothing is changed unless you pass -Execute.

    SQL admin credentials are never taken here; the underlying scripts prompt for
    them at runtime and never write them to disk.

.PARAMETER ResourceGroupName
    The resource group to deploy into / discover. Required.

.PARAMETER SubscriptionId
    Azure subscription id. Defaults to the current `az` context.

.PARAMETER EnvironmentUrl
    Power Platform environment URL (e.g. https://org.crm.dynamics.com). Used for
    the solution import step.

.PARAMETER Variant
    Direct (PoC) is the default in this version. The KeyVault (production) variant is
    hidden for now (planned for a later version) — pass -Variant KeyVault to opt in.

.PARAMETER Mode
    Auto (default), Redeploy or Fresh. Auto decides from what is in the RG.

.PARAMETER CustomerPrefix
    5-10 char lowercase prefix. Only needed when it cannot be derived from the RG
    name (or to override it).

.PARAMETER Location
    Azure region. Required only for a FRESH deployment that creates the RG.

.PARAMETER Execute
    Actually run the deployment. Without it, the script only prints the plan.

.PARAMETER Force
    Skip the confirmation prompt in -Execute mode.

.EXAMPLE
    .\Deploy-PaymentRecon-Smart.ps1 -ResourceGroupName contoso-paymentrecon-rg -EnvironmentUrl https://contoso.crm.dynamics.com
    # Read-only plan: discovers the RG and shows whether it would redeploy or create fresh.

.EXAMPLE
    .\Deploy-PaymentRecon-Smart.ps1 -ResourceGroupName contoso-paymentrecon-rg -EnvironmentUrl https://contoso.crm.dynamics.com -Execute
#>
[CmdletBinding()]
param(
    [string] $ResourceGroupName,
    [string] $SubscriptionId,
    [string] $TenantId,
    [string] $ServicePrincipalClientId,
    [System.Security.SecureString] $ServicePrincipalSecret,
    [string] $SqlAdminUsername,
    [System.Security.SecureString] $SqlAdminPassword,
    [string] $EnvironmentUrl,
    [ValidateSet('KeyVault','Direct')] [string] $Variant,
    [ValidateSet('Auto','Redeploy','Fresh')] [string] $Mode = 'Auto',
    [string] $CustomerPrefix,
    [string] $Location,
    [switch] $Execute,
    [switch] $Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$scriptDir = $PSScriptRoot
if (-not $scriptDir) { $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path }

function Write-Head($m) { Write-Host "`n=== $m ===" -ForegroundColor Cyan }
function Write-Info($m) { Write-Host "    $m" }
function Write-Warn2($m) { Write-Host "    $m" -ForegroundColor Yellow }

# --- Interactive front-end: ask FRESH vs UPDATE first (when no RG was passed) ---
if (-not $ResourceGroupName) {
    Write-Host "`n============================================================" -ForegroundColor Magenta
    Write-Host "  Payment Recon - Smart Installer" -ForegroundColor Magenta
    Write-Host "============================================================" -ForegroundColor Magenta
    Write-Host "What would you like to do?" -ForegroundColor Cyan
    Write-Host "  [1] Update / redeploy an EXISTING deployment"
    Write-Host "  [2] FRESH deployment (create new resources)"
    do { $sel = (Read-Host "Enter choice [1/2]").Trim() } until ($sel -in @('1','2'))
    if ($sel -eq '1') {
        $Mode = 'Redeploy'
        do { $ResourceGroupName = (Read-Host "Resource group of the existing deployment").Trim() } until ($ResourceGroupName)
    } else {
        $Mode = 'Fresh'
        do { $CustomerPrefix = (Read-Host "Customer prefix (5-10 lowercase letters/numbers)").Trim().ToLower() } until ($CustomerPrefix -match '^[a-z0-9]{5,10}$')
        $ResourceGroupName = "$CustomerPrefix-paymentrecon-rg"
        if (-not $Location) { do { $Location = (Read-Host "Azure region (e.g. eastus)").Trim() } until ($Location) }
    }
    if (-not $EnvironmentUrl) { $EnvironmentUrl = (Read-Host "Power Platform environment URL (blank to skip)").Trim() }
    if (-not $Execute) { $Execute = $true }   # interactive = intend to deploy (a plan is still shown + confirmed below)
}
if (-not $ResourceGroupName) { throw "ResourceGroupName is required (pass -ResourceGroupName or run the installer interactively)." }

# --- 0. Azure context (same module-ensure + sign-in technique as the deploy scripts) ---
Write-Head "Connecting to Azure"
$requiredModules = [ordered]@{ 'Az.Accounts' = '2.10.0'; 'Az.Resources' = '6.0.0' }
$toInstall = @()
foreach ($modName in $requiredModules.Keys) {
    $minVer = [version]$requiredModules[$modName]
    $installed = Get-Module -ListAvailable -Name $modName | Sort-Object Version -Descending | Select-Object -First 1
    if (-not $installed -or $installed.Version -lt $minVer) { $toInstall += $modName }
}
if ($toInstall.Count -gt 0) {
    Write-Info ("Installing/updating modules for CurrentUser: {0}" -f ($toInstall -join ', '))
    foreach ($modName in $toInstall) {
        Install-Module -Name $modName -MinimumVersion $requiredModules[$modName] -Scope CurrentUser -Force -AllowClobber -Repository PSGallery
    }
}
foreach ($modName in $requiredModules.Keys) {
    Get-Module -Name $modName | Remove-Module -Force -ErrorAction SilentlyContinue
    $latest = Get-Module -ListAvailable -Name $modName |
              Where-Object { $_.Version -ge [version]$requiredModules[$modName] } |
              Sort-Object Version -Descending | Select-Object -First 1
    if (-not $latest) { throw "Module $modName is required but not available after install." }
    Import-Module -Name $modName -RequiredVersion $latest.Version -ErrorAction Stop | Out-Null
}

$spLoginRequested = -not [string]::IsNullOrWhiteSpace($TenantId) -or
                    -not [string]::IsNullOrWhiteSpace($ServicePrincipalClientId) -or
                    $null -ne $ServicePrincipalSecret
try {
    if ($spLoginRequested) {
        if ([string]::IsNullOrWhiteSpace($TenantId) -or [string]::IsNullOrWhiteSpace($ServicePrincipalClientId)) {
            throw "Service principal login requires both -TenantId and -ServicePrincipalClientId."
        }
        if (-not $ServicePrincipalSecret) { $ServicePrincipalSecret = Read-Host -Prompt "Enter service principal secret" -AsSecureString }
        $spCred = [PSCredential]::new($ServicePrincipalClientId, $ServicePrincipalSecret)
        Connect-AzAccount -ServicePrincipal -Tenant $TenantId -Credential $spCred | Out-Null
    } elseif (-not (Get-AzContext -ErrorAction SilentlyContinue)) {
        Write-Info "Launching interactive Azure sign-in..."
        Connect-AzAccount | Out-Null
    }
} catch { throw "Azure sign-in failed: $($_.Exception.Message)" }

if ($SubscriptionId) { Set-AzContext -SubscriptionId $SubscriptionId | Out-Null }
$ctx = Get-AzContext
if (-not $ctx) { throw "No Azure context after sign-in. Please run Connect-AzAccount manually." }
$SubscriptionId = $ctx.Subscription.Id
Write-Info "Account      : $($ctx.Account.Id)"
Write-Info "Subscription : $($ctx.Subscription.Name) ($SubscriptionId)"
Write-Info "Tenant       : $($ctx.Tenant.Id)"

# --- 1. Discover the resource group ----------------------------------------
Write-Head "Discovering resource group '$ResourceGroupName'"
$rg = Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue
$rgExists = [bool]$rg

$storage = @(); $adf = @(); $kv = @(); $sqlServers = @(); $sqlDbs = @()
if ($rgExists) {
    $res = @(Get-AzResource -ResourceGroupName $ResourceGroupName)
    $storage    = @($res | Where-Object { $_.ResourceType -eq 'Microsoft.Storage/storageAccounts' })
    $adf        = @($res | Where-Object { $_.ResourceType -eq 'Microsoft.DataFactory/factories' })
    $kv         = @($res | Where-Object { $_.ResourceType -eq 'Microsoft.KeyVault/vaults' })
    $sqlServers = @($res | Where-Object { $_.ResourceType -eq 'Microsoft.Sql/servers' })
    $sqlDbs     = @($res | Where-Object { $_.ResourceType -eq 'Microsoft.Sql/servers/databases' })
    Write-Info ("Resource group exists. Found: {0} storage, {1} data factory, {2} SQL server, {3} key vault." -f `
        $storage.Count, $adf.Count, $sqlServers.Count, $kv.Count)
} else {
    Write-Warn2 "Resource group does not exist in subscription '$($ctx.Subscription.Name)'."
}

# SQL detail (server FQDN + first non-system database)
$sqlServerFqdn = $null; $sqlDatabaseName = $null
if ($sqlServers.Count -gt 0) {
    $srv = $sqlServers[0].Name
    $sqlServerFqdn = "$srv.database.windows.net"
    $userDb = @($sqlDbs | ForEach-Object { ($_.Name -split '/')[-1] } | Where-Object { $_ -and $_ -ne 'master' })
    if ($userDb.Count -gt 0) { $sqlDatabaseName = $userDb[0] }
}

# --- 2. Decide the mode -----------------------------------------------------
$hasCore = ($storage.Count -gt 0 -and $adf.Count -gt 0)
if ($Mode -eq 'Auto') { $Mode = if ($hasCore) { 'Redeploy' } else { 'Fresh' } }
Write-Head "Mode: $Mode"
# Update (Redeploy) reuses what exists and creates what is missing, so it does NOT require
# all resources to be present - it only needs the resource group itself to exist.
if ($Mode -eq 'Redeploy' -and -not $rgExists) {
    throw "Resource group '$ResourceGroupName' was not found. Run a first-time install (Create) to provision a new deployment."
}

# --- 3. Resolve prefix / variant -------------------------------------------
if (-not $CustomerPrefix) {
    if ($ResourceGroupName -match '^(?<p>[a-z0-9]{5,10})-paymentrecon-rg$') { $CustomerPrefix = $Matches['p'] }
}
if (-not $CustomerPrefix) {
    throw "Could not derive the customer prefix from the RG name. Pass -CustomerPrefix (5-10 lowercase chars)."
}
# Key Vault variant hidden for now (planned for a later version): default to Direct.
# Pass -Variant KeyVault explicitly to opt in.
if (-not $Variant) { $Variant = 'Direct' }
Write-Info "Customer prefix : $CustomerPrefix"
Write-Info "Variant         : $Variant"
Write-Info ("Storage account : {0}" -f $(if ($storage.Count -gt 0) { "$($storage[0].name)  (reuse)" } else { 'missing -> will CREATE' }))
Write-Info ("Data factory    : {0}" -f $(if ($adf.Count    -gt 0) { "$($adf[0].name)  (reuse)" } else { 'missing -> will CREATE' }))
Write-Info ("Azure SQL       : {0}" -f $(if ($sqlServerFqdn)      { "$sqlServerFqdn / $sqlDatabaseName  (reuse)" } else { 'missing -> will CREATE + apply base schema' }))

# --- 4. Build the plan ------------------------------------------------------
$variantScript = Join-Path $scriptDir ("Deploy-PaymentRecon-{0}.ps1" -f $Variant)
$ppScript      = Join-Path $scriptDir 'Deploy-PowerPlatform.ps1'

$azureArgs = @{ CustomerPrefix = $CustomerPrefix; ResourceGroupName = $ResourceGroupName; SubscriptionId = $SubscriptionId }
if ($Mode -eq 'Fresh') {
    $azureArgs.CreateResourceGroup = $true
    if ($Location) { $azureArgs.Location = $Location }
    if ($sqlServerFqdn) { $azureArgs.SqlServerName = $sqlServerFqdn; $azureArgs.SqlDatabaseName = $sqlDatabaseName }
    else                { $azureArgs.CreateSql = $true }
    $azureArgs.RunSqlScripts = $true   # fresh: create the base schema
} else {
    # Update (Redeploy): reuse what exists, create what is missing. ARM is applied
    # incrementally, so a missing Storage account / Data Factory is created and existing
    # ones are reused. SQL is created (and the base schema applied) only when absent; an
    # existing SQL database is reused and its data is preserved (schema NOT re-run).
    if ($rg) { $azureArgs.Location = $rg.Location }
    if ($sqlServerFqdn) {
        $azureArgs.SqlServerName = $sqlServerFqdn; $azureArgs.SqlDatabaseName = $sqlDatabaseName
    } else {
        $azureArgs.CreateSql = $true
        $azureArgs.RunSqlScripts = $true
    }
}

Write-Head "Plan ($Mode)"
Write-Info "1) Azure  : $([System.IO.Path]::GetFileName($variantScript))"
$argStr = ($azureArgs.GetEnumerator() | ForEach-Object {
    if ($_.Value -is [bool]) { if ($_.Value) { "-$($_.Key)" } } else { "-$($_.Key) $($_.Value)" }
}) -join ' '
Write-Info "           $argStr"
if ($Mode -eq 'Redeploy') { Write-Info "           (reuse existing + create missing; existing SQL data preserved; SQL password prompted)" }
else                      { Write-Info "           (creates resources + base schema; SQL password prompted)" }
Write-Info ("2) Power Platform : Deploy-PowerPlatform.ps1 -EnvironmentUrl {0}" -f ($(if ($EnvironmentUrl) { $EnvironmentUrl } else { '<env-url>' })))
Write-Info "           (imports/UPGRADES PaymentReconSolutionV5 - the merged solution: Power App + all Copilot Studio agents)"
if (-not $EnvironmentUrl) { Write-Warn2 "No -EnvironmentUrl given: step 3 will prompt for it (or skip if you only want Azure)." }

# --- 5. Execute (gated) -----------------------------------------------------
if (-not $Execute) {
    Write-Head "Dry run"
    Write-Info "This was a read-only plan. Re-run with -Execute to perform it."
    return
}

if (-not $Force) {
    $ans = Read-Host "`nProceed with the $Mode above? Type 'yes' to continue"
    if ($ans -ne 'yes') { Write-Warn2 "Aborted."; return }
}

foreach ($p in @($variantScript,$ppScript)) {
    if (-not (Test-Path $p)) { throw "Required script not found: $p" }
}

# Prompt SQL admin credentials for the Azure step (ADF linked service / SQL).
# Held in memory only - never written to disk.
if (-not $SqlAdminUsername) {
    $u = Read-Host "SQL admin username [sqladmin]"
    $SqlAdminUsername = if ([string]::IsNullOrWhiteSpace($u)) { 'sqladmin' } else { $u.Trim() }
}
if (-not $SqlAdminPassword) {
    $SqlAdminPassword = Read-Host "SQL admin password for '$SqlAdminUsername'" -AsSecureString
}
$azureArgs.SqlAdminUsername = $SqlAdminUsername
$azureArgs.SqlAdminPassword = $SqlAdminPassword

Write-Head "Step 1/2 - Azure ($Variant)"
& $variantScript @azureArgs

Write-Head "Step 2/2 - Power Platform solution import"
$ppArgs = @{ BootstrapConnectionSetup = $true }
if ($EnvironmentUrl) { $ppArgs.EnvironmentUrl = $EnvironmentUrl }
& $ppScript @ppArgs

Write-Head "Done ($Mode)"
Write-Info "Remember the 2 Copilot Studio designer steps for the agent upload action (storage account + attachment->body binding)."
