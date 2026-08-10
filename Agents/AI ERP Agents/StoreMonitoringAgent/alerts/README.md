# Alerts

This folder contains alert-triggered integrations for the Store Monitoring Agent.

## Projects

- [StoreMonitoringAlertFunction](StoreMonitoringAlertFunction): .NET 8 Azure Functions app that receives Azure Monitor alert HTTP POSTs and relays them to a Copilot Studio Agent Flow using service principal authentication. Setup, deployment, and security guidance are documented in [Alert-Triggered Agent](../docs/alert-triggered-agent.md).
