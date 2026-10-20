# Release notes

## 2.0.0.1 - new implementation

**Distribution:** unmanaged solution, separate from legacy v1.

**Package:** `InventoryFulfillmentAgent_V2_2.0.0.1_unmanaged.zip`

**SHA-256:** `b1aaeb388a1127c49b4f64fbe1c71b2eb9f59136bd6cc2b1354802118ab23d04`

### Included

- GitHub Copilot-based Copilot Studio orchestration (`CLICopilotRecognizer`), retaining the `Sonnet5` model configuration.
- Sales and transfer skills, native ERP MCP binding, exact-item inventory/ATP, product resolution, reservation, and unreservation tools.
- Five isolated flows, including the token helper; four native workflow-tool registrations.
- Seven environment-variable definitions and two unbound connection references.
- Corrected empty conversation-starter metadata that previously prevented Teams manifest generation.
- User-facing labels without the "v2" suffix; immutable internal identities remain versioned.
- Instructions that use the explicit or configured legal entity for order proposals rather than the ERP user's current company.
- Product-routing corrections for size syntax and colours that are part of product names, while preserving explicitly requested filters.
- Blank workflow-level IVS defaults as well as blank target environment-variable values. The exact-inventory flow no longer falls back to an exported source endpoint, environment, or demo company.

### Compatibility

This is not an in-place v1 upgrade. See [version comparison](version-comparison.md). The package preserves its original logical identities and input/output slots. Do not rename internal `V2` references or shorten skill/main instructions as cleanup.

### Validation and limitations

Fresh-install validation is blocked before IFA import by a first-party prerequisite installation failure. See [validation](validation.md) for completed checks, the blocker, and outstanding gates. Earlier configured-environment testing is supporting evidence, not proof of the current package's fresh installation.

- The prior 116-case evaluation scored **115 PASS, 1 FAIL** (99.1%) evidence-led. The native General quality grader reported 86/103 passes and was advisory.
- **FUL-014 remains open:** an intermittent response can label another warehouse's stock as the requested store's stock. Require explicit location verification and confirmation before acting; do not treat stock from another location as local availability.
- Eleven evaluation cases carried fixture-drift qualifications. Empty ATP dates did not establish populated ATP acceptance.
- The three-consecutive-unchanged-run stability gate was not demonstrated.
- A universal customer-neutral fulfillment policy, complete production security assessment, and every tenant/channel combination are not certified.
- Runtime evaluation cases, results, secrets, connections, and demo business data are not shipped.

The distribution ZIP has been repacked from reviewed deployment source. It is not a raw tenant export, and the prior published agent's timestamp is not proof that this ZIP was imported. Use the package hash and the fresh-install record together.

## 1.0.0.7 - retained legacy implementation

The original ZIP remains unchanged at its existing path. It includes the IVS redirect-token fix, default-company support for IVS actions, current on-hand mapping, and improved empty-result handling.

Existing v1 installations can continue using their existing version-specific procedure. V2 availability does not automatically migrate, upgrade, retire, or certify them.
