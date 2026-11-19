# DLP, Azure and Dataverse requirements - Sales Order Agent

Release 1.0.9.0, 3 November 2026. These are deployment requirements. They do not configure a policy, role or
connection for you; each must be approved and tested in the target.

## 1. DLP data policy - connector classification

All six connectors must be in the **same group (normally Business)** and none may be **Blocked**.

| # | Connector name in the admin center | Connector ID | Used by | Required group |
|---|---|---|---|---|
| 1 | **Microsoft Dataverse** | `shared_commondataserviceforapps` | All flows, including the two publish flows, and the agent's **Dataverse MCP** tool | **Business** |
| 2 | **Agents** (shown as *Microsoft Copilot Studio* in some tenants) | `shared_agentnode` | `WhenStatusChanges` runs the agent for VALIDATE and SAVE | **Business** |
| 3 | **Office 365 Outlook** | `shared_office365` | Both intake flows (new email trigger), both notify flows (reviewer email) | **Business** |
| 4 | **Azure AI Content Understanding** | `shared_contentunderstanding` | Both intake flows (analyze document) | **Business** |
| 5 | **Fin & Ops Apps (Dynamics 365)** | `shared_dynamicsax` | The customer resolver's candidate reads and the agent's **ERP MCP** tool | **Business** |
| 6 | **HTTP with Microsoft Entra ID** | `shared_webcontents` | The customer resolver, the policy publish flow, `WhenStatusChanges` and Update Processing Status to Valid read Dataverse configuration and evidence through the dedicated connection `aipod_sharedwebcontents_customermatch` (deployment guide, section 4.1) | **Business** |

If a policy blocks the solution you will see messages such as "Policy '<name>' blocks using **shared_agentnode** with
another connector in this flow". A data policy lets connectors in the same group be used together in one flow and
blocks a flow that mixes groups, and newer connectors fall into the policy's default group, usually Non-business. A
Power Platform admin puts all six connectors in the Business group, or scopes a dedicated policy to the target
environment, in the Power Platform admin center under Security > Data and privacy > Data policy. Then turn each
affected flow off and on, because flows suspended by DLP do not resume by themselves.

Admin must review **all applicable** tenant and environment policies, connector grouping, endpoint restrictions and
action rules. A permissive second policy does not override a more restrictive applicable policy. Do not weaken
tenant-wide policies or classify arbitrary HTTP access as Business merely to unblock this application. Scope the
dedicated connection `aipod_sharedwebcontents_customermatch` to the approved target Dataverse base URL and validate
actual requests under the runtime identity. If the policy uses endpoint filtering for Dataverse, allow the target
environment's URL.

Copilot Studio agent-level connectors are **not required** by this agent and may stay Non-business or Blocked:

| Connector in the admin center | Why it is not needed |
|---|---|
| Chat without Microsoft Entra ID authentication in Copilot Studio | The agent uses Microsoft Entra ID authentication. |
| Direct Line channels, Microsoft Teams and Microsoft 365 channel, other channels in Copilot Studio | The agent is invoked only by the `WhenStatusChanges` flow; no channel is published for users. |
| HTTP (agent) | The agent makes no HTTP requests. The flow-level HTTP with Microsoft Entra ID connector in the table above is separate. |
| Knowledge sources (documents, public websites, SharePoint and OneDrive) | The agent has no knowledge sources. |
| Skills with Copilot Studio | The business skills are Dataverse skill records read through the Dataverse MCP tool, not Azure Bot Service skills. |
| Application Insights in Copilot Studio | Not configured. |

Notes:

* The built-in *When an agent calls the flow* trigger and *Respond to the agent* action in `SOA V3 - Notify` are not
  connectors and are not classified by DLP.
* The Dataverse MCP server is enabled for Copilot Studio by default; no environment setting is required.
* Do not automatically reactivate flows that DLP suspended. Preserve the held release setting and follow the
  deployment guide's activation sequence.

## 2. Azure security roles (Content Understanding)

| Who | Role | Scope | Needed for |
|---|---|---|---|
| Installer | **Cognitive Services Contributor** | Resource group (or the resource) | Find the resource; create the `gpt-4.1` and `text-embedding-3-large` deployments |
| Installer | **Cognitive Services User** | The Azure AI Foundry resource | Set Content Understanding defaults, create/replace the analyzer, contract test. Missing this role causes `401 PermissionDenied` on `/contentunderstanding/defaults` |
| Alternative to Cognitive Services User | Cognitive Services Content Understanding **Owner** | The resource | Same; *Content Understanding Contributor* cannot delete, so `-Force` fails |
| Azure admin | **Owner**, **User Access Administrator** or **Role Based Access Control Administrator** | Resource group or above | Assign the two roles above |
| Runtime connection (key-based) | None | - | The API key is the credential; anyone with Cognitive Services Contributor or User can copy it once |
| Runtime connection (optional, Microsoft Entra ID) | Cognitive Services Content Understanding **Reader** | The resource | Analyze at run time |

Also required: the `Microsoft.CognitiveServices` provider registered; GlobalStandard quota for `gpt-4.1` (2025-04-14)
and `text-embedding-3-large` (1) in the region; key (local) authentication enabled on the resource; public network
access, or network rules that admit Power Platform. Validate subscription, provider, quota, network and both
management-plane and data-plane permissions before activation.

## 3. Dataverse security roles

| Who | Role | Needed for |
|---|---|---|
| Installer | **System Administrator** | Import the managed solution, set environment variables, create connections, attach the three skills and publish the agent, turn flows on, run the first-time setup script |
| Flow owner / connection account (one service account recommended) | **System Administrator**, or the least-privilege alternative **Basic User** plus the shipped **Sales Orders Reviewer** | The flows create and update staging, header and line rows. `Sales Orders Reviewer` grants Create/Read/Write/Delete/Append/Append To/Assign/Share at organization level on `Staging Document`, `Sales Order Header`, `Sales Order Line` and flow privileges. The Unit alias publish flow also needs a connection that can write environment variable values |
| Agent run-time identity = the account behind the **Agents** connection in `WhenStatusChanges` (the agent's Dataverse MCP and ERP MCP tools run as this user, `authMode: Invoker`) | **System Administrator**, or Basic User plus Sales Orders Reviewer plus **Read on the Skill table**; the agent must be shared with this user | Read and update order headers and lines; read the three business skills. The shipped role does not include the Skill table |
| Reviewers (Manual Review) | **Basic User** plus **Sales Orders Reviewer** | Open and correct staging documents, headers and lines; read-only customer match evidence |
| People who change matching rules and unit aliases | **Sales Order Matching Administrator** | Setup > Matching rules and Setup > Units of measure. Create/Read/Write/Append/Append To on the policy and unit alias tables, no Delete. Do not give it to reviewers |

Test the least-privilege variants in your environment before relying on them; broad administrator access does not
establish least privilege. Native header and status fields retain their original editability, and the read-only
Customer Match viewer is not a server-side write authorization boundary: review role privileges, Skill and
configuration table reads, flow ownership and ERP legal-entity rights rather than inferring them from a role's name.

Also required in the environment: **Dataverse search ON** (the agent reads staging and header rows through it);
Copilot Studio enabled with capacity; premium licences for the flow owner (Dataverse and Fin & Ops are premium
connectors). Organization auditing and retention are environment settings; turn them on if you need an audit trail.

The **F&O integration account** used by the Fin & Ops connection needs F&O roles that can read customers, released
products, product default order settings and warehouses, and create sales orders, in every legal entity you process.

Runtime credentials belong in Power Platform connections or approved secret storage, never in solution defaults, logs
or distributable settings. Solution references are not portable credentials or proof of consent.

For activation steps see the [deployment guide](./deployment-guide.md).
