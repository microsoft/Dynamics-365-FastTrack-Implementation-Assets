# Sales Order Agent architecture - 1.0.9.0

Date: 2026-11-03. Content Understanding analyzer `sales_order_extraction_v2_0_7`, native Information form plus
Customer Match, two dashboards, configurable customer matching with a Setup screen, unit-of-measure aliases, and
guarded business-agent processing.

```mermaid
flowchart TD
    Mail["Approved personal OR shared mailbox/folder"]
    Filter["CU intake: source selection and attachment size/type filter"]
    CU["Azure Content Understanding v2.0.7"]
    Stage["Dataverse staging: original file + canonical JSON + count evidence"]
    Count{"Verified independent source-row count?"}
    Loader["Loader: header + complete lines; printed unit normalized by the alias list; load-complete marker"]
    Units["Setup > Units of measure: alias list"]
    Policy["Setup > Matching rules: Published policy snapshot"]
    ERPRead["F&O customer candidates across companies; bounded complete retrieval"]
    Resolve["Customer resolver: normalized name/email/selected address, scored with the Published rules"]
    Proof{"Complete fresh proof; threshold and margin met; no ambiguity?"}
    Held["Held / Manual Review: retained evidence; suggestions only"]
    Release{"Release enabled and current proof/state guards?"}
    WSC["WhenStatusChanges / readiness"]
    Agent["Sales Order Agent V1.2: Invoker Dataverse + ERP MCP"]
    Validate["Skills: customer proof, complete line reads, product/unit validation"]
    Save["SAVE preflight; single guarded attempt; ERP writes + readback"]
    ERP["D365 F&O sales order"]
    Final["Dataverse persisted outcome + ERP number/errors"]
    UI["Native header/lines + read-only Customer Match evidence"]
    Dash["Both dashboards: saved received / ERP-processed / failed totals"]
    Review["Owner/reviewer: inspect, reconcile; no blind retries"]

    Mail --> Filter --> CU --> Stage --> Count
    Count -->|yes| Loader --> Resolve
    Count -->|no or provider failure| Held
    Units --> Loader
    Policy --> Resolve
    ERPRead --> Resolve
    Resolve --> Proof
    Proof -->|no| Held
    Proof -->|yes| Release
    Release -->|held by default| Held
    Release -->|enabled| WSC --> Agent --> Validate
    Validate -->|all eligible and persisted| Save --> ERP
    Validate -->|invalid or incomplete| Held
    ERP -->|independent readback| Final
    Save -->|failed or uncertain| Review
    Stage --> UI
    Loader --> UI
    Held --> UI
    Final --> UI
    Stage --> Dash
    Final --> Dash
    Held --> Review
```

## Boundaries and contracts

| Boundary | Contract and failure behavior |
|---|---|
| Mail to intake | One configured source route per mailbox/folder; surviving attachments or email body, not both. Default minimum 4096 bytes; small-PDF exception off. Extension acceptance is not analyzer format certification. |
| Intake to CU | Correct target resource/authentication and current analyzer pointer; preserve original bytes/operation evidence. Provider failure must not become extracted business data. |
| CU to loader | Persist canonical JSON and source-row/count verification. Count equality is necessary, not a guarantee of correct fields. |
| Loader | Persist complete header/lines and the explicit source ShipTo separately from the operational address fallback. Normalize the printed unit with the alias list; the extraction JSON keeps the unit as printed. Do not dispatch on a partially loaded header. |
| Loader to resolver | Resolver starts only for a completely loaded header. |
| Resolver to proof consumers | Complete candidate and policy reads, normalized proof, source/policy freshness and persisted read verification. Missing, stale or malformed proof fails closed. |
| Matching rules | Exactly one Published policy per key; the resolver reads its snapshot on every run. A rule change while an order is in flight stops that order for review. |
| Address selection | An address basis that is part of the Published policy. BillTo compares the invoice address; ShipTo compares an explicit source address with a valid ERP default delivery address. No try-both or fuzzy auto-accept. |
| Agent to ERP | Invoking-user permissions, matched company/customer, current guarded state, complete line reads and product/unit preflight. The agent validates only from status New and creates an ERP order only when no ERP number exists. The existing duplicate lookup is not transactional. |
| Guard stops | A run that stops because the proof, the matching rules or the load state changed is recorded as Cancelled and leaves the order unchanged for re-run. |
| ERP to completion | Persist the actual outcome and verify ERP data, not just tool prose/status. Partial or uncertain writes require reconciliation before replay. |
| UI | Original native editable controls retained; matching evidence viewer read-only. Dashboards summarize accessible saved records. |

## Deployment state

Shared intake and the resolver's `ReleaseHeaders` ship stopped/false. Those controls are part of the package and are
not permission to activate processing in a target. Connections, API/Entra base-resource bindings and actual Invoker
access do not travel as usable credentials in a solution ZIP, and the resolver's ERP host name is set per target.
No Azure Function or custom connector is required by this CU route.

See the [deployment guide](./deployment-guide.md), [DLP requirements](./dlp-and-security-requirements.md),
[Customer Matching Rules](./customer-matching-rules.md) and the [FAQ](./faq.md).
