# Dataverse Admin Agent: Features and Technology Guide

**Solution version 1.0.0.0**

## At a glance

The Dataverse Admin Agent is a Microsoft Copilot Studio sample that helps
authorized Dataverse and Dynamics 365 administrators explore security
information and carry out two controlled access-management tasks using
natural language.

Instead of navigating several administration screens, an administrator can ask
about a user's roles, team memberships, or assigned licenses in a conversation.
Administrative facts are retrieved through configured Dataverse and Microsoft
Graph tools rather than supplied from model memory.

The agent also supports assigning an existing role to an existing user and
adding an existing user to an existing team. Both actions require a preview and
explicit confirmation before execution.

> This is sample/reference software, not a replacement for your organization's
> access approvals, change management, or periodic access reviews. Validate it
> in your own environment before operational use.

## Who should use it?

| Audience | Typical use |
|---|---|
| Dataverse and Dynamics 365 administrators | Investigate user security configuration and perform authorized role or team assignments |
| Power Platform administrators | Review environment-level security information and support administrative investigations |
| Authorized support and access-management teams | Answer access questions and carry out approved changes within their assigned privileges |
| Solution architects and platform makers | Evaluate the sample and understand its integration and governance requirements |

The agent is intended for authorized administrative operators, not general
business users. Access to the agent does not itself grant access to Dataverse
records or permission to change security assignments.

## Features

### 1. User security overview

Retrieve an existing user's status, business unit, directly assigned security
roles, and team memberships. Where available, the agent can also provide
team-based or inherited access context and field security profile information.

This helps administrators understand the recorded security configuration behind
an access question. It is not a guarantee that a user can access every
particular record or perform every operation.

### 2. Security metadata lookup

Look up existing security roles, teams, and business units. When a name matches
more than one record, provide an exact name, business unit, or another approved
identifier to clarify the intended target.

### 3. Housekeeping and recorded-access insights

Identify disabled users and request reports about recorded Dataverse access.
Access-history scenarios depend on auditing being enabled, suitable retention,
and the operator's permission to read audit data.

**No recorded access does not prove inactivity.** Missing audit evidence must
be treated as Unknown, not as a basis for automatic removal of
access or licenses.

### 4. Read-only licensing visibility

Retrieve assigned license SKUs, service plans, and provisioning status through
Microsoft Graph. Licensing information complements Dataverse security lookups;
it does not replace an entitlement assessment or grant access by itself.

The agent does not assign, remove, or modify licenses.

### 5. Controlled role and team assignments

The agent supports exactly two types of write operation:

- Assign one existing Dataverse security role to one existing user.
- Add one existing user to one existing Dataverse team.

Each request is previewed before it can be applied. The backend validates the
recorded request again before executing the change.

## Example requests

These examples use fictional identities. Replace them only with identities
you are authorized to administer.

| Goal | Example prompt |
|---|---|
| Review a user's security configuration | "Show the security profile for alex.wilber@contoso.com." |
| Check team memberships | "Which teams is Alex Wilber a member of?" |
| Inspect a role | "Show details for the Sales Manager security role." |
| Find disabled users | "Show disabled users in this Dataverse environment." |
| Review recorded access | "Show users with no recorded Dataverse access in the last 90 days." |
| Check licensing | "Show assigned licenses and service plan status for alex.wilber@contoso.com." |
| Preview a role assignment | "Preview assigning the Sales Manager role to alex.wilber@contoso.com." |
| Preview team membership | "Preview adding alex.wilber@contoso.com to the Contoso Support team." |

Results depend on the configured environment, available tools, and the
signed-in operator's permissions.

## What happens when you request a change?

1. **Request:** Identify one existing user and one existing role or team.
2. **Clarify:** Resolve any ambiguous names before proceeding.
3. **Preview:** Review the user, business unit, target role or team, and
   expected effect. Check that the change has the required organizational
   approval.
4. **Confirm or cancel:** Reply with the exact word `CONFIRM` only if the
   preview is correct. Any other response cancels the pending operation.
5. **Check the result:** Review the final status. If verification is
   inconclusive, check Dataverse directly before attempting the change again.

Confirmation is single-use, bound to the operator and previewed target, and
expires after five minutes. These checks are enforced in Power Automate, not
by the model. Confirmation is an execution safeguard, not a substitute for an
approval workflow.

## Technology overview

The sample combines conversational assistance with connected administrative
tools and backend validation.

| Component | Role in the solution |
|---|---|
| Microsoft Copilot Studio | Hosts the conversational agent, skills, and tools used to interpret requests and present results |
| Microsoft Dataverse | Supplies user and security metadata and applies authorized role and team associations |
| Power Automate | Provides five cloud flows supporting the controlled-write process |
| Admin Agent Write Log table | Holds change-control records used by the controlled-write process |
| Microsoft Graph | Supplies read-only user licensing details |
| Get Licensing Info custom connector | Connects the agent and backend components to Microsoft Graph using delegated authentication |
| Microsoft Entra ID | Provides the app registration and delegated authorization used by the licensing connector |
| Power Platform solutions | Package the agent, connector, flows, table, environment variables, and connection references |

### How information and actions flow

```text
Authorized administrator
        |
        v
Copilot Studio agent
        |
        +-- Security lookups --> Dataverse
        |
        +-- License lookups --> Custom connector --> Microsoft Graph
        |
        +-- Supported change --> Preview --> Exact CONFIRM
                                      |
                                      v
                          Backend validation and flows
                                      |
                                      v
                          Dataverse change and write log
```

All Dataverse reads and writes run in the signed-in user's own Dataverse
security context. Microsoft Graph licensing access uses delegated, read-only
permissions. The agent does not elevate the operator's privileges.

An organization may publish the agent through approved Copilot Studio
channels, including Teams or Microsoft 365, subject to publication, sharing,
identity, and tenant app policies. Availability is not automatic across
channels. Microsoft Entra ID sign-in is required in every channel. Customers
control publishing and sharing and should limit the agent to an administrator
security group or channel.

## Prerequisites

### For administrators using the agent

- An organizational account authorized to use the published agent.
- Access to the intended Dataverse environment and the privileges needed for
  each requested lookup or change.
- Any required end-user connection sign-in and consent.
- Familiarity with Dataverse roles, teams, business units, and the
  organization's access-approval process.
- Audit-read privileges for recorded-access scenarios.

### For the team enabling the agent

- A Power Platform environment with Dataverse and Microsoft Copilot Studio,
  with appropriate licensing and capacity confirmed for the intended usage.
- An environment administrator able to import solutions and configure
  connections, with Entra administrator assistance where required.
- The standard `EnvironmentVariables` solution at version `1.0.2406.4` or
  later, as required by the managed package.
- A customer-owned, single-tenant Entra app registration for the licensing
  connector, with delegated `User.Read`, `LicenseAssignment.Read.All`, and
  `offline_access` permissions and consent according to tenant policy.
- Dataverse and custom-connector connections configured for the intended
  operators, and a data policy allowing these connectors to be used together.
- Dataverse auditing and suitable retention for audit-dependent features.
- An approved audience and channel, with retention and data-handling policies
  reviewed before use.

## Installation overview

An environment administrator imports the supplied Power Platform solution,
configures the target environment values and connections, and completes the
licensing connector's Entra authentication setup. The managed package is the
deployment artifact; the unmanaged package supports development and inspection.
The team then validates lookups, confirmation behavior, permissions, and flows
in nonproduction before publishing to an approved channel and sharing with
authorized operators. Detailed deployment procedures are intentionally outside
the scope of this guide.

## Scope and limitations

The agent does **not**:

- Create users, reset passwords, or change Microsoft Entra settings.
- Create or change security role or team definitions.
- Remove roles or team memberships.
- Perform bulk access changes.
- Assign, remove, or modify licenses.
- Query unrelated business records.
- Replace a full effective-access investigation, compliance assessment, or
  access-governance process.

Different administrators may receive different results because their
permissions differ. A missing record can mean that no permitted match was
found; it does not necessarily mean the record does not exist.

## Responsible use and support

- Do not enter passwords, client secrets, access tokens, or unnecessary
  personal information into the conversation.
- Treat user, security, licensing, and audit information as sensitive.
  Conversation transcripts, flow history, and write-log records also require
  appropriate access and retention controls.
- Verify that you are working in the intended environment before authorizing
  any change.
- If a tool reports access denied, request the appropriate administrative
  review rather than trying to bypass the restriction.
- If activity history is reported as Unknown, ask the platform team to check auditing,
  retention, and audit-read privileges.
- If a write outcome is unknown, verify the actual Dataverse association
  before retrying.
- Report connection failures, unexpected results, or suspected data exposure
  through your organization's platform support and security channels.

The organization adopting this sample is responsible for validating,
deploying, operating, and governing it in its own environment.
