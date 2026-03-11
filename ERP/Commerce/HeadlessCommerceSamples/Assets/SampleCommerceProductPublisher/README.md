# Product Publisher Function App

## Overview

The Product Publisher Function App is a .NET 8 application designed to handle products received from the Commerce Runtime (CRT) and send them to a target integration point using an adapter. The solution is divided into multiple projects, each with specific responsibilities.

![Diagram](./resources/diagram.svg)

Learn more about what a [publisher does](./WhatThePublisherDoes.md).

## Project Structure

- **ProductPublisherApp**: Main Azure Function that triggers the product publishing process.
- **ProductPublisher.Core**: Library designed to facilitate the handling of product publishing APIs available in the Headless Commerce Engine.
- **CommerceRuntime**: Commerce runtime extensions

### ProductPublisherApp

This is an example of an Azure Function that is triggered by a timer trigger and uses the proxy to publish products to a channel.
This code is provided as an example and is not intended to be used in a production environment.
The code is provided as is, and Microsoft makes no warranties, express or implied.

#### Prerequisites

- .NET 8
- Azure Functions SDK
- RetailProxy SDK
- The commerce scale unit must be available for external applications to access the API

For more information, see the following documentation: [Consume Retail Server APIs in external applications](https://learn.microsoft.com/en-us/dynamics365/commerce/dev-itpro/consume-retail-server-api#security-and-authentication-that-are-required-to-consume-apis)

#### Configuration

The function uses environment variables for configuration. Ensure the following environment variables are set:

- `OUN`
- `CSUURL`
- `AUTHORITY`
- `CLIENTID`
- `CLIENTSECRET`
- `AUDIENCE`
- `TENANTID`
- `CATALOGID`
- `DEFAULTPAGESIZE`
- `PUBLISHPRICES`

Example of local settings (local.settings.json)

```json
{
  "IsEncrypted": false,
  "Values": {
    "AzureWebJobsStorage": "UseDevelopmentStorage=true",
    "FUNCTIONS_WORKER_RUNTIME": "dotnet",
    "OUN": "your-oun",
    "CSUURL": "https://your-csu-url",
    "AUTHORITY": "https://login.microsoftonline.com/your-tenant-id",
    "CLIENTID": "your-client-id",
    "CLIENTSECRET": "your-client-secret",
    "AUDIENCE": "https://your-audience",
    "TENANTID": "your-tenant-id",
    "CATALOGID": 0,
    "DEFAULTPAGESIZE": 100,
    "PUBLISHPRICES": true
  }
}
```

The function app executes every five minutes by default, but this interval can be adjusted based on specific requirements.

#### Security consideration

> [!IMPORTANT]
> The Client ID and Secret must be secured properly in a production environment. For design time and sandbox, this project uses the credentials hard-coded in the JSON file and access it as environment variables. You should use Azure key vault (or a similarly secure pattern to exchange sccrets) and implement the logic to retrieve the keys properly.

#### Usage

1. Clone the repository.
2. Set the required environment variables in your local file (local.settings.json).
3. Build the project using .NET 8.
4. _Optional_ Deploy the Azure Function to your Azure subscription. At design time, debugging and execution can be done locally through Visual Studio or Visual Studio Code.
5. The function will run based on the timer trigger schedule.

#### Running Locally

To run the function locally, use the Azure Functions Core Tools.
Ensure you have the required environment variables set in your local.settings.json file.

_Refer to this link to learn more about Azure Function Development_: [Develop Azure Functions using Visual Studio](https://learn.microsoft.com/en-us/azure/azure-functions/functions-develop-vs?pivots=isolated)

#### Example Adapters

In the Azure Function app, there is a destination adapter.
For implementing new adapters, you should use the interface provided and follow the same pattern from the examples.
