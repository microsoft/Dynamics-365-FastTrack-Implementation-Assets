# Lab 5 of 9 — Supplier Self-Registration & Onboarding — Pacific Components Ltd.

*⏱ ~45 min · Scenario*

Pacific Components Ltd. finds Technova's supplier portal through a public link and self-registers. Alex Chen reviews and approves the registration in the Supplier Engagement app, which triggers an onboarding invitation. Maria Santos then logs in and completes the onboarding form. Alex qualifies the vendor, synchronizing the global vendor (GV-001) party record to SCM.

### Before you start
- [ ] Labs 0–4 complete. Reference data is populated.
- [ ] Supplier portal access is ready in Power Pages (`make.powerpages.microsoft.com`). For a normal external lab, set **Site visibility = Public**. For a trial/developer/non-production site that can't be public, keep **Site visibility = Private** and use **Security › Site visibility › Grant site access** to share the site with the supplier's redeemed Microsoft Entra B2B guest user.
- [ ] Cloud flows are turned on (Lab 2, Step 6) — invitation emails depend on them.
- [ ] Maria Santos test account (`m.santos@pacificcomponents.com`) has been invited as a **Microsoft Entra guest** in the portal's home tenant and has **redeemed** the invitation, so a guest identity exists for sign-in.

> ⚠️ **Admin fix — "Invalid sign-in attempt" (stale External Identity).**
> If a supplier who previously registered later fails to sign in with *"Invalid sign-in attempt"*, the portal contact is bound to a Microsoft Entra object ID that does not match the guest user who is signing in. This happens when the guest account was deleted and re-added, or when the supplier was manually invited through Teams/Entra instead of being provisioned by the FSCM **Provision Microsoft Entra ID B2B user** workflow task. A manually created guest can have a different Object ID than the one stored on the Supplier Engagement contact. Repoint the contact's `External Identity` record to the current object ID:
> 1. **Get the guest's current Object ID** — `entra.microsoft.com` → *Identity › Users › All users*, search the supplier's email (it appears as a *Guest*; UPN looks like `name_gmail.com#EXT#@<tenant>.onmicrosoft.com`) and copy the **Object ID**. If no user is found, the guest was never re-created — re-invite via Teams/Entra instead (see Lab 6, Step 3).
> 2. **Open the Portal Management app** — from the Power Pages site overview → *…* (ellipsis) → *Portal Management*. Go to *Security › Contacts* and open the contact with that email.
> 3. On the contact, open *Related › External Identities* (`adx_externalidentity`). *(Or Security › External Identities, filtered by that contact.)*
> 4. **Repoint the binding:** open the record and set **Username** (`adx_username`) = the Object ID from step 1, keep the existing Identity Provider / Issuer, and **Save**. *(Alternative: delete the stale External Identity record and have the supplier sign in again to re-bind — only if external sign-in re-registration is enabled; editing is safer.)*
> 5. **Verify:** confirm the contact is *Active* and still holds its web role (*Related › Web Roles*, e.g. *Global Vendor Administrator*). Have the supplier sign out, clear cache or use a fresh browser profile, and sign in again — it now matches on the updated object ID.
>
> Always reuse the same guest account you registered with. (A shorter note also appears at Part A, Step 5.)

## Part A — Supplier Self-Registration (Maria's perspective)

### Step 1 — Maria opens the supplier portal and registers
Maria browses to the supplier portal URL as an anonymous user. On the landing page she clicks **Register as a supplier**. She completes the registration form:

> ⚠️ **Warning — Placeholder identity — use a real email.** *Maria Santos* and `m.santos@pacificcomponents.com` are placeholders for the demo persona. Because the portal sends the invitation to this address and it becomes the Microsoft Entra guest you sign in with, enter a **real external inbox you control** (for example a personal Gmail/Outlook address). Keep the display name if you like; only the email must be real, and use the *same* address every time you sign in.

| Field | Value to Enter |
|---|---|
| Company name | `Pacific Components Ltd.` |
| Primary contact name | `Maria Santos` |
| Primary contact email | `m.santos@pacificcomponents.com` |
| Primary phone | `+1-503-555-0100` |
| Industry / products | `Electronic Components, PCB Manufacturing` |
| Website | `www.pacificcomponents.com` |

In the **Company Address** section, fill in the following. **Description** is a *required* free-text field (max 250 chars) — the portal leaves it blank, so you must enter a value or the form won't submit:

| Field | Value to Enter |
|---|---|
| Country/Region * | `United States` |
| State | `Oregon` |
| Description * | `Headquarters — 4200 SE International Way, Portland, OR 97222` |

Maria clicks **Submit**. The portal displays a confirmation message that the registration is received and under review.

> ✅ **Result:** A new registration request appears in the Supplier Engagement app with Status Reason = New.

## Part B — Internal Review & Approval (Alex's perspective)

### Step 2 — Alex finds and starts reviewing the registration
In the Supplier Engagement app, select the **Menu** area at the bottom of the nav. Go to **Portal registrations → Registration requests**. Find **Pacific Components Ltd.** with Status = `New`.

Open the record, review the submitted details, then click **Review** on the command bar. Confirm the dialog. Status changes to `In review`.

### Step 3 — Alex approves the registration
With the request in *In review* status, click **Approve** on the command bar. Confirm the dialog. If the system detects a possible duplicate global vendor by name, email, or URL, review the existing record and decide whether to proceed or merge before confirming.

On successful approval, the system automatically:
- Creates a new global vendor record with Status = `Prospect` (this will be GV-001)
- Creates a Dataverse contact record for Maria Santos, linked to GV-001
- Assigns Maria the *Global Vendor Admin* portal web role
- Sends Maria an invitation email with a link to sign in and complete onboarding

> ✅ **Result:** Registration status = Approved. A new Prospect global vendor for Pacific Components Ltd. appears in General → Global vendors.

### Step 4 — Alex approves Maria's portal user request in SCM
**Where:** Procurement and sourcing › Vendors › Supplier Engagement › Portal user requests

Find the pending request for Maria Santos. Review and click **Approve**. (If auto-approve was configured in Lab 3 Step 5, this may already be auto-approved.)

> ✅ **Result:** Maria's portal user request is Approved. An external user account is created for her in SCM with the Supplier Portal Prospective User security role.

## Part C — Supplier Onboarding (Maria's perspective)

### Step 5 — Maria receives invitation and signs in to the portal
Maria opens the invitation email and clicks the portal link. She signs in using her Microsoft Entra identity (`m.santos@pacificcomponents.com`). The portal displays the **Onboarding** guide with multiple steps.

> ⚠️ **Warning — Troubleshooting portal sign-in.** Supplier sign-in depends on three things being in place — portal visibility/access, an Entra *guest* identity for the supplier, and a Dataverse contact whose email matches that guest. Common errors and fixes:
> - **"You don't have access to this" (`/private-mode-access-denied`)** — the site is still *Private* and this user hasn't been granted access. Either set **Site visibility → Public** in Power Pages (needs Power Platform Administrator / website owner), or keep it **Private** and grant access to the supplier's redeemed Entra B2B guest through **Security → Site visibility → Grant site access**. This private-site access path is useful for trial/developer/non-production instances where public visibility is unavailable or blocked by tenant policy.
> - **Certificate warning or "Azure Front Door configuration not found"** — the site is still provisioning after going public. Wait 15–30 min and retry in a fresh InPrivate window.
> - **No invitation email arrived** — the guest account was never created, so there is nothing to sign in with. In dev/trial environments the portal invitation email is usually never delivered (no Dataverse email server profile). The preferred fix is to complete Lab 0 Step 7 and Lab 3 Step 5 so FSCM provisions the Entra B2B guest through workflow and stores the matching Object ID on the Supplier Engagement contact. For a dev-only shortcut, add the supplier's email as a guest member of any team in Microsoft Teams — Teams raises the Entra B2B invite and sends an *Accept invitation* mail from `invites@microsoft.com` that redeems in seconds. (Alternative: `entra.microsoft.com` → **Users → Invite external user**, enter `m.santos@pacificcomponents.com`, then redeem the invite.) If you use the manual path, verify or patch the contact's External Identity Object ID as described above.
> - **"Invalid sign-in attempt"** (with *"Registration has been disabled"* shown) — the identity provider maps sign-ins to a contact *by email*, but the signed-in guest's object ID doesn't match the identity stored on the contact. This happens when the guest was **deleted and re-added** or manually created through Teams/Entra outside the FSCM provisioning workflow. Fix: use the workflow-created guest where possible, or have an admin re-point the contact's stored *External Identity* record to the current guest's object ID. Always reuse the *same* guest account you registered with.

### Step 6 — Maria completes the onboarding form
Maria works through the onboarding steps, providing the following data:

| Onboarding Section | Data to Enter |
|---|---|
| Company details | Full legal name, tax ID / organization number, DUNS number, number of employees: `280` |
| Address | `4200 SE International Way, Portland, OR 97222, US` |
| Contact information | Phone `+1-503-555-0100`, website `www.pacificcomponents.com` |
| Certificates | Add `ISO 9001:2015`, certifying org = `Bureau Veritas`, **certification number** = `BV-9001-2025-4711`, valid from `2025-03-01` to `2028-02-28` *(Certification number, type, certifying org, and both dates are all required.)* |
| Capabilities | Select `PCB Assembly` and `Surface Mount Technology` |
| Self-assessment | Answer all four questions (Yes to ISO 9001; select revenue range; 280 employees; describe OECD process) |

On the final step Maria clicks **Submit**. The portal confirms that onboarding data has been submitted for review.

> ✅ **Result:** Onboarding status in the Supplier Engagement app updates to indicate data submitted. Alex can now see the submitted information on the GV-001 record.

## Part D — Qualification (Alex's perspective)

### Step 7 — Alex qualifies Pacific Components as a global vendor
In the Supplier Engagement app, go to **General → Global vendors** and open the **Pacific Components Ltd.** record. Review all tabs (Summary, Certificates, Capabilities, Contacts, Self-assessment answers).

On the command bar click **Qualify**. In the dialog enter comment: `Onboarding reviewed — ISO 9001 verified, capabilities confirmed. Passed initial qualification.` Click **OK**.

The system:
- Changes status to `Qualified`
- Creates a global vendor party record in SCM
- Synchronizes addresses, contacts, and contact methods to SCM
- Upgrades Maria's SCM security role from Prospective User to *Supplier Portal Administrator*

> ✅ **Result:** GV-001 (Pacific Components Ltd.) status = Qualified. Go to SCM → Procurement and sourcing → Vendors → Supplier engagement → All global vendors to confirm the record appears.
