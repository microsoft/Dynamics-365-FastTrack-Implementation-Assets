# Publishing Gold to ADLS Gen2 (temporary path)

Until Dynamics 365 Customer Insights - Data (CI Data) supports OneLake as a source, publish the Gold Lakehouse tables to an ADLS Gen2 account (Delta format) and point CI Data at that store.

> This step is intentionally lightweight so it can be switched off when CI Data moves to OneLake. This package does not include a publish pipeline; choose one of the options below.

## Option A - Fabric Data Factory copy

**Source:** Lakehouse Gold table (for example, `activities_Orders`)  
**Sink:** ADLS Gen2 (Delta folder per table) using a managed connection (service principal).  
**Partitioning:** Configure writes partitioned by `OrderDate` for `activities_Orders` and by `EventDate` for `activities_LoyaltyPoints` (if published).

## Option B - Notebook write (PySpark)

Configure OAuth credentials for the ADLS account, then write the Delta folders per table.

```python
# OAuth for ADLS Gen2 (sample)
spark.conf.set("fs.azure.account.auth.type.<account>.dfs.core.windows.net", "OAuth")
spark.conf.set("fs.azure.account.oauth.provider.type.<account>.dfs.core.windows.net", "org.apache.hadoop.fs.azurebfs.oauth2.ClientCredsTokenProvider")
spark.conf.set("fs.azure.account.oauth2.client.id.<account>.dfs.core.windows.net", "<appId>")
spark.conf.set("fs.azure.account.oauth2.client.secret.<account>.dfs.core.windows.net", "<secret>")
spark.conf.set("fs.azure.account.oauth2.client.endpoint.<account>.dfs.core.windows.net", "https://login.microsoftonline.com/<tenant>/oauth2/token")

orders = spark.read.table("activities_Orders")
(orders
  .write.format("delta")
  .mode("append")
  .partitionBy("OrderDate")
  .save("abfss://gold@<storage-account>.dfs.core.windows.net/activities_Orders/"))
```

After the first write, set table properties on the ADLS-hosted Delta tables (via SQL on the Lakehouse or using a small utility):

- `delta.minReaderVersion = 2`
- `delta.enableDeletionVectors = false`
- `delta.logRetentionDuration = '15 days'`

## ADLS layout (example)

```text
abfss://gold@<storage-account>.dfs.core.windows.net/
  profiles_Customer/
  activities_Orders/
  activities_LoyaltyPoints/
  supporting_Products/
  supporting_Channels/
  supporting_Calendar/
  supporting_LoyaltyRewardPoints/
  supporting_LoyaltyPrograms/
  analytics_CustomerMetrics/
```

Publish only the tables you need. Use the same table names as the Lakehouse Gold tables to keep CI Data mappings straightforward.

## Security

- Storage account with HNS enabled, private endpoints for blob and dfs, and network default deny.
- CI Data service principal granted Storage Blob Data Contributor to the `gold` container.
