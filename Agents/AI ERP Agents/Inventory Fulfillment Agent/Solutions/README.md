# Solution downloads

Start with the [version selector](../README.md) and follow the guide for your chosen version. Both downloads are **unmanaged** implementation samples; neither is a managed production deployment or an automated rollback boundary.

| File | Solution identity | Guide |
| --- | --- | --- |
| [InventoryFulfillmentAgent_V2_2.0.0.1_unmanaged.zip](InventoryFulfillmentAgent_V2_2.0.0.1_unmanaged.zip) | `InventoryFulfillmentAgent_V2`, `2.0.0.1` | [Install v2](../docs/install-v2.md) |
| [InventoryFulfillmentAgent_V1_1_0_0_7.zip](InventoryFulfillmentAgent_V1_1_0_0_7.zip) | `InventoryFulfillmentAgent_V1`, `1.0.0.7` | [Legacy v1 guide](../docs/legacy-v1-installation.md) |

The v1 ZIP is retained byte-for-byte at its existing path. V2 is a separate installation, not an update to v1. Do not run both against shared transactional fixtures or expose both under indistinguishable channel names during cutover.

## V2 configuration and integrity

- [Blank deployment settings](deployment-settings.v2.example.json): populate only in an owner-restricted file outside source control.
- [Package checksum](InventoryFulfillmentAgent_V2_2.0.0.1_unmanaged.zip.sha256): compare after download.
- [Release notes](../docs/release-notes.md) and [validation record](../docs/validation.md).

```powershell
Get-FileHash -LiteralPath .\InventoryFulfillmentAgent_V2_2.0.0.1_unmanaged.zip -Algorithm SHA256
```

Import the solution ZIP itself, not GitHub's repository ZIP. Do not extract/repack or edit its component IDs, native association records, input slots, or internal schema names.

## Legacy 1.0.0.7 release notes

- Fixed IVS token retrieval for environments requiring the documented security-service redirect flow.
- Added environment-variable support for default legal entity and used it in IVS calls.
- Updated on-hand mapping for total on-hand, available to reserve, and total available.
- Improved empty-result handling.
- Removed the previous legal-entity helper flow.
- Preserved upgrade compatibility within the existing **v1** solution identity. This does not imply v1-to-v2 upgrade compatibility.
