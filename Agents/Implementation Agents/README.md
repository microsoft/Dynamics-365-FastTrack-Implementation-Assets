# Implementation Agents

Implementation agents accelerateDynamics 365 project delivery by automating release planning, performance diagnostics, and implementation lifecycle tasks. These prebuilt templates are designed for implementation teams, FastTrack solution architects, support engineers, and partner consultants who need to reduce manual effort, improve quality, and scale their delivery capabilities with AI.

Unlike product-specific agents, implementation agents are cross-functional and can be used across multiple Dynamics 365 modules and deployment scenarios.

> 📖 **Full documentation on Microsoft Learn:** [Implementation agent templates](https://learn.microsoft.com/en-us/dynamics365/guidance/agent-templates/implementation-agents-overview)

> 📝 **Interested in these agent templates?** [Fill in this form](https://forms.cloud.microsoft/r/ZCSSSMhg40) to request access and help us track adoption.

## Available Agents

| Agent | Category | Key Benefit | Folder |
|-------|----------|-------------|--------|
| [Release Planner Helper Agent](Release%20Planner/) | Planning | Automated discovery, analysis, and work-item creation for Dynamics 365 release waves | `Release Planner/` |
| [Trace Parser Agent](Trace%20Parser/) | Diagnostics | Reduces performance trace analysis from hours to minutes through conversational AI | `Trace Parser/` |

## Release Planner Helper Agent

The Release Planner Helper Agent integrates with Microsoft's official release plans to search, retrieve, and analyze upcoming Dynamics 365 features across modules such as Supply Chain Management, Finance, and Commerce. It automates feature discovery, provides timeline and business value analysis, and creates work items in Azure DevOps or Jira.

**Components:**
- **MCP Server** (TypeScript/Node.js) — Queries the Microsoft Release Planner API
- **Copilot Studio Agent** — Natural language interface for release planning

📖 [Learn more on Microsoft Learn](https://learn.microsoft.com/en-us/dynamics365/guidance/agent-templates/release-planner-agent)

## Trace Parser Agent

The Trace Parser Agent uses conversational AI to reduce D365 F&O performance troubleshooting from 6–8 hours of manual trace analysis to approximately 5–10 minutes. It connects to trace data via a Data API Builder MCP server and combines data access with real-time remediation guidance from Microsoft Learn.

**Components:**
- **TraceParserMCP** — Data API Builder-based MCP server exposing trace data via SQL views and stored procedures
- **TraceParserWeb** — Blazor Server web app with Azure Function for ETL trace upload and import
- **Copilot Studio Agent** — Natural language interface for trace analysis

📖 [Learn more on Microsoft Learn](https://learn.microsoft.com/en-us/dynamics365/guidance/agent-templates/trace-parser-agent)

## Licensing Requirements

- Dynamics 365 Finance, Supply Chain Management, or Commerce license
- Microsoft Copilot Studio
- Copilot Studio Credits Capacity

## Disclaimer

> This repository contains **sample/reference code only**. It is provided as-is for educational and demonstration purposes. Microsoft does not operate these agents or any services built with them. Customers are responsible for deploying, operating, and managing this code in their own environments. This code is not production-ready and comes with no guarantees of availability, reliability, or support.
