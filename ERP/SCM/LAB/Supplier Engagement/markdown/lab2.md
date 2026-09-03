# Lab 2 of 9 — Configure Power Platform for Supplier Engagement

*⏱ ~30 min · Configure*

Activate email notifications, create service connections, turn on cloud flows, and enable duplicate detection. These steps connect the Supplier Engagement app and supplier portal with the automation layer that keeps suppliers and procurement staff in sync.

### Before you start
- [ ] Lab 1 complete — app installed, portal activated, identity provider set.
- [ ] Supplier portal URL is known (copy it from Power Pages site settings).
- [ ] Signed in as the dedicated service account.

## Part A — Mailbox & Email Templates

### Step 1 — Activate the service account mailbox for cloud flow notifications
**Why this matters:** the Supplier Engagement cloud flows send invitation and notification emails through a Dataverse mailbox. That mailbox must be activated, approved, and tested before any email will actually go out.

**Where:** Power Platform admin center › your environment › Power Platform Environment Settings app › Email Configuration › Mailboxes

**1. Open the settings app.** In the Power Platform admin center, open your environment and click the link under **Environment URL** to open it in a new tab. Then:
- If a *list of apps* opens, select `Power Platform Environment Settings`.
- If the environment opens *straight into an app*, click the app name on the header bar at the top to open the list of published apps, then select `Power Platform Environment Settings`.

**2. Find the right mailbox.** On the nav pane go to **Email Configuration → Mailboxes**. Open the mailbox whose email address matches the **account you used to install** Supplier Engagement. Click the mailbox to open the record (or select its row).

> **Note — No service account? Use your own ID — that's fine for this lab.** If you're running the lab signed in with your personal/work account and don't have a dedicated service account, activate **your own user's mailbox** (the same account you installed and signed in with). The steps are identical — just pick the mailbox that shows your email address. Everything below works the same way.

**3. Run these three command-bar actions in order**, confirming each dialog as it appears:
1. Click **Activate** → in the `Confirm Mailbox Activation` dialog, click **Activate**.
2. Click **Approve Email** → in the `Approve Primary Email` dialog, click **OK**.
3. Click **Test & Enable Mailboxes** → in the `Test Email Configuration` dialog, click **OK**.

> **Note — Production best practice (not required for this lab):** in a real deployment, point the flows at a permanent, non-personal service account or shared mailbox so automation doesn't break when a person leaves the org. For hands-on lab/trial purposes, your own account is perfectly fine.

> ✅ **Result:** After Test & Enable completes, the mailbox's incoming/outgoing email status shows "Success". Cloud flows can now send email.

### Step 2 — Customize email templates
In the **Power Platform Environment Settings** app go to **Templates → Email Templates**. Locate and open each of the three Supplier Engagement templates:
- `Supplier Engagement invitation` — **Must** include the correct portal URL link before go-live.
- `Supplier Engagement registration status`
- `Supplier Engagement contact portal access`

For the invitation template, replace the default portal URL placeholder with your actual portal URL (from the Power Pages site settings — see this lab's prerequisites). Update subject and body text to match your organization's branding. Save each template.

> ⚠️ **Warning:** The invitation email template must include your real portal URL. Suppliers who receive the default placeholder link will not be able to sign in.

## Part B — Connections & Cloud Flows

### Step 3 — Create Dataverse and Teams connections
In `make.powerapps.com` go to **More → Connections → New connection**. Add connections for:

| Service | Action |
|---|---|
| `Microsoft Dataverse` | Click **+** in Actions column, sign in as service account |
| `Microsoft Teams` | Click **+** in Actions column, sign in as service account |

> ✅ **Result:** Both connections appear in the Connections list with a green check (Connected).

### Step 4 — Update the three SupplierEngagement connection references
Go to **Solutions → Default solution → Objects → Connection References**. Find the entries containing `SupplierEngagement`. Three references should appear:

| Connection Reference | Set "Connection" to |
|---|---|
| `Microsoft Dataverse MicrosoftSupplierEngagement-77aa1` | The Dataverse connection from Step 4 |
| `Microsoft Dataverse msdyn_SupplierEngagementBase-abf2e` | The Dataverse connection from Step 4 |
| `Microsoft Teams MicrosoftSupplierEngagement-0e21b` | The Teams connection from Step 4 |

For each: open its three-dot menu → **Edit** → set **Connection** → **Save**.

> ⚠️ **Warning:** Use the browser's Ctrl+F, not the list's built-in search box. The Connection References list's own search/filter does *not* reliably match these entries — this is a known quirk the docs call out. Press **Ctrl+F** and search for `SupplierEngagement`. Because Ctrl+F only finds rows that are already rendered, **scroll down the list to load all rows first** (or scroll as you search) so none of the three are missed.

> ✅ **Result:** All three connection references show the correct connections without errors.

### Step 5 — Enable cloud flows in both Supplier Engagement solutions
Go to **Solutions → Managed tab**. Open `Supplier Engagement Core` → **Objects → Cloud flows**. For every flow showing **Status: Off**, select it and click **Turn on** on the command bar.

Return to the Managed solutions list, open `Supplier Engagement Portal`, and repeat — turn on all flows that are Off.

> **Note:** Cloud flows are installed but inactive by default. Until they are turned on, no notifications are sent, no user provisioning happens, and no data syncs between the app and portal.

> ✅ **Result:** All cloud flows in both solutions show Status: On.

## Part C — Duplicate Detection

### Step 6 — Publish four duplicate detection rules
In the **Power Platform Environment Settings** app go to **Data Management → Duplicate Detection Rules**. Select the checkbox for each rule below and click **Publish** on the command bar:

| Rule Name | Matching Field |
|---|---|
| `Global vendor with same primary phone number` | Exact match, include blanks |
| `Global vendor with same email address` | Exact match, ignore blanks |
| `Global vendor with same name` | Same first 5 characters, ignore blanks |
| `Global vendor with same primary URL` | Exact match, ignore blanks |

> ✅ **Result:** All four rules show "Status Reason: Published". Duplicate detection is now active for global vendor records.
