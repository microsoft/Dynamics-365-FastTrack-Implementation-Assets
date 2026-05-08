# Periodic Maintenance — Secrets, Certificates & Expiration Checks

This document lists credentials, certificates, and time-bound resources that require periodic rotation or renewal to keep the Store Monitoring solution operational.

## Summary Table

| Item                                 | Default Lifetime              | Rotation Method                                   | Recommended Check Cadence           |
| ------------------------------------ | ----------------------------- | ------------------------------------------------- | ----------------------------------- |
| Azure Arc service principal secret   | 24 months                     | Regenerate in Entra ID, update onboarding scripts | Monthly review, rotate at 18 months |
| Azure Arc device certificates        | Auto-renewed by `himds` agent | Automatic (no action unless agent is offline)     | Monthly — verify agent connectivity |
| Log Analytics workspace key          | No expiration (key-based)     | Rotate via Azure Portal if compromised            | Quarterly review                    |
| Copilot Studio connector credentials | Per connector policy          | Re-authenticate in Power Platform                 | Quarterly review                    |
| Managed Identity tokens              | Auto-renewed by Azure         | Automatic (no action)                             | N/A                                 |
