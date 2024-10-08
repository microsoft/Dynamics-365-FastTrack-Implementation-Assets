<!--
---
page_type: sample
languages:
- csharp
products:
- dotnet
description: "Add 150 character max description"
urlFragment: "update-this-to-unique-url-stub"
---
-->
# Dynamics 365 FastTrack Implementation Assets

<!-- 
Guidelines on README format: https://review.docs.microsoft.com/help/onboard/admin/samples/concepts/readme-template?branch=master

Guidance on onboarding samples to docs.microsoft.com/samples: https://review.docs.microsoft.com/help/onboard/admin/samples/process/onboarding?branch=master

Taxonomies for products and languages: https://review.docs.microsoft.com/new-hope/information-architecture/metadata/taxonomies?branch=master
-->

The Dynamics 365 FastTrack team uses this repository to share Dynamics 365 Customer Service, Dynamics 365 F&O and Commerce best implementation guidelines. These may be documentation, extension code, business practices etc. 

## Contents

Outline the file contents of the repository. It helps users navigate the codebase, build configuration and any related assets.

| File/folder                            | Description                                |
|----------------------------------------|--------------------------------------------|
| [`Finance`](Finance)                   | Dymamics 365 Finance guides                |
| [`Commerce`](Commerce)                 | Dymamics 365 Commerce guides               |
| [`Analytics`](Analytics)               | Dymamics 365 Analytics guides              |
| [`SQL Maintenance`](SQL%20Maintenance) | Indexes & statistics maintenance script    |
| [`Dual-write`](Dual-write)             | Dymamics 365 Dual-write guides             |
| [`SCM`](SCM)      		                 | Tools for SCM and WHS solutions            |
| [`ScheduleAPI`](ScheduleAPI)	         | Project Operations - Schedule API example  |
| [`PO-DataMigration`](PO-DataMigration) | Project Operations - ADF data migration    |
| [`Cloud security`](CloudSecurity)      | Dynamics 365 Cloud security guides         |
| [`Integration`](Integration)           | Dynamics 365 integration samples           |
| [`Monitoring and Telemetry`](MonitoringandTelemetry)           | Monitoring Dynamics 365 using App Insights           |
| [`Customer Service`](Customer%20Service) | Dynamics 365 Customer Service samples & guides |
| [`BatchTracing`](BatchTracing)         | Tool for cpaturing D365 traces from batch  |
| [`.gitignore`](.gitignore)             | Define what to ignore at commit time.      |
| `CHANGELOG.md`                         | List of changes to the sample.             |
| [`CONTRIBUTING.md`](#contributing)     | Guidelines for contributing to the sample. |
| [`README.md`](Readme.md)               | This README file.                          |
| [`LICENSE`](License)                   | The license for the sample.                |


### Finance guides
- [Finance](https://github.com/microsoft/Dynamics-365-FastTrack-Implementation-Assets/blob/master/Finance) 

### Commerce guides
- [POS UI Negative inventory check/prevention (CRT extension)](https://github.com/microsoft/Dynamics-365-FastTrack-Implementation-Assets/tree/master/Commerce/NegativeInventoryCheck)
- [Ecommerce load test sample](https://github.com/microsoft/Dynamics-365-FastTrack-Implementation-Assets/tree/master/Commerce/CommercePerfTestSample)
- [Dynamics 365 Commerce storefront E2E functional test sample](https://github.com/microsoft/Dynamics-365-FastTrack-Implementation-Assets/tree/master/Commerce/EcommerceE2ETestSample)

### Analytics guides 
- [SQL to data lake export](https://github.com/microsoft/Dynamics-365-FastTrack-Implementation-Assets/blob/master/Analytics/AzureDataFactoryARMTemplates/SQLToADLSFullExport/README.md)
- [Export & Process Entity Store Measures in Azure Synapse](https://github.com/microsoft/Dynamics-365-FastTrack-Implementation-Assets/blob/master/Analytics/EntityStoreTools/README.md)

### SQL Maintenance
- [SQL maintenance script](https://github.com/microsoft/Dynamics-365-FastTrack-Implementation-Assets/tree/master/SQL%20Maintenance)

### Dual-write
- [Bootstrapping CDS data](https://github.com/microsoft/Dynamics-365-FastTrack-Implementation-Assets/tree/master/Dual-write/Bootstrapping)

### SCM Tools
- [Small Parcel Shipping Tools](https://github.com/microsoft/Dynamics-365-FastTrack-Implementation-Assets/tree/master/SCM/SPS) A sample TMS DLL is included for testing SPS scenarios without a live connection to a carrier.

### Project Operations - Schedule API
- [Schedule API](https://github.com/microsoft/Dynamics-365-FastTrack-Implementation-Assets/tree/master/ScheduleAPI) A PowerShell sample to illustrate the Schedule API for Project Operations.
- [PO-DataMigration](https://github.com/microsoft/Dynamics-365-FastTrack-Implementation-Assets/tree/master/PO-DataMigration) An Azure Data Factory sample to illustrate data migration for Project Operations.

### Cloud Security
- [Conditional access](https://github.com/microsoft/Dynamics-365-FastTrack-Implementation-Assets/blob/master/CloudSecurity/ConditionalAccess/readme.md) 

### Integration
- [Integration](https://github.com/microsoft/Dynamics-365-FastTrack-Implementation-Assets/tree/master/Integration) Dynamics 365 integration samples.

### Customer Service
- [Solution Component Validator](/Customer%20Service/ALM) Sample to monitor components in solutions based on Horizontal Solution Segmentation approach.

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
