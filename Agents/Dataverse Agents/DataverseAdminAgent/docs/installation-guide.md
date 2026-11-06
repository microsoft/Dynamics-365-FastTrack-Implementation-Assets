# Installation guide

This guide installs the managed Dataverse Admin Agent solution into an existing
Power Platform environment.

## 1. Prerequisites

Before installation, confirm all of the following:

- A Power Platform environment with Dataverse and Microsoft Copilot Studio.
- The target environment's standard `EnvironmentVariables` solution at version
  `1.0.2406.4` or later. The managed package declares this dependency for its
  controlled-write flows; update the environment before import if it is absent
  or older.
- An environment administrator or System Administrator account that can import
  solutions and configure connections.
- Permission to create a single-tenant Microsoft Entra app registration and
  grant delegated Microsoft Graph permissions, or help from an Entra
  administrator.
- Permission to create and use Dataverse and custom-connector connections.
- A Power Platform data policy that allows Microsoft Dataverse and the included
  custom Microsoft Graph connector to be used together.
- Dataverse auditing enabled and retained for any audit-history or
  recorded-access scenarios you intend to use.
- An approved Copilot Studio channel and an authorized administrator audience.

For command-line installation, install the
[Microsoft Power Platform CLI](https://learn.microsoft.com/power-platform/developer/cli/introduction).
The documented commands were validated with CLI version `1.48.2`.

## 2. Prepare configuration

Complete the [configuration guide](./configuration-guide.md) before importing.
You need:

- the target environment URL, such as
  `https://<environment-name>.crm.dynamics.com`;
- the application (client) ID of the customer-owned Entra app registration;
- its generated custom-connector redirect URI registered on the Entra app;
- connections owned by, or individually established for, the intended
  operators.

Never put a client secret, tenant ID, personal account, or real connection ID in
source control.

## 3. Import in the maker portal

1. Sign in to [Power Apps](https://make.powerapps.com).
2. Select the target environment and verify its name and URL.
3. Go to **Solutions** and select **Import solution**.
4. Upload
   `solutions/DataverseAdminAgent_1_0_0_0_managed.zip`.
5. Set **Env URL** to the target environment's HTTPS URL.
6. Set **Licensing Connector Client ID** to the Entra application's
   application (client) ID.
7. Select or create each required Microsoft Dataverse and custom-connector
   connection.
8. Complete the import and review the import log.
9. If the import succeeds with a warning that one or more flows weren't turned
   on, complete the connection setup in Section 5 and then turn on the flows
   manually. A transient Dataverse metadata lookup can fail while the
   solution-owned write-log table is being created.

Don't continue if the import reports a failed component or unresolved
dependency. A flow activation warning can be recovered only after confirming
that the solution components imported successfully.

For current portal behavior, see
[Import solutions in Power Platform](https://learn.microsoft.com/power-apps/maker/data-platform/import-update-export-solutions).

## 4. Import with Power Platform CLI

Copy, don't rename in place,
`config/deployment-settings.example.json` to a location excluded from source
control. Fill in both environment-variable values and every connection ID.
Leave the example file unchanged.

Authenticate interactively and import:

```powershell
pac auth create `
  --name "dataverse-admin-target" `
  --environment "https://<environment-name>.crm.dynamics.com"

pac auth select --name "dataverse-admin-target"
pac auth list

pac solution import `
  --environment "https://<environment-name>.crm.dynamics.com" `
  --path ".\solutions\DataverseAdminAgent_1_0_0_0_managed.zip" `
  --settings-file "<secure-path>\deployment-settings.json" `
  --publish-changes
```

Confirm the active profile and target URL shown by `pac auth list` before
importing. Don't pass passwords or client secrets on a shared command line.

## 5. Complete connector setup

1. In the imported solution, open the **Get Licensing Info** custom connector.
2. Review its security configuration.
3. Copy the generated redirect URI and add it as a **Web** redirect URI on the
   customer Entra app registration.
4. Enter the app's client secret **Value**, not its secret ID, only in the
   target connector's **Security** configuration. Select **Update connector**
   and wait for success. Don't add the secret to an environment variable,
   deployment settings file, or this repository.
5. Create or reconnect the custom-connector connection and grant consent.
   If OAuth fails, follow
   [Licensing authentication troubleshooting](./configuration-guide.md#licensing-authentication-troubleshooting).
6. In the imported solution, open **Connection references** and ensure both
   **Get Licensing Info** references use the working custom-connector
   connection. The agent action uses its own agent-scoped reference; updating
   only the connector or the other reference doesn't make the action available
   to the agent.
7. In Copilot Studio, open **Dataverse Admin Agent** and verify that
   **Get user license details** appears under **Tools** without a connection
   warning.
8. Save and publish the agent after repairing the connector or connection
   references. Start a new test conversation because an existing session can
   retain its earlier tool set.
9. Confirm that the Dataverse connection references use the intended
   user-context connections rather than an unintended maker-owned shared
   connection.

An imported agent can request a new end-user connection even when its solution
connection references are populated. If the test chat shows **Connection
Required**, select **Set up connection**, complete the operator's delegated
connection, and select **Retry**. Don't change authentication to a shared maker
account to bypass this step.

If **Get user license details** is visible and connected under **Tools** but the
agent says it isn't available at runtime, the following tool-binding repair
requires the unmanaged package in a development environment. The managed
package is not customizable; do not remove or add tools in the managed
deployment. Manage changes through your own ALM; they are your responsibility
and outside the configuration Microsoft reviewed.

1. Remove **Get user license details** from the agent.
2. Publish the agent without that tool and wait for publishing to complete.
3. Add **Get user license details** again from the imported
   **Get Licensing Info** connector.
4. Confirm the connection is **Get Licensing Info** and authentication is
   **End user account**.
5. Publish the agent again and wait for publishing to complete.
6. Enable **End-user preview** and start a new conversation.

Publishing between removal and re-addition is required. It forces the runtime
catalog to discard the source-environment tool binding before Copilot Studio
creates the target-environment binding.

Custom-connector resource IDs are environment-specific. Do not edit the
solution ZIP or deployment settings to replace the packaged connector ID with
an ID copied from a target environment. Power Platform resolves the target
connector through the imported connection references.

See
[Authenticate a custom connector with Microsoft Entra ID](https://learn.microsoft.com/connectors/custom-connectors/azure-active-directory-authentication)
for the current connector workflow.

## 6. Validate before publishing

In Copilot Studio, open **Dataverse Admin Agent** and test:

1. A read-only lookup for a test user.
2. A licensing lookup for a test user.
3. An actual role assignment and team-membership addition in approved,
   disposable test scenarios, using the procedure below.
4. A separate write preview followed by a response other than `CONFIRM`;
   verify that no association is created.
5. A request from an operator without the required Dataverse write privilege;
   verify that Dataverse rejects it.
6. An ambiguous user, role, or team name; verify that the agent asks for
   clarification.

Check Power Automate run history, Dataverse audit history, and the agent's
connection status. Resolve every failed connection, disabled flow, or missing
permission before publication.

### Verify an actual write

Repeat this procedure separately for a role assignment and a team-membership
addition, including after importing the managed package:

1. Use an approved test user and an existing role or team. Independently check
   that the requested association does not already exist. An already-assigned
   result is not a successful new-write test.
2. Ask the agent for the change and review the flow-generated preview.
3. Before confirming, independently read the Dataverse association and verify
   that the preview has made no change.
4. Send only the exact word `CONFIRM` within five minutes.
5. Verify that the agent invoked the corresponding execution tool, then
   independently read Dataverse to confirm that the association exists.
   Check the write-log record, flow run history, and final AI disclosure too.
6. Record the test outcome and retain or clean up the test access according to
   your approved procedure. The agent cannot remove assignments or memberships;
   any reset requires a separately authorized administrator action.

A successful write under one operator does not validate another operator's
permissions, confirmation expiry, replay protection, or behavior in another
channel. Test those separately before production use.

### Flow activation warning

If import reports `InvalidOpenApiFlow`,
`DynamicOperationRequestClientFailure`, or
`GetMetadataForGetEntity` / `GetMetadataForPatchEntity`:

1. In the imported solution, confirm that the **Admin Agent Write Log** table
   exists and has logical name `ft_adminagentwritelog`.
2. Open **Connection references** and confirm that every Microsoft Dataverse
   reference is connected to a valid connection in the target environment.
3. Complete the custom connector setup in Section 5.
4. After the import and customization publication finish, open **Cloud flows**
   and retry turning on each disabled flow individually. Recreated table
   metadata can be unavailable during the initial activation attempt.
5. Refresh the solution page and confirm that all five flows show **On**.

If a flow still fails to turn on, download the import log and record the flow
name. Don't publish the agent. In a development environment, open the affected
flow and reselect **Admin Agent Write Logs** in its disabled Dataverse update
actions to refresh table metadata, then save and re-export the solution.
Managed flows should be repaired in the source solution and re-exported rather
than customized directly in the target environment.

## 7. Publish and share

Publish the agent only after validation. Configure each channel independently,
require Microsoft Entra ID sign-in, restrict the audience, and validate identity
propagation and transcript retention for that channel.
The published agent should be shared only with an administrator security group
or channel, and customers should review the
[Transparency Note](./transparency-note.md) before production use.

For Teams and Microsoft 365, follow
[Connect and configure an agent for Teams and Microsoft Copilot](https://learn.microsoft.com/microsoft-copilot-studio/publication-add-bot-to-microsoft-teams).

To include both channels in a managed deployment:

1. In the unmanaged source environment, select **Add channel**, then
   **Teams + Microsoft 365** and **Microsoft Copilot and Microsoft Teams**.
2. Save and publish the source agent. If you rebuilt a tool binding, add its
   current components and required dependencies to the source solution before
   export.
3. Export the solution as managed and import it into the target environment.
4. In the imported agent, verify that **Teams + Microsoft 365** is listed and
   both **View in Microsoft Teams** and **View in Microsoft Copilot** are
   enabled after publication. Managed channel settings are read-only; change
   channel selection in the unmanaged source and promote a new solution.
5. Test a conversation in each channel. Enabled launch controls are not an
   end-to-end channel test.

Channel configuration is separate from sharing or submission to the
organization's catalog. Don't submit for organization-wide distribution unless
that audience has been explicitly approved.

## Rollback

To stop use immediately, remove or disable the published channel and turn off
the solution's flows. Removing a managed solution can remove solution-owned
components and data; assess dependencies and retain required audit evidence
before uninstalling it.
