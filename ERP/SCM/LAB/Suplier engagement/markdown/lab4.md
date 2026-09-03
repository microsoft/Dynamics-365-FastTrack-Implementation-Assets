# Lab 4 of 9 — Reference Data Setup

*⏱ ~30 min · Reference Data*

Populate the lookup tables that drive onboarding, vendor qualification, and risk management. Without this data, procurement staff cannot assign certificates, segments, or risk scenarios to suppliers — and the self-assessment questionnaire will be empty. All steps are performed in the **Supplier Engagement app** (the model-driven app for internal users).

### Before you start
- [ ] Lab 3 complete — Supplier Engagement feature enabled in SCM.
- [ ] Supplier Engagement app is accessible in your Power Platform environment.
- [ ] Signed in as a user with System Administrator or Supplier Engagement admin privileges in Dataverse.

## Part A — Certificates & Capabilities

### Step 1 — Create certificate types
In the Supplier Engagement app, at the bottom of the left nav select the **Configuration** area. Go to **Certificate types → New**. Create the following three certificate types:

> ⚠️ **Warning:** Name field is limited to 10 characters. Use the abbreviated names below — the Description column carries the full meaning.

| Name (max 10 chars) | Description |
|---|---|
| `ISO9001:15` | Quality Management System certification (ISO 9001:2015) |
| `RoHS863EU` | Restriction of Hazardous Substances in electronics (RoHS 2015/863/EU) |
| `IATF16949` | Automotive quality management standard (IATF 16949) |

> ✅ **Result:** Three certificate types appear in the Certificate types list.

### Step 2 — Create certifying organizations
Go to **Configuration → Certifying organizations → New**. Create three organizations:

| Name | Description |
|---|---|
| `Bureau Veritas` | bureauveritas.com — global testing, inspection and certification |
| `SGS Group` | sgs.com — inspection, verification, testing and certification |
| `TÜV Rheinland` | tuv.com — technical services and certification |

> ✅ **Result:** Three certifying organizations appear in the list.

### Step 3 — Create capability types
Go to **Configuration → Capability types → New**. The capability type form has only a **Name** field (plus optional hierarchy fields — *Parent* and *Root item*); there is no Description field. Create these three:

| Name | What it represents (for reference only) |
|---|---|
| `PCB Assembly` | Printed circuit board fabrication and assembly |
| `Surface Mount Technology` | SMT component placement and soldering |
| `Electrical Testing & Inspection` | AOI, ICT, functional testing |

> ✅ **Result:** Three capability types appear in the Capability types list.

## Part B — Segments, Types & Holds

### Step 4 — Create vendor segments
Go to **Configuration → Segments → New**. The segment form has only a **Name** field (plus an optional *Parent* for hierarchy); there is no Description field. Create these three:

| Name | What it represents (for reference only) |
|---|---|
| `Tier 1 Strategic` | Critical single-source or preferred suppliers with long-term contracts |
| `Tier 2 Preferred` | Qualified suppliers with active relationships |
| `Tier 3 Spot` | Spot-buy suppliers used on an ad-hoc basis |

> ✅ **Result:** Three segments appear in the Segments list.

### Step 5 — Create global vendor types
Go to **Configuration → Global vendor types → New**. This form has a **Name** and a **Description** field (Name max 100, Description max 200 characters). Create:

| Name | Description |
|---|---|
| `Direct Material` | Materials that go directly into finished products |
| `Indirect / MRO` | Maintenance, repair and operations supplies |
| `Services` | Service-based suppliers (labor, consulting, logistics) |

> ✅ **Result:** Three global vendor types appear in the list.

## Part C — Risk Management Data *(Optional)*

### Step 6 — (Optional) Create risk scenarios
Go to **Configuration → Risk scenarios → New**. The form has only a **Name** field (plus an optional *Parent* for hierarchy); there is no Description field. Create these three:

| Name | What it represents (for reference only) |
|---|---|
| `Single Source Dependency` | Vendor is the sole qualified source for a critical component |
| `Financial Instability` | Vendor shows signs of financial stress or credit risk |
| `Quality Escapes` | Recurring quality non-conformances or field failures |

> ✅ **Result:** Three risk scenarios appear in the list.

### Step 7 — (Optional) Create corrective action types
Go to **Configuration → Corrective action types → New**. The form has only a **Name** field (plus an optional *Parent* for hierarchy); there is no Description field. Create these three:

| Name | What it represents (for reference only) |
|---|---|
| `Supplier Audit` | On-site quality or process audit |
| `Quality Improvement Plan` | Formal 8D or CAPA report required from vendor |
| `Dual Source Development` | Qualify a second supplier for the component |

> ✅ **Result:** Three corrective action types appear in the list.

## Part D — Self-Assessment Questionnaire

### Step 8 — Create self-assessment questions
Go to **Configuration → Self-assessment questions → New**. Each question has a **Number**, the **Question** text, an **Answer type** (only two choices: *Text* or *Yes/No*) and an **Area**. Create these four questions that suppliers will answer during onboarding:

| # | Question Text | Answer type | Area |
|---|---|---|---|
| 1 | Does your organization hold a current ISO 9001 or equivalent quality certification? | Yes/No | QM – Quality Management |
| 2 | What is your organization's annual revenue range (USD)? | Text | SCM – Supply Chain Management |
| 3 | How many employees does your manufacturing facility employ? | Text | HR – Human Resource |
| 4 | Describe your conflict minerals compliance process (OECD Due Diligence Guidance). | Text | ESG – Environment, Social, Governance |

> ✅ **Result:** Four self-assessment questions appear in the list. Suppliers will see these questions on the final onboarding step in the supplier portal.
