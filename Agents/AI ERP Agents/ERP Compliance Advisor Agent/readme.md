# ERP Compliance Advisor Agent

> AI-powered Security & IT Audit assistant for Dynamics 365 Finance & Operations, built on Microsoft Copilot Studio.

## Use Case

### Overview

The ERP Compliance Advisor Agent is an AI-powered Security & IT Audit assistant built on Microsoft Copilot Studio that enables a designated **Agent Operator** to respond to auditor and compliance questionnaires by performing real-time security audits of Dynamics 365 Finance & Operations (D365 F&O) through natural language conversations.

### Target Users

| Persona | How They Use the Agent |
|---|---|
| Internal Auditors | User access reviews, SOX compliance checks, SoD violation analysis |
| IT Security Teams | Privileged access monitoring, login anomaly detection, role change tracking |
| Compliance Officers | License compliance, policy violation identification, audit trail review |
| External Auditors | Submit evidence requests to the Agent Operator. Receive on-demand evidence. |
| IT Managers | Batch job oversight, data export monitoring, user administration audit |
| CISOs / Risk Officers | Executive security health summaries, risk dashboards |
| Agent Operator — System Administrator (Option 1) | The System Administrator on the customer's project team collects audit questionnaires, uses the agent to query D365 F&O, and returns structured responses to auditors. No additional role needed. Suitable for initial deployment or small teams. |
| Agent Operator — AuditAgentReader User (Option 2 — Recommended) | A dedicated person assigned only the `AuditAgentReader` role. Collects audit questionnaires, queries the agent, and returns responses — without holding full admin privileges. Best practice for SoD compliance. |

### Key Scenarios

- **Periodic User Access Review** — Auditor asks: *"Show me all users with System Administrator role who haven't logged in for 90 days"* — agent cross-references User Security Roles + System User Log entities automatically.
- **SOX Compliance Audit** — Auditor asks: *"Generate a SOX compliance readiness report"* — agent queries multiple entities and produces a structured findings summary.
- **License Optimization** — IT manager asks: *"Which users are over-licensed compared to their role requirements?"* — agent analyses license-by-role data.

## Problem Statement

In enterprise ERP environments such as Dynamics 365 Finance & Operations, auditors, IT security teams, and compliance officers routinely request detailed information to validate governance, access controls, and regulatory compliance.

Typical audit and compliance requests include:

- Lists of users and their assigned security roles
- Identification of privileged access (for example, System Administrator and Security Administrator roles)
- Clear explanations of role-based security models (roles, duties, and privileges)
- Detection and justification of Segregation of Duties (SoD) violations
- Comparison of license assignments versus actual access and usage
- Evidence of role changes, temporary access, and administrative activities
- Verification of security configuration, governance policies, and control effectiveness

### Current Challenges

| Challenge | Impact |
|---|---|
| Manual Audit Processes | When auditors request compliance evidence, a project team member with System Administrator access manually navigates multiple D365 F&O forms, exports data, consolidates it in Excel, and shares it back — taking days or weeks per audit cycle, with the auditors themselves having no direct ERP access. |
| Fragmented Data Sources | Security data is spread across tables/forms in F&O (User security, role assignments, audit logs, batch jobs, database logs, SoD rules) — no single view. |
| Reactive Auditing | Security reviews happen quarterly or annually; issues go undetected for months. |
| Skill Gap | Not all users understand D365 F&O's complex security model (Role → Duty → Privilege hierarchy) or know which forms to check. |
| Slow Evidence Gathering | External auditors request evidence (user lists, role assignments, change logs) and IT teams spend hours manually extracting it. |
| Compliance Risk | Delayed detection of SoD violations, unauthorized role changes, and expired temporary access increases regulatory and financial risk. |

## Solution Capabilities

An AI-driven ERP Compliance Advisor Agent for D365 Finance & Operations that enables plain-English compliance queries without technical navigation. It automatically correlates real-time data across entities to produce structured, audit-ready insights while proactively flagging risks. The solution delivers end-to-end compliance visibility across security, access, change tracking, and IT operations, and is extensible to support customer-specific audit scenarios and rules.

### Core Capabilities

| Capability | Description |
|---|---|
| Natural Language Querying | Ask audit questions in plain English — no OData, SQL, or F&O form navigation required |
| Autonomous Tool Selection | AI-powered generative orchestration automatically determines which data entity(s) to query based on the user's question |
| Real-Time Data | Queries D365 F&O OData endpoints in real time — always current, no data lag |
| Structured Output | Results presented as formatted tables, summaries, or audit-report style narratives |
| Risk Flagging | Agent proactively highlights anomalies and compliance risks in query results |
| Audit Data Sources | Covers user access, license compliance, security governance, role structure |

## Architecture

### High-Level Architecture

*See architecture diagram in the release documentation.*

### Data Flow

*See data flow diagram in the release documentation.*

## Pre-Requisites

### Licensing

| Component | License Required |
|---|---|
| Copilot Studio | Microsoft Copilot Studio license (per-tenant or per-user) |
| D365 Finance & Operations | D365 F&O license (Finance, Supply Chain, or Commerce) |
| Power Platform | Included with Copilot Studio; premium connectors enabled |
| Microsoft Teams / M365 Copilot | Microsoft 365 license |

### D365 F&O Environment

| Requirement | Details |
|---|---|
| Platform version | Platform update 45+ |
| Data entities | 12 custom entities (`AuditAgent*`) must be deployed to F&O |
| OData access | OData v4 endpoints must be accessible (`/data/EntityName`) |
| User Security Governance | D365 User Security Governance module must be enabled (for governance entities) |

### Connectivity & Authentication

| Requirement | Details |
|---|---|
| Network | Copilot Studio / Power Platform must reach F&O OData endpoints (HTTPS 443) |
| Authentication | Microsoft Entra ID (Azure AD) — user-delegated OAuth 2.0 |
| F&O Access | The user accessing the D365 F&O connection must have valid access to the F&O environment and appropriate security permissions assigned. |
| Security role in F&O | Access for the connecting user must be granted either through the System Administrator role (full access) or via a custom role, such as `AuditAgentReader`, that includes read permissions for all relevant entities. |

### Administrative Access

| Who | Needs Access To |
|---|---|
| Copilot Studio maker | Copilot Studio environment (Agent creator role) |
| F&O developer | D365 F&O dev environment (to create/deploy custom entities) |
| Power Platform admin | Power Platform environment (to manage solutions, connections) |
| Entra ID admin | Azure AD (to configure authentication, security groups) |

## Installation Process

### Phase 1 — D365 F&O Preparation (F&O Developer)

These steps must be completed before importing the solution into Copilot Studio.

| Step | Action | Details |
|---|---|---|
| 1.1 | Deploy Custom Data Entities | Import `SA_ERPComplianceAdvisorAgent.axpp` and deploy the 12 custom `AuditAgent*` data entities into your D365 F&O environment via a deployable package. |
| 1.2 | Validate Entity Visibility | Go to **System Administration → Data Management → Data Entities** → confirm all 19 entities have **Is Public = Yes**. |
| 1.3 | Test OData Access | Open a browser and navigate to `https://<your-env>.operations.dynamics.com/data/AuditAgentInvalidUsers` — verify JSON data is returned. |
| 1.4 | Enable Database Logging | Go to **System Administration → Database log setup** → configure logging on required tables. |
| 1.5 | Enable Audit Trail | Ensure audit trail is active on relevant tables. |
| 1.6 | Create Read-Only Security Role | Create a custom security role `AuditAgentReader` with Read permission on all 19 data entities. |
| 1.7 | Assign Security Role to Agent Users | **Option 2 only:** Assign the `AuditAgentReader` role to the designated Agent Operator in D365 F&O. If using Option 1 (System Administrator), skip this step — the System Administrator account already has the required access. |

**Recommendation: AuditAgentReader Role — Two Options for Agent Operators**

The agent is operated by a designated Agent Operator — a person from the customer's project team who collects audit questionnaires, queries the agent, and returns responses to auditors. Auditors never receive direct D365 F&O access. Two options are supported:

- **Option 1 — System Administrator Operates the Agent.** The existing System Administrator uses the agent directly. No additional role assignment is needed. Suitable for initial deployment or small teams. *Note: The System Administrator holds elevated privileges beyond what is needed for audit response capture alone — not recommended for long-term production use.*
- **Option 2 — Dedicated AuditAgentReader Operator (Recommended for Production).** A dedicated person is assigned only the `AuditAgentReader` role with no broader admin access. They act as the sole intermediary between auditors and the ERP system. This is recommended because it:
  - Avoids unnecessary elevated access for the person capturing audit responses.
  - Maintains a clear audit trail of who has agent-specific (`AuditAgentReader`) access.
  - Complies with Segregation of Duties policies — the audit response operator should not hold System Administrator privileges. Auditors themselves should never be assigned any D365 F&O role.

### Phase 2 — Download the Solution Package

| Step | Action |
|---|---|
| 2.1 | Obtain the solution file `AI ERP IT and Security Audit Solution` (`.zip` file) from your organization's distribution channel (e.g., SharePoint, email, or internal portal). |
| 2.2 | Save the `.zip` file to your local machine — **do not extract/unzip it**. |

#### Solution Package Structure

`AI ERP IT and Security Audit Solution.zip` contains:

- ERP Compliance Advisor Agent (preconfigured agent with instructions)
- 19 Connector Tools (Fin & Ops Apps → *List items present in table*)
- Connection Reference – Fin & Ops Apps (Dynamics 365)
- Knowledge Sources (if included)

### Phase 3 — Import the Solution into Your Environment

**Step 3.1 — Sign in to Copilot Studio**

- Open your browser and go to: https://copilotstudio.microsoft.com
- Sign in with your Microsoft 365 / Entra ID credentials.
- At the top right, verify you are in the correct environment (your target Power Platform environment).
- If not, click the **Environment selector** (top right corner, next to your profile icon) and select your target environment from the dropdown.

> **Important:** The environment you select here is where the agent will be deployed. Make sure it matches the environment connected to your D365 F&O instance.

**Step 3.2 — Navigate to Solutions**

- In the left navigation pane, click **Solutions**.
- If you don't see *Solutions* in the left nav, go to https://make.powerapps.com → select the same environment → click **Solutions** in the left nav. You can import the solution from either portal.

**Step 3.3 — Import the Solution**

1. Click **Import solution** (top command bar).
2. Click **Browse** → select the `AI ERP IT and Security Audit Solution.zip` file from your local machine.
3. Click **Next**.
4. The import wizard shows the solution details:
   - **Display name:** AI ERP IT and Security Audit Solution
   - **Publisher:** (your organization's publisher)
   - **Version:** (solution version)
5. Click **Next**.

**Step 3.4 — Configure the Connection Reference**

During import, you will be asked to set up the **Fin & Ops Apps (Dynamics 365)** connection:

1. Under **Connection References**, you will see: *Fin & Ops Apps (Dynamics 365)*.
2. Click the **Select a connection** dropdown:
   - If you already have an existing Fin & Ops connection, select it from the dropdown.
   - If you need to create a new connection, click **+ New connection**.
3. A new browser tab opens for Power Platform connection setup.
4. Sign in with credentials that have read access to your D365 F&O environment (the user with `AuditAgentReader` role).
5. Click **Create**.
6. Return to the import wizard tab and click **Refresh** to see the new connection.
7. Select the newly created connection.
8. Click **Next**.

**Step 3.5 — Complete the Import**

1. Review the summary — verify solution name, connection reference, and components.
2. Click **Import**.
3. Wait for the import to complete — a green banner confirms: *"Solution imported successfully"*.

> Import typically takes 1–3 minutes. Do not navigate away during import.

### Phase 4 — Verify the Imported Solution

**Step 4.1 — Open the Solution**

- Go to **Solutions** in the left nav.
- You should now see *AI ERP IT and Security Audit Solution* in the list.
- Click on it to open.
- Verify all components are present:

| Component Type | Name | Count |
|---|---|---|
| Agent | ERP Compliance Advisor Agent | 1 |
| Agent Tools | Get Invalid Users, Get System User Log, etc. | 19 |
| Connection Reference | Fin & Ops Apps (Dynamics 365) | 1 |

**Step 4.2 — Update the F&O Instance URL in Tools**

> **Critical Step:** The tools in the imported solution contain a placeholder or original maker's F&O URL. You must update them to point to your F&O environment.

For each of the 19 tools:

1. In the solution, click on the agent → go to **Tools**.
2. Click on a tool (e.g., *Get Invalid Users*).
3. Under **Inputs**, find the **Instance** field.
4. Change the value from the existing URL to your F&O environment URL: `https://<your-environment>.operations.dynamics.com`
5. Click **Save**.
6. Repeat for all 19 tools.

**Step 4.3 — Verify Connection Is Working**

- Open any tool → check that the connection shows a green checkmark (connected).
- If it shows an error, go to **Settings → Connections** and re-authenticate the Fin & Ops Apps connection.

### Phase 5 — Test the Agent

| Step | Action |
|---|---|
| 5.1 | Open the **ERP Compliance Advisor Agent** from within the solution. |
| 5.2 | Click the **Test your agent** pane (bottom-right corner). |
| 5.3 | Type a test prompt: *Show me all invalid users*. |
| 5.4 | Verify the agent calls the *Get Invalid Users* tool and returns data from your F&O. |
| 5.5 | Check the **Activity Map** (below the test chat) to confirm correct tool selection. |
| 5.6 | Test at least one prompt per audit domain:<br>• *"Show me all users with System Administrator role"* (User Access)<br>• *"Who has privileged access right now?"* (Security Governance)<br>• *"Show database log entries from today"* (Change Tracking)<br>• *"List all failed batch jobs this week"* (IT Operations) |
| 5.7 | If any tool fails, check: entity name spelling, F&O instance URL, connection status, user permissions in F&O. |

### Phase 6 — Publish & Deploy to Channels

| Step | Action |
|---|---|
| 6.1 | Once testing passes, click **Publish** (top right in Copilot Studio). |
| 6.2 | **Deploy to Microsoft Teams:** Go to **Channels → Microsoft Teams** → click **Turn on Teams** → **Submit for admin approval** (if required) or **Open in Teams**. |
| 6.3 | *(Optional)* **Deploy to SharePoint:** **Channels → SharePoint** → follow the embed steps. |
| 6.4 | *(Optional)* **Deploy to custom website:** **Channels → Custom website** → copy the embed code. |

### Phase 7 — Configure Security & Access Control

| Step | Action |
|---|---|
| 7.1 | Go to **Settings → Security → Authentication**. |
| 7.2 | Select **Authenticate with Microsoft (Entra ID)**. |
| 7.3 | Under **Access**, restrict to specific Security Groups (e.g., *Agent Operators* group — the team members designated to respond to audit questionnaires). |
| 7.4 | Click **Save**. |

## Limitations & Constraints

### Technical Limitations

| Limitation | Details | Mitigation |
|---|---|---|
| Tool limit | Max 128 tools per agent; recommended ≤ 25–30 for best performance | Current design uses 19 tools — within optimal range |
| Token limits | AI response context window has limits; very large result sets may be truncated | `$select` is hardcoded to return only relevant columns; `$top` limits row count |
| Single environment | Each tool is hardcoded to one F&O instance URL | For multi-environment audits, create separate agents or parameterize the instance |
| Read-only | Agent can only read data via *List items present in table* — cannot write, update, or delete | By design — audit agents should not modify data |
| No real-time alerts | Agent is conversational (pull-based); does not push alerts or notifications | Roadmap: add Power Automate scheduled triggers for proactive monitoring |

### Functional Limitations

| Limitation | Details |
|---|---|
| No drill-down to F&O forms | Agent returns data but cannot link directly to F&O screens |
| No chart/visualization | Responses are text/table only — no embedded charts |
| Filter complexity | AI-generated OData filters work for common scenarios but may struggle with highly complex nested filter logic |
| No data aggregation | OData doesn't support `GROUP BY` or `SUM` — the AI can summarize returned rows but cannot do server-side aggregation |
| SoD analysis depth | SoD tool shows existing configured conflicts; it does not compute new SoD rules dynamically |

### Security Constraints

| Constraint | Details |
|---|---|
| Data access = user's access | Connector runs with the signed-in user's credentials; they only see data their F&O security role permits |
| No data caching | Data is not stored in Copilot Studio or Power Platform — queried and returned in real time |
| Audit of the agent itself | Agent conversations are logged in Copilot Studio analytics but not in F&O audit trail |

## Roadmap

**Phase 1 — Foundation (Current Release)**

- 19 connector-based tools covering 5 audit domains
- Natural language querying with generative orchestration
- Single-solution packaging
- Teams and web channel deployment
- Knowledge integration (security policies)

**Phase 2 — Proactive Monitoring (Next)**

- Scheduled audit checks — Power Automate flows run daily/weekly to detect anomalies and send email/Teams alerts
- Dashboard integration — embed agent findings into Power BI dashboards
- Audit report generation — export formatted audit reports as PDF/Word documents
- Anomaly detection — AI-driven pattern analysis to flag unusual login times, sudden role changes, bulk data exports

## Return on Investment (ROI)

| Metric | Before (Manual) | After (Agent) | Savings |
|---|---|---|---|
| Time per user access review | 40–80 hours | 2–4 hours | 90–95% reduction |
| Time to gather audit evidence | 4–8 hours per request | 2–5 minutes per question | 97% reduction |
| Audit cycle frequency | Quarterly (4×/year) | On demand / continuous | Real-time compliance |
| Time to detect SoD violations | Weeks (next audit cycle) | Seconds (ask the agent) | Near-instant detection |
| Time to investigate security incidents | 2–5 days (manual data collection) | 15–30 minutes (multi-entity queries) | 95% reduction |
| Full IT audit labour | 500–1,000 hours/year | 50–100 hours/year | 80–90% reduction |
