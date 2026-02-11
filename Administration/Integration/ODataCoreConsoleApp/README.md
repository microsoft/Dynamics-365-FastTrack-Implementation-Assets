<!--
---
page_type: sample
languages:
- csharp
products:
- dynamics-finance-operations
- dotnet-core

description: "Dynamics 365 for Finance and Operations sample OData console application"
urlFragment: "d365-fo-odata-console"
---
-->
# Dynamics 365 for Finance and Operations sample OData console application

Conceptually, this asset is similar to the OData console application sample provided at [Dynamics-AX-Integration OData Console Application](https://github.com/microsoft/Dynamics-AX-Integration/tree/master/ServiceSamples/ODataConsoleApplication). 
Instead of the older client libraries used in the previous sample, it has been written to take advantage of the modern [OData Connected Service](https://github.com/odata/ODataConnectedService), 
.Net Core and supporting NuGet packages.

You will need to add the Connected service as described at https://learn.microsoft.com/en-us/odata/client/getting-started#using-the-odata-connected-service.

# Contents
| File/folder | Description |
|-------------|-------------|
| `README.md` | This README file. |
| `ODataCoreConsoleApp.csproj` | Visual Studio 2022 project definition. |
| `AuthenticationConfig.cs` | Utility class for EntraId authentication using the web application (EntraId client ID + secret) flow. |
| `Program.cs` | Main console application performing some CRUD operations via OData. |
| `appsettings.json` | Settings template file to be edited for target F&O environment. Must be present in the same folder as the executable console application. |


