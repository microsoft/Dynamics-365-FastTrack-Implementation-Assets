<#
.SYNOPSIS
    Deploys the Azure components for the Payment Recon Agent solution.

.DESCRIPTION
    The deployment is driven by a single customer prefix. The script asks for
    the prefix first, derives the Resource Group name from it, and then
    deploys Storage, Data Factory, and optionally SQL into that Resource Group
    using the ARM templates in this folder. Customers do not edit ARM JSON.

    Prefix rules:
      - 5 to 10 letters or numbers, lowercase
      - Used to build the Resource Group: <prefix>-paymentrecon-rg
      - Used to derive Azure resource names (Storage, ADF, SQL)
      - A short stable suffix is appended for globally unique names

    SQL is optional. Use -CreateSql to create Azure SQL, or pass an existing
    SQL server/database. SQL schema execution stays optional via -RunSqlScripts.

.PARAMETER CustomerPrefix
    Customer or project prefix (5-10 letters/numbers, lowercase). If omitted,
    the script prompts for it first.

.PARAMETER ResourceGroupName
    Optional. If omitted, derived as "<prefix>-paymentrecon-rg".

.PARAMETER Location
    Optional Azure region. Uses the Resource Group location if the Resource
    Group already exists. Required only when creating a new Resource Group.

.PARAMETER CreateResourceGroup
    Create the Resource Group if it does not exist. Requires subscription-level
    permission.

.PARAMETER CreateSql
    Create Azure SQL Server and Database. If omitted, -SqlServerName and
    -SqlDatabaseName must be provided.

.PARAMETER SqlServerName
    SQL server name or FQDN (only required for existing SQL).

.PARAMETER SqlDatabaseName
    SQL database name (only required for existing SQL).

.PARAMETER SqlAdminUsername
    SQL admin username. Default: sqladmin.

.PARAMETER SqlAdminPassword
    SQL admin password (SecureString). Prompted if not supplied.

.PARAMETER SubscriptionId
    Optional Azure Subscription ID.

.PARAMETER TenantId
    Tenant ID for service principal login. Use with -ServicePrincipalClientId.

.PARAMETER ServicePrincipalClientId
    Service principal client/application ID.

.PARAMETER ServicePrincipalSecret
    Service principal secret (SecureString).

.PARAMETER RunSqlScripts
    Run 01_schema.sql (twice), 02_indexes.sql, 03_seed_rules.sql after deploy.

.PARAMETER ForceAzureLogin
    Force an interactive Azure sign-in even when an Az context is already cached.

.EXAMPLE
    .\Deploy-PaymentRecon-Direct.ps1
    # Prompts for customer prefix, then runs deployment using existing SQL.

.EXAMPLE
    $sqlPwd = Read-Host -AsSecureString "SQL password"
    .\Deploy-PaymentRecon-Direct.ps1 -CustomerPrefix "contoso" -CreateSql -SqlAdminPassword $sqlPwd -RunSqlScripts

.EXAMPLE
    $spSecret = Read-Host -AsSecureString "SP secret"
    $sqlPwd   = Read-Host -AsSecureString "SQL password"
    .\Deploy-PaymentRecon-Direct.ps1 `
        -CustomerPrefix "contoso" `
        -TenantId "<tenant-id>" `
        -SubscriptionId "<subscription-id>" `
        -ServicePrincipalClientId "<app-client-id>" `
        -ServicePrincipalSecret $spSecret `
        -CreateSql `
        -SqlAdminPassword $sqlPwd
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$CustomerPrefix,

    [Parameter(Mandatory = $false)]
    [string]$ResourceGroupName,

    [Parameter(Mandatory = $false)]
    [string]$Location,

    [Parameter(Mandatory = $false)]
    [switch]$CreateResourceGroup,

    [Parameter(Mandatory = $false)]
    [switch]$CreateSql,

    [Parameter(Mandatory = $false)]
    [string]$SqlServerName,

    [Parameter(Mandatory = $false)]
    [string]$SqlDatabaseName,

    [Parameter(Mandatory = $false)]
    [string]$SqlAdminUsername = "",

    [Parameter(Mandatory = $false)]
    [SecureString]$SqlAdminPassword,

    [Parameter(Mandatory = $false)]
    [string]$SubscriptionId,

    [Parameter(Mandatory = $false)]
    [string]$TenantId,

    [Parameter(Mandatory = $false)]
    [string]$ServicePrincipalClientId,

    [Parameter(Mandatory = $false)]
    [SecureString]$ServicePrincipalSecret,

    [Parameter(Mandatory = $false)]
    [switch]$RunSqlScripts,

    [Parameter(Mandatory = $false)]
    [switch]$ForceAzureLogin
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Surface any terminating error clearly before the script ends.
trap {
    Write-Host "`n[ERROR] $($_.Exception.Message)" -ForegroundColor Red
    if ($script:LogPath) {
        Write-Host "Log file: $script:LogPath" -ForegroundColor Gray
        "[$([DateTime]::Now.ToString('s'))] ERROR : $($_.Exception.Message)" |
            Out-File -FilePath $script:LogPath -Append -Encoding utf8
    }
    throw
}

# ---------------------------------------------------------------------------
# Logging - mirror screen output to a timestamped log file
# ---------------------------------------------------------------------------

$script:LogPath = $null
$script:Actions = New-Object System.Collections.Generic.List[string]

function Initialize-Log {
    param([string]$Directory, [string]$Prefix)

    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $script:LogPath = Join-Path $Directory "deploy-$Prefix-$stamp.log"
    "[$([DateTime]::Now.ToString('s'))] Log started: $script:LogPath" | Out-File -FilePath $script:LogPath -Encoding utf8
}

function Write-Log {
    param([string]$Line)
    if ($script:LogPath) {
        "[$([DateTime]::Now.ToString('s'))] $Line" | Out-File -FilePath $script:LogPath -Append -Encoding utf8
    }
}

function Write-Step {
    param([string]$m)
    Write-Host "`n==> $m" -ForegroundColor Cyan
    Write-Log "STEP  : $m"
}

function Write-Success {
    param([string]$m)
    Write-Host "    [OK] $m" -ForegroundColor Green
    Write-Log "OK    : $m"
    $script:Actions.Add("[OK]   $m") | Out-Null
}

function Write-Warn {
    param([string]$m)
    Write-Host "    [WARN] $m" -ForegroundColor Yellow
    Write-Log "WARN  : $m"
    $script:Actions.Add("[WARN] $m") | Out-Null
}

function Write-Info {
    param([string]$m)
    Write-Host "    $m" -ForegroundColor Gray
    Write-Log "INFO  : $m"
}

function Read-Confirm {
    param([string]$Question, [string]$Default = "Y")

    $suffix = if ($Default -eq "Y") { "[Y/n]" } else { "[y/N]" }
    while ($true) {
        $answer = Read-Host -Prompt "$Question $suffix"
        if ([string]::IsNullOrWhiteSpace($answer)) { $answer = $Default }
        switch ($answer.ToUpperInvariant()) {
            "Y"   { return $true }
            "YES" { return $true }
            "N"   { return $false }
            "NO"  { return $false }
            default { Write-Host "Please answer Y or N." -ForegroundColor Yellow }
        }
    }
}

# ---------------------------------------------------------------------------
# Helper functions
# ---------------------------------------------------------------------------

function Read-CustomerPrefix {
    while ($true) {
        $value = Read-Host -Prompt "Enter customer prefix (5-10 letters/numbers)"
        $clean = ($value.ToLowerInvariant() -replace '[^a-z0-9]', '')

        if ($clean.Length -lt 5 -or $clean.Length -gt 10) {
            Write-Warn "Prefix must be 5-10 letters/numbers. You entered '$clean' ($($clean.Length) chars). Try again."
            continue
        }

        return $clean
    }
}

function Resolve-CustomerPrefix {
    param([string]$Value)

    $clean = ($Value.ToLowerInvariant() -replace '[^a-z0-9]', '')
    if ($clean.Length -lt 5 -or $clean.Length -gt 10) {
        throw "CustomerPrefix must be 5-10 letters/numbers after normalization. Got '$clean' ($($clean.Length) chars)."
    }
    return $clean
}

function Get-StableSuffix {
    param(
        [string]$SubscriptionId,
        [string]$ResourceGroupName,
        [string]$CustomerPrefix
    )

    $seed  = "$SubscriptionId|$ResourceGroupName|$CustomerPrefix".ToLowerInvariant()
    $bytes = [Text.Encoding]::UTF8.GetBytes($seed)
    $sha   = [Security.Cryptography.SHA256]::Create()
    try   { $hash = $sha.ComputeHash($bytes) }
    finally { $sha.Dispose() }

    return (([BitConverter]::ToString($hash) -replace '-', '').ToLowerInvariant()).Substring(0, 6)
}

function Get-StorageAccountName {
    param([string]$Prefix, [string]$Suffix)

    $base = ($Prefix + $Suffix) -replace '[^a-z0-9]', ''
    $name = ($base + "st")
    if ($name.Length -gt 24) { $name = $name.Substring(0, 24) }
    return $name
}

function Get-DashedName {
    param(
        [string]$Prefix,
        [string]$Suffix,
        [string]$Kind,
        [int]$MaxLength
    )

    $name = "$Prefix$Suffix-$Kind"
    if ($name.Length -le $MaxLength) { return $name }

    $maxBase = $MaxLength - $Kind.Length - 1
    if ($maxBase -lt 3) { throw "Cannot derive name for '$Kind'." }
    $base = ($Prefix + $Suffix).Substring(0, $maxBase).TrimEnd('-')
    return "$base-$Kind"
}

function Get-SqlServerShortName {
    param([string]$Server)
    return ($Server -replace '\.database\.windows\.net$', '').ToLowerInvariant()
}

function Get-KeyVaultName {
    param(
        [string]$Prefix,
        [string]$Suffix
    )
    # KV: 3-24 chars, alphanumeric + dashes, must start with letter, must be globally unique
    $name = "$Prefix-$Suffix-kv".ToLowerInvariant()
    $name = ($name -replace '[^a-z0-9-]', '')
    if ($name.Length -gt 24) {
        $base = ($Prefix.ToLowerInvariant()).Substring(0, [Math]::Min(13, $Prefix.Length))
        $name = "$base-$Suffix-kv"
    }
    if ($name -notmatch '^[a-z]') { $name = "kv$name" }
    if ($name.Length -gt 24) { $name = $name.Substring(0, 24) }
    return $name.TrimEnd('-')
}

function Get-SqlServerFqdn {
    param([string]$Server)
    if ($Server -match '\.database\.windows\.net$') { return $Server.ToLowerInvariant() }
    return "$($Server.ToLowerInvariant()).database.windows.net"
}

function ConvertTo-PlainText {
    param([SecureString]$Secure)
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Secure)
    try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
}

function Write-PowerPlatformDeploymentSettings {
    param(
        [Parameter(Mandatory)] [string]$Directory,
        [Parameter(Mandatory)] [string]$SubscriptionId,
        [Parameter(Mandatory)] [string]$ResourceGroupName,
        [Parameter(Mandatory)] [string]$DataFactoryName,
        [Parameter(Mandatory)] [string]$StorageAccountName,
        [Parameter(Mandatory)] [string]$SqlServerFqdn,
        [Parameter(Mandatory)] [string]$SqlDatabaseName
    )

    $settingsPath = Join-Path $Directory "PaymentReconSolutionV5.deployment-settings.json"
    $settings = [ordered]@{
        EnvironmentVariables = @(
            [ordered]@{ SchemaName = "cap_PaymentReconAzureSubscriptionId"; Value = $SubscriptionId },
            [ordered]@{ SchemaName = "cap_PaymentReconAzureResourceGroupName"; Value = $ResourceGroupName },
            [ordered]@{ SchemaName = "cap_PaymentReconDataFactoryName"; Value = $DataFactoryName },
            [ordered]@{ SchemaName = "cap_PaymentReconStorageAccountName"; Value = $StorageAccountName },
            [ordered]@{ SchemaName = "cap_PaymentReconSqlServerFqdn"; Value = $SqlServerFqdn },
            [ordered]@{ SchemaName = "cap_PaymentReconSqlDatabaseName"; Value = $SqlDatabaseName },
            [ordered]@{ SchemaName = "cap_PaymentReconCommercePipelineName"; Value = "ProcessAllCommercePaymentTransV4_PaymentAccountingReport" },
            [ordered]@{ SchemaName = "cap_PaymentReconPaymentProcessorPipelineName"; Value = "ProcessAllPaymentProcessorV4_PaymentAccountingReport" }
        )
        SqlBinding = [ordered]@{
            ServerFqdn = $SqlServerFqdn
            Database   = $SqlDatabaseName
        }
        Connections = [ordered]@{
            SqlConnectionId                   = ""
            BlobConnectionId                  = ""
            AzureDataFactoryConnectionId      = ""
            MicrosoftCopilotStudioConnectionId = ""
            A365McpServersConnectionId        = ""
        }
    }

    $settings | ConvertTo-Json -Depth 5 | Out-File -FilePath $settingsPath -Encoding utf8
    return $settingsPath
}

function Test-SqlConnectivity {
    param(
        [Parameter(Mandatory)] [string]$ServerFqdn,
        [Parameter(Mandatory)] [string]$Database,
        [Parameter(Mandatory)] [string]$Username,
        [Parameter(Mandatory)] [SecureString]$Password,
        [int]$TimeoutSeconds = 15
    )

    $pwdPlain = ConvertTo-PlainText -Secure $Password
    $connStr = "Server=tcp:$ServerFqdn,1433;Initial Catalog=$Database;Persist Security Info=False;User ID=$Username;Password=$pwdPlain;MultipleActiveResultSets=False;Encrypt=True;TrustServerCertificate=False;Connection Timeout=$TimeoutSeconds;"

    $conn = New-Object System.Data.SqlClient.SqlConnection $connStr
    try {
        $conn.Open()
        $cmd = $conn.CreateCommand()
        $cmd.CommandText = "SELECT 1"
        [void]$cmd.ExecuteScalar()
        return [pscustomobject]@{ Success = $true; Message = "Connected as $Username." }
    } catch {
        return [pscustomobject]@{ Success = $false; Message = $_.Exception.Message }
    } finally {
        if ($conn.State -eq 'Open') { $conn.Close() }
        $conn.Dispose()
    }
}

function Invoke-SqlScriptFile {
    <#
        Executes a .sql file against Azure SQL using the built-in
        System.Data.SqlClient (part of the .NET Framework that ships with
        Windows PowerShell). This intentionally avoids the SqlServer module's
        Invoke-Sqlcmd, whose Microsoft.Data.SqlClient native SNI dependency
        fails on machines that do not have a matching install
        ("The type initializer for 'Microsoft.Data.SqlClient.TdsParser' threw
        an exception"). The file is split into batches on lines containing only
        GO, exactly as sqlcmd does.
    #>
    param(
        [Parameter(Mandatory)] [string]$ServerFqdn,
        [Parameter(Mandatory)] [string]$Database,
        [Parameter(Mandatory)] [string]$Username,
        [Parameter(Mandatory)] [string]$PasswordPlain,
        [Parameter(Mandatory)] [string]$ScriptPath,
        [int]$CommandTimeoutSeconds = 300
    )

    $connStr = "Server=tcp:$ServerFqdn,1433;Initial Catalog=$Database;Persist Security Info=False;User ID=$Username;Password=$PasswordPlain;MultipleActiveResultSets=False;Encrypt=True;TrustServerCertificate=True;Connection Timeout=30;"
    $sql = Get-Content -Path $ScriptPath -Raw
    $batches = [regex]::Split($sql, '(?im)^[ \t]*GO[ \t]*$')

    $conn = New-Object System.Data.SqlClient.SqlConnection $connStr
    try {
        $conn.Open()
        foreach ($batch in $batches) {
            if ([string]::IsNullOrWhiteSpace($batch)) { continue }
            $cmd = $conn.CreateCommand()
            $cmd.CommandText = $batch
            $cmd.CommandTimeout = $CommandTimeoutSeconds
            [void]$cmd.ExecuteNonQuery()
        }
    } finally {
        if ($conn.State -eq 'Open') { $conn.Close() }
        $conn.Dispose()
    }
}

function Select-AzureRegion {
    param(
        [string]$DefaultRegion = "eastus"
    )

    Write-Info "Fetching available Azure regions for your subscription..."
    $allLocations = @()
    try {
        $allLocations = Get-AzLocation -ErrorAction Stop |
            Where-Object { $_.Providers -contains "Microsoft.Storage" -and $_.Providers -contains "Microsoft.DataFactory" } |
            Sort-Object Location
    } catch {
        Write-Warn "Could not fetch region list: $($_.Exception.Message). Falling back to manual entry."
    }

    if (-not $allLocations -or $allLocations.Count -eq 0) {
        $input = Read-Host "  Enter Azure region (press Enter for '$DefaultRegion')"
        if ([string]::IsNullOrWhiteSpace($input)) { return $DefaultRegion }
        return $input.Trim().ToLowerInvariant()
    }

    Write-Host ""
    Write-Host "  Available Azure regions:" -ForegroundColor Cyan
    for ($i = 0; $i -lt $allLocations.Count; $i++) {
        $loc = $allLocations[$i]
        $marker = if ($loc.Location -eq $DefaultRegion) { " (default)" } else { "" }
        $line = "  [{0,3}] {1,-22} {2}{3}" -f ($i + 1), $loc.Location, $loc.DisplayName, $marker
        Write-Host $line
    }
    Write-Host ""

    while ($true) {
        $choice = Read-Host "  Enter number, region name, or press Enter for '$DefaultRegion'"
        if ([string]::IsNullOrWhiteSpace($choice)) { return $DefaultRegion }
        $choice = $choice.Trim()

        $asNum = 0
        if ([int]::TryParse($choice, [ref]$asNum)) {
            if ($asNum -ge 1 -and $asNum -le $allLocations.Count) {
                return $allLocations[$asNum - 1].Location
            }
            Write-Warn "Number out of range. Try again."
            continue
        }

        $needle = $choice.ToLowerInvariant()
        $match = $allLocations | Where-Object { $_.Location -eq $needle } | Select-Object -First 1
        if ($match) { return $match.Location }

        Write-Warn "Region '$choice' not found. Try again."
    }
}

# ---------------------------------------------------------------------------
# Step 1 - Ask for the customer prefix first
# ---------------------------------------------------------------------------

Write-Host "`n============================================================" -ForegroundColor Magenta
Write-Host "  Payment Recon Agent - Azure Deployment" -ForegroundColor Magenta
Write-Host "============================================================" -ForegroundColor Magenta

if ([string]::IsNullOrWhiteSpace($CustomerPrefix)) {
    $customerPrefixClean = Read-CustomerPrefix
} else {
    $customerPrefixClean = Resolve-CustomerPrefix -Value $CustomerPrefix
}

# Derive Resource Group name from prefix when not supplied
$rgWasDerived = [string]::IsNullOrWhiteSpace($ResourceGroupName)
if ($rgWasDerived) {
    $ResourceGroupName = "$customerPrefixClean-paymentrecon-rg"
}

$scriptDir = $PSScriptRoot
if (-not $scriptDir) { $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path }

# Start the log file now that we know the prefix
Initialize-Log -Directory $scriptDir -Prefix $customerPrefixClean
Write-Success "Customer prefix accepted: $customerPrefixClean"
if ($rgWasDerived) {
    Write-Success "Derived Resource Group name: $ResourceGroupName"
}
Write-Info "Log file: $script:LogPath"

# ---------------------------------------------------------------------------
# Step 1b - Decide SQL option (interactive if not specified)
# ---------------------------------------------------------------------------

$sqlInputsProvided = -not [string]::IsNullOrWhiteSpace($SqlServerName) -and -not [string]::IsNullOrWhiteSpace($SqlDatabaseName)

if (-not $CreateSql -and -not $sqlInputsProvided) {
    Write-Step "SQL configuration"
    Write-Host "    The deployment needs a SQL Database. ADF will use the password directly (no Key Vault)." -ForegroundColor Gray

    if (Read-Confirm -Question "Create a new Azure SQL Server and Database in this Resource Group?" -Default "Y") {
        $CreateSql = $true
        Write-Success "SQL choice: create new Azure SQL (names auto-derived from prefix)."
    } else {
        Write-Success "SQL choice: use existing Azure SQL."
        Write-Host "    Please provide the name of the existing SQL Server and Database." -ForegroundColor Gray
        while ([string]::IsNullOrWhiteSpace($SqlServerName)) {
            $SqlServerName = Read-Host -Prompt "  Existing SQL Server name (e.g. myserver or myserver.database.windows.net)"
        }
        while ([string]::IsNullOrWhiteSpace($SqlDatabaseName)) {
            $SqlDatabaseName = Read-Host -Prompt "  Existing SQL Database name"
        }
        Write-Success "Will point ADF at $SqlServerName / $SqlDatabaseName"
    }
}

# Collect SQL admin user + password AFTER the create/existing choice.
Write-Step "SQL administrator credentials"
Write-Host "    Stored as SecureString in the ADF linked service (no Key Vault used in this variant)." -ForegroundColor Gray

if ([string]::IsNullOrWhiteSpace($SqlAdminUsername)) {
    $u = Read-Host -Prompt "  SQL admin username [default: sqladmin]"
    if ([string]::IsNullOrWhiteSpace($u)) { $SqlAdminUsername = "sqladmin" } else { $SqlAdminUsername = $u.Trim() }
}
if (-not $SqlAdminPassword) {
    $SqlAdminPassword = Read-Host -Prompt "  SQL admin password for '$SqlAdminUsername'" -AsSecureString
}
Write-Success "SQL admin: $SqlAdminUsername"

# Ask whether to run SQL setup scripts (schema + indexes + seed rules) at end of deploy.
if (-not $RunSqlScripts) {
    Write-Step "SQL schema + seed data"
    Write-Host "    The deployment can run these scripts against the database after ADF is ready:" -ForegroundColor Gray
    Write-Host "      - 01_schema.sql   (creates tables; runs twice to seed policy data)" -ForegroundColor Gray
    Write-Host "      - 02_indexes.sql  (performance indexes)" -ForegroundColor Gray
    Write-Host "      - 03_seed_rules.sql (seeds reconciliation rules)" -ForegroundColor Gray
    if (Read-Confirm -Question "Run the SQL setup + seed scripts automatically after deploy?" -Default "Y") {
        $RunSqlScripts = $true
        Write-Success "Will run SQL setup scripts after deployment."
    } else {
        Write-Info "Skipping SQL scripts. You can run them manually later."
    }
}

# If using EXISTING SQL, validate connectivity right now before going further.
if (-not $CreateSql -and -not [string]::IsNullOrWhiteSpace($SqlServerName) -and -not [string]::IsNullOrWhiteSpace($SqlDatabaseName)) {
    $existingFqdn = Get-SqlServerFqdn -Server $SqlServerName
    Write-Step "Verifying SQL connectivity to '$existingFqdn' / '$SqlDatabaseName'..."
    Write-Host "    (If your client IP is not allowed by the SQL firewall, add it in the Azure Portal." -ForegroundColor Gray
    Write-Host "     SQL Server > Networking > add client IP, then re-run.)" -ForegroundColor Gray

    $attempt = 0
    while ($true) {
        $attempt++
        $result = Test-SqlConnectivity -ServerFqdn $existingFqdn -Database $SqlDatabaseName -Username $SqlAdminUsername -Password $SqlAdminPassword
        if ($result.Success) {
            Write-Success "SQL connectivity verified ($($result.Message))"
            break
        }
        Write-Warn "SQL connection failed: $($result.Message)"
        if ($attempt -ge 3) {
            throw "SQL connectivity check failed 3 times. Aborting."
        }
        if (-not (Read-Confirm -Question "Retry SQL connectivity (you can re-enter credentials)?" -Default "Y")) {
            throw "User aborted SQL connectivity check."
        }
        $u2 = Read-Host -Prompt "  SQL admin username [current: $SqlAdminUsername, press Enter to keep]"
        if (-not [string]::IsNullOrWhiteSpace($u2)) { $SqlAdminUsername = $u2.Trim() }
        $SqlAdminPassword = Read-Host -Prompt "  SQL admin password for '$SqlAdminUsername'" -AsSecureString
    }
}

# ---------------------------------------------------------------------------
# Step 2 - Connect to Azure
# ---------------------------------------------------------------------------

Write-Step "Connecting to Azure..."

# Pre-flight: ensure required Az modules are available
# Required modules + minimum versions. Anything older gets auto-updated so we don't
# get into "old cmdlet missing parameter" surprises mid-deployment.
$requiredModules = [ordered]@{
    'Az.Accounts'    = '2.10.0'
    'Az.Resources'   = '6.0.0'
    'Az.Sql'         = '4.0.0'
    'Az.Storage'     = '5.0.0'
    'Az.DataFactory' = '1.16.0'
}

$toInstall = @()
foreach ($modName in $requiredModules.Keys) {
    $minVer = [version]$requiredModules[$modName]
    $installed = Get-Module -ListAvailable -Name $modName | Sort-Object Version -Descending | Select-Object -First 1
    if (-not $installed) {
        $toInstall += [pscustomobject]@{ Name = $modName; Reason = "not installed (need >= $minVer)" }
    } elseif ($installed.Version -lt $minVer) {
        $toInstall += [pscustomobject]@{ Name = $modName; Reason = "found $($installed.Version), need >= $minVer" }
    }
}

if ($toInstall.Count -gt 0) {
    Write-Warn "PowerShell module versions need updating:"
    foreach ($m in $toInstall) { Write-Host "    - $($m.Name): $($m.Reason)" -ForegroundColor Yellow }
    if (Read-Confirm -Question "Install/update them now for the current user?" -Default "Y") {
        foreach ($m in $toInstall) {
            Write-Info "Installing $($m.Name) (>= $($requiredModules[$m.Name]))..."
            Install-Module -Name $m.Name -MinimumVersion $requiredModules[$m.Name] `
                           -Scope CurrentUser -Force -AllowClobber -Repository PSGallery
        }
        Write-Success "Required modules installed/updated."
    } else {
        throw "Required Az modules are missing/outdated. Update with: Install-Module Az -Scope CurrentUser -Force"
    }
}

foreach ($modName in $requiredModules.Keys) {
    # Remove any older version that may already be loaded, then import the highest installed version.
    Get-Module -Name $modName | Remove-Module -Force -ErrorAction SilentlyContinue
    $latest = Get-Module -ListAvailable -Name $modName |
              Where-Object { $_.Version -ge [version]$requiredModules[$modName] } |
              Sort-Object Version -Descending | Select-Object -First 1
    if (-not $latest) { throw "Module $modName is required but not available after install." }
    Import-Module -Name $modName -RequiredVersion $latest.Version -ErrorAction Stop | Out-Null
}
Write-Success "Az modules loaded."

$spLoginRequested = -not [string]::IsNullOrWhiteSpace($TenantId) -or
                    -not [string]::IsNullOrWhiteSpace($ServicePrincipalClientId) -or
                    $null -ne $ServicePrincipalSecret

try {
    if ($spLoginRequested) {
        if ([string]::IsNullOrWhiteSpace($TenantId) -or [string]::IsNullOrWhiteSpace($ServicePrincipalClientId)) {
            throw "Service principal login requires both -TenantId and -ServicePrincipalClientId."
        }
        if (-not $ServicePrincipalSecret) {
            $ServicePrincipalSecret = Read-Host -Prompt "Enter service principal secret" -AsSecureString
        }
        $spCred = [PSCredential]::new($ServicePrincipalClientId, $ServicePrincipalSecret)
        Connect-AzAccount -ServicePrincipal -Tenant $TenantId -Credential $spCred | Out-Null
        Write-Success "Connected with service principal $ServicePrincipalClientId."
    } elseif ($ForceAzureLogin) {
        Write-Info "Forcing interactive Azure sign-in (browser window; tokens kept in memory only, not written to disk)..."
        # Keep the access/refresh tokens in-process only so nothing reusable is
        # persisted under the user's ~/.Azure token cache.
        Disable-AzContextAutosave -Scope Process -ErrorAction SilentlyContinue | Out-Null
        Clear-AzContext -Scope Process -Force -ErrorAction SilentlyContinue
        Connect-AzAccount | Out-Null
    } else {
        if (-not (Get-AzContext -ErrorAction SilentlyContinue)) {
            Write-Info "Launching interactive Azure sign-in..."
            Connect-AzAccount | Out-Null
        } else {
            Write-Success "Already signed in to Azure."
        }
    }
} catch {
    throw "Azure sign-in failed: $($_.Exception.Message)"
}

if ($SubscriptionId) { Set-AzContext -SubscriptionId $SubscriptionId | Out-Null }

$ctx = Get-AzContext
if (-not $ctx) { throw "No Azure context after sign-in. Please run Connect-AzAccount manually." }
Write-Success "Subscription: $($ctx.Subscription.Name) ($($ctx.Subscription.Id))"

# ---------------------------------------------------------------------------
# Step 2b - Pick Azure region (live list from subscription)
# ---------------------------------------------------------------------------

if ([string]::IsNullOrWhiteSpace($Location)) {
    Write-Step "Choose Azure region for the Resource Group and all resources"
    $Location = Select-AzureRegion -DefaultRegion "eastus"
    Write-Success "Azure region selected: $Location"
} else {
    Write-Success "Azure region (from -Location): $Location"
}

# ---------------------------------------------------------------------------
# Step 3 - Resource Group
# ---------------------------------------------------------------------------

Write-Step "Resolving Resource Group '$ResourceGroupName'..."

$rg = Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue

if ($rg) {
    Write-Success "Resource Group already exists in '$($rg.Location)'."
    if ($Location -ne $rg.Location) {
        Write-Warn "Requested region '$Location' differs from existing RG region '$($rg.Location)'. Using existing RG region."
        $Location = $rg.Location
    }
} else {
    Write-Info "Resource Group not found. Creating '$ResourceGroupName' in '$Location'..."
    New-AzResourceGroup -Name $ResourceGroupName -Location $Location | Out-Null
    Write-Success "Resource Group created in $Location."
    $script:Actions.Add("Created Resource Group '$ResourceGroupName' in $Location") | Out-Null
}

# ---------------------------------------------------------------------------
# Step 4 - Derive Azure resource names from prefix + stable suffix
# ---------------------------------------------------------------------------

$nameSuffix      = Get-StableSuffix -SubscriptionId $ctx.Subscription.Id -ResourceGroupName $ResourceGroupName -CustomerPrefix $customerPrefixClean
$storageAcctName = Get-StorageAccountName -Prefix $customerPrefixClean -Suffix $nameSuffix
$adfName         = Get-DashedName -Prefix $customerPrefixClean -Suffix $nameSuffix -Kind "adf" -MaxLength 63

# SQL names: derived from prefix ONLY when creating new SQL.
# If using an existing SQL, the user-supplied names are kept as-is.
if ($CreateSql) {
    if ([string]::IsNullOrWhiteSpace($SqlServerName))   { $SqlServerName   = Get-DashedName -Prefix $customerPrefixClean -Suffix $nameSuffix -Kind "sqlsrv" -MaxLength 63 }
    if ([string]::IsNullOrWhiteSpace($SqlDatabaseName)) { $SqlDatabaseName = Get-DashedName -Prefix $customerPrefixClean -Suffix $nameSuffix -Kind "db"     -MaxLength 128 }
}

$sqlServerShortName = Get-SqlServerShortName -Server $SqlServerName
$sqlFqdn            = Get-SqlServerFqdn -Server $SqlServerName

Write-Host "`n------------------------------------------------------------" -ForegroundColor Magenta
Write-Host "  Planned deployment" -ForegroundColor Magenta
Write-Host "------------------------------------------------------------" -ForegroundColor Magenta
Write-Host "  Customer Prefix : $customerPrefixClean"
Write-Host "  Resource Group  : $ResourceGroupName"
Write-Host "  Location        : $Location"
Write-Host "  Storage Account : $storageAcctName"
Write-Host "  Data Factory    : $adfName  (System-Assigned MI)"
Write-Host "  SQL Server      : $sqlFqdn"
Write-Host "  SQL Database    : $SqlDatabaseName"
Write-Host "  SQL Admin       : $SqlAdminUsername"
Write-Host "  Create SQL      : $CreateSql"
Write-Host "  Run SQL Scripts : $RunSqlScripts"
Write-Host "  ADF Auth Mode   : SQL login + Storage key (direct, no Key Vault)"
Write-Host "------------------------------------------------------------`n" -ForegroundColor Magenta

# ---------------------------------------------------------------------------
# Step 5 - SQL (optional)
# ---------------------------------------------------------------------------

if ($CreateSql) {
    Write-Step "Provisioning Azure SQL Server '$sqlServerShortName'..."

    if (Get-AzSqlServer -ResourceGroupName $ResourceGroupName -ServerName $sqlServerShortName -ErrorAction SilentlyContinue) {
        Write-Warn "SQL Server already exists - skipping creation."
    } else {
        New-AzSqlServer `
            -ResourceGroupName $ResourceGroupName `
            -ServerName $sqlServerShortName `
            -Location $Location `
            -SqlAdministratorCredentials ([PSCredential]::new($SqlAdminUsername, $SqlAdminPassword)) | Out-Null
        Write-Success "SQL Server created: $sqlFqdn"
    }

    Write-Step "Configuring SQL firewall..."
    New-AzSqlServerFirewallRule `
        -ResourceGroupName $ResourceGroupName `
        -ServerName $sqlServerShortName `
        -FirewallRuleName "AllowAzureServices" `
        -StartIpAddress "0.0.0.0" -EndIpAddress "0.0.0.0" `
        -ErrorAction SilentlyContinue | Out-Null

    try {
        $myIp = (Invoke-RestMethod -Uri "https://api.ipify.org?format=json").ip
        New-AzSqlServerFirewallRule `
            -ResourceGroupName $ResourceGroupName `
            -ServerName $sqlServerShortName `
            -FirewallRuleName "DeploymentClient" `
            -StartIpAddress $myIp -EndIpAddress $myIp `
            -ErrorAction SilentlyContinue | Out-Null
        Write-Success "Firewall: Azure services + client IP ($myIp) allowed."
    } catch {
        Write-Warn "Could not detect client IP. Add a firewall rule manually if needed."
    }

    Write-Step "Creating SQL Database '$SqlDatabaseName'..."
    if (Get-AzSqlDatabase -ResourceGroupName $ResourceGroupName -ServerName $sqlServerShortName -DatabaseName $SqlDatabaseName -ErrorAction SilentlyContinue) {
        Write-Warn "SQL Database already exists - skipping."
    } else {
        New-AzSqlDatabase `
            -ResourceGroupName $ResourceGroupName `
            -ServerName $sqlServerShortName `
            -DatabaseName $SqlDatabaseName `
            -Edition "Standard" -RequestedServiceObjectiveName "S1" | Out-Null
        Write-Success "SQL Database created."
    }
} else {
    Write-Success "Using existing SQL: $sqlFqdn / $SqlDatabaseName"
}

# ---------------------------------------------------------------------------
# Step 6 - Storage Account (ARM)
# ---------------------------------------------------------------------------

Write-Step "Checking Storage Account name '$storageAcctName'..."

if (Get-AzStorageAccount -ResourceGroupName $ResourceGroupName -Name $storageAcctName -ErrorAction SilentlyContinue) {
    Write-Warn "Storage Account already exists in this RG - reusing it."
} else {
    $nameStatus = Get-AzStorageAccountNameAvailability -Name $storageAcctName
    if (-not $nameStatus.NameAvailable) {
        throw "Storage Account name '$storageAcctName' is not available: $($nameStatus.Message). Pick a different -CustomerPrefix."
    }
    Write-Success "Storage Account name is available."
}

Write-Step "Deploying Storage Account ARM template..."

$storageTemplate = Join-Path $scriptDir "arm-storage-v4.json"
if (-not (Test-Path $storageTemplate)) { throw "ARM template not found: $storageTemplate" }

New-AzResourceGroupDeployment `
    -ResourceGroupName $ResourceGroupName `
    -TemplateFile $storageTemplate `
    -TemplateParameterObject @{
        storageAccounts_paymentreconstoragev3_name = $storageAcctName
        location                                   = $Location
    } `
    -Mode Incremental `
    -Name "StorageDeployment-$(Get-Date -Format 'yyyyMMddHHmmss')" | Out-Null

Write-Success "Storage Account '$storageAcctName' deployed with 4 blob containers."

# ---------------------------------------------------------------------------
# Step 7 - Retrieve storage key + build connection string for ADF
# ---------------------------------------------------------------------------

Write-Step "Retrieving Storage Account key..."
$storageKey = (Get-AzStorageAccountKey -ResourceGroupName $ResourceGroupName -Name $storageAcctName)[0].Value
$storageConnStr = "DefaultEndpointsProtocol=https;AccountName=$storageAcctName;AccountKey=$storageKey;EndpointSuffix=core.windows.net"
Write-Success "Storage connection string built."

# ---------------------------------------------------------------------------
# Step 8 - Azure Data Factory instance
# ---------------------------------------------------------------------------

Write-Step "Creating Azure Data Factory '$adfName' if needed..."
if (Get-AzDataFactoryV2 -ResourceGroupName $ResourceGroupName -Name $adfName -ErrorAction SilentlyContinue) {
    Write-Warn "Data Factory already exists - reusing it."
} else {
    New-AzDataFactoryV2 -ResourceGroupName $ResourceGroupName -Name $adfName -Location $Location | Out-Null
    Write-Success "Data Factory created."
    $script:Actions.Add("Created Data Factory '$adfName'") | Out-Null
}

# ---------------------------------------------------------------------------
# Step 9 - Deploy ADF ARM template (linked services use direct secrets)
# ---------------------------------------------------------------------------

Write-Step "Deploying ADF ARM template (pipelines, datasets, direct-secret linked services)..."

$adfTemplate = Join-Path $scriptDir "arm-datafactory-v4-direct.json"
if (-not (Test-Path $adfTemplate)) { throw "ARM template not found: $adfTemplate" }

$sqlPwdPlainForArm = ConvertTo-PlainText -Secure $SqlAdminPassword

New-AzResourceGroupDeployment `
    -ResourceGroupName $ResourceGroupName `
    -TemplateFile $adfTemplate `
    -TemplateParameterObject @{
        factoryName                                        = $adfName
        PaymentReconFiles_connectionString                 = $storageConnStr
        PaymentReconSQL_password                           = $sqlPwdPlainForArm
        PaymentReconSQL_properties_typeProperties_server   = $sqlFqdn
        PaymentReconSQL_properties_typeProperties_database = $SqlDatabaseName
        PaymentReconSQL_properties_typeProperties_userName = $SqlAdminUsername
    } `
    -Mode Incremental `
    -Name "AdfDeployment-$(Get-Date -Format 'yyyyMMddHHmmss')" | Out-Null

Write-Success "Data Factory '$adfName' configured (secrets stored directly in linked services)."
$powerPlatformSettingsPath = Write-PowerPlatformDeploymentSettings `
    -Directory $scriptDir `
    -SubscriptionId $ctx.Subscription.Id `
    -ResourceGroupName $ResourceGroupName `
    -DataFactoryName $adfName `
    -StorageAccountName $storageAcctName `
    -SqlServerFqdn $sqlFqdn `
    -SqlDatabaseName $SqlDatabaseName
Write-Success "Power Platform deployment settings generated: $powerPlatformSettingsPath"
$script:Actions.Add("Generated Power Platform environment variable settings file") | Out-Null
$script:Actions.Add("Deployed ADF pipelines/datasets/linked services (direct secrets)") | Out-Null

# ---------------------------------------------------------------------------
# Step 10 - Optional SQL schema execution
# ---------------------------------------------------------------------------

if ($RunSqlScripts) {
    Write-Step "Running SQL setup scripts..."

    $sqlPwdPlain = ConvertTo-PlainText -Secure $SqlAdminPassword

    foreach ($scriptFile in @("01_schema.sql", "01_schema.sql", "02_indexes.sql", "03_seed_rules.sql")) {
        $scriptPath = Join-Path $scriptDir $scriptFile
        if (Test-Path $scriptPath) {
            Write-Host "    Running $scriptFile..." -NoNewline
            Invoke-SqlScriptFile -ServerFqdn $sqlFqdn -Database $SqlDatabaseName `
                -Username $SqlAdminUsername -PasswordPlain $sqlPwdPlain `
                -ScriptPath $scriptPath -CommandTimeoutSeconds 300
            Write-Host " done." -ForegroundColor Green
            Write-Log "OK    : SQL script executed: $scriptFile"
        } else {
            throw "Required SQL script not found: $scriptPath"
        }
    }
    Write-Success "SQL setup scripts completed."
}

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

Write-Host "`n============================================================" -ForegroundColor Magenta
Write-Host "  Deployment Complete - Summary" -ForegroundColor Magenta
Write-Host "============================================================" -ForegroundColor Magenta
Write-Host "  Customer Prefix : $customerPrefixClean"
Write-Host "  Resource Group  : $ResourceGroupName ($Location)"
Write-Host "  Storage Account : $storageAcctName"
Write-Host "  Data Factory    : $adfName"
Write-Host "  SQL Server      : $sqlFqdn"
Write-Host "  SQL Database    : $SqlDatabaseName"
Write-Host "  SQL Username    : $SqlAdminUsername"
Write-Host "  PP Settings     : $powerPlatformSettingsPath"
Write-Host "============================================================" -ForegroundColor Magenta

Write-Host "`nActions completed:" -ForegroundColor Cyan
foreach ($a in $script:Actions) { Write-Host "  $a" }

Write-Host "`nLog file: $script:LogPath" -ForegroundColor Gray

if (-not $RunSqlScripts) {
    Write-Host "`nNext Steps:" -ForegroundColor Yellow
    Write-Host "  1. Run SQL scripts manually (or rerun with -RunSqlScripts):"
    Write-Host "     - 01_schema.sql  (run TWICE)"
    Write-Host "     - 02_indexes.sql"
    Write-Host "     - 03_seed_rules.sql"
    Write-Host "  2. Verify ADF Linked Service connections in ADF Studio."
    Write-Host "  3. Import PaymentReconSolutionV5.zip into Power Platform using:"
    Write-Host "     $powerPlatformSettingsPath"
}

Write-Host ""
