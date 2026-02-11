# Curation notebooks

This section describes the two notebooks in `notebooks/`. Paths, suffixes, and table names reflect the notebook code to avoid drift.

## Common configuration

- Database: `ci_lakehouse` (used for both `SOURCE_DB` and `TARGET_DB` via `USE ci_lakehouse`)
- Silver root: `Files/Tables_silver` (tables are registered to this fixed `LOCATION`)
- Gold root: `Files/Tables_gold` (tables are registered to this fixed `LOCATION`)
- Write mode: snapshot overwrite (idempotent). The code is structured so it can be switched to `MERGE` later.
- Decimals: default cast is `Decimal(18,4)` in helper `cast_decimal`.
- Soft delete handling: helper `exclude_soft_deleted` drops rows where `IsDelete` is true (if the column exists).
- Dedupe: helper `dedupe_latest(df, pk_cols, order_cols)` keeps the latest row per PK using a descending window.
- PK checks: non-fatal warnings via `assert_pk_unique(df, pk_cols, label)`.

---

## 01_bronze_to_silver.ipynb - Bronze -> Silver

**Purpose.** Reads Link-managed Bronze tables in the Lakehouse and writes standardized Silver tables with coherent types, UTC timestamps, light dedupe, and soft-delete filtering. The notebook is modular and skips gracefully when an upstream table is missing.

### Key helpers

- `table_exists`, `safe_read_table` - tolerant table discovery
- `to_utc_ts`, `cast_decimal`
- `write_delta(df, name, partition_cols=None)` - writes to `Files/Tables_silver/<name>` and registers the Delta table
- `dedupe_latest`, `assert_pk_unique`, `exclude_soft_deleted`

### Silver outputs (Lakehouse metastore names)

- `postal_address_silver` - current postal addresses per `location_recid`
  - Derived from `logisticslocation` + `logisticspostaladdress`.
  - Columns include: `location_id`, `location_description`, `is_postal_address`, `location_recid`, `address_line`, `street`, `street_number`, `city`, `state`, `county`, `postal_code`, `country_region_id`, `latitude`, `longitude`, `timezone`, `valid_from_utc`, `valid_to_utc`, `private_for_party`, and computed `is_current`.
- `dirpersonname_current_silver` - current person names with validity window
  - From `dirpersonname`; filtered where `valid_from_utc <= now <= valid_to_utc`, deduped per `person_recid`.
  - Columns: `person_recid`, `dirpersonname_recid`, `person_first_name`, `person_middle_name`, `person_last_name`, `person_last_name_prefix`, `valid_from_utc`, `valid_to_utc`.
- `dirparty_silver` - party core with primary email/phone and address pointers
  - From `dirpartytable` plus lookups into `logisticselectronicaddress` (email/phone) and `dirpersonname_current_silver`.
  - Columns include: `party_recid`, `party_number`, `name`, `name_alias`, `known_as`, `language_id`, `data_area_id`, `instance_relation_type`, `primary_contact_email_recid`, `primary_contact_phone_recid`, `primary_email`, `primary_email_description`, `primary_email_is_im`, `primary_email_purpose`, `primary_phone`, `primary_phone_description`, `primary_phone_extension`, `primary_phone_is_mobile`, `primary_phone_purpose`, `primary_address_location_recid`, `address_books`.
- `customer_silver` - denormalized customer profile base
  - From `custtable` + `dirparty_silver` (+ optional join to `postal_address_silver` where `is_current = true`).
  - Representative columns: `account_num`, `cust_group`, `party_recid`, `customer_recid`, `data_area_id`, `party_type`, `name`, `known_as`, `language_id`, `primary_email`, `primary_phone`, `primary_address_location_recid`, `person_first_name`, `person_middle_name`, `person_last_name`, plus address fields from `postal_address_silver` when available.
  - PK: `["data_area_id", "account_num"]` (deduped by latest `party_recid`).
- `salestable_silver` - order header stub (for joins)
  - From `salestable`. Columns: `cust_account`, `sales_id`, `retail_channel_recid`, `data_area_id`.
- `salesline_silver` - line-level sales facts (preferred grain)
  - From `salesline`. Columns include: `item_id`, `line_recid`, `sales_id`, `sales_qty`, `sales_price`, `unit_price` (derived), `line_discount`, `line_amount`, `cost_price`, `currency_code`, `sales_unit`, `price_unit`, `line_num`, `sales_status`, `data_area_id`, `created_datetime_utc`, constant `event_type = "Purchase"`, and `product_name`.
  - Deduped per `["data_area_id", "sales_id", "line_recid"]` by latest `created_datetime_utc`.
- `retailchannel_silver` - channel lookup for CI Data
  - From `retailchanneltable`. Columns: `channel_id`, `channel_recid` (stable join key).
- Loyalty (prepared for future extensions; not used in Gold v1)
  - `loyalty_card_silver` - card attributes plus optional `customer_id` lookup via `customer_silver`
  - `loyalty_card_tier_silver` - tier assignments per card (`rec_id`)
  - `loyalty_point_trans_silver` - reward point transactions (card, amounts, store/terminal/staff; deduped by latest)
  - `loyalty_program_affiliation_silver` - program catalog

> All Silver tables are written to `Files/Tables_silver/<name>` and registered into the Lakehouse metastore with the `_silver` suffix.

---

## 02_silver_to_gold.ipynb - Silver -> Gold

**Purpose.** Transform cleaned Silver tables into Gold tables aligned to Dynamics 365 Customer Insights - Data (CI Data) contracts.

### Compatibility rules applied on write

- `delta.minReaderVersion = 2`
- `delta.enableDeletionVectors = false`
- `delta.logRetentionDuration = '15 days'`
- Write mode: snapshot overwrite today; a flag exists to switch to merge/upsert when the schema is stable.

### Gold outputs (Lakehouse metastore names)

- `profiles_Customer` (PK: `CustomerId`)
  - Built from `customer_silver`. `CustomerId = lower(data_area_id + '_' + account_num)`.
  - Columns: `CustomerId`, `DataAreaId`, `AccountNum`, `PartyType`, `Name`, `KnownAs`, `LanguageId`, `PrimaryEmail`, `PrimaryPhone`, `PersonFirstName`, `PersonMiddleName`, `PersonLastName`, `AddressLine`, `Street`, `StreetNumber`, `City`, `State`, `County`, `PostalCode`, `CountryRegionId`, `Latitude`, `Longitude`, `PartyRecordId`, `PrimaryAddressLocationId`, `RowModifiedUtc`.
- `activities_Orders` (PK: `OrderLineId`, partitioned by `OrderDate`)
  - Built from `salesline_silver` + `salestable_silver` + `retailchannel_silver` (+ optional `customer_silver` for consistent `CustomerId`).
  - Channel lookup dedupes by `channel_recid` before joining to avoid order-line inflation.
  - `OrderLineId = sales_id + '_' + line_recid`. `OrderTimestamp = to_utc(created_datetime_utc)`. `OrderDate = to_date_utc(created_datetime_utc)`.
  - Columns: `OrderLineId`, `OrderId`, `CustomerId`, `ChannelId`, `ItemId`, `ProductName`, `OrderDate`, `OrderTimestamp`, `SalesQty`, `UnitPrice`, `LineDiscount`, `LineAmount`, `CostPrice`, `CurrencyCode`, `SalesUnit`, `PriceUnit`, `SalesStatus`, `DataAreaId`, `RowModifiedUtc`.
- `supporting_Products` (PK: `ProductId`)
  - From `product_silver` if present, else distincts from `salesline_silver`. Columns: `ProductId`, `ProductName`, `RowModifiedUtc`.
- `supporting_Channels` (PK: `ChannelId`)
  - From `retailchannel_silver`. Columns: `ChannelId`, `ChannelRecId`, `RowModifiedUtc`.
- `supporting_Calendar` (PK: `Date`)
  - A generated date dimension across observed order dates. Columns: `Date`, `Year`, `Quarter`, `Month`, `Day`, `WeekOfYear`, `DayOfWeek`, `RowModifiedUtc`.
- `activities_LoyaltyPoints` (optional) (PK: `LoyaltyEventId`, partitioned by `EventDate`)
  - Built from `loyalty_point_trans_silver` plus optional joins to `loyalty_card_silver`, `loyalty_card_tier_silver`, `salestable_silver`, and `retailchannel_silver`.
  - Skips gracefully if required sources are missing.
- `supporting_LoyaltyRewardPoints` (optional) (PK: `RewardPointId`)
  - Schema-only placeholder for CI Data compatibility.
- `supporting_LoyaltyPrograms` (optional) (PK: `ProgramId`)
  - From `loyalty_program_affiliation_silver` when present.
- `analytics_CustomerMetrics` (optional)
  - Optional customer KPI snapshot built from the in-memory Gold DataFrames (`profiles_Customer`, `activities_Orders`, `activities_LoyaltyPoints`).
  - Partitioned by `AsOfDate`; defaults to `current_date()` but can be supplied as a parameter for deterministic snapshots; available for BI/agents without affecting CI Data loads.

### Write mechanics

All Gold tables are written to `Files/Tables_gold/<name>` and registered. Properties above are enforced post-write. `activities_Orders` is partitioned by `OrderDate`; `activities_LoyaltyPoints` is partitioned by `EventDate` when created.

---

## Run order and scheduling

1. Link to Microsoft Fabric must be active and Bronze tables present in the Lakehouse.
2. Run `01_bronze_to_silver.ipynb`. The notebook will skip missing sources and still produce what it can.
3. Run `02_silver_to_gold.ipynb`. Gold tables are registered under `Tables` and written to `Files/Tables_gold`.
4. (Optional) Trigger the publish to ADLS pipeline/notebook if CI Data is still reading from ADLS (not included in this package).
5. Align schedules with the Dataverse-to-Fabric snapshot cadence; aim for <= 30 minutes Bronze->Silver and <= 30 minutes Silver->Gold plus publish, subject to volume and capacity.

> Both notebooks use idempotent snapshot writes by default, so a re-run is safe.
