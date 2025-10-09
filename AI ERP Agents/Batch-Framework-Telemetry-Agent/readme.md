# Batch Framework Telemetry Agent

> AI-powered monitoring & diagnostics for D365 Finance & Supply Chain batch jobs, built with **Copilot Studio** and **Application Insights**.

[![Made with Copilot Studio](https://img.shields.io/badge/Copilot%20Studio-Enabled-blue)](#) [![D365 FSCM](https://img.shields.io/badge/D365-F%26SCM-success)](#)

## 📚 Table of Contents
- [Overview](#-overview)
- [Key Capabilities](#-key-capabilities)
- [Screenshots](#-screenshots)
- [Architecture](#-architecture)
- [Prerequisites](#-prerequisites)
- [Install & Configure](#-install--configure)
  - [1) Import Solution](#1-import-solution)
  - [2) Verify Agent & Connections](#2-verify-agent--connections)
  - [3) Knowledge Source (Optional)](#3-knowledge-source-optional)
- [Usage](#-usage)
- [Automation Ideas](#-automation-ideas)
- [Troubleshooting](#-troubleshooting)
- [FAQ](#-faq)
- [Resources](#-resources)
- [Contributors](#-contributors)

---

## 🧠 Overview
The **Batch Telemetry Agent** optimizes batch job execution in Dynamics 365 by combining **Application Insights telemetry** with Copilot Studio. It answers natural-language questions, surfaces anomalies, and can guide or automate remediations.

## 🔧 Key Capabilities
- **Telemetry collection** across job start/end, thread usage, throttling, queue sizes, failures, and Infolog errors.  
- **Prompt-based analysis** (GPT-4o / GPT-5 ready) to query and interpret telemetry using KQL.  
- **Anomaly detection** for throttling, long runtimes, and scheduling inefficiencies.  
- **Self-healing hooks** to trigger safe recovery steps (e.g., rerun failed jobs).  
- **Dashboards & reports** for priority distribution, throttling trends, exceptions, and history.

---

## 🖼️ Screenshots
> Add these right up front so users immediately see what they’re getting.

<div align="center">
  <img src="./Images/Teams-Chat-Home.png" alt="Teams - Batch Telemetry Agent app home" width="900"><br/>
  <sub>Teams app home with quick prompts</sub>
</div>

<div align="center">
  <img src="./Images/m365-Home.png" alt="Copilot Studio Chat entry point" width="900"><br/>
  <sub>Copilot Studio chat with quick prompts</sub>
</div>

<div align="center">
  <img src="./Images/Studio-Overview-Topics.png" alt="Copilot Studio - Overview & Topics" width="900"><br/>
  <sub>Copilot Studio Overview & Topics</sub>
</div>

<div align="center">
  <img src="./Images/Studio-Overview-Instructions-Tools.png" alt="Agent instructions & tools" width="900"><br/>
  <sub>Agent instructions and connected tools</sub>
</div>

<div align="center">
  <img src="./Images/Studio-Overview-Details.png" alt="Agent details" width="900"><br/>
  <sub>Agent details and orchestration model</sub>
</div>

---

## 🏗️ Architecture
<p align="center">
  <img src="./Images/Architecture.png" alt="Batch Framework Telemetry Agent Architecture" width="1200"/>
</p>

**Flow**
1. D365 F&O emits batch telemetry → **Application Insights**.  
2. The agent runs KQL via a tool connection to App Insights.  
3. Users interact via **Teams / M365 Chat / Copilot Studio**.  
4. Optional remediation is invoked and validated via telemetry feedback.

---

## ✅ Prerequisites
- **D365 F&SCM** 10.0.45 (7.0.7690.21 / PU69) or later  
- **Application Insights** connected for batch telemetry  
- Access to **Copilot Studio** and **Power Automate**  
- **App Insights API Access** (Application ID + API Key) for query tool

---

## 🚀 Install & Configure

### 1) Import Solution
1. Clone or download this repository’s release **solution** file.  
2. Go to **make.powerapps.com** → **Solutions** → **Import**.  
   <div align="center"><img src="./Images/ImportSolution.png" width="700" alt="Import solution"></div>
3. The wizard prompts to **create/sign in** to required connections.  
4. Click **Import** and wait for completion.  
   <div align="center"><img src="./Images/SolutionImporting.png" width="700" alt="Solution importing"></div>
5. On success, you’ll see confirmation:  
   <div align="center"><img src="./Images/SolutionImported.png" width="700" alt="Solution imported"></div>
   <div align="center"><img src="./Images/SolutionImportedSuccessfully.png" width="700" alt="Solution imported successfully"></div>
6. Open the solution and verify components:  
   <div align="center"><img src="./Images/SolutionComponents.png" width="300" alt="Solution components"></div>

### 2) Verify Agent & Connections
1. Open **copilotstudio.preview.microsoft.com** and select the correct environment.  
   You should see **“Batch Telemetry Agent.”**  
   <div align="center"><img src="./Images/BatchAgent.png" width="700" alt="Agent visible in Copilot Studio"></div>
2. In the test pane, choose **Manage connections**.  
   <div align="center"><img src="./Images/ManageConnections.png" width="700" alt="Manage connections"></div>
3. Ensure all are **Connected**; create missing ones if needed.  
   <div align="center"><img src="./Images/ConnectConnection.png" width="700" alt="Create connection"></div>
4. For **Application Insights**, provide **Application (App) ID** and **API Key**.  
   <div align="center"><img src="./Images/APIKey.png" width="700" alt="Application Insights API key"></div>

> **Note:** If your tenant/org enforces SSO/2FA, ensure your connections are authorized for the environment hosting the agent.

### 3) Knowledge Source (Optional)
- Add the **Microsoft Learn Docs MCP Server** (or other approved knowledge) to enrich answers to “how/why” questions about Batch Framework.

---

## 🧪 Usage

### Suggested Prompts (cards shown in UI)
- “Show me last 1 hour **Priority distribution**.”  
- “Were any of my batch jobs **throttled** recently?”  
- “How many **threads** are currently available for batch jobs?”  
- “Provide details about recent **batch job failures**.”  
- “Show **CPU, Memory, and SQL DTU** metrics during batch throttling events.”  
- “**Batch Execution History** for Batch Job Id `<ID>`.”

> Results are backed by KQL queries against your App Insights instance.

---

## ⚙️ Automation Ideas
- Auto-rerun failed jobs when the error code matches an approved policy.  
- Post anomaly digests to a **Teams** channel daily.  
- Trigger escalation if throttling breaches an agreed threshold.

---

## 🧩 Troubleshooting
- **Agent not visible in Copilot Studio:** Confirm environment, security roles, and solution import status.  
- **Query errors:** Verify App Insights **Application ID / API Key** and workspace mapping.  
- **No telemetry returned:** Check D365 → App Insights connection and time range.  
- **Connection shows “Not connected”:** Re-authenticate; some orgs require SSO **authorization per environment**.

---

## ❓ FAQ
**Q: Does this change batch schedules?**  
A: No—by default it is read-only. Optional flows can be enabled for safe actions.

**Q: Can we swap models?**  
A: Yes. The agent uses the environment’s default model (e.g., GPT-4o). You can change this in Copilot Studio.

**Q: Multi-environment support?**  
A: Yes. Create separate connections per environment and parameterize the workspace if needed.

---

## 📎 Resources
- 📦 [Batch Telemetry Dashboard Release](https://github.com/microsoft/Dynamics-365-FastTrack-FSCM-Telemetry-Samples/releases/tag/Batch-1.0.0.0)  
- 📘 [Monitoring telemetry overview](https://learn.microsoft.com/en-us/dynamics365/fin-ops-core/dev-itpro/monitoring-telemetry/)  
- 🚀 [Monitoring: getting started](https://learn.microsoft.com/en-us/dynamics365/fin-ops-core/dev-itpro/monitoring-telemetry/monitoring-getting-started)

---

## 👥 Contributors
- Prashant Verma (AI Business Solutions)  
- Hemanth Kumar