# Dynamics 365 F&O – X++ source (FTA_CCAISearch)

This folder contains the extracted X++ source of the **AI Product Search** D365 Finance &
Operations model, as shipped in `FTA_CCAISearch_V8_20261116.axpp`.

## Structure

| Path | Contents |
| --- | --- |
| `Model/` | Model descriptor (`FTA.xml`) |
| `Project/` | Visual Studio project (`FTA_CCAISearch.rnrproj`) |
| `ProjectItem/` | All model objects, grouped by type |

Key objects under `ProjectItem/`:

- **Forms** – `CCAIProductSearch`, `CCAISearchServiceParameters`, `CCAISearchServiceIntegrationLog`
- **Classes** – service/API managers, export data, batch jobs (initialize / update / reindex)
- **Tables** – service parameters, integration log, staging, product list/search temp tables
- **Data entity** – `CCAISearchEcoResProductsEntity`
- **Resources** – AI Search index / indexer / data source schemas and request bodies (JSON under
  `AxResource/ResourceContent/Data/`)
- **Extensions** – `SalesTable`, `InventTable`, menu and form extensions
- **Security** – privileges for maintain/view
- **Labels** – `FTA.en-US.label.txt`

## How to build / deploy

You normally deploy using a packaged `.axpp` from the release zip `CCAISearch_V8_20261116.zip`
in the [`src/`][releases] folder rather than these loose files. The zip contains two packages:

| Package | Use when |
|---|---|
| `FTA_CCAISearch_V8_20261116.axpp` (full) | New customer – installs every object of the solution. |
| `FTA_CCAISearch_V8_20261116_Delta.axpp` (delta) | Upgrade from V7 – contains only the 18 objects changed or added in V8. |

The `.axpp` packages contain the resource and label objects but not their content files. The
zip therefore also contains the folder `FTA_ResourceContent_V8_20261116/FTA/` with the 5 resource
JSON files and the label text file `FTA.en-US.label.txt`.

1. On a D365 F&O development VM, open Visual Studio.
2. **Dynamics 365 ▸ Import Project** and select the full or delta `.axpp` file.
3. Copy the contents of `FTA_ResourceContent_V8_20261116/FTA/` into the `FTA` model folder of
   your metadata location (for example `PackagesLocalDirectory\FTA\FTA\`), overwriting existing
   files. This places the JSON files in `AxResource\ResourceContent\Data\` and the label text in
   `AxLabelFile\LabelResources\en-US\`.
4. **Rebuild** the `FTA` model (a full rebuild is needed to pick up resource and label content),
   then **Dynamics 365 ▸ Deploy** (or create a deployable package for a sandbox/production
   environment).
5. Run **database synchronization** (V8 adds new fields to the data entity and parameters).

If the build reports *Resource content file '…Json' not found* or labels show as `@FTA:…`,
step 3 was skipped or copied to the wrong folder.

To work from this source directly, place the `FTA` model under your
`PackagesLocalDirectory` / metadata folder and open `Project/FTA_CCAISearch.rnrproj`.

> This source is provided for transparency and version control. See the repository
> [Disclaimer](../README.md#disclaimer).

---

Continue with **[F&O configuration](fno-configuration.md)** to configure the imported model and enable the search feature.

<!-- Link shortcuts - update here if URLs change -->
[releases]: ../src
