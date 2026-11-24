# User guide

For the people who use the Sales Order Agent every day: sales operations, order reviewers and the administrators who keep the matching rules and unit aliases up to date. Installation is in the [Quick start](quick-start.md) and the [Deployment guide](deployment-guide.md).

## 1. Who does what

| Role | What you can do |
| --- | --- |
| **Sales Orders Reviewer** | Open orders, read the header, lines and the **Customer Match** tab (read only), and use both dashboards |
| **Sales Order Matching Administrator** | Everything a reviewer does, plus the **Setup** area: matching rules and unit aliases |
| **System Administrator** | Setup, flow and connection management, release control |

The **Setup** area appears only to users who can write to the matching tables. If you do not see it, you do not have the administrator role.

## 2. The journey of an order

1. An email arrives in the monitored mailbox. The intake flow takes one source: a supported attachment, otherwise the email body.
2. Azure AI Content Understanding reads the header and every line. The original file and the extracted JSON are kept.
3. The loader creates the order header and lines, checks that the number of rows equals the number found in the document, and normalizes each printed unit with the alias list.
4. The customer resolver scores every candidate customer in every company and saves the evidence.
5. If the match is accepted and release is on, the agent validates the customer and every product, creates the sales order in Finance and Operations, and reads it back.
6. If anything is unsure, the order is held with a reason.

### Order status

| Status | Meaning | What you do |
| --- | --- | --- |
| **New** | Loaded and waiting for validation. The agent only validates an order from this status | Nothing; processing continues |
| **Manual Review** | Stopped because a person must decide, for example a unit that does not match the item | Read the reason, fix the cause, ask an administrator to re-run (section 6) |
| **Valid** | The customer, products and lines passed validation | Nothing; the ERP order is created next |
| **Processed** | The ERP order was created and verified. The order has an ERP order number | Open it in Finance and Operations if you need to check it |
| **Processing Failed** | Processing hit an error | Report it with the details in section 9 |

A flow run can also end as **Cancelled**. That is not an order status: a guard stopped the run because the saved proof, the matching rules or the load state changed, and the order was left unchanged so it can be re-run.

Do not change an order's status or ERP number by hand to push it through. The guards exist to prevent wrong or duplicate ERP orders.

## 3. Dashboards

Both dashboards open with a totals tile: **Received**, **ERP processed** and **Failed**.

* The totals are the saved records you are allowed to see. Two users with different access can see different totals.
* They are read from Dataverse. They are not a live check against the ERP.
* If the tile is blank or shows a broken page, tell an administrator (deployment guide, section 12).

## 4. Open and read an order

Open the order in the Sales Order Agent app. The form shows the header, the lines and the **Customer Match** tab.

Check these first:

* **Header**: PO number, customer, requested delivery date. The date is stored exactly as printed. It reaches the ERP only if it is today or later; a past date is not sent and the validation message says so.
* **Lines**: item, quantity, unit and price as printed. The printed price is for audit only. Finance and Operations calculates the price when it creates the line.
* **Bill-to and ship-to**: both are stored. Matching uses the address basis of the published rules (Bill-To by default).
* **Validation message**: the plain reason an order stopped, if it did.

## 5. The Customer Match tab

The tab is read only. It shows how the order was matched and why.

| You see | Meaning |
| --- | --- |
| Company and customer | The legal entity and account that were matched |
| Score | The points earned by the best candidate, built from name, email, street, ZIP, city and state |
| Margin | The lead over the next best candidate |
| Reason | The code that explains the decision |

The result is **Accepted** only when the score reaches the threshold (default 70), the lead reaches the margin (default 15), the name earned points, and every ERP search needed to rule out other customers completed. Otherwise the order goes to review. Never edit the saved proof.

### Review reasons and what to do

| Reason | Meaning | What to do |
| --- | --- | --- |
| `CustomerMatchBelowThreshold` | The best customer scored under the threshold | Compare the customer name and address on the document with the ERP customer. Fix the customer master data, or ask the sender to correct the document |
| `CustomerMatchAmbiguous` | Two customers are tied or too close, often the same name and address in two companies | Fix the duplicate master data so one customer is clearly better. Do not lower the margin to force it through |
| `CustomerMatchShipToMissing` | Ship-To matching is on but the document has no ship-to address | Use a document with a ship-to address, or ask an administrator whether the address basis should be Bill-To |
| `CustomerMatchRetrievalIncomplete` | An ERP search failed or hit its limit, so the match cannot be proven | Ask an administrator to check ERP availability and re-run |
| `CustomerMatchEvidenceTooLarge` | The saved evidence would exceed its size limit | Report it with the order identifier |
| `CustomerMatchPolicyUnavailable` | The published rules could not be read | Ask an administrator: the publish flow, the connection and the setup script (deployment guide, section 12) |
| `CustomerMatchPolicyChanged` | The rules changed while the order was in flight | Ask an administrator to re-run the order |
| `CustomerMatchStateOrInputChanged` | The header or saved proof changed after the match | Ask an administrator to re-run the order |
| `CustomerMatchReleaseDisabled` | Matched and held; release is off, so nothing was sent to the ERP | Expected. An administrator sets the environment variable `aipod_ReleaseHeaders` to `true` after the checks pass. To release one order by hand, check the customer, set Valid Customer to Yes and set the order status to New |
| `CustomerMatchReused` | An unchanged, still valid proof was reused | Informational |

The full scoring tables and worked examples are in [Customer Matching Rules](customer-matching-rules.md).

### When you know the right customer: decide it yourself (release 1.1.0.0)

Use this when an order is in **Manual Review** with a customer reason (the **Customer Match Status** is *Review Required*), for example two customers tied, and you know which customer and company the order belongs to. The system never picks between tied customers on its own.

1. Open the order, tab **Processed Data**, section **Extracted Customer Data**. The **ERP Customer Number** and **Company Code** fields are editable only while the Customer Match Status is Review Required.
2. Type the ERP customer number and the company (legal entity) code.
3. Fill **Customer Override Reason** with why you chose it (for example "confirmed by phone with the buyer"). The reason is required.
4. Set **Valid Customer** to **Yes**.
5. Set the order **Processing Status** to **Valid** (**New** also works) and save.

The agent then records your decision (your name, the time and the reason) in the saved evidence, keeps the system's own result in the **Customer Match** tab, checks that the customer exists in that company in the ERP, validates every line and creates the ERP order. The **Customer Match** tab shows a notice that the customer was chosen by a reviewer.

If you chose the wrong customer, correct the two fields and set the status again. This works until an ERP order exists; after that the fields are locked. If the ERP does not have that customer in that company, the order stops with `ManualOverrideCustomerNotFound`. Fix the customer number and set the status again.

### When one line is the problem: decide the line yourself

Use this when the customer is accepted but a line stopped for review (for example the item code on the document is not an ERP item).

1. Open the line (select it in the **Items** list).
2. Type the correct **ERP Product Code**.
3. Set **Manual Override** to **Yes** and fill **Override Reason**. Both the code and the reason are required, otherwise the line stops with `ManualOverrideIncomplete`.
4. Go back to the order and set **Processing Status** to **Valid**.

The agent validates every line again. A line you overrode is accepted with your ERP product code without an ERP item lookup; the quantity must still be valid. The ERP checks that protect the order are not skipped: the unit of measure, the Site and Warehouse, and the read-back of the created ERP order. An overridden line that the ERP cannot accept still stops the order with the ERP reason.

Anyone who can edit orders can use both overrides, so give the edit right only to people who may decide customers and products. Never edit the saved evidence yourself.

## 6. Other reasons an order stops

| Reason | Meaning | What to do |
| --- | --- | --- |
| `LineCountMismatch` | The number of extracted rows differs from the number of rows in the document | Compare the original with the extracted lines. Never waive the check or create a short order |
| `LineCountUnverifiable` | The document has no detectable table, for example an email body that lists items without one | Process it manually, or resend with a line-item table |
| `UnitOfMeasureMismatch` | The unit does not match the item's ERP sales unit | Add or correct the alias (section 8), or correct the item's unit in the ERP, then ask for a re-run |
| `InvalidValidationState` | The order is not in a status that allows the requested step | Do not force the status. Check prior runs and the ERP outcome first |

Re-running an order is done by an administrator. Never resend the document while the first copy is still processing, because two identical emails that arrive together are each processed.

## 7. Changing the matching rules (administrators)

Open **Setup > Customer matching > Matching rules**. A published rule set is read only, so you create a new version:

1. Create a **New** row for the policy key `default`. It starts with the approved defaults.
2. Change the values until the warning banner is empty.
3. Enter the **Change reason**, set **Publish request** to **Yes** and save.
4. The publish flow checks the safety floors and publishes it. The new rules apply to the next order. An order matched under the previous version that is not yet in the ERP stops for review and is re-run.

**Rule history** keeps every version with its reason. Test every change in a development environment first. Do not lower a value to push one order through: fix the customer data or the document instead. The safety floors cannot be lowered: threshold at least 60, margin at least 10.

## 8. Unit-of-measure aliases (administrators)

Documents print units in many ways (EA, EACH, PCS, Pc, E). The loader turns each printed unit into one value before the order line is written.

Open **Setup > Units of measure > Unit aliases**.

| Field | Use |
| --- | --- |
| **Printed as** | The unit as it appears on documents. Case and periods are ignored, so `PCS.`, `Pcs` and `pcs` are one alias |
| **Becomes** | The value the order line receives |
| **Active** | Set to **No** to stop using an alias. Do not delete rows |
| **Reason** | Why the change was made |

* **Saving a row publishes it.** The row shows **Published** within a minute or two. If it fails the checks it shows **Rejected** with the reason and appears under **Needs attention**; the list in use does not change.
* The change applies to orders loaded afterwards. Orders already loaded do not change.
* **Try a printed unit** shows what a printed unit becomes and, if you enter the item's ERP unit, whether the order can continue.
* The count units ea, each, pc, pcs, piece and pieces are treated as the same unit, and the order is created with the item's own ERP sales unit. For every other unit, **Becomes** must equal the item's ERP sales unit symbol, otherwise the order goes to Manual Review with `UnitOfMeasureMismatch`. Set **Becomes** to the symbol your ERP uses, for example `cs` to `CS`.
* Quantities are never converted between units, for example case to each.
* The extraction JSON keeps the unit as printed, so the original is always available for audit.
* Do not edit the `aipod_UomAliasMap` variable by hand; the next publish replaces it. Test each new mapping with **Try a printed unit** and one sample document.

## 9. Good habits

* Send **one order per document**. A document with several orders is processed as one.
* Do not resend an order while the first copy is still processing.
* Do not point two intake flows at the same mailbox and folder.
* Confirm results in Dataverse and the ERP, not from a flow step that shows Succeeded.
* If a document is held for a reason you cannot resolve, preserve it and raise it. Do not change values to force a pass.

### Getting help

Raise an issue with: the installed release version, the analyzer identifier, the staging record identifier, the order header identifier, the name of the flow that failed with the time of the run, and the validation message. Do not include mailbox contents, customer data, keys or connection secrets. See the deployment guide, section 13.
