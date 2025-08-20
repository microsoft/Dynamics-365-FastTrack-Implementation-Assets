<!--
---
page_type: sample
languages:
- csharp
products:
- dynamics-finance-operations

description: "Dynamics 365 for Finance and Operations sample Message Processor console application"
urlFragment: "d365-fo-message-processor-console"
---
-->
# Dynamics 365 for Finance and Operations sample Message Processor console application

This asset contains a sample console application that demonstrates how to use the the Message Processor to import simple sales orders in Dynamics 365 for Finance and Operations (F&O).
The sample consists of 

## How to install
	1. Download the sample code from the [GitHub repository](https://github.com/microsoft/Dynamics-365-FastTrack-Implementation-Assets).
	2. Import and compile the Dynamics 365 for Finance and Operations project into your F&O environment.
	3. Configure the message processr in your environemnt by following the instructions in the [Message Processor documentation](https://docs.microsoft.com/en-us/dynamics365/fin-ops-core/dev-itpro/data-entities/message-processor).
	4. Open the solution in Visual Studio 2022.	
	5. Edit the `appsettings.json` file to include the correct settings for your F&O environment.
	6. Build the solution.
	7. Run the console application.

# Contents
| File/folder | Description |
|-------------|-------------|
| `README.md` | This README file. |
| `MessageProcessorConsoleApp.csproj` | Visual Studio 2022 project definition. |
| `AuthenticationConfig.cs` | Utility class for EntraId authentication using the web application (EntraId client ID + secret) flow. |
| `Program.cs` | Main console application performing the import of sales orders via the Message Processor. |
| `appsettings.json` | Settings template file to be edited for target F&O environment. Must be present in the same folder as the executable console application. |
| `QuickOrderProcessor.axpp` | F&O project containing the Message Processor configuration and the data entity used for the import. |




