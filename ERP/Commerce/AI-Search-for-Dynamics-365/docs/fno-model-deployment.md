# Dynamics 365 F&O – X++ source (FTA_CCAISearch)

This folder contains the extracted X++ source of the **AI Product Search** D365 Finance &
Operations model, as shipped in `FTA_CCAISearch_V7.axpp`.

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

You normally deploy using the packaged **`FTA_CCAISearch_V7.axpp`** from the
[GitHub Releases][releases] page rather than these loose files:

1. On a D365 F&O development VM, open Visual Studio.
2. **Dynamics 365 ▸ Import Project** and select the `.axpp` file.
3. Build the model, then **Dynamics 365 ▸ Deploy** (or create a deployable package for a
   sandbox/production environment).

For detailed deployment instructions, see **[Dynamics 365 Model Deployment](../fno-model-deployment.md)** guide.

To work from this source directly, place the `FTA` model under your
`PackagesLocalDirectory` / metadata folder and open `Project/FTA_CCAISearch.rnrproj`.

> This source is provided for transparency and version control. See the repository
> [Disclaimer](../../README.md#disclaimer).

---

Continue with **[F&O configuration](fno-configuration.md)** to configure the imported model and enable the search feature.

<!-- Link shortcuts - update here if URLs change -->
[releases]: https://github.com/fechiram_microsoft/AI-Search-for-Dynamics365/releases
