# Fabric-first Commerce to Customer Insights - Data (CI Data)

Last updated: 2026-01-16

This package provides a reference implementation for landing Dataverse (Commerce) data into Microsoft Fabric, curating Bronze -> Silver -> Gold Delta tables, and preparing Dynamics 365 Customer Insights - Data (CI Data) ingestion. The notebooks in `notebooks/` are the source of truth; the docs describe the current design and operating guidance.

## Package layout

- `docs/` Architecture, data model, and operational guidance
- `notebooks/` PySpark notebooks that build Silver and Gold tables
- `README.md` This overview

## How it works

1. Link to Microsoft Fabric replicates Dataverse (Commerce) tables to OneLake (Bronze).
2. `01_bronze_to_silver.ipynb` standardizes and cleans data into Silver.
3. `02_silver_to_gold.ipynb` builds Gold tables aligned to CI Data contracts.
4. (Optional) Publish Gold to ADLS Gen2 until CI Data supports OneLake directly.

## Import notebooks into Fabric

1. Create or open a Fabric workspace and Lakehouse. The notebooks default to `ci_lakehouse`; either use that name or update `SOURCE_DB` and `TARGET_DB` in the notebooks.
2. Import the notebooks from `notebooks/` (upload or Git sync).
3. Attach the Lakehouse to each notebook and set it as the default.
4. Run `01_bronze_to_silver.ipynb`, then `02_silver_to_gold.ipynb`.
5. (Optional) Schedule runs with Fabric pipelines or jobs to align with your Dataverse snapshot cadence.

## Documentation

- `docs/architecture.md` Target design, flows, and guardrails
- `docs/curation-notebooks.md` Notebook behavior, inputs, outputs, and rules
- `docs/data-model-gold.md` Gold schema for Profiles, Activities, Supporting, and optional analytics
- `docs/customer-metrics.md` Optional customer KPI snapshot definitions
- `docs/publishing-to-adls.md` Publishing Gold to ADLS Gen2 (temporary)

## Prerequisites

- A Microsoft Fabric workspace with a Lakehouse
- Link to Microsoft Fabric configured for Dataverse (Commerce) tables
- Dynamics 365 Customer Insights - Data environment
- (Optional) ADLS Gen2 account for interim publishing

## Partner statements

> "The CI & Commerce Better Together Medallion Blueprint fundamentally shifts the delivery model from manual effort to a roll-out approach. By utilizing reusable artefacts, partners slash deployment times from months to mere days while taking advantage of Microsoft insights into the complex world of Commerce. This shift drives tangible operational improvements: significantly reducing costs and error rates while boosting cross-project consistency and delivery predictability." - Rune Daub, Enterprise Architect, HSO
> "With the CI & Commerce Better Together medallion blueprint, partners have an extendable accelerator that can be adjusted to the customer's needs. This significantly reduces time to value and increases delivery predictability and maintainability." - Jakob Thomadsen, Context&

## Notes

- Gold tables enforce `delta.minReaderVersion = 2`, `delta.enableDeletionVectors = false`, and `delta.logRetentionDuration = '15 days'`.
- If documentation and notebooks diverge, follow the notebooks.
