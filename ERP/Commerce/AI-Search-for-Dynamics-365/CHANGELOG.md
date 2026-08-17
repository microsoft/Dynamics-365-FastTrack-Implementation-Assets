# Changelog

All notable changes to this project are documented here.

## [V7-20260815] – 2026-08-15

### Changed
- **D365 X++ (`CCAIProductSearchExportData`)** now extracts only the blob **endpoint URL** from
  the storage connection string (retrieved from Key Vault) and sends that non-secret URL to the
  Function App. The storage **account key is no longer transmitted**. A helper,
  `getBlobEndpointFromConnectionString`, performs the parsing; the existing method/field/JSON
  naming (`retrieveProductSearchStorageConnectionString`, `DestinationConnectionString`) is kept.
- **Function App (`ProductListStorageWriter`)** now authenticates to the destination storage
  account using its **managed identity** (`DefaultAzureCredential`) and treats the incoming
  `DestinationConnectionString` value as the blob endpoint URL. Added the `Azure.Identity` package.

### Security
- The storage **account key is never sent** from D365 to the Function App and is **not stored** on
  the function, removing the risk of the secret leaking via request bodies, logs, or telemetry.
  The full connection string remains only in Key Vault (still used by the Azure AI Search data
  source).

### Fixed
- Corrected CLR exception handling in `exportInitialProductData` and `copyData` (proper
  `System.Exception.get_Message()` retrieval and CLR object cleanup).
- Aligned DMF refresh type with the sync mode (`FullPush` for initial sync,
  `IncrementalPush` otherwise) and added error logging in the generic catch blocks.

### Upgrade notes
- Enable a **system-assigned managed identity** on the Function App and grant it **Storage Blob
  Data Contributor** on the destination storage account. No storage app setting is required.
  See [`docs/azure-setup.md`](docs/azure-setup.md).

## [7.0] – 2025-11-21

### Changed
- `CCAIProductSearch.createOrderLines`: removed `_fds.research(true)`.
- `CCAIProductSearch.canClose()`: added `RetailInventTable` to the entity (custom tables can be
  added); removed the code in `defaultCTQuery()`.

### Resources
- `CCAISearchProductSearchDataSourceSchema`
- `CCAISearchProductSearchIndexSchema`
- `FTA.en-US.label`

> Version 7 corresponds to the D365 F&O deployable package `FTA_CCAISearch_V7.axpp`, distributed
> separately from this repository.
