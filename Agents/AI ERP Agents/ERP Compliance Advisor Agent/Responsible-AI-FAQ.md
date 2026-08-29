# ERP Compliance Advisor Agent

## Transparency Note and Responsible AI FAQ

This document explains how the ERP Compliance Advisor Agent works, what it can and cannot do, how data is handled, and how to use it responsibly.

| Document detail | Value |
|---|---|
| Document version | 1.1 |
| Effective date | August 25, 2026 |
| Latest reviewed solution | 1.0.1.0 |
| Reviewed package | [`ERPComplianceAdvisorAgentSolution_1_0_1_0.zip`](ERPComplianceAdvisorAgentSolution_1_0_1_0.zip) (unmanaged) |
| Classification | Public |
| Platform | Microsoft Copilot Studio and Dynamics 365 Finance & Operations |

## Contents

1. [Transparency Note](#1-transparency-note)
2. [Responsible AI Principles](#2-responsible-ai-principles)
3. [Capabilities and Intended Use](#3-capabilities-and-intended-use)
4. [Data, Privacy, and Security](#4-data-privacy-and-security)
5. [Accuracy, Limitations, and Human Oversight](#5-accuracy-limitations-and-human-oversight)
6. [Access Control and Permissions](#6-access-control-and-permissions)
7. [Compliance and Audit Readiness](#7-compliance-and-audit-readiness)
8. [Risk and Impact Assessment](#8-risk-and-impact-assessment)
9. [Guidelines for Responsible Use](#9-guidelines-for-responsible-use)

## 1. Transparency Note

### What is the ERP Compliance Advisor Agent?

The ERP Compliance Advisor Agent is an AI-powered Security and IT Audit assistant built on Microsoft Copilot Studio. It enables a designated Agent Operator to use plain-English questions to retrieve and analyze compliance information from Dynamics 365 Finance & Operations (D365 F&O) without writing OData or SQL or navigating F&O forms directly.

The agent is an assistive tool. It does not replace a certified auditor, professional judgment, formal audit procedures, or required human approval.

### Who is it designed for?

- **Internal auditors:** User access reviews, SOX compliance checks, and Segregation of Duties (SoD) analysis.
- **IT security teams:** Privileged-access monitoring, login anomaly detection, and role-change tracking.
- **Compliance officers:** Governance-policy verification and audit-evidence gathering.
- **IT managers:** User-administration and compliance oversight.
- **CISOs and risk officers:** Security-health summaries and risk review.
- **Agent Operators:** Authorized personnel who query the agent and provide validated responses to auditors.

External auditors submit evidence requests to the Agent Operator and receive approved evidence. They should not be given direct D365 F&O access solely to operate this agent.

### How does the agent work?

The agent uses generative orchestration to interpret natural-language audit questions and select relevant read-only connector tools. The Fin & Ops Apps (Dynamics 365) connector retrieves current data from D365 F&O through authenticated OData `GET` requests. The agent then formats the returned records as tables, summaries, or audit-style narratives.

The solution uses a foundation model hosted through Microsoft Copilot Studio. It does not include a custom-trained model based on an organization's audit data.

### What data and tools does the reviewed solution use?

Version 1.0.1.0 contains **19 read-only tools** backed by:

- **10 custom `AuditAgent*` entities** deployed through the provided F&O package.
- **9 standard F&O entities** already available in D365 F&O.

The tools cover user and access review, security governance, security structure, change and audit tracking, and related compliance scenarios. The exact data returned remains subject to the signed-in user's F&O permissions and source configuration.

This export does **not** include Duty-Privilege Mapping, Batch Jobs, Batch History, or Data Management tools. The agent cannot answer questions that require those absent tools unless the solution is extended and reviewed.

### How are OData query options and responses handled?

`$select` is updated across all 19 connector actions to retrieve only the required columns. The current connector actions do not configure `$filter` or `$top`. Agent instructions govern how returned records are analyzed and displayed; they do not add server-side filters or row limits to the OData request.

### How does the updated release reduce payload size?

The updated release configures `$select` on all 19 read-only connector tools. Each tool retrieves only the fields required for its audit scenario instead of returning every column exposed by the D365 F&O entity.

This reduces JSON payload size and unnecessary exposure of data. However, `$select` reduces columns, not the number of records returned.

### Does the updated release apply `$filter` or `$top`?

No. The current tools do not configure `$filter` or `$top`. Therefore, they may retrieve every record made available by the connector for the selected entity.

The agent's response-handling instructions determine how returned records are analyzed and displayed. They do not apply server-side filtering or row limits to the OData request.

### How are returned records displayed?

The agent is instructed to analyze all records returned by the connector.

- For 100 or fewer records, it displays all records.
- For more than 100 records, it displays the 20 most relevant records and summarizes the complete returned result.
- When no records are returned, it states: **"Showing 0 of 0 returned records."**

The agent also reports the displayed and returned record counts and flags relevant risks, anomalies, suspicious patterns, and policy violations.

The response instructions require the agent to analyze all records returned by a tool before responding:

- For 100 or fewer returned records, display every record and state: **"Showing [total] of [total] records."**
- For more than 100 returned records, analyze the full returned dataset, display the 20 most relevant records, and state: **"Showing 20 of [total] records."**
- For more than 100 returned records, also state: **"Total records returned by the connector: [N] | Displaying: 20 most relevant records. All records returned by the connector have been analyzed and summarized."**
- When no records are returned, state: **"Showing 0 of 0 returned records."** and clearly explain that no matching records were returned.
- Summaries should use the full returned dataset for totals, breakdowns, date ranges, patterns, anomalies, risk flags, and policy-violation findings.
- The agent should ask a clarifying question only when the business request is genuinely ambiguous. It should determine entity names, filters, and technical parameters without asking the user.
- The agent should not offer exports, export to SharePoint, or re-query data while formatting a response.

The 20-record rule controls presentation only. It is not equivalent to applying OData `$top=20` and does not reduce the number of records initially retrieved by the connector.

### Does displaying only 20 records reduce the OData payload?

No. The 20-record rule affects only the generated response. It does not prevent the connector from retrieving a larger result set.

The complete returned payload must first reach the agent before it can analyze the records and select the 20 most relevant ones.

### What does "the full dataset has been analyzed" mean?

It means all records successfully returned to the agent by the connector were considered when generating totals, breakdowns, distributions, anomalies, and risk findings.

It does not guarantee that every record in the underlying D365 F&O entity was returned. Connector pagination, response-size limits, timeouts, service-protection limits, or model-context limits may affect completeness.

For greater precision, use:

> "All records returned by the connector have been analyzed and summarized."

Avoid claiming:

> "The entire F&O dataset has been analyzed."

### Is the agent read-only?

Yes. The 19 built-in tools issue only OData `GET` requests. They cannot create, update, delete, approve, or otherwise modify records in D365 F&O or another connected system. Adding a write action requires a new security and Responsible AI review.

### What are the known limitations?

- The quality of findings depends on the completeness and accuracy of source data and configuration in D365 F&O.
- Because the connector actions do not apply `$filter`, broad entity queries may retrieve more records than needed for the audit question.
- `$top` is not fixed in the exported connector actions; large initial result sets can encounter connector, context-window, latency, or timeout limits.
- The 20-record display rule does not reduce initial retrieval volume.
- OData does not provide all reporting-style aggregation capabilities at the source; the agent summarizes records returned to it.
- SoD findings depend on the configured SoD rules and data exposed by the included tools.
- Database-log findings depend on which tables and fields the F&O administrator has configured for logging.
- The agent is connected to one F&O environment per configured set of tool instance URLs.
- The current release is conversational and does not provide proactive alerts or scheduled audits.
- Outputs may contain mistakes in reasoning, categorization, summarization, or risk interpretation and require human validation.

## 2. Responsible AI Principles

The design considers Microsoft's six Responsible AI principles.

### Fairness

The agent queries structured F&O data and should apply the same analysis rules regardless of the person being reviewed. Users must ensure that audit criteria do not introduce inappropriate bias and that findings are interpreted in their proper business and legal context.

### Reliability and Safety

The built-in tools are read-only, and corrective actions remain outside the agent. Platform safety controls and scoped instructions help reduce misuse but do not eliminate prompt-injection, reasoning, or configuration risks. Human validation is mandatory before action.

### Privacy and Security

Access is enforced through Microsoft Entra ID, the connector identity, F&O entity permissions, and the least-privilege `AuditAgentReader` role. Communication uses authenticated encrypted connections. Audit outputs and transcripts may contain sensitive personal and security data and must be protected accordingly.

### Inclusiveness

Plain-English interaction lowers the technical barrier for authorized audit and compliance personnel who do not know OData or the F&O security model. Responses should remain clear and usable for both technical and non-technical reviewers.

### Transparency

The solution identifies itself as AI-assisted, documents its tool scope and limitations, and provides record counts and display disclosures. Users should disclose AI assistance when findings are used in formal audit work.

### Accountability

Qualified humans remain accountable for validating evidence, interpreting findings, approving conclusions, and taking corrective action. Administrators remain accountable for access, retention, configuration, and monitoring controls.

## 3. Capabilities and Intended Use

### What can the agent do?

The agent can retrieve and analyze data exposed by the 19 configured tools. Typical questions include:

- "Show me all users with the System Administrator role who have not logged in for 90 days."
- "Which disabled or invalid users still have active role assignments?"
- "Who has privileged access without a corresponding recording?"
- "Which temporary role assignments are past their expiration date?"
- "Which users appear over-licensed compared with role requirements?"
- "Show database-log changes for a specified date range."
- "Summarize configured SoD conflicts returned by the included tools."

The agent should flag relevant anomalies, suspicious patterns, risks, excessive licenses, expired temporary roles, privileged access without recordings, and policy violations found in all records returned by the connector.

### Can the agent verify which tables and fields are configured for database logging?

No. The current **Get Database Log** tool reads recorded changes from the standard `DatabaseLogs` entity, but the reviewed release has no tool that exposes **Database log setup**. The agent can analyze available log evidence, but it cannot confirm which tables, fields, and change operations are configured for logging or identify configuration gaps where logging was never enabled.

For control-design assurance, review **System administration > Setup > Database log > Database log setup** directly. The setup form exposes the configured table, optional field, type of change, and signature-control status. Database-log findings remain dependent on the completeness and correctness of that F&O configuration.

### Can database-log setup visibility be added to the agent?

Yes. An F&O developer can explore the data sources used by the **Database log setup** form and create a read-only custom data entity that exposes the required configuration fields, such as table, optional field, change operation, and signature-control status. The exact backing setup tables and supported fields must be confirmed for the target F&O version before implementation.

After the custom entity is developed and deployed:

1. Make the entity public through OData.
2. Grant read access through `AuditAgentReader` or an equivalent reviewed least-privilege role.
3. Add a new **Fin & Ops Apps (Dynamics 365)** tool in the agent's **Tools** section.
4. Configure `$select` so the tool retrieves only the required fields.
5. Test authorization, payload size, source completeness, and audit responses before production use.

This extension would close the control-design-versus-control-evidence gap by pairing database-log configuration with the existing recorded-change evidence. Adding it changes the reviewed 19-tool scope and requires solution ALM, security, privacy, and Responsible AI review.

### What is the agent not designed to do?

- It cannot write, update, delete, or approve records.
- It cannot enforce policy or automatically revoke access.
- It cannot replace a certified auditor or formal audit engagement.
- It cannot query data outside the 19 configured tools unless the solution is extended.
- It cannot query general business transactions unless an authorized, reviewed tool exposes them.
- It cannot provide Duty-Privilege Mapping, Batch Jobs, Batch History, or Data Management results in this export.
- It cannot guarantee database-log completeness when source logging is not fully configured.
- It does not offer or perform exports as part of its response instructions.

### Is the agent suitable for external audit evidence?

It can accelerate evidence gathering and produce structured output for review. An authorized person must validate the data against D365 F&O, document the query date and scope, resolve discrepancies, and approve the evidence before external submission. The agent is not the system of record.

### Can the agent perform multi-environment audits?

A configured agent points its tools to one F&O environment. Use separately configured and reviewed agent instances for multiple environments. Do not assume cross-environment correlation unless it is explicitly designed, secured, and validated.

### Can the agent run scheduled audits?

Not in the reviewed release. Scheduled checks, notifications, or Power Automate flows are separate extensions that require design, security, privacy, and Responsible AI review.

## 4. Data, Privacy, and Security

### Does the solution persist retrieved data?

The solution does not add a separate application database or custom persistence layer for retrieved F&O records. However, retrieved data can appear in user prompts, agent responses, operational telemetry, and Copilot Studio conversation transcripts according to tenant configuration and retention settings. Do not state that data is categorically "not stored in Copilot Studio."

Organizations must review current Microsoft product terms, tenant settings, geographic and residency requirements, retention policies, and access controls for their deployment. The agent's knowledge sources are separate from conversation transcripts; retrieved audit records are not intentionally added to the agent's knowledge base by this solution.

### Does the model learn from organizational data?

This solution does not implement model training or fine-tuning using retrieved F&O records. Data handling by the Microsoft services used by the tenant remains governed by the applicable product terms, privacy commitments, and tenant configuration. Administrators should verify those terms rather than relying only on this FAQ.

### What may be logged?

Depending on licensed features and tenant settings:

- Copilot Studio may retain conversation inputs, tool interactions, and outputs for analytics, monitoring, or review.
- Power Platform and Microsoft Purview audit capabilities may record connector and administrative activity.
- OData reads are not the same as F&O database-log write events and should not be described as a complete F&O audit trail of agent activity.

Restrict transcript and analytics access, define retention periods, and treat logged content as sensitive audit data.

### Does the agent handle personal data?

Yes. Results may contain names, user IDs, email addresses, role assignments, login history, activity timestamps, and other personal or security-sensitive data. Organizations should:

- Restrict access to authorized Agent Operators and administrators.
- Apply least privilege and periodic access reviews.
- Review applicable privacy laws and organizational policies.
- Configure appropriate transcript, audit-log, and operational-log retention.
- Consult privacy, legal, compliance, and data-protection stakeholders before production deployment.
- Share outputs only through approved secure channels.

### Are conversations confidential?

Do not assume that only the end user can access conversation content. Authorized Copilot Studio or tenant administrators may be able to access transcripts and analytics according to roles and settings. Establish a policy for transcript access, use, retention, deletion, and disclosure.

### How is the F&O connection secured?

The Fin & Ops Apps (Dynamics 365) connector uses Microsoft Entra ID and OAuth 2.0. Requests run under the configured signed-in identity and are limited by that identity's D365 F&O permissions. Use the dedicated least-privilege `AuditAgentReader` role for routine operation rather than System Administrator access.

### Can the agent be accessed outside the corporate network?

Availability depends on the enabled Copilot Studio channels and tenant policies. Require Microsoft Entra ID authentication, restrict access to approved security groups, and apply appropriate Conditional Access and device controls.

## 5. Accuracy, Limitations, and Human Oversight

### Can the ERP Compliance Advisor Agent analyze millions of records or complete ERP tables?

No. The agent is designed for interactive compliance questions over relevant, reasonably sized datasets. It is not a replacement for a data warehouse, SQL query layer, reporting engine, Power BI, or Microsoft Fabric.

For large datasets, filtering, joins, calculations, and aggregation should be performed upstream before data reaches the agent.

### How accurate are responses?

Retrieval reflects the source data and permissions available at query time, but errors can still occur:

- The agent may choose the wrong tool or misunderstand the request.
- Instruction-driven filters may be too broad, too narrow, or syntactically incorrect.
- A connector or platform limit may prevent the entire intended dataset from being returned.
- The model may make incorrect inferences when combining tools.
- Summaries may overemphasize or omit patterns.
- Risk classifications may not match organizational policy.

Treat every output as a preliminary finding subject to human validation.

### How should uncertain results be handled?

Check displayed records, total counts, date ranges, applied criteria, and source configuration. Independently verify high-impact findings in native F&O forms or through an approved reporting process. Do not ask the agent to re-query merely to format an answer, and never rely solely on agent output for access revocation, disciplinary action, regulatory filing, or audit sign-off.

### Can the agent make automated decisions?

No. It only retrieves and analyzes information. A properly authorized human must decide and perform any access change, incident escalation, control remediation, or audit conclusion.

### What happens when the agent cannot answer?

It should clearly say that the required data was not returned, the needed tool is unavailable, authorization failed, or the request is outside scope. It should not fabricate an answer. A clarifying question is appropriate only when the business request itself is genuinely ambiguous, such as a name matching multiple users.

### Does the agent support counts and aggregations?

The agent can calculate summaries from the records returned to it. Those calculations are constrained by connector response limits, platform context limits, timeouts, and source completeness. For recurring or very large reporting workloads, use a reviewed reporting architecture designed for aggregation and reconciliation.

### Can the agent guarantee complete counts for large entities?

Not solely through its instructions. Counts are based on the records returned by the connector. Where completeness is required for formal audit evidence, validate totals against D365 F&O or an approved reporting platform.

### Is the agent a bulk-export tool?

No. The agent does not offer export options, export to SharePoint, or automatically re-query data. It is intended for scoped compliance analysis and audit interpretation, not bulk extraction.

### Why can token or response-size limits still occur?

Although `$select` reduces the number of columns, an entity may still return a large number of rows. The model context also contains agent instructions, tool definitions, connector schemas, conversation history, orchestration information, and response content.

A result containing thousands of narrowly projected records can therefore still exceed connector, response-size, or model-context limits.

### What should I do if a large-data or timeout error occurs?

Errors such as `TooMuchDataToHandle`, `ExecutionTimeout`, or another context-limit error indicate that the request, connector output, conversation history, or execution path exceeded a platform limit.

1. Start a new chat to remove accumulated conversation history.
2. Ask a narrower question using a specific date range, user, table, role, or company.
3. Retry once in case the timeout was transient.
4. If the error persists, provide the error code and timestamp to the agent administrator.

A narrower prompt does **not guarantee** a smaller OData payload in this release because `$filter` and `$top` are not configured in the connector actions. Persistent errors require server-side filtering, pagination, row limits, or another bounded retrieval layer.

### Will switching models resolve large-result problems?

A model with a larger context window may help, but it does not remove the underlying retrieval limitation. The recommended solution is server-side filtering, aggregation, pagination, and enforced row limits before records reach the model.

### What is recommended when an entity contains many records?

Create a bounded retrieval layer using one or more of the following:

- A purpose-built filtered or aggregated D365 F&O data entity.
- A Power Automate flow that applies `$filter`, `$top`, and controlled pagination.
- A custom API that validates and applies supported query parameters.
- SQL, Microsoft Fabric, Data Lake, or Power BI for large-scale analysis.

The agent should receive only the records needed to answer the specific audit question.

### What is the human's role?

Humans remain responsible for:

- Defining appropriate audit questions and policy criteria.
- Confirming that the returned scope is complete for the intended conclusion.
- Validating findings against source records.
- Interpreting business, legal, and regulatory context.
- Resolving false positives and false negatives.
- Deciding and executing corrective actions.
- Approving audit reports and compliance attestations.

## 6. Access Control and Permissions

### Who should operate the agent?

Use a designated Agent Operator with a legitimate audit, compliance, risk, or IT security responsibility. Restrict access through Microsoft Entra ID security groups. External auditors should request and receive validated evidence through the operator rather than receive direct F&O access solely for this agent.

### What F&O permissions are required?

The connecting identity needs read access to the 10 custom and 9 standard entities used by the 19 tools. Assign the custom `AuditAgentReader` role or an equivalent reviewed least-privilege role. System Administrator access works technically but is not recommended for routine production use.

### What happens with partial entity permissions?

The connector enforces F&O authorization. A tool may fail or return incomplete cross-tool results when the signed-in identity lacks access to a required entity. The response should identify authorization failures and must not imply that partial results are complete.

### How should privileged administration be managed?

Copilot Studio administrators can change tools, instructions, authentication, channels, and transcript access. Limit these privileges to named personnel, log and review changes, separate incompatible duties, and include administrators in periodic access reviews.

## 7. Compliance and Audit Readiness

### Does using the agent satisfy SOX or another framework?

No. The agent can support control activities and evidence gathering, but compliance depends on the organization's control design, source configuration, procedures, review evidence, human sign-off, and formal audit trail.

### Should AI use be disclosed to auditors?

Yes. Disclose AI-assisted evidence gathering when required by organizational policy or applicable professional standards. Provide this transparency note, document the scope and date of queries, and retain evidence of independent validation.

### Does the agent create its own formal audit trail?

It does not write a formal activity record to the F&O database log. Copilot Studio, Power Platform, or Microsoft Purview may retain relevant activity according to tenant configuration. Organizations must determine whether those records satisfy their audit requirements and establish an approved evidence-retention procedure.

### Which frameworks informed the design?

Design considerations include:

- Microsoft Responsible AI principles.
- NIST AI Risk Management Framework concepts.
- ISO/IEC 42001 AI management-system concepts.
- Privacy and data-protection-by-design principles.
- SOX IT general control practices for access, change management, and audit evidence.

This alignment statement is not a certification, legal opinion, or claim that deploying the agent creates compliance with any framework.

### Can findings be cited in audit reports?

Yes, with appropriate controls. State that AI-assisted tooling was used, document the query scope and date, disclose material limitations, independently validate the evidence, and obtain qualified human approval.

## 8. Risk and Impact Assessment

| Risk | Likelihood | Impact | Primary mitigations |
|---|---|---|---|
| Incorrect tool or filter returns incomplete or wrong data | Medium | High | Validate criteria, counts, and source records; require human review |
| Initial retrieval exceeds connector, context, or timeout limits | Medium | Medium | Monitor large-result behavior; use time-bounded requests or reviewed server-side controls when required |
| A 20-row display is mistaken for a 20-row retrieval | Medium | Medium | Show total-returned counts and document that the display rule is not `$top=20` |
| Unauthorized access to sensitive audit data | Low | High | Entra ID authentication, security groups, Conditional Access, and `AuditAgentReader` least privilege |
| PII or security data appears in transcripts | Medium | High | Restrict transcript access and configure retention and deletion policies |
| AI findings are used without validation | Medium | High | Mandatory human review, evidence reconciliation, and sign-off |
| Prompt injection or scope manipulation | Medium | Medium | Scoped tools and instructions, platform controls, monitoring, and no write actions |
| Database-log gaps create incomplete evidence | Medium | Medium | Document logging scope and validate F&O database-log configuration |
| SoD rules are stale or misconfigured | Low | High | Maintain and periodically review the SoD rule library |
| Missing tools are assumed to be available | Medium | Medium | Publish the exact 19-tool scope and clearly list excluded tools |
| Connector or agent configuration changes without review | Medium | High | Apply solution ALM, change control, regression testing, and renewed security review |

## 9. Guidelines for Responsible Use

### For all users

- Validate findings against D365 F&O before acting.
- Confirm counts, date ranges, source scope, and applicable policy.
- Do not share outputs containing personal, access, security, or vulnerability data through unapproved channels.
- Disclose AI assistance when findings are used in formal work.
- Report incorrect, incomplete, or unsafe behavior to the solution owner.
- Do not enter credentials, secrets, tenant identifiers, or unnecessary sensitive data into prompts.

### For administrators

- Restrict agent access to approved security groups.
- Use the `AuditAgentReader` role or an equivalent least-privilege role.
- Review all 19 tool instance URLs, connections, `$select` values, descriptions, and permissions after import.
- Confirm that `$filter` and `$top` are not configured in this export, and test large-result scenarios accordingly.
- Configure and periodically review transcript, analytics, and audit-log access and retention.
- Use a designated least-privilege connection identity, not a broadly privileged personal account.
- Monitor tool, instruction, channel, and authentication changes through formal ALM and change control.
- Repeat security, privacy, and Responsible AI review when adding tools, knowledge, channels, automation, or write actions.

### For audit leaders

- Define when secondary validation is mandatory.
- Include agent use and limitations in audit workpapers.
- Train users on tool scope, excluded tools, source-data dependencies, and the difference between retrieval and display limits.
- Establish evidence-retention and transcript-handling procedures.
- Review this document with security, privacy, legal, compliance, and audit stakeholders before production use.

> [!WARNING]
> **Not a substitute for professional judgment.** All compliance determinations, audit conclusions, access decisions, and corrective actions remain the responsibility of qualified and authorized people.

> [!IMPORTANT]
> Review this transparency note at least annually and whenever the agent's tools, instructions, model, data scope, channels, authentication, retention, or regulatory context changes.
