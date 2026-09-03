# Lab 7 of 9 — Migrate Existing Vendor to Global Vendor — Acme Office Supplies

*⏱ ~20 min · Migration*

Technova already has an existing local vendor, **Acme Office Supplies (vendor 1001)**, that predates Supplier Engagement. This lab shows how to bring an existing vendor into the global vendor model using the built-in migration wizard, so it can be onboarded to the supplier portal without re-entering its identity data.

### Before you start
- [ ] Labs 0–3 complete — Supplier Engagement enabled in both Power Platform and SCM.
- [ ] An existing local vendor (`Acme Office Supplies`, vendor account `1001`) exists in the target legal entity (USMF).

## Part A — Run the Global Vendor Creation Wizard

### Step 1 — Select the vendor and launch the wizard
**Where:** Accounts payable › Vendors › All vendors

Find and select **Acme Office Supplies** (vendor account `1001`). On the Action Pane, go to the **Global vendor** tab (or **Vendor** menu, depending on version) and click **Create global vendor**. This launches the **Global Vendor Creation Wizard**.

The wizard walks through four pages:

| Page | Purpose |
|---|---|
| 1. Welcome | Introduces the wizard and process |
| 2. Select vendor | Confirms the source local vendor (`1001` — Acme Office Supplies) — pre-populated since you launched from the vendor record |
| 3. Check for duplicates | Runs a duplicate check against existing global vendors by name/address/contact match |
| 4. Summary | Reviews the data that will be copied to the new global vendor before submission |

Step through each page, reviewing the duplicate-check results (none expected for this lab), and click **Submit** on the Summary page.

> **Note:** The wizard submits an asynchronous batch job to create the global vendor. It does not complete instantly — processing typically finishes within a few minutes.

> ✅ **Result:** A confirmation message indicates the request was submitted. The wizard closes and returns you to the vendor record.

## Part B — Verify the Migration

### Step 2 — Review the Global Vendor Creation Log
**Where:** Procurement and sourcing › Vendors › Supplier engagement › Global vendor creation log

Find the log entry for vendor `1001` / Acme Office Supplies. Wait for **Status** to show `Completed`. If it shows `Error`, open the entry to view the error details.

> ✅ **Result:** Log entry shows Status = Completed.

### Step 3 — Confirm the new global vendor in SCM and the Supplier Engagement app
**Where:** Procurement and sourcing › Vendors › Supplier engagement › All global vendors (SCM), and General → Global vendors (Supplier Engagement app)

Confirm a new global vendor record for **Acme Office Supplies** now exists (this is GV-003), with:

| Field | Expected Value |
|---|---|
| Origin | `Supply Chain Management` |
| Status | `Qualified` (wizard-migrated vendors start Qualified, skipping the Prospect review step) |
| Linked local vendor | `1001` — Acme Office Supplies (USMF) — visible on the Lifecycle tab |

> **Note:** Unlike Labs 5 and 6, this global vendor starts at `Qualified` rather than `Prospect`, since it is derived from an already-vetted, existing vendor relationship rather than a new registration.

> ✅ **Result:** GV-003 (Acme Office Supplies) appears in both SCM and the Supplier Engagement app, linked to local vendor 1001, with Origin = Supply Chain Management.

### Step 4 — (Optional) Enable collaboration activation for portal access
If Acme Office Supplies should also transact through the supplier portal, open the local vendor `1001` record, go to the **Vendor collaboration** section on the **General** tab, and set **Collaboration activation** to `Active (PO is not auto-confirmed)`, then **Save** — the same step used in Lab 6, Step 9.

> ✅ **Result:** Acme Office Supplies is portal-enabled, using the same global vendor migration path as any newly onboarded supplier.
