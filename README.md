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

The Dynamics 365 FastTrack team uses this repository to share Dynamics 365 F&O and Commerce best implementation guidelines. These may be documentation, extension code, business practices etc. 

## Contents

Outline the file contents of the repository. It helps users navigate the codebase, build configuration and any related assets.

| File/folder       | Description                                |
|-------------------|--------------------------------------------|
| `Commerce`        | Dymamics 365 Commerce guides               |
| `Analytics`       | Dymamics 365 Analytics guides              |
| `SQL Maintenance` | Indexes & statistics maintenance script    |
| `Dual-write`      | Dymamics 365 Dual-write guides             |
| `.gitignore`      | Define what to ignore at commit time.      |
| `CHANGELOG.md`    | List of changes to the sample.             |
| `CONTRIBUTING.md` | Guidelines for contributing to the sample. |
| `README.md`       | This README file.                          |
| `LICENSE`         | The license for the sample.                |

### Commerce guides

- [POS UI Negative inventory check/prevention (CRT extension)](https://github.com/microsoft/Dynamics-365-FastTrack-Implementation-Assets/tree/master/Commerce/NegativeInventoryCheck)

### Analytics guides 
- [SQL to data lake export](https://github.com/microsoft/Dynamics-365-FastTrack-Implementation-Assets/blob/master/Analytics/AzureDataFactoryARMTemplates/SQLToADLSFullExport/README.md)

### SQL Maintenance
- [SQL maintenance script](https://github.com/microsoft/Dynamics-365-FastTrack-Implementation-Assets/tree/master/SQL%20Maintenance) - A standalone, tuneable T-SQL script for maintaining SQL Server or Azure SQL indexes and statistics.

### Dual-write
- [Bootstrapping CDS data](https://github.com/microsoft/Dynamics-365-FastTrack-Implementation-Assets/tree/master/Dual-write/Bootstrapping)

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
