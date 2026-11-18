# Changelog

All notable changes to this project are documented here.

## [V8-20261116] – 2026-11-16

Release package: `src/CCAISearch_V8_20261116.zip` containing `FTA_CCAISearch_V8_20261116.axpp`
(full package, for new customers), `FTA_CCAISearch_V8_20261116_Delta.axpp` (only the 18 objects
changed or added since V7, for upgrades from V7), the Function App source folder `CCAISearch-Deploy-V8_20261116/` and `What-is-new-in-V8_20261116.pdf`.
From V8 each release is shipped as one zip, and the Function App package follows the release
version. `src/` holds only the current release zip; earlier releases are kept as one zip each in
`src/archive/` (for example `src/archive/CCAISearch_V7_20260815.zip`).

### Added
- **Variant search** – products are found by their variant color, size and style. Three new
  parameters (**Include variant colors / sizes / styles in search**) choose which dimensions are
  used for ranking and semantic search; cleared dimensions stay available as filters.
- **Category counts** in the category tree of the product search screen. After a search, each
  category shows how many products match, e.g. **Shoes (12)**; categories with matches are shown
  in **bold**, so users see at a glance where the results are. A parent category includes the
  products of its subcategories. New parameter **Category counts**:
  - *Off* – no counts; the tree shows only category names (fastest).
  - *Retrieved results* – counts only the products loaded into the grid (limited by **Number of
    Records Retrieved**). The count always matches what the grid shows for that category.
  - *All matches* – counts every matching product in the Azure AI Search index, also those not
    loaded into the grid. Use it to see where more results are, then click the category to
    search inside it. The counts come back with the same search request (no extra call).
- **Category filter** – selecting a category in the tree narrows the results shown. A new search
  text always searches all categories; clicking **Search** again with the same text searches
  only the selected category. A "Searched in" label under the Search button shows the scope.

### Changed
- **Function App (`ProductListStorageWriter`)** converts the new `VARIANTSJSON` and
  `CATEGORYRECIDSJSON` export columns into index fields. Function name and URL are unchanged;
  both columns are optional, so data from older D365 versions still works. Runtime is now
  **.NET 10 (isolated)**. Invalid request input returns `400 Bad Request`.
- **Index schema** adds the variant and category fields, scoring and semantic configuration.
- **Search** returns only the fields needed by the screen, without a total count, and uses one
  database query for all result rows; fewer grid reloads.
- **Search calls** time out after 60 seconds; Azure error details are written to the
  integration log. A failed search shows a message and an empty result.
- **Initialize index** switches search to the new index only after it completes successfully.
- The data export blocks a comma or colon as column separator (they occur in variant data).

### Upgrade notes
- Deploy the D365 package (with **database synchronization**) and the Function App from this
  release together, then run **Initialize index**. Roll back both together.
- Set the Function App runtime to **.NET 10 (isolated)** before deploying the new package.
- Existing parameters, Function URL and function key are unchanged.

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
