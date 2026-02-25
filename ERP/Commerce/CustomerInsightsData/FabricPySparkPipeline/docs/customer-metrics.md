# Customer metrics (optional)

## Overview

CI Data refers to Dynamics 365 Customer Insights - Data.

- Produced by `02_silver_to_gold.ipynb` when Silver order tables are available; loyalty metrics are included when `activities_LoyaltyPoints` is available.
- Outputs an optional `analytics_CustomerMetrics` Delta table for BI, agents, or custom exports.
- Snapshot grain: one row per `CustomerId` per `AsOfDate` (optional `as_of_date` parameter; defaults to `current_date()` at run time).
- Partitioned by `AsOfDate`; idempotent overwrite per run, matching other Gold write patterns.

## Sources and cadence

- Orders data derives from `activities_Orders` (in-memory DataFrame before it is written).
- Loyalty engagement derives from `activities_LoyaltyPoints` when available.
- Customer attributes come from the in-memory `profiles_Customer` DataFrame, ensuring consistent identifiers with CI Data contracts.
- Recommended cadence mirrors the existing Bronze->Silver->Gold schedule (typically daily). Consumers can opt in or ignore the table with no impact on CI Data loads.

## Columns and calculations

| Column | Description | Calculation |
| --- | --- | --- |
| `CustomerId` | Stable customer key (`lower(data_area_id + '_' + account_num)`) | From `profiles_Customer` |
| `DataAreaId`, `AccountNum`, `PartyType`, `Name`, `LanguageId` | Reference attributes for downstream slicing | Pass-through from `profiles_Customer` |
| `AsOfDate` | Snapshot date (UTC) | Supplied `as_of_date` parameter, else `current_date()` at run time |
| `TotalOrders` | Distinct order headers per customer | `count_distinct(OrderId)` |
| `TotalRevenue` | Gross line revenue | `sum(LineAmount)` |
| `TotalCost` | Aggregated cost basis | `sum(CostPrice)` |
| `TotalDiscount` | Discount value applied | `sum(LineDiscount)` |
| `GrossMargin` | Economic contribution | `TotalRevenue - TotalCost` |
| `GrossMarginPct` | Margin percentage | `GrossMargin / TotalRevenue` when revenue > 0 |
| `AverageOrderValue` | Mean order size | `TotalRevenue / TotalOrders` when orders > 0 |
| `OrderFrequencyPerMonth` | Activity cadence | `TotalOrders / max(1, months_between(AsOfDate, FirstOrderDate))` |
| `FirstOrderDate`, `LastOrderDate` | Order bookends | `min(OrderDate)`, `max(OrderDate)` |
| `RecencyDays` | Days since last order | `datediff(AsOfDate, LastOrderDate)` |
| `ActiveDays` | Span between first and last orders (inclusive) | `datediff(LastOrderDate, FirstOrderDate) + 1` |
| `DistinctChannels` | Channels engaged | `count_distinct(ChannelId)` |
| `DistinctProducts` | Product breadth | `count_distinct(ItemId)` |
| `PointsEarned` | Loyalty points accrued | `sum(PointsDelta where > 0)` |
| `PointsRedeemed` | Loyalty points spent | `sum(abs(PointsDelta) where < 0)` |
| `PointsBalance` | Net loyalty position | `sum(PointsDelta)` |
| `HasLoyaltyActivity` | Flag for any loyalty movement | `(PointsEarned + PointsRedeemed) > 0` |
| `DiscountShare` | Discount intensity | `TotalDiscount / TotalRevenue` when revenue > 0 |

> Aggregate counts and sums coalesce to `0` when the contributing aggregate is null. Derived ratios return `null` if the denominator is zero.

## Usage guidance

- The analytics table is optional; CI Data continues to ingest the standard Profiles/Activities/Supporting contracts.
- Fabric semantic models, Power BI datasets, or custom agents can consume the table directly from OneLake.
- When introducing new metrics, update both the notebook helper (`build_customer_metrics`) and this document to keep definitions aligned.
