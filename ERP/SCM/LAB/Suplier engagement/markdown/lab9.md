# Lab 9 of 9 — PO Collaboration & Vendor Invoice — Pacific Components Ltd.

*⏱ ~60 min · Document Processing*

Complete the end-to-end procurement cycle. Alex creates a purchase order for 500 PCB-CON-M12 connectors at the awarded price and sends it to Pacific Components for confirmation. Maria confirms the PO in the supplier portal. After receiving the goods, Maria submits an invoice from the portal, and Alex posts it in SCM. This closes the TX-500 sourcing cycle through Supplier Engagement. An optional bonus part covers a small consignment inventory use case.

### Before you start
- [ ] Lab 8 complete — RFQ awarded to Pacific Components Ltd.
- [ ] Pacific Components local vendor has Collaboration activation = Active in USMF.
- [ ] Maria Santos can sign in to the supplier portal.
- [ ] Vendor invoice workflow configured in Accounts payable (Lab 3 reference).

> **Lab variable:** Lab 9 continues to use `USSEP-0002` as the example Pacific Components local vendor account. If your Lab 8 setup produced a different vendor account, substitute that value in every RFQ, PO, invoice, and consignment step.

## Part A — Create & Send PO (Alex in SCM)

### Step 1 — Open the purchase order generated in Lab 8
When you accepted the RFQ reply in Lab 8 Step 6, SCM automatically created a purchase order from the awarded bid. **Do not create a new PO** — open the one that was generated.

**Where:** Procurement and sourcing › Purchase orders › All purchase orders

Filter by vendor `USSEP-0002` or sort by created date descending. Open the PO and verify it contains:

| Field | Expected value |
|---|---|
| Vendor account | `USSEP-0002` — Pacific Components Ltd. |
| Item number | `PCB-CON-M12` |
| Quantity | `500 ea` |
| Unit price | `2.45 USD` (from the accepted bid) |
| Net amount | `USD 1,225.00` |
| Delivery date | `2026-09-10` |

> **Note:** If the PO was not auto-generated (e.g., the RFQ Purchase type was not set to *Purchase order*), create a new PO manually: vendor `USSEP-0002`, item `PCB-CON-M12`, qty `500`, price `2.45`, site `1`, warehouse `11`.

### Step 2 — Confirm the PO and send it to the supplier portal
Open the PO from Step 1. On the Action Pane → **Purchase** tab → click **Confirm**. This changes the PO status to `Confirmed` and triggers the vendor collaboration send, making the PO visible to Pacific Components in the supplier portal.

> **Note — Vendor PO Confirmation flow:** Pacific Components' local vendor is set to **Collaboration activation = Active (PO is not auto-confirmed)**. With this method, the buyer's **Confirm** is what publishes the PO to the portal, where the vendor then accepts (or requests changes) — the vendor's acceptance does not auto-confirm the order. There is no separate "Send to supplier" button. Until you confirm it, the PO stays at `Open order` and never reaches the portal.

> ⚠️ **PO not appearing on the portal? Check these in order:**
> - **PO not Confirmed** — the most common cause. Confirm it via Action Pane → Purchase tab → Confirm.
> - **Vendor not enabled for collaboration** — go to **Accounts payable → Vendors → All vendors → USSEP-0002 → General tab** and verify **Collaboration activation = Active**.
> - **Maria's portal security role** — in SCM go to **Procurement and sourcing → Vendors → Supplier Engagement → External users**, confirm Maria has the *Vendor portal user* or *Supplier Portal Administrator* role.
> - **Stale portal session** — have Maria sign out, clear browser cache, and sign back in. The portal caches the PO list.

> ✅ **Result:** PO status = Confirmed. The PO appears in the supplier portal under Pacific Components' account, awaiting confirmation.

## Part B — PO Visible to Supplier (portal)

### Step 3 — Confirm the PO reached the supplier portal
Because Alex confirmed the PO in Step 2, it is now shared with Pacific Components. Maria signs in to the supplier portal, opens **Purchase orders**, and sees PO `00000125` under the **Pending delivery** tile. That visibility *is* the collaboration hand-off — there is no Accept/Confirm button to click, because a buyer-confirmed PO is already agreed and simply awaits goods.

> **Note — The three portal tiles:** **For review** = POs awaiting the supplier's response; **Awaiting customer review** = supplier requested a change, buyer must respond; **Pending delivery** = confirmed POs awaiting shipment. A change-request conversation only happens if a PO reaches the portal *before* buyer confirmation (landing in *For review*) — optional and not required for this lab.

> ✅ **Result:** PO 00000125 is visible to Pacific Components under Pending delivery. The buyer→supplier link is proven; proceed to product receipt.

## Part C — Receive Goods & Supplier Invoice

### Step 4 — Alex posts a product receipt in SCM
Goods arrive from Pacific Components. On the confirmed PO, go to Action Pane → **Receive** tab → **Product receipt**. In the dialog enter:

| Field | Value |
|---|---|
| Product receipt number | `PR-2026-0089` |
| Quantity | `500` (full delivery) |
| Date | Today's date |

Click **OK**. The inventory is received into warehouse 11.

> ✅ **Result:** Product receipt posted. Inventory on-hand for PCB-CON-M12 increases by 500 in USMF, warehouse 11.

### Step 5 — Maria submits the vendor invoice via the supplier portal
Maria signs in to the supplier portal and navigates to **Vendor invoices → New invoice**. She fills in the invoice details:

| Field | Value |
|---|---|
| Invoice number | `INV-PC-2026-001` |
| Invoice date | Today's date |
| PO reference | `00000125` |
| Quantity invoiced | `500` |
| Invoice amount | `USD 1,225.00` |

Maria attaches the PDF invoice document and submits it.

> **Note:** The supplier portal supports invoice submission as part of vendor collaboration; exact portal labels and layout may differ in preview. The submitted invoice flows into SCM for review and posting.

> ✅ **Result:** Invoice INV-PC-2026-001 appears in SCM as a pending vendor invoice, awaiting review.

### Step 6 — Alex reviews and posts the invoice in SCM
**Where:** Accounts payable › Vendor invoices › Pending vendor invoices

Find `INV-PC-2026-001`. Open it and verify the three-way match: PO line (500 × 2.45), product receipt (500 received), and invoice (500 × 2.45 = 1,225.00). All three should align with no matching exceptions.

On the Action Pane click **Post**. The invoice is posted and a voucher is created in the general ledger.

> ✅ **Result:** Invoice posted. Status = Posted in Accounts payable. A payment voucher of USD 1,225.00 is created and the invoice appears in Open transactions for Pacific Components Ltd. — awaiting payment processing.

## Part D — Bonus: Consignment Inventory Mini Use Case *(Optional)*

### Step 7 — (Optional) Set up a consignment agreement and receive vendor-owned stock
**Where:** Procurement and sourcing › Vendors › All vendors

Open `USSEP-0002` (Pacific Components Ltd.) and, on the **Purchase order defaults** tab, add a consignment agreement for item `PCB-CON-M12` at the agreed price of `2.45 USD`. Then create and confirm a **consignment replenishment order** for `200 ea`, site `1`, warehouse `11` — the same flow as a normal PO, except the stock lands as *vendor-owned* inventory with no payable created yet.

**Where:** Procurement and sourcing › Purchase orders › All consignment replenishment orders

> **Note:** The **Maintain consignment replenishment orders** and **Maintain consignment product receipt** duties needed for this step were already added to the Purchasing manager / Purchasing agent roles back in **Lab 3, Part B, Step 3**.

> ✅ **Result:** 200 ea of PCB-CON-M12 are on hand in warehouse 11, owned by Pacific Components Ltd. — no vendor invoice or liability exists yet, since you only pay for what you actually use.

### Step 8 — (Optional) Consume the stock, which auto-generates a consigned PO
**Where:** Inventory management › Journal entries › Items › Inventory ownership change journal

When the warehouse or production actually consumes some of that stock (for example `50 ea`), post an **ownership change journal** line for PCB-CON-M12, changing ownership from `Consignment` to `Regular` (company-owned). Posting the journal creates a product receipt for the consumed quantity and automatically generates a **consigned purchase order** for that 50 ea — this is what creates the vendor's payable, not the earlier receipt of the 200 ea.

> **Note — Why this matters:** with a normal PO, receiving goods creates the liability immediately. With consignment, the vendor is paid only for what you consume, tracked at whatever cadence you run the ownership-change journal — useful for high-value or fast-moving parts where you don't want to prepay for on-hand stock.

> ✅ **Result:** 50 ea of PCB-CON-M12 move from vendor-owned to company-owned, and a consigned PO for 50 ea is generated. The remaining 150 ea stays vendor-owned and unbilled until the next consumption event.

### Step 9 — (Optional) Maria monitors and invoices consignment stock from the portal
**Where:** Supplier portal › Consignment inventory

Maria signs in to the supplier portal and opens the **Consignment inventory** workspace (top nav bar, or the Consignment inventory panel on the home page). It shows four tiles, each a count she can drill into:

| Tile | What it shows |
|---|---|
| `On-hand` | Current stock Pacific Components still owns at the USMF warehouse — the 200 ea from Step 7, dropping to 150 ea after Step 8. |
| `Received items` | Product receipt lines created when ownership changed from vendor to customer (the 50 ea from Step 8's journal). Selecting a line opens the related PO. |
| `Consigned POs` | Purchase orders auto-generated from consumption — the 50 ea consigned PO created in Step 8. |
| `Invoiced POs` | Consigned POs that have been invoiced, with header/line detail including consignment-specific fields. |

Maria confirms the consigned PO for 50 ea and submits her invoice against it — the same portal invoicing flow as Step 5, but scoped only to what Pacific Components has actually shipped and Contoso has consumed, never the full 200 ea sitting on the shelf.

> **Note:** Unlike Part A–C, the vendor never sees a "Confirm PO" step for the initial 200 ea replenishment order arriving — that's just a stock movement. The vendor's portal actions (confirm, invoice) only kick in once a consigned PO exists for consumed quantity.

> ✅ **Result:** Maria sees On-hand = 150, Received items and Consigned POs each showing the 50 ea event, and can invoice that consigned PO from the portal — without touching the untouched 150 ea still owned by Pacific Components.

## Lab Series Complete

### What you have configured and validated
By completing this lab series you have stood up a full Supplier Engagement environment from scratch:

| Lab | Outcome |
|---|---|
| Lab 0 | Environment verified — SCM version, Dataverse link, virtual entities, service account |
| Lab 1 | Supplier Engagement app + Power Pages portal installed and activated |
| Lab 2 | Portal URL, email templates, cloud flows, and duplicate detection configured |
| Lab 3 | Feature enabled in SCM, workflows, security roles, and localization metadata set |
| Lab 4 | Reference data populated (certs, risks, capabilities, segments, questionnaire) |
| Lab 5 | Pacific Components self-registered, onboarded, and qualified (GV-001) |
| Lab 6 | Alps Sensors internally invited, full lifecycle: qualify → approve → release → activate (GV-002) |
| Lab 7 | Acme Office Supplies migrated from existing vendor via Global Vendor Creation Wizard (GV-003) |
| Lab 8 | RFQ issued, bid received via portal, awarded to Pacific Components |
| Lab 9 | PO confirmed via portal, goods received, invoice submitted by supplier and posted |

> **Note — Next steps to explore:** Risk management and corrective actions (assign a risk scenario to GV-001 and track a corrective action), deeper consignment inventory scenarios via the portal (Part D above covers a starter use case), procurement category requests from suppliers, and the Supply Risk Assessment Power BI report.
