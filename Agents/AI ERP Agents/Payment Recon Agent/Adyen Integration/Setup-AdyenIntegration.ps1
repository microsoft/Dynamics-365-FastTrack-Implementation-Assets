<#
.SYNOPSIS
    Provisions the Azure resources for the Adyen webhook integration and returns
    the Entra app credentials to configure in Power Automate.

.DESCRIPTION
    Creates (idempotently) a resource group, a Key Vault (named `<prefix>-adyen-kv` from a
    prompted prefix), a secret placeholder for
    the Adyen Report User API key, and an Entra app registration / service principal
    granted "Key Vault Secrets User" on the vault. On completion it prints the
    Tenant ID, Client ID, and Client Secret to paste into the Power Automate
    connection.

    Requires the Azure CLI (`az`) to be installed. If you are not already signed in,
    the script runs `az login` for you, then lets you pick the target subscription.

.NOTES
    The client secret is shown only once - copy it immediately.
#>

[CmdletBinding()]
param(
    [string]$SubscriptionId,
    [string]$Prefix,
    [string]$ResourceGroup = "PaymentReconIntegration",
    [string]$KeyVaultName,
    [string]$SecretName    = "ReportUserAPIKey",
    [string]$SecretValue   = "PLACEHOLDER-UPDATE-AFTER-ADYEN-SETUP",
    [string]$Location      = "westeurope",
    [string]$AppName       = "PowerAutomate-AdyenWebhook"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Ensure the Azure CLI is available.
if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    throw "Azure CLI ('az') was not found on PATH. Install it from https://aka.ms/installazurecli and try again."
}

# Always sign in fresh so you can choose / switch the account each run. Clearing
# any cached accounts first ensures a previously used identity (e.g. an SSO
# browser session) is not silently reused, and that the subscription menu shows
# only the account you actually sign in with.
Write-Host "Clearing any cached Azure sessions..."
az logout 2>$null | Out-Null
az account clear 2>$null | Out-Null

Write-Host "Signing in to Azure (a browser window will open - pick the account you want)..."
az login --output none
if ($LASTEXITCODE -ne 0) {
    throw "Azure sign-in failed. Run 'az login' manually and try again."
}
$signedInAs = az account show --query user.name --output tsv
Write-Host "Signed in as: $signedInAs"

# Select the subscription: if not supplied (or still the placeholder), present a
# numbered menu of the subscriptions available to the signed-in account.
if ([string]::IsNullOrWhiteSpace($SubscriptionId) -or $SubscriptionId -like "*your-azure-subscription-id*") {
    Write-Host "Fetching available subscriptions..."
    $subs = az account list --all --query "[?state=='Enabled'].{Name:name, Id:id, IsDefault:isDefault}" --output json 2>$null | ConvertFrom-Json

    if (-not $subs -or @($subs).Count -eq 0) {
        throw "No enabled subscriptions found for the signed-in account. Run 'az login' and try again."
    }
    $subs = @($subs)

    if ($subs.Count -eq 1) {
        $SubscriptionId = $subs[0].Id
        Write-Host "Using the only available subscription: $($subs[0].Name) ($SubscriptionId)"
    } else {
        Write-Host ""
        Write-Host "Available subscriptions:"
        for ($i = 0; $i -lt $subs.Count; $i++) {
            $marker = if ($subs[$i].IsDefault) { " (current default)" } else { "" }
            Write-Host ("  [{0}] {1}  -  {2}{3}" -f ($i + 1), $subs[$i].Name, $subs[$i].Id, $marker)
        }
        Write-Host ""

        while ($true) {
            $choice = Read-Host ("Select a subscription (1-{0})" -f $subs.Count)
            $index = 0
            if ([int]::TryParse($choice, [ref]$index) -and $index -ge 1 -and $index -le $subs.Count) {
                $SubscriptionId = $subs[$index - 1].Id
                Write-Host "Selected: $($subs[$index - 1].Name) ($SubscriptionId)"
                break
            }
            Write-Host "Invalid selection. Enter a number between 1 and $($subs.Count)." -ForegroundColor Yellow
        }
    }
}
if ([string]::IsNullOrWhiteSpace($SubscriptionId)) {
    throw "A valid Azure Subscription ID is required."
}

Write-Host "Setting subscription..."
az account set --subscription $SubscriptionId
$TenantId = az account show --query tenantId --output tsv
if ([string]::IsNullOrWhiteSpace($TenantId)) { throw "Could not determine the tenant for the selected subscription." }

# Derive the Key Vault name from a prefix (prompted if not supplied). Azure Key
# Vault names must be 3-24 chars, start with a letter, contain only letters,
# digits and hyphens, and be globally unique.
if ([string]::IsNullOrWhiteSpace($KeyVaultName)) {
    if ([string]::IsNullOrWhiteSpace($Prefix)) {
        while ($true) {
            $Prefix = (Read-Host "Enter a prefix for the Key Vault (3-15 lowercase letters/numbers, must start with a letter)").Trim().ToLowerInvariant()
            if ($Prefix -match '^[a-z][a-z0-9]{2,14}$') { break }
            Write-Host "Invalid prefix. Use 3-15 lowercase letters/numbers, starting with a letter." -ForegroundColor Yellow
        }
    } else {
        $Prefix = $Prefix.Trim().ToLowerInvariant()
        if ($Prefix -notmatch '^[a-z][a-z0-9]{2,14}$') {
            throw "Invalid -Prefix '$Prefix'. Use 3-15 lowercase letters/numbers, starting with a letter."
        }
    }
    $KeyVaultName = "$Prefix-adyen-kv"
}
if ($KeyVaultName.Length -gt 24 -or $KeyVaultName -notmatch '^[a-zA-Z][a-zA-Z0-9-]{1,22}[a-zA-Z0-9]$') {
    throw "Derived Key Vault name '$KeyVaultName' is invalid (must be 3-24 chars, start with a letter, letters/digits/hyphens only). Try a shorter prefix."
}
Write-Host "Key Vault name: $KeyVaultName"

$script:GraphLoggedIn = $false
function Invoke-GraphLogin {
    if ($script:GraphLoggedIn) { return }
    # Try to get a Graph token silently for THIS tenant first (no prompt if the
    # current session already covers it). Only fall back to an interactive login
    # scoped to the selected tenant, so unrelated MFA-guarded tenants are not
    # enumerated (which was causing 'Status_InteractionRequired' failures).
    az account get-access-token --resource https://graph.microsoft.com --tenant $TenantId --output none 2>$null
    if ($LASTEXITCODE -eq 0) { $script:GraphLoggedIn = $true; return }

    Write-Host "One more sign-in is needed for Microsoft Graph (to register the app)..."
    az login --scope https://graph.microsoft.com//.default --tenant $TenantId --output none
    if ($LASTEXITCODE -ne 0) {
        throw "Microsoft Graph sign-in failed. Run 'az login --scope https://graph.microsoft.com//.default --tenant $TenantId' manually and retry."
    }
    $script:GraphLoggedIn = $true
}

Write-Host "Creating resource group..."
az group create --name $ResourceGroup --location $Location --output none
if ($LASTEXITCODE -ne 0) { throw "Failed to create resource group '$ResourceGroup'." }

Write-Host "Creating Key Vault..."
az keyvault create --name $KeyVaultName --resource-group $ResourceGroup --location $Location --enable-rbac-authorization true --output none
if ($LASTEXITCODE -ne 0) { throw "Failed to create Key Vault '$KeyVaultName' (the name must be globally unique - try a different prefix)." }

# Write the secret via the ARM CONTROL plane (a nested deployment) rather than
# the Key Vault data plane. Control-plane writes use your Contributor/Owner
# rights on the resource group and take effect immediately, so we avoid the
# multi-minute wait for Key Vault data-plane RBAC to propagate.
Write-Host "Adding secret to Key Vault (via control plane)..."
$secretTemplate = [ordered]@{
    '$schema'      = 'https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#'
    contentVersion = '1.0.0.0'
    resources      = @(
        [ordered]@{
            type       = 'Microsoft.KeyVault/vaults/secrets'
            apiVersion = '2023-07-01'
            name       = "$KeyVaultName/$SecretName"
            properties = [ordered]@{ value = $SecretValue }
        }
    )
} | ConvertTo-Json -Depth 10

$tmplFile = Join-Path ([System.IO.Path]::GetTempPath()) ("kvsecret-{0}.json" -f ([guid]::NewGuid().ToString('N')))
Set-Content -Path $tmplFile -Value $secretTemplate -Encoding utf8
az deployment group create --resource-group $ResourceGroup --template-file $tmplFile --only-show-errors --output none
$secretOk = ($LASTEXITCODE -eq 0)
Remove-Item $tmplFile -Force -ErrorAction SilentlyContinue
if (-not $secretOk) {
    throw "Failed to create secret '$SecretName' in '$KeyVaultName'. Ensure you have Contributor on resource group '$ResourceGroup'."
}

Write-Host "Creating Entra App Registration..."
$kvScope = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.KeyVault/vaults/$KeyVaultName"

$spJson = az ad sp create-for-rbac --name $AppName --role "Key Vault Secrets User" --scopes $kvScope --years 2 2>$null
if ($LASTEXITCODE -ne 0) {
    # App registration requires Microsoft Graph - re-authenticate for Graph and retry once.
    Invoke-GraphLogin
    $spJson = az ad sp create-for-rbac --name $AppName --role "Key Vault Secrets User" --scopes $kvScope --years 2
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to create the app registration '$AppName'. Your account may not be permitted to register applications in this tenant."
    }
}
$result = $spJson | ConvertFrom-Json
if (-not $result -or -not ($result.PSObject.Properties.Name -contains 'appId')) { throw "App registration did not return credentials." }

Write-Host ""
Write-Host "Done! Use these values in Power Automate:"
Write-Host "----------------------------------------------"
Write-Host "Tenant ID:     $($result.tenant)"
Write-Host "Client ID:     $($result.appId)"
Write-Host "Client Secret: $($result.password)"
Write-Host "----------------------------------------------"
Write-Host "IMPORTANT: Copy the client_secret now - it will not be shown again"
