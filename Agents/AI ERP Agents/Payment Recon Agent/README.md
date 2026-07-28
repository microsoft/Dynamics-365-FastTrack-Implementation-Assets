# Payment Recon V2

This repository contains the **Payment Recon Agent** — automated payment reconciliation for
**Microsoft Dynamics 365 Commerce**, running on **Microsoft Azure** and **Microsoft Power Platform**.

## Repository layout

```
PaymentReconAgent/                     the agent solution + deployment package
├─ README.md                           agent overview & architecture
├─ INSTALL.md                          quick-start install notes
├─ Deployment/                         scripts, ARM templates, SQL, and the Power Platform solution
│  ├─ Install-PaymentRecon.cmd         primary installer entry point
│  ├─ DEPLOYMENT.md                    full step-by-step deployment guide
│  └─ Solutions/                       merged Power Platform solution (.zip)
└─ Samples/                            sample CSV files for validation

PaymentTransactionDataExport/          Dynamics 365 F&O project (.axpp) to export payment transactions

Adyen Integration/                     Azure setup for the Adyen webhook → Power Automate integration
├─ Setup-AdyenIntegration.cmd          launcher for the Azure setup script
├─ Setup-AdyenIntegration.ps1          provisions Key Vault + Entra app, returns credentials
└─ AdyenPaymentFileIntegration_*.zip   Power Platform solution for the Adyen file integration
```

## Where to start

| I want to… | Go to |
|------------|-------|
| Understand what the agent does | [PaymentReconAgent/README.md](PaymentReconAgent/README.md) |
| Deploy it end-to-end | [PaymentReconAgent/Deployment/DEPLOYMENT.md](PaymentReconAgent/Deployment/DEPLOYMENT.md) |
| Quick install notes | [PaymentReconAgent/INSTALL.md](PaymentReconAgent/INSTALL.md) |
| Export payment data from D365 F&O | [PaymentTransactionDataExport/README.md](PaymentTransactionDataExport/README.md) |
| Set up the Adyen integration | [Adyen Integration/README.md](Adyen%20Integration/README.md) |
