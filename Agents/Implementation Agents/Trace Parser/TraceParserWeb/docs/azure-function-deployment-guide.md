# Azure Function Deployment Guide — TraceParserFunction

## Overview

The `ParseEtl` Azure Function parses large ETL trace files (up to 2 GB) and imports them
into Azure SQL. It uses `Microsoft.Diagnostics.Tracing.TraceEvent` (ETWTraceEventSource)
which requires **Windows**. This guide covers the best deployment option and explains the
architecture decisions.

---

## Hard Constraint: `net8.0-windows`

The project targets `net8.0-windows` because ETWTraceEventSource requires Windows APIs
for ETL parsing. This eliminates all Linux-only hosting options.

---

## Hosting Options Comparison

| Plan | Windows? | Max Timeout | Memory | Temp Disk | Cost/month | Verdict |
|------|----------|------------|--------|-----------|------------|---------|
| **Consumption** | Yes | **10 min** | 1.5 GB | 0.5 GB | Pay-per-use | **Eliminated** — 10 min timeout too short |
| **Flex Consumption** | **No** | Unbounded | 4 GB | 0.8 GB | Pay-per-use | **Eliminated** — Windows not supported |
| **Container Apps** | **No** | Unbounded | Varies | N/A | Pay-per-use | **Eliminated** — Windows not supported |
| **Premium (EP1)** | Yes | **Unbounded** | 3.5 GB | 21 GB | ~$175 | **Best fit** — already in deploy.ps1 |
| **Premium (EP2)** | Yes | **Unbounded** | 7 GB | 42 GB | ~$350 | Good for larger ETL files |
| **Premium (EP3)** | Yes | **Unbounded** | 14 GB | 140 GB | ~$700 | Overkill for this workload |
| **Dedicated (S2)** | Yes | Unbounded* | 3.5 GB | 21 GB | ~$100 | Cheaper, no auto-scale |
| **Dedicated (P1v3)** | Yes | Unbounded* | 8 GB | 16 GB | ~$120 | Good value, no auto-scale |

\* Dedicated plans require **Always On** enabled for unbounded timeout.

### Why most plans don't work

- **Consumption (max 10 min)**: A 978 MB ETL file produces 10.2M rows. Even in Azure
  (same region), the import takes ~12-20 minutes — well beyond the 10-minute limit.
- **Flex Consumption**: Microsoft's recommended serverless plan, but it only supports
  **Linux**. Our `net8.0-windows` target framework is incompatible.
- **Container Apps**: Also Linux-only for Azure Functions hosting.

---

## Recommended: Premium EP1

The `deploy.ps1` already deploys with **EP1 (Elastic Premium)**. This is the best choice.

### Why EP1 is the right fit

1. **Windows support**: Required for `net8.0-windows` / ETWTraceEventSource
2. **Unbounded timeout**: `host.json` sets `functionTimeout: "01:00:00"` — fully honored
3. **3.5 GB RAM**: Sufficient — the function streams in 200K-row batches (~50-100 MB
   DataTable in memory at a time), not the full 10.2M rows
4. **21 GB temp disk**: Plenty of room for the 2 GB max ETL file download
5. **VNET integration**: Can connect to Azure SQL via private endpoint (eliminates need
   for public firewall rules)
6. **Pre-warmed instances**: Reduces cold-start when a user uploads an ETL
7. **Auto-scale**: If multiple ETL files are uploaded concurrently, the plan scales out

### Premium plan SKUs

| SKU | vCPUs | Memory | Storage | Est. Cost/month |
|-----|-------|--------|---------|-----------------|
| EP1 | 1 | 3.5 GB | 250 GB | ~$175 |
| EP2 | 2 | 7 GB | 250 GB | ~$350 |
| EP3 | 4 | 14 GB | 250 GB | ~$700 |

### When to upgrade to EP2

Consider EP2 if:
- Users upload ETL files close to the 2 GB limit
- Memory profiling shows the function approaching 3.5 GB
- You need more CPU for faster ETL parsing

---

## Performance: Local vs Azure Deployment

### The network bottleneck problem

Running the function **locally** against Azure SQL is dramatically slower than running it
**in Azure** (same region). The bottleneck is SqlBulkCopy over the internet:

| Metric | Local → Azure SQL | Azure EP1 → Azure SQL |
|--------|-------------------|----------------------|
| Network latency | ~20-40ms RTT | <1ms RTT |
| Bulk insert speed | ~123K rows/min | ~2M rows/min (est.) |
| Wait type observed | `ASYNC_NETWORK_IO` | Minimal waits |

### Import timing comparison (978 MB ETL, 10.2M rows)

| Phase | Local SQL Express | Local → Azure SQL S9 | Azure EP1 → Azure SQL S3 |
|-------|-------------------|---------------------|--------------------------|
| Blob download | N/A | N/A (Azurite) | ~2-5 sec |
| Phase 1: Stream 10.2M rows | ~5 min | **~82 min** | **~5-8 min** |
| Phase 2: Dimension upserts | ~10 sec | ~30 sec | ~10-15 sec |
| Phase 3: Remap ThreadIds | ~1.5 min | ~5 min | ~1-2 min |
| Phase 4: INSERT 10.2M rows | ~4.7 min | ~5 min | ~3-5 min |
| Phase 4b: Index rebuild | ~2 min | ~2 min | ~1-3 min |
| Phase 5: Bind params | ~30 sec | ~2 min | ~30-60 sec |
| **Total** | **~14 min** | **~97 min** | **~12-20 min** |

The key insight: **When the function runs in Azure, even S3 (100 DTU, ~$75/month) is
sufficient** because the SQL server isn't waiting on slow network data anymore. You
don't need S9 (1600 DTU) like you do when running locally.

---

## Deployment Steps

### 1. Deploy resources

The existing `deploy.ps1` creates all resources:

```powershell
./deploy.ps1
```

This creates:
- Storage Account (`sttraceparser<timestamp>`)
- Function App Plan (EP1, Windows)
- Function App (`func-traceparser-<timestamp>`)
- Web App Plan (B2) + Blazor Web App

### 2. Publish the function

```bash
cd TraceParserFunction
func azure functionapp publish <FUNC_NAME> --dotnet-isolated
```

### 3. Upload ETL

Upload via the Blazor web app (EtlUploadService) or via CLI:

```bash
az storage blob upload \
  --account-name <STORAGE_NAME> \
  --container-name etl-uploads \
  --name "<session>/<filename>.etl" \
  --file "<path-to-etl>" \
  --overwrite true
```

The blob trigger fires automatically. Monitor in Application Insights or via SQL queries.

---

## Azure SQL Tier Recommendations

When the function runs **in Azure** (same region), lower SQL tiers work well:

| Azure SQL Tier | DTU | Import Time (est.) | Cost/month | Recommendation |
|---------------|-----|-------------------|------------|----------------|
| S1 (20 DTU) | 20 | ~40-60 min | ~$15 | Too slow |
| S2 (50 DTU) | 50 | ~20-30 min | ~$37 | Acceptable for small files |
| **S3 (100 DTU)** | 100 | **~15-20 min** | **~$75** | **Good balance** |
| S4 (200 DTU) | 200 | ~12-15 min | ~$150 | Comfortable |
| S9 (1600 DTU) | 1600 | ~10-12 min | ~$800 | Overkill when in-Azure |

**Recommendation**: Use **S3 (100 DTU)** as the steady-state tier when the function runs
in Azure. Scale up temporarily to S4/S9 only for bulk historical imports.

---

## Cost Optimization

### Scale to zero (Premium plan)

Premium plans bill for at least one always-warm instance. If ETL imports are infrequent,
set minimum instances to 0:

```bash
az functionapp plan update \
  -g rg-traceparser-prod \
  -n plan-func-traceparser \
  --min-instances 0
```

This enables scale-to-zero behavior (pay only when active) while retaining Premium
features. Trade-off: ~20-30 second cold-start on the first upload after idle.

### Alternative: Dedicated Plan

If cost is the primary concern and auto-scaling isn't needed:

| Plan | vCPU | Memory | Cost/month | Notes |
|------|------|--------|------------|-------|
| S2 | 2 | 3.5 GB | ~$100 | Basic, Always On required |
| P1v3 | 2 | 8 GB | ~$120 | Better value, more memory |

Trade-off: No elastic auto-scaling, slightly longer cold starts. For a low-traffic
internal tool, this is viable.

---

## Security Best Practices

### VNET Integration (recommended for production)

With Premium EP1, enable VNET integration to access Azure SQL via private endpoint:

1. Create a VNET with a subnet delegated to `Microsoft.Web/serverFarms`
2. Enable VNET integration on the Function App
3. Create a private endpoint for Azure SQL in the same VNET
4. Remove public firewall rules from Azure SQL

This eliminates the need for IP-based firewall rules and keeps all traffic private.

### Managed Identity (recommended)

Instead of storing SQL credentials in app settings, use Managed Identity:

1. Enable system-assigned managed identity on the Function App
2. Grant the identity `db_datareader` and `db_datawriter` roles on `TraceParserDB`
3. Change the connection string to:
   ```
   Server=sql-traceparser-*.database.windows.net;Database=TraceParserDB;Authentication=Active Directory Managed Identity;Encrypt=True
   ```

---

## Architecture Diagram

```
User → Blazor Web App (B2) → Azure Blob Storage → [Blob Trigger] → Function App (EP1)
                                                                          ↓
                                                                    Azure SQL DB (S3)
                                                                          ↓
                                                                    DAB App Service
                                                                          ↓
                                                                    Blazor Web App (reads)
```

All components in the same Azure region (`westus2`). Internal network latency <1ms.

---

## File Reference

| File | Purpose |
|------|---------|
| `deploy.ps1` | Creates all Azure resources (EP1 plan, Function App, Web App, Storage) |
| `TraceParserFunction/host.json` | Function timeout: 1 hour |
| `TraceParserFunction/local.settings.json` | Local development settings (gitignored) |
| `TraceParserFunction/ParseEtlFunction.cs` | Blob trigger entry point |
| `TraceParserFunction/EtlParser.cs` | ETW trace parsing, 200K-row batch streaming |
| `TraceParserFunction/SqlImporter.cs` | SqlBulkCopy, dimension upserts, PromoteStageToTraceLines |
