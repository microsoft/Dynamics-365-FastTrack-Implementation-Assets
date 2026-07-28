# Adyen Integration

Azure setup for the **Adyen webhook → Power Automate** integration used by the Payment Recon Agent.

## Contents

```
Setup-AdyenIntegration.cmd              double-click launcher (calls the PowerShell script)
Setup-AdyenIntegration.ps1              provisions Azure resources + returns app credentials
AdyenPaymentFileIntegration_1_0_0_2.zip Power Platform solution for the Adyen file integration
README.pdf                              detailed integration walkthrough
```

## What the setup does

Idempotently provisions, via the **Azure CLI**:

1. Resource group `PaymentReconIntegration`
2. Key Vault `PaymentReconkeyvault` (RBAC-enabled)
3. Secret `ReportUserAPIKey` (placeholder — update after Adyen setup)
4. An Entra app registration / service principal granted **Key Vault Secrets User**

On completion it prints the **Tenant ID**, **Client ID**, and **Client Secret** to configure in the
Power Automate connection. *The client secret is shown only once — copy it immediately.*

## Prerequisites

- **Azure CLI** (`az`) installed. If you're not already signed in, the script runs `az login` for you.
- Permission to create resources and app registrations in the target subscription/tenant.

## Run it

Double-click **`Setup-AdyenIntegration.cmd`**, or from PowerShell:

```powershell
.\Setup-AdyenIntegration.ps1
```

The script signs you in, then lists the subscriptions available to your account and lets you
**pick one from a numbered menu** — no subscription ID to look up or paste. It then asks for a short
**prefix** and creates the Key Vault as `<prefix>-adyen-kv` (you can still pass `-KeyVaultName "<name>"`
or `-Prefix "<prefix>"` to skip the prompt). All other values (resource group, location, etc.) have
sensible defaults and can be overridden via parameters. See **README.pdf** for the full walkthrough,
including the Adyen-side configuration.
