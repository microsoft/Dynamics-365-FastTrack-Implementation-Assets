# ERP Compliance Advisor Agent

> AI-powered Security & IT Audit assistant for Dynamics 365 Finance & Operations, built on Microsoft Copilot Studio.

> [!WARNING]
> **Security & responsible use — ERP Compliance Advisor Agent**
>
> - **Do not store or share credentials, client secrets, or tenant identifiers** in this README, in the agent's conversation history, in screenshots, or in any derived audit report. Authentication is performed by the connector via the signed-in user's Microsoft Entra ID identity — no secret should ever be entered into the agent.
> - **Audit responses may contain sensitive data** (user lists, role assignments, login history, SoD exceptions). Treat all agent output as confidential and share only with authorized auditors, compliance officers, and security personnel.
> - **The agent runs with the signed-in user's F&O permissions.** Operate the agent only under an account assigned the least-privilege `AuditAgentReader` role; do **not** use a System Administrator account for routine queries.
> - **Read-only by design.** The 17 built-in tools issue only OData `GET` requests. Do not modify the solution to add write actions without a fresh security review.
> - **Do not paste, screenshot, email, or record** audit output containing PII, security configuration, or vulnerability indicators in non-secure channels.

## Table of Contents

- [Use Case](#use-case)
  - [Overview](#overview)
  - [Target Users](#target-users)
  - [Key Scenarios](#key-scenarios)
- [Problem Statement](#problem-statement)
  - [Current Challenges](#current-challenges)
- [Solution Capabilities](#solution-capabilities)
  - [Core Capabilities](#core-capabilities)
- [Architecture](#architecture)
  - [High-Level Architecture](#high-level-architecture)
  - [Data Flow](#data-flow)
- [Extensibility](#extensibility)
- [Pre-Requisites](#pre-requisites)
  - [Licensing](#licensing)
  - [D365 F&O Environment](#d365-fo-environment)
  - [Connectivity & Authentication](#connectivity--authentication)
  - [Administrative Access](#administrative-access)
- [Installation Process](#installation-process)
  - [Phase 1 — D365 F&O Preparation (F&O Developer)](#phase-1--d365-fo-preparation-fo-developer)
  - [Phase 2 — Download the Solution Package](#phase-2--download-the-solution-package)
  - [Phase 3 — Import the Solution into Your Environment](#phase-3--import-the-solution-into-your-environment)
  - [Phase 4 — Verify the Imported Solution](#phase-4--verify-the-imported-solution)
  - [Phase 5 — Test the Agent](#phase-5--test-the-agent)
  - [Phase 6 — Production Deployment](#phase-6--production-deployment)
  - [Phase 7 — Publish & Deploy to Channels](#phase-7--publish--deploy-to-channels)
  - [Phase 8 — Configure Security & Access Control](#phase-8--configure-security--access-control)
- [Limitations & Constraints](#limitations--constraints)
  - [Technical Limitations](#technical-limitations)
  - [Functional Limitations](#functional-limitations)
  - [Security Constraints](#security-constraints)
- [Roadmap](#roadmap)

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

<img width="541" height="313" alt="image" src="https://github.com/user-attachments/assets/6df1b905-e3fd-48cb-aa4d-3c4b3f193422" />

### Data Flow

<img width="975" height="731" alt="image" src="https://github.com/user-attachments/assets/5ea707b8-8122-44ad-b559-7b8dce470fb8" />

## Extensibility

The ERP Compliance Advisor Agent is designed to be **fully extensible** so customers can adapt it to their own audit, security, and IT governance scenarios without modifying the base solution.

**What you can extend**

- **Add your own D365 F&O data entities** — Create a new custom data entity (or expose an existing standard entity) in your F&O environment that surfaces any table, view, or aggregated data relevant to your compliance scenario (for example: custom approval logs, vendor onboarding checklists, segregation-of-duties exceptions specific to your industry, or regulator-mandated audit trails).
- **Publish the entity** — Build, publish, and refresh the data entity list in F&O so it is available over OData with the appropriate read permissions granted to the `AuditAgentReader` role (or your own equivalent role).
- **Hook it into the Copilot agent** — In Copilot Studio, add a new tool to the agent using the same **Fin & Ops Apps (Dynamics 365) → List items present in table** action used by the 17 built-in tools. Point it at your new entity, set the **Instance** to your F&O environment URL, and add a clear natural-language description of when the agent should use the tool.
- **Maintain it yourself** — Because every tool is just a connector action plus a description, customers own the full lifecycle of their extensions: add, modify, version, or retire tools at any time from Copilot Studio without depending on Microsoft or the original publisher. Standard Power Platform ALM (solutions, environments, pipelines) applies.

**Typical extension patterns**

- Industry-specific compliance (e.g., FDA 21 CFR Part 11, SOX ITGC, GDPR DSAR evidence) backed by custom entities.
- Customer-specific SoD rules or sensitive-duty combinations that go beyond the standard USG output.
- Integration with non-F&O audit data (via Dataverse or other connectors) added as additional tools.
- **Extend with your own compliance knowledge** — Beyond the 17 built-in OData connector tools, customers can extend the agent with their own ERP compliance knowledge by attaching additional knowledge sources in Copilot Studio — for example, a SharePoint site or document library containing internal audit policies, SoD matrices, control narratives, regulatory mappings (SOX, GDPR, ISO 27001), prior audit reports, or company-specific compliance playbooks. Once added, users can ask questions that blend live D365 F&O telemetry with their own documentation in a single response (e.g., *"List users with the System Administrator role and cross-check them against our SOX privileged-access policy"*). Supported sources include SharePoint sites/files, OneDrive documents, public websites, Dataverse tables, Graph connectors, and uploaded files (PDF, DOCX, XLSX, TXT, etc.). Configure these under **Copilot Studio → your agent → Knowledge → + Add knowledge**.

Because the agent is read-only by design, extensions inherit the same security posture — they should also be limited to read operations against entities the connecting account is authorized to view.

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
| Data entities | 10 custom entities (`AuditAgent*`) must be deployed to F&O |
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
| 1.1 | Deploy Custom Data Entities | Import [`SA_ERPComplianceAdvisorAgent.axpp`](https://github.com/ankur198015/Dynamics-365-FastTrack-Implementation-Assets/blob/add-erp-compliance-advisor-agent-folder/Agents/AI%20ERP%20Agents/ERP%20Compliance%20Advisor%20Agent/SA_ERPComplianceAdvisorAgent.axpp) and deploy the 10 custom `AuditAgent*` data entities into your D365 F&O environment via a deployable package. |
| 1.2 | Validate Entity Visibility | Go to **System Administration → Data Management → Data Entities** → confirm all 17 entities have **Is Public = Yes**. |
| 1.3 | Test OData Access | Open a browser and navigate to `https://<your-env>.operations.dynamics.com/data/AuditAgentInvalidUsers` — verify JSON data is returned. |
| 1.4 | Enable Database Logging | Go to **System Administration → Database log setup** → configure logging on required tables. |
| 1.5 | Enable Audit Trail | Ensure audit trail is active on relevant tables. |
| 1.6 | Create Read-Only Security Role | Create a custom security role `AuditAgentReader` with Read permission on all 17 data entities. |
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
| 2.1 | Obtain the solution file [`ERPComplianceAdvisorAgentSolution_1_0_0_1.zip`](https://github.com/ankur198015/Dynamics-365-FastTrack-Implementation-Assets/blob/add-erp-compliance-advisor-agent-folder/Agents/AI%20ERP%20Agents/ERP%20Compliance%20Advisor%20Agent/ERPComplianceAdvisorAgentSolution_1_0_0_1.zip) from your organization's distribution channel (e.g., SharePoint, email, or internal portal). |
| 2.2 | Save the `.zip` file to your local machine — **do not extract/unzip it**. |

#### Solution Package Structure

[`ERPComplianceAdvisorAgentSolution_1_0_0_1.zip`](https://github.com/ankur198015/Dynamics-365-FastTrack-Implementation-Assets/blob/add-erp-compliance-advisor-agent-folder/Agents/AI%20ERP%20Agents/ERP%20Compliance%20Advisor%20Agent/ERPComplianceAdvisorAgentSolution_1_0_0_1.zip) contains:

- ERP Compliance Advisor Agent (preconfigured agent with instructions)
- 17 Connector Tools (Fin & Ops Apps → *List items present in table*)
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
2. Click **Browse** → select the [`ERPComplianceAdvisorAgentSolution_1_0_0_1.zip`](https://github.com/ankur198015/Dynamics-365-FastTrack-Implementation-Assets/blob/add-erp-compliance-advisor-agent-folder/Agents/AI%20ERP%20Agents/ERP%20Compliance%20Advisor%20Agent/ERPComplianceAdvisorAgentSolution_1_0_0_1.zip) file from your local machine.
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
| Agent Tools | Get Invalid Users, Get System User Log, etc. | 17 |
| Connection Reference | Fin & Ops Apps (Dynamics 365) | 1 |

**Step 4.2 — Update the F&O Instance URL in Tools**

> **Critical Step:** The tools in the imported solution contain a placeholder or original maker's F&O URL. You must update them to point to your F&O environment.

For each of the 17 tools:

1. In the solution, click on the agent → go to **Tools**.
2. Click on a tool (e.g., *Get Invalid Users*).
3. Under **Inputs**, find the **Instance** field.
4. Change the value from the existing URL to your F&O environment URL: `https://<your-environment>.operations.dynamics.com`
5. Click **Save**.
6. Repeat for all 17 tools.

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

### Phase 6 — Production Deployment

> [!IMPORTANT]
> Complete Phase 5 testing in a **sandbox / UAT environment** before proceeding. Production deployment should only begin after full validation.

**Step 6.1 — D365 F&O Model Deployment Options**

The deployable package ([`SA_ERPComplianceAdvisorAgent.axpp`](https://github.com/ankur198015/Dynamics-365-FastTrack-Implementation-Assets/blob/add-erp-compliance-advisor-agent-folder/Agents/AI%20ERP%20Agents/ERP%20Compliance%20Advisor%20Agent/SA_ERPComplianceAdvisorAgent.axpp)) creates a separate model called **`SA_ERPCompliance`** in D365 F&O. Customers have two options for managing this model in production:

| Option | Description | When to Use |
|---|---|---|
| **Option A — Deploy as-is** | Deploy the `SA_ERPCompliance` model directly to production as a standalone model. It will sit alongside your existing models with no changes required. | Recommended for fastest deployment; suitable when you do not need to modify the custom entities. |
| **Option B — Merge into your own model** | Move all custom objects (10 `AuditAgent*` data entities and the `AuditAgentReader` security role) from the `SA_ERPCompliance` model into your organization's own model/solution. Delete or decommission the `SA_ERPCompliance` model after migration. | Recommended when your ALM process requires a single consolidated model, or when you plan to extend/modify the entities. |

> [!NOTE]
> Both options are functionally equivalent — the custom entities and security role work identically regardless of which model hosts them. Choose based on your organization's ALM and release management standards.

**Step 6.2 — Deploy to Production**

| Step | Action |
|---|---|
| 6.2.1 | Build and deploy the [`SA_ERPComplianceAdvisorAgent.axpp`](https://github.com/ankur198015/Dynamics-365-FastTrack-Implementation-Assets/blob/add-erp-compliance-advisor-agent-folder/Agents/AI%20ERP%20Agents/ERP%20Compliance%20Advisor%20Agent/SA_ERPComplianceAdvisorAgent.axpp) package (Option A) or your consolidated model (Option B) to the **production** D365 F&O environment through your standard LCS / release pipeline. |
| 6.2.2 | Validate entity deployment: navigate to **System Administration → Data Management → Data Entities** and confirm all 17 entities show **Is Public = Yes**. |
| 6.2.3 | Test OData access: open `https://<prod-env>.operations.dynamics.com/data/AuditAgentInvalidUsers` in a browser and verify JSON is returned. |
| 6.2.4 | Assign the `AuditAgentReader` security role to the designated Agent Operator in the production environment. |
| 6.2.5 | In Copilot Studio, update the **Instance** URL in all 17 tools to point to the production F&O URL (`https://<prod-env>.operations.dynamics.com`). |
| 6.2.6 | Re-authenticate the **Fin & Ops Apps (Dynamics 365)** connection reference to use production credentials. |
| 6.2.7 | Run a smoke test — repeat the Phase 5 test prompts against production data to confirm end-to-end connectivity. |

### Phase 7 — Publish & Deploy to Channels

| Step | Action |
|---|---|
| 7.1 | Once testing passes, click **Publish** (top right in Copilot Studio). |
| 7.2 | **Deploy to Microsoft Teams:** Go to **Channels → Microsoft Teams** → click **Turn on Teams** → **Submit for admin approval** (if required) or **Open in Teams**. |
| 7.3 | *(Optional)* **Deploy to SharePoint:** **Channels → SharePoint** → follow the embed steps. |
| 7.4 | *(Optional)* **Deploy to custom website:** **Channels → Custom website** → copy the embed code. |

### Phase 8 — Configure Security & Access Control

| Step | Action |
|---|---|
| 8.1 | Go to **Settings → Security → Authentication**. |
| 8.2 | Select **Authenticate with Microsoft (Entra ID)**. |
| 8.3 | Under **Access**, restrict to specific Security Groups (e.g., *Agent Operators* group — the team members designated to respond to audit questionnaires). |
| 8.4 | Click **Save**. |

## Limitations & Constraints

### Technical Limitations

| Limitation | Details | Mitigation |
|---|---|---|
| Tool limit | Max 128 tools per agent; recommended ≤ 25–30 for best performance | Current design uses 17 tools — within optimal range |
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

**Foundation (Current Release)**

- 17 connector-based tools covering 5 audit domains
- Natural language querying with generative orchestration
- Single-solution packaging
- Teams and web channel deployment
- Knowledge integration (security policies)