[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName,

    [Parameter(Mandatory = $true)]
    [string]$WorkspaceResourceId,

    [string]$Location,

    [string]$AlertRuleName = 'store-monitoring-device-offline',

    [int]$OfflineThresholdMinutes = 5,

    [int]$ActiveDeviceLookbackDays = 7,

    [bool]$BusinessHoursOnly = $true,

    [ValidateRange(0, 23)]
    [int]$BusinessHoursStartHourUtc = 8,

    [ValidateRange(0, 23)]
    [int]$BusinessHoursEndHourUtc = 17,

    [int]$Severity = 2,

    [string]$EvaluationFrequency = 'PT5M',

    [string]$WindowSize = 'PT5M',

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
$templateFile = Join-Path $deployRoot 'device-offline-alert.bicep'

if (-not (Test-Path -LiteralPath $templateFile)) {
    throw "Template file not found: $templateFile"
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

$deploymentName = 'store-monitoring-device-offline-alert-{0}' -f (Get-Date -Format 'yyyyMMddHHmmss')
$parameterFile = Join-Path ([System.IO.Path]::GetTempPath()) "$deploymentName.parameters.json"

$parameters = @{
    '$schema'      = 'https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#'
    contentVersion = '1.0.0.0'
    parameters     = @{
        workspaceResourceId       = @{ value = $WorkspaceResourceId }
        location                  = @{ value = $Location }
        alertRuleName             = @{ value = $AlertRuleName }
        offlineThresholdMinutes   = @{ value = $OfflineThresholdMinutes }
        activeDeviceLookbackDays  = @{ value = $ActiveDeviceLookbackDays }
        businessHoursOnly         = @{ value = $BusinessHoursOnly }
        businessHoursStartHourUtc = @{ value = $BusinessHoursStartHourUtc }
        businessHoursEndHourUtc   = @{ value = $BusinessHoursEndHourUtc }
        severity                  = @{ value = $Severity }
        evaluationFrequency       = @{ value = $EvaluationFrequency }
        windowSize                = @{ value = $WindowSize }
        actionGroupResourceIds    = @{ value = $ActionGroupResourceIds }
        alertFunctionWebhookUri   = @{ value = $AlertFunctionWebhookUri }
        actionGroupName           = @{ value = $ActionGroupName }
        actionGroupShortName      = @{ value = $ActionGroupShortName }
        skipQueryValidation       = @{ value = [bool]$SkipQueryValidation }
    }
}

try {
    $parameters | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $parameterFile -Encoding utf8

    $deploymentCommand = if ($WhatIf) { 'what-if' } else { 'create' }
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
        "@$parameterFile",
        '--only-show-errors'
    )

    az @azArgs
}
finally {
    Remove-Item -LiteralPath $parameterFile -Force -ErrorAction SilentlyContinue
}