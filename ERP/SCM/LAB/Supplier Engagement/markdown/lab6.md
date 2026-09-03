# Lab 6 of 9 — Internal Invitation & Full Vendor Lifecycle — Alps Sensors GmbH

*⏱ ~35 min · Scenario*

Alex manually creates a Prospect global vendor (GV-002) for Alps Sensors GmbH and invites Klaus Weber to the portal. After Klaus completes onboarding, Alex qualifies and then approves the vendor. Finally, Alex releases GV-002 to the USMF legal entity, creating a local vendor account, and enables the vendor for portal-based purchase order collaboration. An optional **Part D** releases the *same* global vendor to a second legal entity (DEMF) to demonstrate the one-profile-across-many-companies model.

### Before you start
- [ ] Lab 5 complete — self-registration flow understood.
- [ ] Klaus Weber test account (`k.weber@alps-sensors.de`) has a Microsoft Entra identity.
- [ ] Reference data from Lab 4 is available (segments, vendor types, capabilities).

## Part A — Create Global Vendor Manually

### Step 1 — Alex creates a new Prospect global vendor
In the Supplier Engagement app, go to **General → Global vendors → New**. Only **Name** is mandatory; the rest are optional but fill them in for the demo. **Country/Region of Operation** and **Type** are *lookups* — click the field and start typing to filter, then pick from the list.

| Field (exact label on form) | Value | Notes |
|---|---|---|
| Name * | `Alps Sensors GmbH` | Required. |
| Country/Region of Operation | `Germany` | Lookup. |
| Type | `Direct Material` | Lookup to the *Global vendor types* you created in Lab 4. |
| Organization Number | `DE 12345 6789` | Free text. |
| Number of Employees | `145` | Whole number. |
| Primary Contact URL | `www.alps-sensors.de` | This is the field used for the company website (there is no separate "Website" field). |

> **Note:** Segment is not a header field. A global vendor can belong to several segments, so segments are managed through the **Segments** related tab / subgrid rather than a single dropdown on the header. After you save the record, open the **Segments** area and add `Tier 2 Preferred`.

Click **Save**. The record is created with Status = `Prospect`.

### Step 2 — Add address and contact information
On the **Summary** tab, find the **Addresses** section and click **+ New** (or **New Address**) to add the primary address. **Country/Region** is a lookup; the other fields are free text.

| Field | Value |
|---|---|
| Street | `Kaiserswerther Str. 115` |
| City | `Ratingen` |
| ZIP/Postal Code | `40880` |
| Country/Region | `Germany` |

On the **Contacts** tab (or the **Contacts** subgrid), click **New Contact** and fill the quick-create form:

| Field | Value |
|---|---|
| First Name | `Klaus` |
| Last Name | `Weber` |
| Email | `k.weber@alps-sensors.de` |
| Phone (Business Phone) | `+49-211-555-0200` |

> ⚠️ **Warning — Placeholder identity — use a real email for the contact.** *Klaus Weber* and `k.weber@alps-sensors.de` are placeholders for the demo persona. The portal invitation is sent to whatever you enter in **Email**, and that address becomes the Microsoft Entra guest you later sign in with — so enter a **real external inbox you control** (for example a personal Gmail/Outlook address). You can keep the display name (Klaus Weber) as-is; only the **Email** must be real. Use the *same* address consistently for every sign-in.

Save the contact. Back on the **Summary** tab, set Klaus Weber as the **Primary contact**.

## Part B — Invite to Portal & Approve User

### Step 3 — Invite Alps Sensors to the supplier portal
On the GV-002 record command bar, click **Invite to supplier portal**. The system sends an invitation email to Klaus Weber (`k.weber@alps-sensors.de`) and creates a portal user request in SCM with Klaus provisioned as *Global Vendor Administrator*.

> **Note:** The "Invite to supplier portal" button only appears if a Primary contact with a valid email is set on the global vendor record.

> ⚠️ **Warning — Dev/trial shortcut — create the Entra guest via Microsoft Teams.**
> **Why:** the portal signs users in through Entra (Azure AD), so the external email must first exist in the tenant as a *B2B guest*. The built-in "Invite to supplier portal" relies on a Dataverse email server profile to deliver its invitation — and dev/trial environments usually have none, so that email is generated but never actually sent. Result: no guest, nothing to sign in with.
>
> **Dev/trial workaround:** in **Microsoft Teams**, add the supplier's email (`k.weber@alps-sensors.de` — or your real test inbox) as a *guest member of any team*. Teams raises the Entra B2B invitation on your behalf and sends its own *"Accept invitation"* email from `invites@microsoft.com`, which the person redeems in seconds. Once redeemed, the guest exists in the tenant; they sign in to the portal and Power Pages matches them to the contact by email — no portal invitation email required.
>
> **Preferred path:** configure Lab 0 Step 7 and Lab 3 Step 5 so the FSCM workflow runs **Provision Microsoft Entra ID B2B user**. In that path, the guest is created by FSCM and the same Entra **Object ID** is stored on the Supplier Engagement contact automatically.
>
> **Do it once — don't remove & re-add.** Removing then re-adding the guest mints a *new* Entra object ID that no longer matches the ID stored on the contact's External Identity record, producing the `"Invalid sign-in attempt"` error. If that happens, an admin must re-point the contact's External Identity to the current guest's object ID (see the sign-in troubleshooting box in Lab 5, Step 5).

### Step 4 — Approve Klaus's portal user request in SCM
**Where:** Procurement and sourcing › Vendors › Supplier Engagement › Portal user requests

Find the request for Klaus Weber and click **Approve**. (Auto-approves if Lab 3 Step 5 configured.) Klaus receives a portal access confirmation email.

> ✅ **Result:** Klaus's portal access is active. He can sign in to the supplier portal and see his company profile.

### Step 5 — Klaus signs in and completes onboarding
Klaus opens the invitation email, clicks the portal link, and signs in. He completes the onboarding form, adding:
- Confirm company details (populated from manual entry, Klaus reviews and supplements)
- Certificate: `IATF 16949`, certifying org = `TÜV Rheinland`, **certification number** = `TR-16949-2024-8842`, valid from `2024-06-01` to `2027-05-31` *(Certification number, type, certifying org, and both dates are all required.)*
- Capabilities: `Electrical Testing & Inspection`
- Self-assessment: complete all four questions

Klaus clicks **Submit** on the final onboarding step.

## Part C — Qualify, Approve & Release

### Step 6 — Alex qualifies GV-002
In the Supplier Engagement app, open **Alps Sensors GmbH (GV-002)**. Review all onboarding data. On the command bar click **Qualify**. Enter comment: `IATF 16949 verified. Electrical testing capability confirmed. Approved for sensor procurement.` Click **OK**.

> ✅ **Result:** Status = Qualified. Global vendor party created in SCM and data synchronized.

### Step 7 — Alex approves GV-002
On the command bar click **Approve → Approve**. Enter comment: `Meets all qualification and compliance criteria. Cleared for release to USMF.` Click **OK**.

> ✅ **Result:** Status = Approved. GV-002 is now eligible for release to a legal entity.

### Step 8 — Release GV-002 to USMF legal entity
On the GV-002 record command bar, click **Release vendor**. Select **OK** in the confirmation dialog. In the **Release vendor** dialog, enter:

| Field | Value |
|---|---|
| Global vendor | Alps Sensors GmbH (read-only reference) |
| Legal entity | `USMF` |
| Vendor group | Select any **active vendor group configured in this legal entity** (e.g., `10`). Vendor groups vary by environment — if you don't see a group named "Foreign vendors", just pick any group in the list. They're defined in SCM under *Accounts payable → Setup → Vendor groups*; create one there first if the dropdown is empty. |
| Vendor number | Enter a vendor number (or leave to auto-number per group) |
| Currency code | `EUR` (leave blank to use the legal entity default) |
| Vendor hold | Leave blank (vendor is not on hold) |

Click **Release**. The system creates a local vendor account in USMF linked to the same party as GV-002.

> ✅ **Result:** A local vendor account appears in SCM for Alps Sensors GmbH under USMF. The Lifecycle tab shows the local vendor in the Vendors section.

### Step 9 — Enable the local vendor for supplier portal collaboration
In the Supplier Engagement app, open the **Alps Sensors GmbH (GV-002)** record and open the **Lifecycle** tab. In the **Vendors** section, select the **Vendor account** link for the USMF local vendor. The vendor opens; on the **General** tab, in the **Vendor collaboration** section, set **Collaboration activation** to one of:

| Value | Behavior |
|---|---|
| `Active (PO is not auto-confirmed)` | Purchase orders require manual confirmation by the supplier (use this for the lab) |
| `Active (PO is auto-confirmed)` | Purchase orders are automatically confirmed on submission |

On the command bar, click **Save**.

> **Note:** This activation step is required before the vendor can see purchase orders in the supplier portal. Without it, the PO view is empty for this vendor's portal users.

> ✅ **Result:** Alps Sensors GmbH local vendor has Collaboration activation = Active. Klaus can now see purchase orders in the supplier portal for the USMF legal entity.

## Part D — Release to a Second Legal Entity *(optional · illustrates the global vendor model)*

### Step 10 — (Optional) Release the same global vendor (GV-002) to DEMF
Technova also buys from Alps Sensors through its German company. Because GV-002 is a **single global profile**, you can release it to a second legal entity without re-entering any identity data — demonstrating the core value of the global vendor model.

In the Supplier Engagement app, open **Alps Sensors GmbH (GV-002)**. On the command bar click **Release vendor**, select **OK** in the confirmation dialog, and enter:

| Field | Value |
|---|---|
| Global vendor | Alps Sensors GmbH (read-only reference) |
| Legal entity | `DEMF` (the German company) |
| Vendor group | Select the appropriate German vendor group |
| Vendor number | Enter a vendor number (or leave to auto-number per group) |
| Currency code | `EUR` |
| Vendor hold | Leave blank |

Click **Release**. A **second** local vendor account is created — this time in DEMF — linked to the same party as GV-002.

> **Note — What this proves:** The shared identity data (name, addresses, contacts, certificates, agreements) was entered *once* on the global vendor and now backs *two* local vendors. Each local vendor keeps its own legal-entity-specific settings (currency, vendor group, bank accounts, tax IDs). Open the **Lifecycle** tab — the **Vendors** section now lists both the USMF and DEMF local vendors.

> ✅ **Result:** GV-002 is released to two legal entities. The Lifecycle tab shows two local vendors (USMF + DEMF) under one global vendor profile.

### Step 11 — (Optional) Enable the DEMF local vendor for collaboration
If suppliers should collaborate on German-company purchase orders too, repeat Step 9 for the DEMF local vendor: open it from the **Lifecycle → Vendors** section and set **Collaboration activation** to `Active (PO is not auto-confirmed)`. Certificates and contacts from the global vendor already apply — no re-entry needed.

> ✅ **Result:** The DEMF local vendor is portal-enabled, sharing the same global identity as the USMF vendor.
