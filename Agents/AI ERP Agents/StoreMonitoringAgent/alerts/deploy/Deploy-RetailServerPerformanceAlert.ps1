[CmdletBinding()]
param(
    [string]$ParameterFile,

    [string]$ResourceGroupName,

    [string]$WorkspaceResourceId,

    [string]$Location,

    [string]$AlertRuleName = 'store-monitoring-retail-server-performance',

    [int]$PerformanceThresholdMs = 10000,

    [string]$QueryLookback = '10m',

    [int]$Severity = 2,

    [string]$EvaluationFrequency = 'PT5M',

    [string]$WindowSize = 'PT10M',

    [string[]]$ActionGroupResourceIds = @(),

    [string]$AlertFunctionWebhookUri = '',

    [string]$ActionGroupName = 'store-monitoring-agent-alerts',

    [string]$ActionGroupShortName = 'SMAgent',

    [switch]$SkipQueryValidation,

    [switch]$WhatIf
)

$ErrorActionPreference = 'Stop'

if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    throw 'Azure CLI (az) was not found. Install Azure CLI and run az login before using this deployment script.'
}

$deployRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$templateFile = Join-Path $deployRoot 'retail-server-performance-alert.bicep'

if (-not (Test-Path -LiteralPath $templateFile)) {
    throw "Template file not found: $templateFile"
}

if ([string]::IsNullOrWhiteSpace($ParameterFile)) {
    $ParameterFile = Join-Path $deployRoot 'retail-server-performance-alert.parameters.json'
}

$ParameterFile = (Resolve-Path -LiteralPath $ParameterFile).Path

$parameterFileValues = @{}
if (Test-Path -LiteralPath $ParameterFile) {
    $parameterFileJson = Get-Content -LiteralPath $ParameterFile -Raw | ConvertFrom-Json
    foreach ($parameter in $parameterFileJson.parameters.PSObject.Properties) {
        $parameterFileValues[$parameter.Name] = $parameter.Value.value
    }
}
else {
    throw "Parameter file not found: $ParameterFile"
}

if ([string]::IsNullOrWhiteSpace($WorkspaceResourceId) -and $parameterFileValues.ContainsKey('workspaceResourceId')) {
    $WorkspaceResourceId = [string]$parameterFileValues['workspaceResourceId']
}

if ([string]::IsNullOrWhiteSpace($ResourceGroupName) -and -not [string]::IsNullOrWhiteSpace($WorkspaceResourceId)) {
    $resourceGroupMatch = [regex]::Match($WorkspaceResourceId, '/resourceGroups/([^/]+)', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if ($resourceGroupMatch.Success) {
        $ResourceGroupName = $resourceGroupMatch.Groups[1].Value
    }
}

if ([string]::IsNullOrWhiteSpace($Location) -and $parameterFileValues.ContainsKey('location')) {
    $Location = [string]$parameterFileValues['location']
}

if ([string]::IsNullOrWhiteSpace($ResourceGroupName)) {
    throw 'Unable to determine resource group. Pass -ResourceGroupName or set parameters.workspaceResourceId.value in the parameter file.'
}

if ([string]::IsNullOrWhiteSpace($WorkspaceResourceId)) {
    throw 'Unable to determine workspace resource ID. Pass -WorkspaceResourceId or set parameters.workspaceResourceId.value in the parameter file.'
}

$accountJson = az account show --only-show-errors 2>$null
if (-not $accountJson) {
    throw 'Azure CLI is not logged in. Run az login and select the target subscription before deploying.'
}

if ([string]::IsNullOrWhiteSpace($Location)) {
    $Location = az group show --name $ResourceGroupName --query location --output tsv --only-show-errors
}

if ([string]::IsNullOrWhiteSpace($Location)) {
    throw 'Unable to determine deployment location. Pass -Location explicitly.'
}

$deploymentName = 'store-monitoring-retail-server-performance-alert-{0}' -f (Get-Date -Format 'yyyyMMddHHmmss')
$deploymentCommand = if ($WhatIf) { 'what-if' } else { 'create' }
$parameterOverrides = @()

if (-not [string]::IsNullOrWhiteSpace($AlertFunctionWebhookUri)) {
    $parameterOverrides += 'alertFunctionWebhookUri={0}' -f $AlertFunctionWebhookUri
}

$azArgs = @(
    'deployment',
    'group',
    $deploymentCommand,
    '--resource-group',
    $ResourceGroupName,
    '--name',
    $deploymentName,
    '--template-file',
    $templateFile,
    '--parameters',
    "@$ParameterFile",
    $parameterOverrides,
    '--only-show-errors'
)

az @azArgs