# Finance and Supply Chain Management Monitoring and Telemetry using Application Insights
The monitoring and telemetry feature in finance and operations apps is a direct, point-to-point integration between an instance of a 
finance and operations app and the target Application Insights destination. This feature lets developers and admins triage and resolve 
application issues in near-real time. The telemetry that's generated isn't collected by Microsoft for support or other operational reporting. 
Instead, the data is customer owned and customer driven.

Get started by following the documentation on MSLearn: [Monitoring and telemetry using Application Insights](https://learn.microsoft.com/en-us/dynamics365/fin-ops-core/dev-itpro/sysadmin/monitoring-and-telemetry-appinsights)

For specific guidelines on Warehouse Management telemetry, documentation can be found on MSLearn:
- [Enable warehousing telemetry with Application Insights](https://learn.microsoft.com/en-us/dynamics365/supply-chain/warehousing/application-insights-warehousing)
- [Monitor Warehouse Management usage and performance](https://learn.microsoft.com/en-us/dynamics365/supply-chain/warehousing/application-insights-monitor-usage-performance)

# What resources can I find in this repository?
This repository contains instructions on how to gather telemetry from Dynamics 365 Supply Chain Management product.
The telemetry is sent to the customer owned Application Insights instance.

| Area  | Description  | Take me there (use CTRL+click to open in a new tab) |
| ------ | ------ | ------ |
| Kusto queries | A repository of queries to consult Application Insights telemetry | [Alerting on telemetry](kusto queries) |
| Dashboards\Azure Data Explorer | Making interactive dashboards in Azure Data Explorer with data from Azure Application Insights | [Using Excel with telemetry](dashboards/Azure Data Explorer) |

## Contributing

This project welcomes contributions and suggestions.  Most contributions require you to agree to a
Contributor License Agreement (CLA) declaring that you have the right to, and actually do, grant us
the rights to use your contribution. For details, visit https://cla.opensource.microsoft.com.

When you submit a pull request, a CLA bot will automatically determine whether you need to provide
a CLA and decorate the PR appropriately (e.g., status check, comment). Simply follow the instructions
provided by the bot. You will only need to do this once across all repos using our CLA.

This project has adopted the [Microsoft Open Source Code of Conduct](https://opensource.microsoft.com/codeofconduct/).
For more information see the [Code of Conduct FAQ](https://opensource.microsoft.com/codeofconduct/faq/) or
contact [opencode@microsoft.com](mailto:opencode@microsoft.com) with any additional questions or comments.

## Trademarks

This project may contain trademarks or logos for projects, products, or services. Authorized use of Microsoft 
trademarks or logos is subject to and must follow 
[Microsoft's Trademark & Brand Guidelines](https://www.microsoft.com/en-us/legal/intellectualproperty/trademarks/usage/general).
Use of Microsoft trademarks or logos in modified versions of this project must not cause confusion or imply Microsoft sponsorship.
Any use of third-party trademarks or logos are subject to those third-party's policies.