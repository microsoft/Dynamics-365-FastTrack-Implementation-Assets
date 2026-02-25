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
| [`Finance`](ERP/Finance)                   | Dynamics 365 Finance guides                |
| [`Commerce`](ERP/Commerce)                 | Dynamics 365 Commerce guides               |
| [`Analytics`](Administration/Analytics)               | Dynamics 365 Analytics guides              |
| [`SQL Maintenance`](Administration/SQL%20Maintenance) | Indexes & statistics maintenance script    |
| [`Storage Management`](Administration/Storage%20Management) | Data cleanup scripts    |
| [`Dual-write`](Administration/Dual-write)             | Dynamics 365 Dual-write guides             |
| [`SCM`](ERP/SCM)      		                 | Tools for SCM and WHS solutions            |
| [`ScheduleAPI`](Administration/ScheduleAPI)	         | Project Operations - Schedule API example  |
| [`PO-DataMigration`](Administration/PO-DataMigration) | Project Operations - ADF data migration    |
| [`Cloud security`](Administration/CloudSecurity)      | Dynamics 365 Cloud security guides         |
| [`Integration`](Administration/Integration)           | Dynamics 365 integration samples           |
| [`Monitoring and Telemetry`](Administration/MonitoringAndTelemetry)           | Monitoring Dynamics 365 using App Insights           |
| [`Customer Service`](Customer%20Service/Customer%20Service) | Dynamics 365 Customer Service samples & guides |
| [`Field Service`](Customer%20Service/Field%20Service) | Dynamics 365 Field Service samples & guides |
| [`BatchTracing`](Administration/BatchTracing)         | Tool for capturing D365 traces from batch  |
| [`.gitignore`](.gitignore)             | Define what to ignore at commit time.      |
| `CHANGELOG.md`                         | List of changes to the sample.             |
| [`CONTRIBUTING.md`](#contributing)     | Guidelines for contributing to the sample. |
| [`README.md`](Readme.md)               | This README file.                          |
| [`LICENSE`](License)                   | The license for the sample.                |


### Finance guides
- [Finance](ERP/Finance) 

### Commerce guides
- [POS UI Negative inventory check/prevention (CRT extension)](ERP/Commerce/NegativeInventoryCheck)
- [Ecommerce load test sample](ERP/Commerce/CommercePerfTestSample)
- [Dynamics 365 Commerce storefront E2E functional test sample](ERP/Commerce/EcommerceE2ETestSample)

### Analytics guides 
- [SQL to data lake export](Administration/Analytics/AzureDataFactoryARMTemplates/SQLToADLSFullExport/README.md)
- [Export & Process Entity Store Measures in Azure Synapse](Administration/Analytics/EntityStoreTools/readme.md)

### SQL Maintenance
- [SQL maintenance script](Administration/SQL%20Maintenance)

### Dual-write
- [Bootstrapping CDS data](Administration/Dual-write/Bootstrapping)

### SCM Tools
- [Small Parcel Shipping Tools](ERP/SCM/SPS) A sample TMS DLL is included for testing SPS scenarios without a live connection to a carrier.

### Project Operations - Schedule API
- [Schedule API](Administration/ScheduleAPI) A PowerShell sample to illustrate the Schedule API for Project Operations.
- [PO-DataMigration](Administration/PO-DataMigration) An Azure Data Factory sample to illustrate data migration for Project Operations.

### Cloud Security
- [Conditional access](Administration/CloudSecurity/ConditionalAccess/readme.md) 

### Integration
- [Integration](Administration/Integration) Dynamics 365 integration samples.

### Customer Service
- [Solution Component Validator](/Customer%20Service/ALM) Sample to monitor components in solutions based on Horizontal Solution Segmentation approach.

### Field Service
- [Schedule Board Settings Management PCF Control](Customer%20Service/Field%20Service/Component%20Library/URS/ScheduleBoardSettingsManagement) A PCF control created to help manage Schedule Board Settings records, including viewing details about each attribute, copying boards, deleting boards, disabling/enabling boards, and opening the board record form.
- [Schedule Board Settings Management PCF Control (Virtual)](Customer%20Service/Field%20Service/Component%20Library/URS/ScheduleBoardSettingsManagement_Virtual) A variant of the Schedule Board Settings Management PCF control built using the virtual PCF control framework for faster load times and bundle.js size reduction.
- [Azure DevOps Sample Pipelines](Customer%20Service/Field%20Service/ALM/Azure%20DevOps%20Sample%20Pipelines) Azure DevOps export and import sample pipelines for Dataverse (not Field Service-specific) to help you easily implement healthy ALM practices and move away from manual solution deployment processes.

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
