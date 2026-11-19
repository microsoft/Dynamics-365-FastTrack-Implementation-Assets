# Quick start

The shortest path from download to a first verified order. Use a **test** environment and an isolated mailbox. This page is a checklist; the [Deployment guide](deployment-guide.md) has the full procedure, and each step below names its section.

## Before you begin

- [ ] Azure subscription, `Microsoft.CognitiveServices` registered, GlobalStandard quota for `gpt-4.1` and `text-embedding-3-large`
- [ ] Azure AI Foundry resource and an identity that can deploy the analyzer (guide section 3.2)
- [ ] Power Platform environment with Dataverse (search on) and Copilot Studio; you are System Administrator
- [ ] Dynamics 365 Finance and Operations instance with an integration account (read customers and products, create sales orders)
- [ ] The Claude Sonnet model available in Copilot Studio, or plan to use **Auto**
- [ ] A test mailbox and folder that no other flow monitors
- [ ] PowerShell 7+ and the Azure CLI signed in (`az login`)
- [ ] DLP approval for the six connectors the solution uses (guide section 4.1)
- [ ] Release downloaded and `SHA256SUMS.txt` verified

## Install in six steps

| # | Step | What you do | Guide |
| --- | --- | --- | --- |
| 1 | **Deploy the analyzer** | `.\Deploy-Analyzer.ps1 -Endpoint https://<resource>.services.ai.azure.com`, then `.\Test-AnalyzerContract.ps1 -Endpoint ... -AnalyzerId sales_order_extraction_v2_0_7 -SampleDocument <sample.pdf>`. Continue only when it reports `FAIL = 0` | Part A |
| 2 | **Create connections, import** | Create the **HTTP with Microsoft Entra ID** connection with both URLs set to *your* Dataverse environment URL, plus the other connections. Import the **managed** solution and map every connection reference | Part B, 4.1-4.2 |
| 3 | **Set variables** | Set the reviewer email, mailbox and folder variables. **Use a reviewer address that is not the monitored mailbox**, or monitor a dedicated folder: notification emails sent to the monitored mailbox are read as new orders. Open the flow *SOA - Resolve Customer Company Exact V1* and set `FinanceOperationsInstance` to your F&O host name. Keep `ReleaseHeaders = false` | Part C |
| 4 | **Attach skills, publish agent** | In Copilot Studio open **Sales Order Agent V1.2**, attach the three business skills, check the Dataverse MCP and ERP MCP bindings, choose Claude Sonnet (or Auto), publish | Part D |
| 5 | **Activate and initialize** | Turn on the two publish flows, run `.\Initialize-SalesOrderAgent.ps1 -EnvironmentUrl https://<env>.crm.dynamics.com` (preview) and again with `-Apply`, then turn on the processing flows for held validation only | Part E |
| 6 | **Verify** | Run `.\Test-CuReadiness.ps1`, then the first order test below | Part F |

Stop and fix any step that fails before moving on. An import that succeeds does not mean the solution works: steps 3 to 5 cannot be done by the import.

## First order test (plan about 30 minutes)

Send **one** single-order document to the test mailbox. Use a PDF of at least 4096 bytes whose customer and items exist in the test legal entity, with a clear line-item table.

| Check | What you should see |
| --- | --- |
| 1. Intake | The intake flow ran once and created one staging record |
| 2. Extraction | The staging record holds the extracted JSON; header fields and every line match the document |
| 3. Order loaded | In the Sales Order Agent app the order shows its header and all lines; printed units show their normalized value |
| 4. Customer match | The **Customer Match** tab shows the company, customer, score, margin and reason. An accepted match meets the threshold and margin |
| 5. Held by default | With `ReleaseHeaders = false` the accepted order stays held and **no** ERP order exists |
| 6. Release (needs owner approval) | After the approved release, Dataverse shows **Processed** with an ERP order number |
| 7. ERP readback | Open that order in Finance and Operations. Company, customer, PO and every line (item, quantity, unit, site, warehouse) match the validated order |

Then try the held cases: a customer that is ambiguous, a unit that does not match the item, and an email body without a table. Each should stay held with a reason and create no ERP order.

A flow step that shows Succeeded is **not** proof. Always confirm the Dataverse record and the ERP order.

## If something stops

| Symptom | First thing to check |
| --- | --- |
| Agent says a skill is unavailable | Step 4: the three skills are attached and the agent is published |
| Orders stop with `CustomerMatchPolicyUnavailable` | The publish flow is On, the Entra connection URLs are your environment, and the setup script ran |
| Every validation stops on a product lookup | The agent model is Claude Sonnet or Auto |
| Dashboard totals tile is blank | The tile must be the `aipod_order_dashboard.html` web resource; reload with the cache cleared |
| Two copies of every order | Two intake flows watch the same mailbox and folder; keep one active |
| Notification emails turn into new orders | The reviewer address is the monitored mailbox. Use a different reviewer address or a dedicated monitored folder, stop intake, and delete the notification emails from the monitored folder |

More in the [FAQ](faq.md) and the deployment guide troubleshooting table (section 12).

## Next

- Day-to-day use: [User guide](user-guide.md)
- Tune customer matching: [Customer Matching Rules](customer-matching-rules.md)
- Add a document layout or a field: deployment guide, section 10
