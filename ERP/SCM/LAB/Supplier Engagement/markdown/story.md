# 🏭 Technova Industries — Lab Scenario

Technova Industries is a mid-size precision electronics manufacturer operating in the `USMF` legal entity (Contoso US Manufacturing). The company has just stood up a fresh Dynamics 365 SCM 10.0.48 instance and is rolling out the **Supplier Engagement** preview module to replace manual email-based supplier interactions.

The immediate driver is the **TX-500 Smart Controller Board** — a new product line requiring three new strategic suppliers to be onboarded before the Q4 2026 production run. Procurement Manager **Alex Chen** will own all internal steps. The three suppliers will engage exclusively through the new Supplier Portal.

## Key Suppliers to Onboard

| Global Vendor | Company | Country | Category | Onboarding Path |
|---|---|---|---|---|
| `GV-001` | **Pacific Components Ltd.** | United States | Electronic Components / PCB | Supplier self-registration |
| `GV-002` | **Alps Sensors GmbH** | Germany | Sensors & Transducers | Internal invitation |
| `GV-003` | **Acme Office Supplies** | United States | Office Supplies | Existing vendor migration |

> **About "GV-001 / GV-002 / GV-003":** these are friendly labels used throughout this guide to refer to the three suppliers. They are *not* the literal Global Vendor Number — the system assigns that automatically from your environment's number sequence (e.g., a value like `GV-000001` or a plain running number), so the actual numbers you see will differ. Identify each record by its **company name**, not the GV-00x label.

## Personas

| Persona | Type | Role | Email |
|---|---|---|---|
| **Alex Chen** | 👤 Internal | Procurement Manager, Technova Industries | alex.chen@technova.com |
| **Maria Santos** | 🌐 Supplier | Supplier Admin, Pacific Components Ltd. | m.santos@pacificcomponents.com |
| **Klaus Weber** | 🌐 Supplier | Supplier Admin, Alps Sensors GmbH | k.weber@alps-sensors.de |

## Lab Reference Data — Use these values throughout all labs

| Entity | Value |
|---|---|
| Legal entity | `USMF` |
| Min SCM version | `10.0.48 build 10.0.2645.52` |
| RFQ item | `PCB-CON-M12` — M12 PCB Connector |
| RFQ quantity | `500 ea`, needed by `2026-09-15` |
| Awarded unit price | `USD 2.45` |
| PO total | `USD 1,225.00` (500 × 2.45) |
| PO Invoice number | `INV-PC-2026-001` |
| Certificate types | ISO 9001:2015 · RoHS 2015/863/EU · IATF 16949 |
| Certifying organizations | Bureau Veritas · SGS Group · TÜV Rheinland |
| Supplier segments | Tier 1 Strategic · Tier 2 Preferred · Tier 3 Spot |

> ⚠️ **Preview disclaimer:** Supplier Engagement is a preview feature in D365 SCM 10.0.48. It is not intended for production use and is subject to supplemental terms of use. All lab steps are grounded in official Microsoft documentation dated July 27, 2026 and rechecked on September 3, 2026.
