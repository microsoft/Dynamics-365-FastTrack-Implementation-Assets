[CmdletBinding()]
param(
    [string]$ResourceGroup,

    [ValidateNotNullOrEmpty()]
    [string]$ParametersFile,

    [ValidateNotNullOrEmpty()]
    [string]$PromptPath = (Join-Path $PSScriptRoot "assistant-instructions.txt"),

    [string]$ResourceGroupLocation = "canadacentral",

    [string]$DeploymentName = "commerce-assistant-infrastructure",

    [ValidatePattern("^[a-z0-9]{1,8}$")]
    [string]$ResourceSuffix,

    [ValidateNotNullOrEmpty()]
    [string]$Tenant
)

$ErrorActionPreference = "Stop"

function Invoke-AzureCli {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    $output = & az @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Azure CLI command failed: az $($Arguments[0]) $($Arguments[1])"
    }

    return $output
}

function Invoke-AzureDeploymentWithRetry {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments,

        [int]$MaximumAttempts = 6,

        [int]$RetryDelaySeconds = 15
    )

    for ($attempt = 1; $attempt -le $MaximumAttempts; $attempt++) {
        $output = & az @Arguments 2>&1
        $exitCode = $LASTEXITCODE
        if ($exitCode -eq 0) {
            return $output
        }

        $errorText = ($output | ForEach-Object { $_.ToString() }) -join [System.Environment]::NewLine
        $isTransientConflict = $errorText -match "RequestConflict" -and
            $errorText -match "Another operation (is in progress|is being performed)"
        $isTransientConnectionFailure = $errorText -match "RemoteDisconnected|ConnectionResetError|Connection aborted|Connection reset by peer"
        if ((-not $isTransientConflict -and -not $isTransientConnectionFailure) -or $attempt -eq $MaximumAttempts) {
            throw "Azure CLI command failed: az $($Arguments[0]) $($Arguments[1])$([System.Environment]::NewLine)$errorText"
        }

        if ($isTransientConnectionFailure) {
            Write-Warning "The Azure deployment connection was interrupted. Retrying deployment ($attempt/$MaximumAttempts). $errorText"
        }
        else {
            Write-Warning "Azure is still completing another Foundry operation. Retrying deployment ($attempt/$MaximumAttempts)."
        }
        Start-Sleep -Seconds $RetryDelaySeconds
    }
}

function Test-ResourceExists {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ResourceType,

        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    & az resource show `
        --resource-group $ResourceGroup `
        --resource-type $ResourceType `
        --name $Name `
        --query id `
        --output none 2>$null

    return $LASTEXITCODE -eq 0
}

function Get-CollisionSuffix {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Value
    )

    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Value)
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        $hash = $sha256.ComputeHash($bytes)
    }
    finally {
        $sha256.Dispose()
    }

    return ([System.BitConverter]::ToString($hash).Replace("-", "").Substring(0, 6)).ToLowerInvariant()
}

function Test-GlobalNameAvailable {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("apim", "storage", "foundry", "search")]
        [string]$Service,

        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string]$SubscriptionId
    )

    switch ($Service) {
        "apim" {
            $available = Invoke-AzureCli @("apim", "check-name", "--name", $Name, "--query", "nameAvailable", "--output", "tsv")
        }
        "storage" {
            $available = Invoke-AzureCli @("storage", "account", "check-name", "--name", $Name, "--query", "nameAvailable", "--output", "tsv")
        }
        "foundry" {
            $body = (@{ subdomainName = $Name; type = "Microsoft.CognitiveServices/accounts" } | ConvertTo-Json -Compress).Replace('"', '\"')
            $available = Invoke-AzureCli @(
                "rest", "--method", "post",
                "--url", "https://management.azure.com/subscriptions/$SubscriptionId/providers/Microsoft.CognitiveServices/checkDomainAvailability?api-version=2025-06-01",
                "--body", $body,
                "--query", "isSubdomainAvailable",
                "--output", "tsv"
            )
        }
        "search" {
            $available = Invoke-AzureCli @(
                "search", "service", "check-name-availability",
                "--name", $Name,
                "--type", "searchServices",
                "--query", "nameAvailable",
                "--output", "tsv"
            )
        }
    }

    return ($available -join "").Trim() -eq "true"
}

function Resolve-GlobalResourceName {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("apim", "storage", "foundry", "search")]
        [string]$Service,

        [Parameter(Mandatory = $true)]
        [string]$ResourceType,

        [Parameter(Mandatory = $true)]
        [string]$BaseName,

        [Parameter(Mandatory = $true)]
        [string]$SubscriptionId,

        [Parameter(Mandatory = $true)]
        [string]$Suffix
    )

    if ((Test-ResourceExists -ResourceType $ResourceType -Name $BaseName) -or
        (Test-GlobalNameAvailable -Service $Service -Name $BaseName -SubscriptionId $SubscriptionId)) {
        return $BaseName
    }

    $candidate = if ($Service -eq "storage") {
        $storagePrefix = $BaseName.Substring(0, $BaseName.Length - 3)
        "$($storagePrefix.Substring(0, [Math]::Min($storagePrefix.Length, 15)))stg$Suffix"
    }
    else {
        "$BaseName-$Suffix"
    }

    if ((Test-ResourceExists -ResourceType $ResourceType -Name $candidate) -or
        (Test-GlobalNameAvailable -Service $Service -Name $candidate -SubscriptionId $SubscriptionId)) {
        Write-Warning "$BaseName is unavailable; using $candidate."
        return $candidate
    }

    throw "Neither '$BaseName' nor collision-safe name '$candidate' is available for $Service."
}

function Set-FoundryIqResources {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SearchEndpoint,

        [Parameter(Mandatory = $true)]
        [string]$FoundryOpenAIEndpoint,

        [Parameter(Mandatory = $true)]
        [string]$KnowledgeSourceName,

        [Parameter(Mandatory = $true)]
        [string]$KnowledgeBaseName,

        [Parameter(Mandatory = $true)]
        [string]$EmbeddingDeploymentName,

        [Parameter(Mandatory = $true)]
        [string]$EmbeddingModelName,

        [int]$MaximumAttempts = 18,

        [int]$RetryDelaySeconds = 10
    )

    $apiVersion = "2026-08-01-preview"
    $escapedKnowledgeSourceName = [Uri]::EscapeDataString($KnowledgeSourceName)
    $escapedKnowledgeBaseName = [Uri]::EscapeDataString($KnowledgeBaseName)

    for ($attempt = 1; $attempt -le $MaximumAttempts; $attempt++) {
        try {
            $accessToken = Invoke-AzureCli @(
                "account", "get-access-token",
                "--scope", "https://search.azure.com/.default",
                "--query", "accessToken",
                "--output", "tsv"
            )
            $headers = @{
                Authorization = "Bearer $(($accessToken -join '').Trim())"
                Prefer = "return=representation"
            }

            $knowledgeSourceBody = [ordered]@{
                name = $KnowledgeSourceName
                kind = "file"
                description = "Customer-managed Commerce documentation uploaded through Microsoft Foundry."
                fileParameters = [ordered]@{
                    ingestionParameters = [ordered]@{
                        embeddingModel = [ordered]@{
                            kind = "azureOpenAI"
                            azureOpenAIParameters = [ordered]@{
                                resourceUri = $FoundryOpenAIEndpoint.TrimEnd('/')
                                deploymentId = $EmbeddingDeploymentName
                                modelName = $EmbeddingModelName
                            }
                        }
                        contentExtractionMode = "minimal"
                    }
                }
            } | ConvertTo-Json -Depth 10
            $knowledgeSourceUrl = "$($SearchEndpoint.TrimEnd('/'))/knowledgesources/$escapedKnowledgeSourceName`?api-version=$apiVersion"
            Invoke-RestMethod `
                -Method Put `
                -Uri $knowledgeSourceUrl `
                -Headers $headers `
                -ContentType "application/json" `
                -Body $knowledgeSourceBody | Out-Null

            $knowledgeBaseBody = [ordered]@{
                name = $KnowledgeBaseName
                description = "Commerce knowledge base backed by customer-managed files."
                knowledgeSources = @(
                    @{ name = $KnowledgeSourceName }
                )
                outputMode = "extractiveData"
                retrievalReasoningEffort = @{
                    kind = "minimal"
                }
            } | ConvertTo-Json -Depth 10
            $knowledgeBaseUrl = "$($SearchEndpoint.TrimEnd('/'))/knowledgebases/$escapedKnowledgeBaseName`?api-version=$apiVersion"
            Invoke-RestMethod `
                -Method Put `
                -Uri $knowledgeBaseUrl `
                -Headers $headers `
                -ContentType "application/json" `
                -Body $knowledgeBaseBody | Out-Null

            return
        }
        catch {
            if ($attempt -eq $MaximumAttempts) {
                throw
            }

            Write-Warning "Search roles, service, or embedding deployment are still propagating. Retrying Foundry IQ provisioning ($attempt/$MaximumAttempts)."
            Start-Sleep -Seconds $RetryDelaySeconds
        }
    }
}

$scriptDirectory = $PSScriptRoot
$templatePath = Join-Path $scriptDirectory "azuredeploy.json"
$policyPath = Join-Path $scriptDirectory "commerce-assistant-policy.xml"
$attachmentUploadPolicyPath = Join-Path $scriptDirectory "commerce-assistant-attachment-upload-policy.xml"
$attachmentDeletePolicyPath = Join-Path $scriptDirectory "commerce-assistant-attachment-delete-policy.xml"
$resolvedParametersFile = $null
if ($ParametersFile) {
    $resolvedParametersFile = (Resolve-Path -LiteralPath $ParametersFile).Path
    $parameterDocument = Get-Content -LiteralPath $resolvedParametersFile -Raw | ConvertFrom-Json
}
else {
    $parameterDocument = [pscustomobject]@{ parameters = [ordered]@{} }
    $parameterPrompts = [ordered]@{
        apimPublisherEmail = "apimPublisherEmail (API Management publisher email; e.g. admin@contoso.com)"
        retailServerBaseUrl = "retailServerBaseUrl (HTTPS Retail Server URL without a trailing slash; e.g. https://scuvon97iay25090713-rs.su.retail.test.dynamics.com)"
        commerceChannelId = "commerceChannelId (Commerce channel record ID; e.g. 5637144592)"
        posOrigin = "posOrigin (Cloud POS origin: scheme and host only; e.g. https://scuvon97iay25090713-cpos.su.retail.test.dynamics.com)"
    }
    foreach ($parameterName in $parameterPrompts.Keys) {
        do {
            $value = Read-Host -Prompt $parameterPrompts[$parameterName]
            if ([string]::IsNullOrWhiteSpace($value)) {
                Write-Warning "$parameterName is required."
            }
        } while ([string]::IsNullOrWhiteSpace($value))

        $parameterDocument.parameters[$parameterName] = @{ value = $value.Trim() }
    }
}
$resolvedPromptPath = (Resolve-Path -LiteralPath $PromptPath).Path
$promptBytes = [System.IO.File]::ReadAllBytes($resolvedPromptPath)
if ($promptBytes.Length -eq 0) {
    throw "The prompt file must not be empty."
}

$utf8 = [System.Text.UTF8Encoding]::new($false, $true)
$utf8.GetString($promptBytes) | Out-Null
$policy = Get-Content -LiteralPath $policyPath -Raw
$attachmentUploadPolicy = Get-Content -LiteralPath $attachmentUploadPolicyPath -Raw
$attachmentDeletePolicy = Get-Content -LiteralPath $attachmentDeletePolicyPath -Raw
. (Join-Path $scriptDirectory "Assert-CustomerIdentityConfiguration.ps1")
Assert-CustomerIdentityConfiguration -ParameterDocument $parameterDocument
$policy = ConvertTo-CustomerIdentityCorsPolicy -Policy $policy -ParameterDocument $parameterDocument
$attachmentUploadPolicy = ConvertTo-CustomerIdentityCorsPolicy -Policy $attachmentUploadPolicy -ParameterDocument $parameterDocument
$attachmentDeletePolicy = ConvertTo-CustomerIdentityCorsPolicy -Policy $attachmentDeletePolicy -ParameterDocument $parameterDocument
$commerceScaleUnitId = $parameterDocument.parameters.commerceScaleUnitId.value

if ([string]::IsNullOrWhiteSpace($commerceScaleUnitId)) {
    $retailServerBaseUrl = $parameterDocument.parameters.retailServerBaseUrl.value
    try {
        $retailServerHostLabel = ([Uri]$retailServerBaseUrl).Host.Split('.')[0]
    }
    catch {
        throw "retailServerBaseUrl must be an absolute HTTPS URL."
    }

    if ($retailServerHostLabel -notmatch "^(?<scaleUnitId>[a-z0-9]+)-rs$") {
        throw "Cannot derive commerceScaleUnitId from '$retailServerBaseUrl'. Use a standard '<id>-rs' Retail Server hostname or add commerceScaleUnitId to the parameters file."
    }

    $commerceScaleUnitId = $Matches.scaleUnitId
}

if ($commerceScaleUnitId -notmatch "^[a-z0-9]{3,21}$") {
    throw "commerceScaleUnitId must contain 3-21 lowercase letters and numbers. Use the CSU environment ID, for example 'contosocsu01'."
}

$resourceNamePrefix = if ([string]::IsNullOrWhiteSpace($ResourceSuffix)) {
    $commerceScaleUnitId
}
else {
    "$commerceScaleUnitId-$ResourceSuffix"
}
$storagePrefixLength = 21 - $ResourceSuffix.Length
$storageScaleUnitPrefix = $commerceScaleUnitId.Substring(0, [Math]::Min($commerceScaleUnitId.Length, $storagePrefixLength))
$storageAccountBaseName = "$storageScaleUnitPrefix$($ResourceSuffix)stg"

if ([string]::IsNullOrWhiteSpace($ResourceGroup)) {
    $ResourceGroup = "$resourceNamePrefix-mcprg"
}

$requiresLogin = $false
if ($Tenant) {
    $activeTenantOutput = & az account show --query tenantId --output tsv 2>$null
    $requiresLogin = $LASTEXITCODE -ne 0 -or ($activeTenantOutput -join "").Trim() -ne $Tenant
}
$null = & az account get-access-token --output none 2>$null
$requiresLogin = $requiresLogin -or $LASTEXITCODE -ne 0
if ($requiresLogin) {
    Write-Host "Azure CLI sign-in is missing, expired, or for a different tenant. Starting az login."
    $loginArguments = @("login", "--output", "none")
    if ($Tenant) {
        $loginArguments += @("--tenant", $Tenant)
    }
    Invoke-AzureCli -Arguments $loginArguments | Out-Null
    if ($Tenant) {
        $activeTenantOutput = Invoke-AzureCli @("account", "show", "--query", "tenantId", "--output", "tsv")
        if (($activeTenantOutput -join "").Trim() -ne $Tenant) {
            throw "Azure CLI's active subscription is not in tenant '$Tenant'. Select a subscription in the requested tenant before deploying."
        }
    }
    Invoke-AzureCli @("account", "get-access-token", "--output", "none") | Out-Null
}

$subscriptionIdOutput = Invoke-AzureCli @("account", "show", "--query", "id", "--output", "tsv")
$subscriptionId = ($subscriptionIdOutput -join "").Trim()

$null = & az group show --name $ResourceGroup --query id --output none 2>$null
$resourceGroupExists = $LASTEXITCODE -eq 0
if (-not $resourceGroupExists) {
    $resourceGroupOwner = [string]$parameterDocument.parameters.apimPublisherEmail.value
    if ([string]::IsNullOrWhiteSpace($resourceGroupOwner)) {
        throw "apimPublisherEmail is required to set the resource group's Owner tag."
    }

    Invoke-AzureCli @(
        "group", "create",
        "--name", $ResourceGroup,
        "--location", $ResourceGroupLocation,
        "--tags", "Owner=$resourceGroupOwner",
        "--output", "none"
    ) | Out-Null
}

$collisionSuffix = Get-CollisionSuffix -Value "$subscriptionId/$ResourceGroup"
$apimServiceName = Resolve-GlobalResourceName `
    -Service "apim" `
    -ResourceType "Microsoft.ApiManagement/service" `
    -BaseName "$resourceNamePrefix-apim" `
    -SubscriptionId $subscriptionId `
    -Suffix $collisionSuffix
$storageAccountName = Resolve-GlobalResourceName `
    -Service "storage" `
    -ResourceType "Microsoft.Storage/storageAccounts" `
    -BaseName $storageAccountBaseName `
    -SubscriptionId $subscriptionId `
    -Suffix $collisionSuffix
$foundryAccountName = Resolve-GlobalResourceName `
    -Service "foundry" `
    -ResourceType "Microsoft.CognitiveServices/accounts" `
    -BaseName "$resourceNamePrefix-foundry" `
    -SubscriptionId $subscriptionId `
    -Suffix $collisionSuffix
$searchServiceName = Resolve-GlobalResourceName `
    -Service "search" `
    -ResourceType "Microsoft.Search/searchServices" `
    -BaseName "$resourceNamePrefix-search" `
    -SubscriptionId $subscriptionId `
    -Suffix $collisionSuffix

$publisherPrincipalId = Invoke-AzureCli @(
    "ad", "signed-in-user", "show",
    "--query", "id",
    "--output", "tsv"
)

$runtimeParametersPath = Join-Path ([System.IO.Path]::GetTempPath()) "commerce-assistant-$([Guid]::NewGuid().ToString('N')).parameters.json"
$runtimeParameters = [ordered]@{
    '$schema' = "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#"
    contentVersion = "1.0.0.0"
    parameters = [ordered]@{
        commerceAssistantPolicy = @{ value = $policy }
        commerceAssistantAttachmentUploadPolicy = @{ value = $attachmentUploadPolicy }
        commerceAssistantAttachmentDeletePolicy = @{ value = $attachmentDeletePolicy }
        promptPublisherPrincipalId = @{ value = ($publisherPrincipalId -join "").Trim() }
        apimServiceName = @{ value = $apimServiceName }
        storageAccountName = @{ value = $storageAccountName }
        foundryAccountName = @{ value = $foundryAccountName }
        searchServiceName = @{ value = $searchServiceName }
        foundryProjectName = @{ value = "$resourceNamePrefix-assistant" }
        assistantContainerName = @{ value = if ([string]::IsNullOrWhiteSpace($ResourceSuffix)) { "assistant-config" } else { "assistant-config-$ResourceSuffix" } }
    }
}
$armDeploymentName = if ([string]::IsNullOrWhiteSpace($ResourceSuffix)) { $DeploymentName } else { "$DeploymentName-$ResourceSuffix" }

if (-not $resolvedParametersFile) {
    foreach ($parameterName in $parameterDocument.parameters.Keys) {
        $runtimeParameters.parameters[$parameterName] = $parameterDocument.parameters[$parameterName]
    }
}

try {
    $runtimeParametersJson = $runtimeParameters | ConvertTo-Json -Depth 5
    [System.IO.File]::WriteAllText($runtimeParametersPath, $runtimeParametersJson, [System.Text.UTF8Encoding]::new($false))
    $deploymentArguments = @(
        "deployment", "group", "create",
        "--name", $armDeploymentName,
        "--resource-group", $ResourceGroup,
        "--template-file", $templatePath,
        "--parameters"
    )
    if ($resolvedParametersFile) {
        $deploymentArguments += "@$resolvedParametersFile"
    }
    $deploymentArguments += @(
        "@$runtimeParametersPath",
        "--query", "properties.outputs",
        "--output", "json"
    )
    $deploymentOutput = Invoke-AzureDeploymentWithRetry -Arguments $deploymentArguments

    $outputs = ($deploymentOutput -join [System.Environment]::NewLine) | ConvertFrom-Json
}
finally {
    Remove-Item -LiteralPath $runtimeParametersPath -Force -ErrorAction SilentlyContinue
}

Set-FoundryIqResources `
    -SearchEndpoint $outputs.searchServiceEndpoint.value `
    -FoundryOpenAIEndpoint $outputs.foundryOpenAIEndpoint.value `
    -KnowledgeSourceName $outputs.foundryIqKnowledgeSourceName.value `
    -KnowledgeBaseName $outputs.foundryIqKnowledgeBaseName.value `
    -EmbeddingDeploymentName $outputs.embeddingDeploymentName.value `
    -EmbeddingModelName $outputs.embeddingModelName.value

$storageAccountName = ([Uri]$outputs.assistantBlobUrl.value).Host.Split('.')[0]
$blobPath = ([Uri]$outputs.assistantBlobUrl.value).AbsolutePath.TrimStart('/').Split('/', 2)

$maximumAttempts = 12
for ($attempt = 1; $attempt -le $maximumAttempts; $attempt++) {
    try {
        Invoke-AzureCli @(
            "storage", "blob", "upload",
            "--account-name", $storageAccountName,
            "--container-name", $blobPath[0],
            "--name", $blobPath[1],
            "--file", $resolvedPromptPath,
            "--auth-mode", "login",
            "--overwrite", "true",
            "--content-type", "text/plain; charset=utf-8",
            "--output", "none"
        ) | Out-Null

        break
    }
    catch {
        if ($attempt -eq $maximumAttempts) {
            throw
        }

        Write-Warning "Blob role assignment is still propagating. Retrying prompt upload ($attempt/$maximumAttempts)."
        Start-Sleep -Seconds 10
    }
}

Write-Output "Deployed $($promptBytes.Length) prompt bytes to the private assistant configuration blob."
$outputs | ConvertTo-Json -Depth 10
