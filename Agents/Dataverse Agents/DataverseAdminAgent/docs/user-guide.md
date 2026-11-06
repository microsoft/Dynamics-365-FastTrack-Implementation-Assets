# User guide

## Purpose

The Dataverse Admin Agent helps authorized administrators retrieve Dataverse
security information and perform a small set of controlled changes through
natural-language requests.

Administrative facts come from configured Dataverse and Microsoft Graph tools,
not from model memory. Results reflect the signed-in operator's permissions and
the data available in the target environment.

## Supported requests

### Read-only

- Show an existing user's security profile.
- List direct roles and team memberships.
- Explain team-based or inherited access context when available.
- Look up an existing security role, team, or business unit.
- Show disabled users.
- Report recorded Dataverse access when auditing is enabled and retained.
- Read assigned license SKUs, service plans, and provisioning status.

### Controlled changes

- Assign one existing Dataverse security role to one existing user.
- Add one existing user to one existing Dataverse team.

## Example prompts

Use fictional or approved test identities when learning the agent:

```text
Show the security profile for alex.wilber@contoso.com.
```

```text
Which teams is Alex Wilber a member of?
```

```text
Show details for the Sales Manager security role.
```

```text
Show users with no recorded Dataverse access in the last 90 days.
```

```text
Preview assigning the Sales Manager role to alex.wilber@contoso.com.
```

```text
Preview adding alex.wilber@contoso.com to the Contoso Support team.
```

## Confirming a change

For a supported write operation:

1. State one user and one role or team.
2. Review the preview carefully, including the target user, business unit,
   role or team, and expected effect.
3. Reply with the exact word `CONFIRM` only if every detail is correct.
4. Any other response cancels the pending operation.
5. Review the final status. If verification is inconclusive, treat the outcome
   as unknown and check Dataverse directly.

A confirmation is single-use, operator-bound, tied to the previewed target, and
expires after five minutes. These checks are enforced in Power Automate, not
by the model. Never confirm a change you don't independently understand and
authorize.

## Interpreting results

- **Not found** means the connected tools couldn't locate a permitted matching
  record.
- **Multiple matches** requires you to identify the intended record; the agent
  shouldn't choose silently.
- **Access denied** means the signed-in operator lacks a required permission.
- **Unknown** for recorded Dataverse access means no usable audit/access record was available. It
  doesn't prove that a user was inactive.
- **Unknown write outcome** requires direct verification in Dataverse before
  retrying.

Two administrators can receive different results because each sees only data
permitted by their own Dataverse and Microsoft Graph access.

## Safe-use guidance

- Don't enter passwords, secrets, access tokens, or unnecessary personal data.
- Use a unique identifier only when needed to disambiguate a user.
- Follow organizational approval and change-management processes.
- Treat responses as administrative assistance, not a compliance decision.
- Report unexpected access, data exposure, or behavior through your
  organization's support and security channels.

## Troubleshooting

| Symptom | Action |
|---|---|
| Agent says the licensing action isn't present in its tool set | Verify both licensing connection references, confirm **Get user license details** appears under **Tools**, save and publish the agent, and start a new conversation |
| Licensing lookup fails | Ask an administrator to verify the Entra app permissions, redirect URI, custom-connector secret, consent, and connection |
| Agent shows **Connection Required** | Select **Set up connection**, complete your delegated sign-in for the intended connector, then select **Retry** or start a new conversation; don't enter secrets into chat |
| Dataverse lookup is incomplete | Verify the operator's permissions and the target environment |
| Access-history answer is Unknown | Verify Dataverse auditing, retention, and audit-read privileges |
| Role or team name is ambiguous | Retry with the exact name, business unit, or another approved identifier |
| Preview works but execution fails | Check operator privileges, confirmation expiry, flow status, Power Automate run history, and Dataverse audit history |
| Agent isn't visible in Teams or Microsoft 365 | Verify publication, sharing, tenant app policy, and channel approval; managed channel selection must be configured in the unmanaged source and promoted through a solution |
