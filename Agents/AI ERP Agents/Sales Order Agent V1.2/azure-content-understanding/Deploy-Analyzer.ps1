<#
.SYNOPSIS
    Deploys the sales-order Content Understanding analyzer to any Azure AI
    Foundry resource, and verifies the deployed contract.

.DESCRIPTION
    This is the whole "ship the model" story for the Content Understanding
    route. There is no custom connector, no Azure Function and no role
    assignments. This script authenticates with the caller's Entra token; the
    runtime Power Platform connection is key-based and is created separately.

    Before creating the analyzer it prepares the resource, so no portal steps
    are needed:
      1. resolves the Azure AI resource from the endpoint (or -ResourceGroup
         and -ResourceName);
      2. reuses existing gpt-4.1 and text-embedding-3-large deployments, or
         creates them (GlobalStandard, capacity 100 by default);
      3. sets the Content Understanding defaults that map gpt-4.1,
         text-embedding-3-large, prebuilt-analyzer-completion and
         prebuilt-analyzer-embedding to those deployments. A new resource
         rejects every analyzer with DefaultsNotSet until this is done.
    Requires Azure CLI sign-in. The installer identity needs:
      - Cognitive Services Contributor on the resource group (or resource):
        resolve the resource and create model deployments (control plane);
      - Cognitive Services User on the resource: set CU defaults and create,
        read and replace analyzers (data plane). Cognitive Services Content
        Understanding Contributor is not enough for -Force, because it cannot
        delete analyzers; Content Understanding Owner is.
    The script does not create the resource or assign roles. GlobalStandard
    quota for both models must exist in the region. See
    docs/architecture-diagrams.md section 3 for the full permission set.
    Use -SkipResourcePreparation to manage deployments and defaults yourself.

    The script is idempotent. Re-running against an endpoint that already has
    the analyzer reports NoChange unless -Force is supplied. -WhatIf reports
    every deployment, default and analyzer it would create, and changes nothing.

.PARAMETER Endpoint
    Resource endpoint, e.g. https://<name>.services.ai.azure.com

.PARAMETER AnalyzerId
    Analyzer identifier. Pattern is [a-zA-Z0-9._]{1,64} - hyphens are rejected
    by the service.

.PARAMETER DefinitionPath
    Path to the analyzer JSON. Defaults to the shipped typed definition.

.PARAMETER Force
    Replace an existing analyzer of the same ID.

.PARAMETER WhatIf
    Validate and report without creating anything.

.EXAMPLE
    .\Deploy-Analyzer.ps1 -Endpoint https://contoso.services.ai.azure.com
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^https://[a-zA-Z0-9.\-]+$')]
    [string]$Endpoint,

    [ValidatePattern('^[a-zA-Z0-9._]{1,64}$')]
    [string]$AnalyzerId = 'sales_order_extraction_v2_0_7',

    # Release packages ship the definition next to this script; the repository keeps it under ..\analyzer.
    [string]$DefinitionPath = $(
        $packaged = Join-Path $PSScriptRoot 'sales-order-extraction.v2_0_7.json'
        if (Test-Path $packaged) { $packaged } else { Join-Path $PSScriptRoot '..\analyzer\sales-order-extraction.v2_0_7.json' }
    ),

    [string]$ApiVersion = '2025-11-01',

    # Resource preparation: model deployments and Content Understanding defaults.
    # Resolved from the endpoint when not supplied.
    [string]$ResourceGroup,
    [string]$ResourceName,
    [string]$DeploymentSku = 'GlobalStandard',
    [ValidateRange(1, 10000)]
    [int]$CompletionCapacity = 100,
    [ValidateRange(1, 10000)]
    [int]$EmbeddingCapacity = 100,
    [switch]$SkipResourcePreparation,

    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$Endpoint = $Endpoint.TrimEnd('/')

function Write-Step { param($Message) Write-Host "  $Message" }

function Get-CuToken {
    $token = az account get-access-token `
        --resource 'https://cognitiveservices.azure.com' `
        --query accessToken -o tsv 2>$null | Select-Object -Last 1
    if (-not $token -or $token -notmatch '^ey') {
        throw "Could not acquire an Entra token. Run 'az login' first."
    }
    return $token.Trim()
}

function Invoke-Cu {
    param($Method, $Uri, $Body, $Token, [switch]$AllowNotFound)
    $headers = @{ Authorization = "Bearer $Token" }
    try {
        $params = @{
            Uri         = $Uri
            Method      = $Method
            Headers     = $headers
            TimeoutSec  = 300
        }
        if ($Body) {
            $params.Body = $Body
            $params.ContentType = 'application/json'
        }
        return Invoke-WebRequest @params
    }
    catch {
        $status = $_.Exception.Response.StatusCode.value__
        if ($AllowNotFound -and $status -eq 404) { return $null }
        throw "HTTP $status on $Method $Uri`n$($_.ErrorDetails.Message)"
    }
}

# Models the analyzer needs on the resource. The completion model comes from the
# definition; 'prebuilt-analyzer-embedding' is an alias that resolves to this model.
$RequiredModels = [ordered]@{
    completion = @{ Name = $null; Version = '2025-04-14'; Capacity = $CompletionCapacity }
    embedding  = @{ Name = 'text-embedding-3-large'; Version = '1'; Capacity = $EmbeddingCapacity }
}

function Invoke-Az {
    param([string[]]$Arguments)
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = & az @Arguments 2>&1
        $exit = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previous
    }
    if ($exit -ne 0) {
        throw "az $($Arguments[0..3] -join ' ') failed: $(($output | Out-String).Trim())"
    }
    $text = ($output | Where-Object { $_ -is [string] }) -join "`n"
    if ($text.Trim()) { return $text | ConvertFrom-Json }
    return $null
}

function Resolve-CuResource {
    if ($ResourceGroup -and $ResourceName) {
        return @{ Group = $ResourceGroup; Name = $ResourceName }
    }
    $subdomain = ([uri]$Endpoint).Host.Split('.')[0]
    $accounts = @(Invoke-Az @('cognitiveservices', 'account', 'list', '--query',
            "[?properties.customSubDomainName=='$subdomain' || name=='$subdomain'].{name:name, group:resourceGroup}",
            '-o', 'json'))
    if ($accounts.Count -ne 1) {
        throw ("Could not identify the Azure AI resource for '$Endpoint' in the current subscription " +
            "(found $($accounts.Count)). Run 'az account set --subscription <id>' or pass -ResourceGroup and -ResourceName.")
    }
    return @{ Group = $accounts[0].group; Name = $accounts[0].name }
}

function Get-CuDefaults {
    param($Token)
    try {
        return (Invoke-Cu -Method GET -Uri "$Endpoint/contentunderstanding/defaults?api-version=$ApiVersion" -Token $Token).Content |
            ConvertFrom-Json
    }
    catch {
        if ("$_" -match 'DefaultsNotSet') { return $null }
        throw
    }
}

function Initialize-CuResource {
    param($Token)
    $resource = Resolve-CuResource
    Write-Step "resource   : $($resource.Name) (resource group $($resource.Group))"
    $deployments = @(Invoke-Az @('cognitiveservices', 'account', 'deployment', 'list',
            '-g', $resource.Group, '-n', $resource.Name, '-o', 'json'))

    $names = @{}
    foreach ($role in $RequiredModels.Keys) {
        $model = $RequiredModels[$role]
        $match = $deployments | Where-Object {
            $_.properties.model.name -eq $model.Name -and $_.properties.provisioningState -eq 'Succeeded'
        } | Sort-Object { if ($_.properties.model.version -eq $model.Version) { 0 } else { 1 } } | Select-Object -First 1
        if ($match) {
            $names[$role] = $match.name
            Write-Step "deployment : $($model.Name) -> '$($match.name)' (existing, version $($match.properties.model.version))"
            continue
        }
        $target = $model.Name
        if (-not $PSCmdlet.ShouldProcess("$($resource.Name)/$target",
                "Create $DeploymentSku deployment of $($model.Name) $($model.Version), capacity $($model.Capacity)")) {
            $names[$role] = $target
            Write-Step "deployment : $($model.Name) -> '$target' (WOULD CREATE)"
            continue
        }
        Write-Step "deployment : creating '$target' ($($model.Name) $($model.Version), $DeploymentSku, capacity $($model.Capacity))"
        try {
            Invoke-Az @('cognitiveservices', 'account', 'deployment', 'create', '-g', $resource.Group, '-n', $resource.Name,
                '--deployment-name', $target, '--model-name', $model.Name, '--model-version', $model.Version,
                '--model-format', 'OpenAI', '--sku-name', $DeploymentSku, '--sku-capacity', "$($model.Capacity)",
                '-o', 'json') | Out-Null
        }
        catch {
            throw ("Could not create the $($model.Name) deployment. If the error mentions quota, rerun with a lower " +
                "-CompletionCapacity / -EmbeddingCapacity or request quota for $DeploymentSku in this region. $_")
        }
        $names[$role] = $target
    }

    $desired = [ordered]@{
        ($RequiredModels.completion.Name) = $names.completion
        ($RequiredModels.embedding.Name)  = $names.embedding
        'prebuilt-analyzer-completion'    = $names.completion
        'prebuilt-analyzer-embedding'     = $names.embedding
    }
    $current = Get-CuDefaults -Token $Token
    $missing = @($desired.Keys | Where-Object { -not $current -or $current.modelDeployments.$_ -ne $desired[$_] })
    if (-not $missing) {
        Write-Step 'defaults   : already set'
        return
    }
    if (-not $PSCmdlet.ShouldProcess($Endpoint, "Set Content Understanding defaults for: $($missing -join ', ')")) {
        Write-Step "defaults   : WOULD SET $($missing -join ', ')"
        return
    }
    $body = @{ modelDeployments = $desired } | ConvertTo-Json -Depth 4
    Invoke-Cu -Method PATCH -Uri "$Endpoint/contentunderstanding/defaults?api-version=$ApiVersion" -Body $body -Token $Token | Out-Null
    $after = Get-CuDefaults -Token $Token
    $wrong = @($desired.Keys | Where-Object { -not $after -or $after.modelDeployments.$_ -ne $desired[$_] })
    if ($wrong) { throw "Content Understanding defaults did not persist for: $($wrong -join ', ')" }
    Write-Step "defaults   : set ($($desired.Keys -join ', '))"
}

Write-Host "`nContent Understanding analyzer deployment" -ForegroundColor Cyan
Write-Host ("=" * 60)
Write-Step "endpoint   : $Endpoint"
Write-Step "analyzerId : $AnalyzerId"

if (-not (Test-Path $DefinitionPath)) {
    throw "Analyzer definition not found: $DefinitionPath"
}
$definitionRaw = Get-Content $DefinitionPath -Raw
$definition = $definitionRaw | ConvertFrom-Json
$definitionSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $DefinitionPath).Hash

# The service rejects a definition with no completion model deployment, and the
# error does not name the missing property - so fail early and clearly here.
foreach ($required in 'baseAnalyzerId', 'fieldSchema', 'models') {
    if (-not $definition.PSObject.Properties.Name.Contains($required)) {
        throw "Definition is missing required property '$required'. The shippable analyzer must retain 'models' and 'processingLocation'."
    }
}
$headerCount = $definition.fieldSchema.fields.PSObject.Properties.Name.Count
$itemCount = $definition.fieldSchema.fields.items.items.properties.PSObject.Properties.Name.Count
Write-Step "contract   : $headerCount header fields, $itemCount item fields"
Write-Step "models     : completion=$($definition.models.completion) embedding=$($definition.models.embedding)"
Write-Step "definition : $DefinitionPath"
Write-Step "sha256     : $definitionSha256"

$token = Get-CuToken
$RequiredModels.completion.Name = $definition.models.completion
if ($SkipResourcePreparation) {
    Write-Step 'resource   : preparation skipped (-SkipResourcePreparation)'
}
else {
    Initialize-CuResource -Token $token
}
$base = "$Endpoint/contentunderstanding/analyzers/$AnalyzerId"
$existing = Invoke-Cu -Method GET -Uri "$base`?api-version=$ApiVersion" -Token $token -AllowNotFound

if ($existing -and -not $Force) {
    Write-Host "`nRESULT: NoChange - analyzer already exists. Use -Force to replace." -ForegroundColor Yellow
    $current = $existing.Content | ConvertFrom-Json
    Write-Step "status : $($current.status)"
    return
}

if (-not $PSCmdlet.ShouldProcess($AnalyzerId, "Deploy analyzer to $Endpoint")) {
    Write-Host "`nRESULT: WhatIf - validated only, nothing created." -ForegroundColor Yellow
    return
}

if ($existing -and $Force) {
    Write-Step 'existing analyzer found - deleting'
    Invoke-Cu -Method DELETE -Uri "$base`?api-version=$ApiVersion" -Token $token | Out-Null
    Start-Sleep -Seconds 5
}

Write-Step 'creating analyzer'
$response = Invoke-Cu -Method PUT -Uri "$base`?api-version=$ApiVersion" -Body $definitionRaw -Token $token

# PUT returns 201 plus an Operation-Location; the analyzer is NOT usable until
# that operation reports a terminal state.
$operation = $response.Headers['Operation-Location']
if ($operation -is [array]) { $operation = $operation[0] }

if ($operation) {
    Write-Step 'polling creation operation'
    $deadline = (Get-Date).AddMinutes(10)
    do {
        Start-Sleep -Seconds 5
        $state = (Invoke-Cu -Method GET -Uri $operation -Token $token).Content | ConvertFrom-Json
        $status = $state.status
    } while ($status -in @('Running', 'NotStarted') -and (Get-Date) -lt $deadline)

    if ($status -ne 'Succeeded') {
        throw "Analyzer creation did not succeed. Status '$status'. $($state.error.message)"
    }
}

$final = (Invoke-Cu -Method GET -Uri "$base`?api-version=$ApiVersion" -Token $token).Content | ConvertFrom-Json
if ($final.status -ne 'ready') {
    throw "Analyzer deployed but status is '$($final.status)', expected 'ready'."
}
if ($final.description -ne $definition.description) {
    throw "Deployed analyzer description does not match the selected definition file."
}
$expectedLineMethod = $definition.fieldSchema.fields.items.items.properties.linenumber.method
$actualLineMethod = $final.fieldSchema.fields.items.items.properties.linenumber.method
if ($actualLineMethod -ne $expectedLineMethod) {
    throw "Deployed linenumber method is '$actualLineMethod', expected '$expectedLineMethod'."
}

Write-Host "`nRESULT: Deployed - status ready" -ForegroundColor Green
Write-Step "analyzerId : $AnalyzerId"
Write-Step "endpoint   : $Endpoint"
Write-Host "`nSet these environment variables in Power Platform:"
Write-Step "aipod_AzureContentUnderstandingEndpoint   = $Endpoint"
Write-Step "aipod_AzureContentUnderstandingAnalyzerId = $AnalyzerId"
