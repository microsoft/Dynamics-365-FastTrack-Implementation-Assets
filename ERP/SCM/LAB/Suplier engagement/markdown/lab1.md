# Lab 1 of 9 — Install Supplier Engagement on Power Platform

*⏱ ~30 min · Deploy*

Install the Supplier Engagement model-driven app and supplier portal into your Power Platform environment. Then reactivate the portal and configure the identity provider so that both internal admins and external suppliers can sign in correctly. Keep the portal hidden from the public until all configuration is complete.

### Before you start
- [ ] Lab 0 complete — all prerequisites confirmed.
- [ ] Signed in to Power Platform admin center as the dedicated service account.
- [ ] Target Power Platform environment identified and selected.

## Part A — Install the App

### Step 1 — Install Supplier Engagement from Power Platform admin center
Sign in to `admin.powerplatform.microsoft.com` and navigate to **Manage → Environments**. Open your target environment, then on the command bar click **Resources → Dynamics 365 apps → Install app**.

Search for `Supplier Engagement in Dynamics 365 Supply Chain Management (Preview)`, select it, accept the terms of service, then click **Install**.

> ✅ **Result:** Installation starts and the app appears in the Dynamics 365 apps list with status "Installing".

### Step 2 — Track installation progress in Power Apps
Sign in to `make.powerapps.com` and select your environment. On the left nav click **Solutions**, then on the command bar click **See History**. Watch for all Supplier Engagement solutions to show status **Succeeded**.

If the solution `msdyn_SupplierEngagementVendorEntity` fails with a *"String or binary data would be truncated"* error — wait **2 hours** and repeat the import from Step 1. This is a known timing issue with metadata sync.

> ✅ **Result:** All Supplier Engagement solutions show "Succeeded" in the solution history.

## Part B — Activate the Supplier Portal

### Step 3 — Reactivate the supplier portal in Power Pages
In `make.powerapps.com` go to **Solutions → Supplier Engagement Portal Solution → Objects → Sites**. Find `Microsoft Dynamics 365 Supplier Portal`, open its three-dot **Commands** menu and select **Open**. The browser will redirect to `make.powerpages.microsoft.com`.

Open the **Inactive sites** tab, find the portal, and click **Reactivate**. Confirm the reactivation and wait for the site to go live.

> **Note — Give the site time to finish provisioning.** Immediately after a reactivation (or after changing site visibility later), the SSL certificate and Azure Front Door routing are still being set up. During this window (typically **15–30 minutes**, occasionally up to an hour) the URL may show `ERR_CERT_COMMON_NAME_INVALID` / an HSTS block, or a *"We weren't able to find your Azure Front Door Service configuration"* page. This is expected — wait and retry. To test without waiting for browser caches to clear, open the URL in a fresh **InPrivate** window or a browser profile that hasn't visited the site.

> ✅ **Result:** The supplier portal site status changes from Inactive to Active in Power Pages.

### Step 4 — Configure Microsoft Entra ID as the identity provider
In Power Pages (`make.powerpages.microsoft.com`) open the *Microsoft Dynamics 365 Supplier Portal* site. On the left nav select **Security → Identity providers**. Find `Microsoft Entra ID`, open its three-dot menu, and select **Edit configuration**.

Set **Contact mapping with email** to `On`, then click **Save**.

> **Note:** For the preview period, Microsoft Entra ID is the recommended identity provider. This ensures supplier contacts can be mapped to Dataverse contact records by email address, which is required for the onboarding flow.

> **Note — This is the B2B guest access wiring.** Supplier sign-in works because each supplier contact becomes a Microsoft Entra B2B guest in your tenant (see Lab 0, Step 7 for the tenant-level guest settings this depends on), and this identity provider setting is what maps that guest's email back to the Dataverse contact record. Labs 5 and 6 walk through actually creating those guest accounts.

> ✅ **Result:** "Contact mapping with email" is saved as On for the Entra ID provider.

### Step 5 — Set site visibility to private
Keep the portal private while you complete Labs 2 and 3. In Power Pages, navigate to the site settings and set **Site visibility** to **Private** (accessible only to users with direct access). You will make it public after full configuration is validated.

> **Trial / non-production option:** Developer sites can't be made public, and some tenants block non-production sites from being switched to Public. In that case, keep the site **Private** and grant access to the supplier's redeemed Microsoft Entra B2B guest user: Power Pages › **Security** › **Site visibility** › **Grant site access**, enter the supplier user's email, then select **Share**. This only grants access to view the private site; the supplier still needs the Supplier Engagement contact, portal web role, and FSCM user provisioning steps later in the lab.

> ⚠️ **Warning:** Do not make the portal public until email templates are customized with the correct URL (Lab 2, Step 8) and the vendor user workflow is configured (Lab 3, Step 6). Premature public access causes incomplete onboarding emails to be sent.

## Part C — Brand the Portal *(Optional · company-compliant look)*

### Step 6 — (Optional) Open the Power Pages Management app
Out of the box the portal ships with placeholder company name, logo, and banner image. You replace these using the **Power Pages Management app** — branding lives in two component types:

| Component | Used for | Where |
|---|---|---|
| **Content snippets** | Text (company name, banner text) | Content → Content Snippets |
| **Web files** | Images (logo, banner image) | Content → Web Files |

In `make.powerpages.microsoft.com`, open your *Microsoft Dynamics 365 Supplier Portal* site. On the site overview page, click the **…** (ellipsis) next to the **Edit** / **Preview** buttons, then select **Power Pages Management**. This opens the model-driven management app where all branding lives.

> **Note — Other ways to open it, and a name caveat.** The app is called **Power Pages Management** when the site uses the *enhanced data model* — on the standard data model it appears as **Portal Management**. You can also reach it from:
> - **Design studio**: open the site → click the **…** on the tool belt → **Power Pages Management** / **Portal Management**.
> - **Power Apps** (`make.powerapps.com`): left pane → **Apps** → **Portal Management** (opens in a new tab).
>
> You need the **System Administrator** role in this Dataverse environment. If an ad-blocker is enabled you may see a script error — disable it for this app or use a clean browser.

> ⚠️ **Warning:** Editing these components creates unmanaged customization layers in Dataverse, which can affect solution management. Keep track of what you change (see the Learn article *"Manage unmanaged customizations on the supplier portal"*).

### Step 7 — (Optional) Update text — company name (content snippet)
Go to **Content → Content Snippets**, open the snippet below, update the **Value** field, and click **Save**.

| Snippet name | Controls |
|---|---|
| `Home/CompanyName` | Company name shown on the home page |

> **Note:** The home-page banner text is *not* a snippet. It displays the **Global vendor name** field value for the signed-in supplier — so it is per-vendor, not a global setting. Keep that name under ~500 characters to avoid layout overflow.

### Step 8 — (Optional) Update images — home banner & hero image (web files)
Go to **Content → Web Files**. To replace an image: open the web file record, in the **File Content** field select **Delete** to remove the existing image, then **Choose File** to upload your new one, and click **Save & Close**.

| Web file | Controls |
|---|---|
| `homepage-banner` | Top banner image across the home page |
| `home-heroimage.jpg` | Hero image on the home page |

**Banner image requirements:**
- Aspect ratio `12:1` (width : height) — off-ratio images stretch or crop.
- Recommended render size `3758 × 308 px`.
- Formats: `.png`, `.jpg`, `.svg`, `.webp`.
- Max file size = Dataverse attachment limit (default `5 MB`). Optimize for web to keep load times fast.

> **Note — Advanced (optional):** deeper styling — colors, fonts, banner height/positioning — is done through CSS (e.g. `dom.css`, the `.workspace-hero-banner` class). Test any CSS change across screen sizes.

> ✅ **Result:** The supplier portal shows your company name, banner, and hero image instead of the default placeholders.

### Step 9 — (Optional) Update the placeholder links on the Help card
The **Help** card on the home page shows four links — *Terms & Condition*, *How to Respond to a Purchase Order*, *How to Add or Remove a User*, and *Contact Support*. Out of the box every one of them is a dead placeholder (`href="#"`), so clicking them does nothing. The link *text* comes from content snippets, but the *target URL* is hard-coded in a web template — so you fix the targets there, not in the snippet.

In **Power Pages Management → Web Templates**, open `Essentials Help` and edit the **Source**. Replace each `href="#"` with a real target:

| Help link | Set `href` to |
|---|---|
| Terms & Condition | `/terms-and-conditions` — the page you create (see note below), or your external terms URL |
| How to Respond to a Purchase Order | `/Purchase-order-workspace` |
| How to Add or Remove a User | `/user-management` |
| Contact Support | `mailto:support@yourcompany.com` — your support inbox |

For example, the Contact Support anchor becomes:

```html
<a href="mailto:support@yourcompany.com" class="vendor-link">{{ snippets['Home/Help/ContactSupport'] }}</a>
```

> **Note — Creating a Terms & Conditions page:** in the Power Pages **design studio → Pages**, click **+ Page**, name it *Terms and Conditions*, add a **Text** component with your terms, and confirm its partial URL (e.g. `terms-and-conditions`) in the page settings. Set its visibility (anonymous if terms must be readable before sign-in, otherwise authenticated). Then point the *Terms & Condition* link at `/terms-and-conditions`.

> ⚠️ **Warning:** Editing a web template is an **unmanaged customization**, and the portal caches templates and pages — after saving, click **Sync** in the design studio (or clear the portal cache) or the old `#` links will persist.

> ✅ **Result:** Each Help link navigates to the correct portal page or opens the support mailbox.
