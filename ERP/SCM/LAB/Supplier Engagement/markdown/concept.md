# 🧩 The Global Vendor Model

The **global vendor** is the central idea that Supplier Engagement is built on. Instead of maintaining the same supplier separately in every legal entity, you keep **one master profile** — the global vendor — and connect it to the operational **local (released) vendors** in Supply Chain Management. Understanding this model makes the rest of the labs (creation, lifecycle, release, collaboration) click into place.

A global vendor is the **governing record for supplier identity**: company details, contacts, addresses, agreements, certifications, and ownership. It is **not transactional** — you don't raise purchase orders or invoices against it. Transactions always run against the local vendor in a specific legal entity.

## Global vendor vs. local (released) vendor

| Aspect | Global vendor | Local (released) vendor |
|---|---|---|
| Scope | Shared across all legal entities | Specific to one legal entity (e.g., USMF) |
| Purpose | Master profile & data consolidation | Day-to-day transaction processing |
| Transactions | None (non-transactional) | Purchase orders, receipts, invoices, payments |
| Holds identity data | Company details, contacts, addresses, certificates, agreements, ownership | Legal entity–specific settings: vendor group, currency, bank accounts, tax IDs |
| Managed in | Supplier Engagement app | Supply Chain Management (synced from the global vendor) |
| Relationship | One global vendor → | can link to many local vendors (one per legal entity it is released to) |

> **Key rule:** Only vendors associated with a global vendor are accessible through the Supplier Engagement app or the supplier portal. A plain local vendor with no global vendor link cannot use the portal — which is exactly why Lab 7 migrates an existing vendor into a global vendor.

## How a global vendor is created — three origins

Every global vendor records the **origin** of how the relationship started. This lab series exercises all three:

| Creation method | Origin value | In this lab |
|---|---|---|
| Supplier submits a portal registration that you approve | `Supplier portal` | Lab 5 — Pacific Components (GV-001) |
| Internal user creates it manually in the Supplier Engagement app | `Supplier Engagement` | Lab 6 — Alps Sensors (GV-002) |
| Created from existing vendor data via the wizard in SCM | `Supply Chain Management` | Lab 7 — Acme Office Supplies (GV-003) |

## The onboarding lifecycle

A global vendor moves through a status lifecycle. Release to a legal entity becomes possible once the vendor is **Qualified**.

| Status | Meaning |
|---|---|
| `Prospect` | Newly created and under review (self-registered and manually created vendors start here) |
| `Qualified` | Passed initial validation and can be released to legal entities (wizard-migrated vendors start here directly) |
| `Approved` | Fully approved for business use |
| `Disqualified / Disapproved / Terminated` | Did not meet requirements, or is no longer active |

> **Release creates the local vendor:** When a qualified/approved global vendor is released to a legal entity (Lab 6, using the **Release vendor** command), the system creates a local vendor account in that company, linked to the same party. From then on, updates sync automatically between the Supplier Engagement app and SCM.

## Infographic — the global vendor journey (Labs 5 & 6)

The two onboarding labs trace the same lifecycle from opposite starting points:

1. **Origin** — Self-registration (GV-001) or internal invitation (GV-002)
2. **Prospect** — Created & under review
3. **Onboarding** — Supplier completes company profile in the portal
4. **Qualified** — Passed validation — eligible for release *(GV-001 stops here · Lab 5)*
5. **Approved** — Approved for business use *(Lab 6)*
6. **Released to USMF** — **Release vendor** → creates the local vendor account *(Lab 6)*
7. **Collaboration active** — Local vendor set Active — ready for PO / RFQ / invoice (Labs 8–9) *(GV-002 · Lab 6)*

- **GV-001 · Pacific Components** (Lab 5) — self-registers, onboards, and stops at *Qualified*
- **GV-002 · Alps Sensors** (Lab 6) — full lifecycle through *Approved → Released → Active*

## One profile, many legal entities

This is the essence of "global." A single global vendor profile can be **released to more than one legal entity** — each release produces its own local vendor without re-entering the supplier's identity data. Alps Sensors GmbH (GV-002) is a German supplier that Technova buys from in both its US and German companies:

**GV-002 · Alps Sensors GmbH** — One global vendor, shared identity, contacts & certificates — released to multiple legal entities:
- **USMF local vendor** — US company · USD · US vendor group
- **DEMF local vendor** — German company · EUR · DE vendor group

**Shared** (maintained once on the global vendor): company name, addresses, contacts, certificates, agreements, ownership.
**Per-entity** (kept on each local vendor): currency, vendor group, bank accounts, tax IDs, holds.

> You practice this in **Lab 6, Part D (optional)** — after releasing GV-002 to USMF, you release the *same* global vendor to `DEMF` and get a second local vendor, with no duplicate identity entry.

## The global vendor record — key tabs

The global vendor form in the Supplier Engagement app organizes supplier data across several tabs:

| Tab | What it holds |
|---|---|
| **Summary / General** | Core company data: name, type, parent, origin, primary contact, profile, ownership, contact methods, addresses, certificates, rating |
| **Lifecycle** | Status & readiness, agreements (NDA, T&Cs, code of conduct), and the related **released (local) vendor** records |
| **Capabilities** | Non-transactional attributes: products, market segments, quality standards, process capabilities |
| **Risks** | Documented supplier risks and corrective actions |
| **Assessment** | Onboarding questionnaire responses and evaluation data |
| **Portal** | Onboarding invitations, portal access status, active users, notifications |
| **Related** | Menu to view other records related to the vendor |

## Duplicate detection

Because the global vendor is a shared identity, the system checks for existing matches whenever you create or validate one. The Supplier Engagement app applies Dataverse duplicate detection rules during manual creation, and SCM validates against existing vendor party records during qualification. These checks surface possible matches so you can **merge, keep, or cancel** — they don't hard-block you. This is why Lab 2 configures duplicate detection rules and Lab 7 includes a duplicate check step.

> **How this maps to the labs:** You create three global vendors through all three origins (Labs 5–7), walk GV-002 through the full *Prospect → Qualified → Approved → Released → Active* lifecycle (Lab 6), and then transact against the resulting *local* vendors via RFQ, PO, and invoice (Labs 8–9).

Grounded in the official [Global vendor management overview](https://learn.microsoft.com/en-us/dynamics365/supply-chain/supplier-engagement/supplier-engagement-global-vendors-overview) and [Manage local vendors](https://learn.microsoft.com/en-us/dynamics365/supply-chain/supplier-engagement/supplier-engagement-manage-local-vendors) documentation.
