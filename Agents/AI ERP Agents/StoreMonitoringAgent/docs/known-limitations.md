# Known Limitations

## Network & Connectivity

- **Event delivery is deferred, not lost** — Windows Event Logs are written locally and AMA caches data on disk, so events are forwarded once connectivity is restored. However, extended outages may exceed AMA's local cache capacity, causing older buffered data to be dropped.
- **Offline detection lag** — heartbeats are sent every 60 seconds, but the offline alert rule evaluates on a 5-minute window, so up to ~5 minutes may pass before a disconnected device is flagged.

## Platform Support

- **Windows-only** — Linux, Android, and iOS POS devices are not supported.
- **Browser-based Store Commerce for web is not supported** — only the installed Windows application (Store Commerce app) is monitored.
- **SQL Server-only** for database metrics — PostgreSQL, MySQL, and other engines are not supported.

## Data Collection & Latency

- **Log Analytics ingestion delay** — query results reflect data that is typically a few minutes behind real-time.
- **Performance counters sampled once per day** by default (86,400 s) — provides a snapshot, not continuous profiling.
- **Database metrics collected every 6 hours** by default — transient issues between cycles are missed.
- **XPath event filters may miss new error types** — only explicitly configured Event IDs and providers are captured.

## Copilot Studio Agent

- **Non-deterministic response generation** — the AI may produce inaccurate summaries or miss relevant details for complex or ambiguous questions.
- **Predefined topics only** — queries outside Application Errors, Hardware Station Errors, Retail Server Errors, Database Metrics, and Device Online/Offline require custom topic authoring.
- **Single Log Analytics workspace** — cross-workspace queries are not supported.

## DatabaseMetricsService

- **Windows Integrated Authentication only** — SQL auth or Azure AD auth requires manual configuration.
- **Manual SQL permissions required** — after MSI installation, run `Grant-SqlPermissions.ps1` to create the SQL login for the Virtual Service Account (`NT SERVICE\DatabaseMetricsService`) and grant `VIEW SERVER STATE` / `VIEW DATABASE STATE`. Before uninstalling, run `Revoke-SqlPermissions.ps1` to clean up.
- **Top-10 tables and indexes only** — databases with more objects have incomplete visibility.
- **Single database per service instance** — multi-database devices need separate instances.

## Scalability & Operations

- **Azure Policy remediation takes 10–15 minutes** — newly onboarded devices are unmonitored during this window.
- **Service principal secrets expire** (default 24 months) — onboarding fails silently if not rotated.
- **No built-in multi-store segmentation** — all devices across all stores are queried together
- **No automated deployment for Copilot Studio** — the agent solution must be manually imported and configured.

## Security

- **All-or-nothing query access** — any user with agent access can query all device data; no row-level or device-level filtering is available.
