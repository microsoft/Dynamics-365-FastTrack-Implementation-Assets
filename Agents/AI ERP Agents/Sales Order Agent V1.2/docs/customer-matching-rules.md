# Customer Matching Rules

Reference and administrator guide for the configurable customer matching and the
**Setup > Matching rules** screens in the Sales Order Agent app. Release 1.0.9.0.

## 1. What the engine does

For every order, the agent reads the customer details printed on the document and the engine finds the
matching customer in Dynamics 365 Finance and Operations (all companies). The result is always one of:

| Result | Meaning | What happens next |
| --- | --- | --- |
| Accepted | One customer reached the threshold and leads the runner-up by at least the margin. | The order keeps going. The matched company and account are saved with the proof. |
| Review | Nothing reached the threshold, two customers are tied or too close, evidence is missing or incomplete. | The order stops with a plain reason for a person to decide. |

The engine never guesses and never picks "the first of two equal customers". Search order does not break ties.

## 2. How a score is built

Each candidate customer earns points for every signal that matches. Defaults are shown; every value except
the safety floors is configurable.

| Signal | Document value | Finance and Operations value | Rule | Default points |
| --- | --- | --- | --- | --- |
| Name exact | Bill-to name (else customer name) | Organization name | Cleaned-up names are identical | 40 |
| Name contains | same | same | The ERP name contains the document name as whole words; only when "exact" does not apply; document name at least 5 characters | 20 |
| Email | Customer email | Primary contact email | Valid email, equal ignoring case | 15 |
| Street | Address on the document | Street of the chosen address | The document address starts with the ERP street (apartment and suite aware) | 10 |
| ZIP | same | 5-digit ZIP | The ZIP5 appears in the document address (ZIP+4 accepted) | 20 |
| City | same | City | The city appears before the state in the document address | 10 |
| State | same | State | The state appears in the document address | 5 |

* **Address basis.** *Bill-To* compares the document billing address with the customer's invoice address.
  *Ship-To* compares an explicit ship-to address on the document with the customer's delivery address. With
  Ship-To and no ship-to address on the document the result is Review (`CustomerMatchShipToMissing`).
* **Cleaning names.** Case, punctuation, spacing, corporate endings (Inc, LLC, Corp, Ltd...) and a trailing
  "/ branch" text are ignored. Each of the last two is a switch (*Ignore legal suffix*, *Strip slash suffix*).
* **Fallback address (optional, off by default).** When on, an address part that does not match the chosen
  address can still score from the other address at reduced points (default street 5, ZIP 10, city 5, state 0).
  Each part scores from one address only, never both.
* **Primary total.** Name exact + email + street + ZIP + city + state must total exactly 100.

## 3. The decision

A customer is **Accepted** only when all of these are true:

1. Score is at least the **threshold** (default 70).
2. Lead over the runner-up is at least the **margin** (default 15).
3. *Require name* is on (default) and the name earned points. An email-plus-address match with a different
   name is never accepted.
4. Every ERP search needed to rule out other customers completed (coverage proof). If a search failed and an
   unseen customer could still win, the result is Review (`CustomerMatchRetrievalIncomplete`).

Otherwise the order goes to Review with one of these reasons.

| Reason shown | Meaning |
| --- | --- |
| `CustomerMatchBelowThreshold` | The best customer scored less than the threshold. |
| `CustomerMatchAmbiguous` | Two customers are tied or closer than the margin (often the same name and address in two companies). |
| `CustomerMatchShipToMissing` | Ship-To basis, but the document has no ship-to address. |
| `CustomerMatchRetrievalIncomplete` | A search failed or hit its row limit, so the match cannot be proven. |
| `CustomerMatchEvidenceTooLarge` | The saved evidence would exceed its size limit. |
| `CustomerMatchPolicyUnavailable` | The published rules could not be read. |
| `CustomerMatchPolicyChanged` | The rules changed while the order was being processed or after it was matched. |
| `CustomerMatchStateOrInputChanged` | The order header or saved proof changed after the match; it must be re-run. |
| `CustomerMatchReused` | An unchanged, still valid proof was reused (Accepted, no new search). |
| `CustomerMatchReleaseDisabled` | Matched and held; the release switch is off, so the order was not sent to ERP. |

### Reviewer override (release 1.1.0.0)

The rules never pick between customers they cannot separate. A reviewer who knows the customer can decide it on the
order: type the ERP customer number and company code, fill the override reason, set Valid Customer to Yes and set the
status to Valid. The decision is saved as evidence of its own kind (`schemaVersion` 5, `source` manual): the selected
company and account, who decided, when and why. The system's own result stays in the *Original Match Evidence* column
and in the Customer Match tab. The status flow, the update-status flow and the three business skills accept a
reviewer decision only while the saved company and account equal the order's current values and the order has no ERP
number; the agent also checks that the customer exists in ERP in that company before it validates any line. Changing
the fields afterwards starts a new decision. Schemas 3 and 4 are unchanged. See the user guide, section 5.

## 4. Safety floors (cannot be lowered)

The publish flow rejects a rule set that breaks any of these. The form shows the same checks live.

* Threshold at least **60**; margin at least **10**; name-contains minimum length at least **5**.
* Every points value, threshold and margin is a whole number from 0 to 100.
* Primary points total exactly 100; name-contains points do not exceed name-exact points.
* No group can reach the threshold alone: name points, email points, or street + ZIP + city + state together.
* Each fallback value does not exceed its primary value.
* Coverage: threshold minus the points the targeted ERP searches cannot cover (street + city + state, plus the
  fallback street, city and state when fallback is on) must be at least the margin. With the defaults:
  70 - 25 = 45, which is at least 15.

## 5. Worked examples (default rules)

| Evidence that matches the customer | Score | Result |
| --- | --- | --- |
| Exact name + full address | 85 | Accepted |
| Exact name + full address + email | 100 | Accepted |
| Exact name + ZIP + city + state (street written differently) | 75 | Accepted |
| Exact name + ZIP + city | 70 | Accepted |
| Exact name + ZIP only | 60 | Review |
| Exact name + city + state, different ZIP | 55 | Review |
| Exact name + email, no address | 55 | Review |
| Name contains + ZIP + city + state | 55 | Review |
| Name contains + full address + email | 80 | Accepted |
| Email + full address, different name | 60 | Review (name required) |
| Two accounts with the same name and address | tie | Review (ambiguous) |

Scores assume no other close candidate. The guide tab on the form recomputes these examples for your values.

## 6. Where to change the rules (Setup area)

The **Setup** area of the Sales Order Agent app is visible only to users with Write permission on the policy
table: **Sales Order Matching Administrator** and **System Administrator**. Everyone else (for example Sales
Orders Reviewer) cannot see it, but still sees each order's read-only **Customer Match** tab with the score
breakdown.

| Menu item | Shows |
| --- | --- |
| Setup > Customer matching > **Matching rules** | The Published rule set that the engine is using now. |
| Setup > Customer matching > **Draft rules** | Drafts, requested and rejected rule sets. |
| Setup > Customer matching > **Rule history** | Every version of every rule set, newest first. |

The policy form has three tabs:

* **Rules** - rule set (name, policy key, address basis, change reason), name matching, email, address matching,
  decision (threshold, margin), optional fallback address, and **Publish request**. A banner lists any safety
  rule that is not met. Hover over a field label for a tooltip.
* **Status and history** - state, version, published on/by, the validation message and the exact snapshot the
  engine uses. Written by the publish flow; read only.
* **How matching works** - the explanation with live numbers, live examples and a publish checklist.

### 6.1 Change the rules

1. Open **Setup > Matching rules** or **Draft rules** and select **New**. A new row starts with the approved
   defaults and the policy key `default`. (A Published or Retired row is read only; create a new row instead.)
2. Adjust points, threshold, margin, address basis and the switches. Watch the banner until it is empty.
3. Enter the **Change reason**.
4. Set **Publish request** to **Yes** and save. Saving is blocked in the browser while the banner shows an error.
5. The publish flow validates the row and publishes it as the next version; the previous Published row becomes
   Retired. If something is wrong the row becomes **Rejected** and **Validation message** says why. Fix the
   values and set Publish request to Yes again.

Rules take effect for the next order. An order that was matched under the previous version but is not in ERP
yet stops for Review (`CustomerMatchPolicyChanged`) and is re-run under the new rules. Orders already created in
ERP are not affected. Never edit saved proof JSON.

| State | Meaning |
| --- | --- |
| Draft | Editable; not used by the engine. |
| Publish requested | The publish flow is validating (seconds). |
| Published | In use. Exactly one Published row exists per policy key. Read only. |
| Retired | Replaced by a newer version. Kept as history. Read only. |
| Rejected | Failed validation; editable and can be requested again. |

## 7. Field tooltips

Each label's hover text is the column description in Dataverse, so it also appears in Advanced Find and in the
column definitions.

| Field | Tooltip |
| --- | --- |
| Name | Friendly name of this rule set, shown in lists. Example: Default rules - Ship-To. |
| Policy key | Identifies the rule set. The matching engine reads the Published row whose key is 'default'. Use lowercase letters, digits and hyphens. Keep 'default' unless you were told otherwise. |
| Address basis | Which customer address is compared with the order address. Bill-To uses the customer's invoice address. Ship-To uses the delivery address and needs an explicit ship-to address on the document. |
| Name exact points | Points when the cleaned-up customer names are identical (case, punctuation and Inc/LLC endings ignored). Default 40. Name exact, email and the four address points must total exactly 100. |
| Name contains points | Points when the Finance and Operations name contains the document name as whole words and 'exact' does not apply. Default 20. Cannot exceed Name exact points. |
| Name contains minimum length | Shortest document name (characters) allowed to earn Name contains points. Stops short names such as 'ABC' matching many customers. Minimum 5. Default 5. |
| Email points | Points when the document email equals the customer's primary contact email (ignoring case). Default 15. Email alone must stay below the threshold. |
| Street points | Points when the document address starts with the customer's street (apartment and suite aware). Default 10. |
| ZIP points | Points when the customer's 5-digit ZIP appears in the document address (ZIP+4 accepted). Default 20, the strongest address signal. |
| City points | Points when the customer's city appears before the state in the document address. Default 10. |
| State points | Points when the customer's state appears in the document address. Default 5. |
| Fallback enabled | Yes: an address part that does not match the chosen address can still score from the other address (Ship-To or Bill-To) at the reduced fallback points. Default No. Each part scores from one address only. |
| Fallback street points | Fallback points for a street match on the other address. Cannot exceed the Street points. Default 5. Used only when Fallback enabled is Yes. |
| Fallback ZIP points | Fallback points for a ZIP match on the other address. Cannot exceed the ZIP points. Default 10. Used only when Fallback enabled is Yes. |
| Fallback city points | Fallback points for a city match on the other address. Cannot exceed the City points. Default 5. Used only when Fallback enabled is Yes. |
| Fallback state points | Fallback points for a state match on the other address. Cannot exceed the State points. Default 0. Used only when Fallback enabled is Yes. |
| Threshold | Minimum total score to accept a customer. Default 70. Cannot be set below 60. Lower values accept weaker matches, so raise it if wrong customers are accepted. |
| Margin | Minimum lead the best customer needs over the runner-up. Default 15, minimum 10. Ties and close scores go to Review instead of guessing. |
| Require name | Yes (default): the name must earn points, so an email plus address match with a different name is never accepted. No: a name match is not required. |
| Strip slash suffix | Yes (default): ignore text after a slash in names, so 'Contoso / Seattle Branch' is compared as 'Contoso'. |
| Ignore legal suffix | Yes (default): ignore endings such as Inc, LLC, Corp and Ltd when comparing names. |
| Publish request | Set to Yes and save to ask the publish flow to validate and publish this row. The flag resets by itself. Only Draft or Rejected rows can be published. Publishing retires the previous version. |
| Change reason | Required. Why this version is needed (for example, 'ZIP match raised after wrong-customer reviews'). Kept in the history for audit. |
| State | Draft until published. Published = in use by the matching engine. Retired = replaced by a newer version. Rejected = the publish flow found a problem (see Validation message). Set only by the publish flow. |
| Version | Version number for this policy key, assigned by the publish flow when the row is published. |
| Policy snapshot | Exact rules the matching engine uses, written by the publish flow when the row is published. Read only. |
| Validation message | Result of the last publish attempt: 'Published version N' or the reasons the row was rejected. |
| Published by | User who requested the publish (name and ID). |
| Published on | Date and time the publish flow published this version. |

## 8. Security

| Item | Setting |
| --- | --- |
| Role **Sales Order Matching Administrator** | Create, Read, Write, Append, AppendTo on the policy table; no Delete. Associated with the Sales Order Agent app. |
| Role **Sales Orders Reviewer** | Read on the policy table only. Cannot see Setup. |
| Setup area | Each menu item requires Write on the policy table, so it is hidden from users without it. |
| Field security | Columns State, Policy snapshot, Validation message, Published on and Published by are secured. Profile *Customer Match Policy Publisher* (read/create/update) is for the publish-flow identity; profile *Customer Match Policy Reader* (read) is assigned to the business-unit default teams. |
| Auditing | Organization auditing is an environment setting; turn it on if you need an audit trail of policy changes. Rule history is kept as rows (versions) and the change reason regardless. |

Assign roles to people, not the profile. Users without the Reader profile see secured columns masked.

The reviewer override (section 3) needs no extra role: whoever can edit an order can decide its customer and its lines.
Each customer decision records the user name and time in the saved evidence. Restrict who can edit orders if you need
fewer people to decide customers.

## 9. Environment settings that interact with matching

* **Address basis** is a property of the Published policy (Bill-To or Ship-To); choose it when the first policy
  is created (section 10) and change it by publishing a new version (section 6.1). There is no environment variable for
  it. Release 1.0.10.0 removed the old variable `aipod_CustomerMatchAddressBasis`, which only the earlier fixed-rule
  proofs (before release 1.0.9.0) used. An order that still carries such a proof and is not yet in ERP stops for
  review and is re-run under the Published rules.
* **Release holds.** The environment variable `aipod_ReleaseHeaders` ships `false` and stays `false` until release is
  separately approved. A matched order is therefore held (`CustomerMatchReleaseDisabled`), never sent to ERP by the
  matching step. Set its Current Value to `true` to release; only the text `true` releases.
* **ERP host.** The environment variable `aipod_FinanceOperationsInstance` must name the environment's own F&O host
  (for example `<your-environment>.operations.dynamics.com`). While it is empty, matching stops with
  `CustomerMatchConfigurationMissing`.

## 10. First-time setup

The solution contains the policy table, the publish flow, the Setup screens, the roles and the field security profiles but no data. After importing the solution:

1. Bind the publish flow's connections and turn the flow "SOA - Publish Customer Match Policy V1" on.
2. Run the first-time setup script from the PowerPlatform folder of the package, as a System Administrator, with the Azure CLI signed in:

```powershell
.\Initialize-SalesOrderAgent.ps1 -EnvironmentUrl https://<your-env>.crm.dynamics.com
.\Initialize-SalesOrderAgent.ps1 -EnvironmentUrl https://<your-env>.crm.dynamics.com -Apply
```

The first command reports what it would do. Add `-AddressBasis ShipTo` for an environment that matches on the Ship-To address (the default is BillTo). The script creates and publishes the first `default` policy with the standard values, adds the starter unit aliases, and assigns the **Customer Match Policy Reader** field security profile to the business-unit default teams. It can be run again; anything that already exists is left alone.

3. Open **Setup > Matching rules** and confirm one Published row with key `default`.
4. Assign **Sales Order Matching Administrator** to the people who may change rules.

## 11. Troubleshooting

| Symptom | Likely cause | Action |
| --- | --- | --- |
| Setup area is missing | The user has no Write permission on the policy table or the role is not in the app | Assign Sales Order Matching Administrator; confirm the role is on the app. |
| Form fields are grey | The row is Published, Retired or waiting for publish | Create a new row for the same policy key. |
| Row becomes Rejected | A safety rule is not met or the change reason is empty | Read **Validation message**, correct the values, request publishing again. |
| Orders stop with `CustomerMatchPolicyChanged` | The rules were published while the order was in flight | Re-run the order; do not edit proofs. |
| Orders stop with `CustomerMatchPolicyUnavailable` | No Published row for the key, or the reader lacks the Reader field-security profile | Run the first-time setup script, or publish a default policy; check profile assignment on the user or team. |
| Too many wrong matches | Threshold or margin too low, or contains-name points too high | Raise the threshold or margin, or lower name-contains points; publish a new version. |
| Too many orders in Review | Threshold too high, margin too wide, or customer addresses in ERP are incomplete | Lower within the floors, enable fallback address, or fix customer master data. |

## 12. Changing the matching logic

Read this before changing anything other than the values on the Setup screen.

### 12.1 Which kind of change is it?

| I want to change... | Change it in | Effort |
| --- | --- | --- |
| Points, threshold, margin, address basis, fallback, name switches | **Policy table** (Setup > Matching rules). The resolver reads the Published snapshot on every run, so no flow or skill changes. | Minutes, no deployment |
| Tooltip text | The column description in the table designer | Small |
| The safety floors, what counts as a name, street, ZIP, city, state or email match, name cleaning, which customers are searched in ERP, the accept/review decision, or a new signal such as a phone number or tax ID | Not configurable. These are part of the delivered resolver flow and skills. | A change to the delivered solution; see 12.3 |
| What happens after a match (release to ERP, notifications) | The consumer flows and the environment variable `aipod_ReleaseHeaders` | Needs separate approval; matched orders stay held while `aipod_ReleaseHeaders` is `false` |

### 12.2 The pieces and who is the authority

| Piece | What it does |
| --- | --- |
| **Policy table** `aipod_customermatchpolicy` | Holds the rule values and the lifecycle (Draft, Published, Retired, Rejected). Edited on the Setup screen. |
| **Publish flow** "SOA - Publish Customer Match Policy V1" | Validates a row against the safety rules, writes the exact **snapshot** and keeps one Published row per key. |
| **Resolver flow** "SOA - Resolve Customer Company Exact V1" | Reads the Published snapshot, searches ERP, scores candidates, decides and saves the evidence on the order header. |
| **Consumer flows** WhenStatusChanges, Update Processing Status to Valid, SOA V3 - Notify | Re-check the saved proof against the current Published policy before validation, ERP save or notification. |
| **Skills** validate-customer, validate-product, create-sales-order | validate-customer reads the saved proof and returns Valid or the reason; the other two repeat the proof guard before writes. Skills never score a customer. |
| **Customer Match tab** | Read-only display of the saved evidence and score breakdown. |

The flows are the authority at run time. The skills and the viewer must agree with them, never the other way round.

### 12.3 Changing the delivered flows or skills

* Do not edit the delivered flows or skill bodies in place. In the portal you may change only connection bindings, turn a flow on or off (keep intake stopped while you do), and the environment variable values `aipod_FinanceOperationsInstance` (the environment's own F&O host) and `aipod_ReleaseHeaders` (keep `false` until release is approved).
* A logic change is made as a controlled change to the solution, in a development environment, and delivered as a new solution version through the upgrade process in the deployment guide.
* Before a logic change goes live, test it with representative orders, including the negative cases, with intake stopped and `aipod_ReleaseHeaders` set to `false`.

### 12.4 What you must not change by hand

Saved proof or evidence JSON, the policy snapshot, Published or Retired policy rows, the evidence `schemaVersion`, delivered flow definitions, delivered skill text, ERP data to force a match, and the `aipod_ReleaseHeaders` switch without separate approval.
