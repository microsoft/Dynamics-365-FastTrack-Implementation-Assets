# Configure C2 customer authentication

The chat, attachment upload, and attachment delete operations support these identities:

| Caller | Token validation |
| --- | --- |
| POS with a Commerce-issued user token | Existing Commerce discovery metadata and issuer. |
| POS with a workforce Microsoft Entra token | Existing workforce metadata, issuer, and `entraTokenAudience`. |
| C2 with Azure AD B2C | Optional, independent B2C discovery metadata, exact issuer, and audience. |
| C2 with Microsoft Entra External ID | Optional, independent **customer tenant** discovery metadata, exact issuer, and audience (`ciamlogin.com`, not another workforce tenant). |

Both customer providers are **disabled by default**. Existing POS deployments need no new settings. `entraTenantId` and `entraTokenAudience` remain workforce POS settings; do not replace them with customer identity values. The `-Tenant` deployment option selects the Azure deployment tenant, not a customer's token-validation authority.

This configures APIM authentication only. C2 sign-in, application registrations, consent, CSU customer authentication, and Commerce authorization must already work. APIM does not exchange customer tokens for another token or grant Commerce permissions.

## Get the provider values

Use the discovery document for the actual tenant and, for B2C, the sign-in flow or custom policy used by C2:

- B2C example: `https://contoso.b2clogin.com/contoso.onmicrosoft.com/B2C_1_signin/v2.0/.well-known/openid-configuration`.
- External ID example: `https://contoso.ciamlogin.com/<customer-tenant-guid>/v2.0/.well-known/openid-configuration`.
- Use the document's exact `issuer`, including any trailing slash. Do not construct it by copying the discovery URL.
- Set the audience to the exact `aud` expected by CSU for the C2 token contract. An access token normally identifies the API registration; an ID token identifies its client registration. It is not necessarily an `api://` value.
- Configure only trusted HTTPS discovery endpoints. APIM obtains signing keys from them. Never use a discovery URL supplied by the caller.

Choose the token type according to the existing CSU contract; enabling a provider is not approval to accept arbitrary ID tokens for an API. For access-token APIs, configure the required delegated permission using the provider's `RequiredScope` setting.

## Configure and deploy

Keep the four environment values in [azuredeploy.parameters.json](../azuredeploy.parameters.json). Add the relevant entries below **inside its existing `parameters` object**, replacing every example or placeholder. Omit the other provider's entries if it is not needed.

```json
{
  "b2cEnabled": { "value": true },
  "b2cOpenIdConfigUrl": {
    "value": "https://contoso.b2clogin.com/contoso.onmicrosoft.com/B2C_1_signin/v2.0/.well-known/openid-configuration"
  },
  "b2cTokenIssuer": { "value": "<exact issuer from B2C discovery>" },
  "b2cTokenAudience": { "value": "<audience expected by CSU>" },
  "b2cPolicyClaim": { "value": "tfp" },
  "b2cPolicy": { "value": "B2C_1_signin" },
  "b2cRequiredScope": { "value": "commerce.read" },
  "externalIdEnabled": { "value": true },
  "externalIdOpenIdConfigUrl": {
    "value": "https://contoso.ciamlogin.com/<customer-tenant-guid>/v2.0/.well-known/openid-configuration"
  },
  "externalIdTokenIssuer": { "value": "<exact issuer from External ID discovery>" },
  "externalIdTokenAudience": { "value": "<audience expected by CSU>" },
  "externalIdRequiredScope": { "value": "commerce.read" },
  "c2Origin": { "value": "https://shop.contoso.com" }
}
```

`commerce.read` is illustrative, not a permission created by this deployment. Supply the actual single permission name issued in `scp`.

Run from the package directory:

```powershell
.\deploy.ps1 -Tenant "<Azure-deployment-tenant-id>" -ParametersFile .\azuredeploy.parameters.json
```

The wrapper rejects incomplete enabled profiles before accessing Azure. Each enabled provider requires its discovery URL, issuer, and audience. Enabled customer providers must have distinct issuers and must not overlap the Commerce or workforce issuers. If deploying the ARM template directly, perform equivalent configuration checks; the wrapper's validation is not part of ARM.

Use the same parameters file for subsequent deployments to retain these optional settings. Running the interactive command without it uses template defaults, including disabling both customer providers.

### Optional restrictions

| ARM parameter | Default | Meaning |
| --- | --- | --- |
| `b2cEnabled`, `externalIdEnabled` | `false` | Independently enable each validator. |
| `anonymousEnabled` | `false` | Allow chat requests with no `Authorization` header. See [Anonymous chat](#anonymous-chat). |
| `b2cPolicy` | `__not-configured__` | Optional exact permitted B2C flow/policy value. |
| `b2cPolicyClaim` | `tfp` | Claim checked when `b2cPolicy` is configured; may instead be `acr`. |
| `b2cRequiredScope`, `externalIdRequiredScope` | `__not-configured__` | Optional exact permission in the space-separated `scp` claim. No substring matching. |
| `c2Origin` | `posOrigin` | Exact additional HTTPS browser origin, without a trailing slash or path. Explicit `*` permits all origins for non-credentialed CORS; use only when deliberately required, not for production. |

Remove `b2cPolicy` and its claim setting if no policy restriction is needed. Different B2C flows can share issuer, audience, and signing keys: a policy-specific discovery URL alone is not a flow restriction. Configure the `tfp` or `acr` check if only an approved flow should be accepted.

Remove a `RequiredScope` entry only when the existing CSU token contract does not require that access-token permission, such as a deliberately supported ID-token contract. Supplying an empty string is not equivalent to leaving a restriction unconfigured.

## Gateway behavior

- The unvalidated issuer is only a routing hint. A selected customer validator must verify the complete JWT's signature, expiration, exact issuer, and its own audience. It never uses the other provider's audience or signing metadata.
- Unknown issuers and disabled customer providers do not acquire trust. The unchanged legacy validator still accepts only its configured Commerce/workforce identities.
- Customer tokens additionally require a nonempty subject and any configured policy/scope. They cannot fall back to another validator after a selected validator fails.
- Customer discovery entries use `validate-connectivity="false"` so disabled placeholder endpoints do not prevent policy deployment. This does **not** disable signature validation: an enabled validator still needs real, reachable metadata and signing keys at runtime.
- The original `Authorization` header is passed to the inline Commerce MCP tool. An optional `DeviceToken` is copied only when present. C2 does not need to invent a device token; POS forwarding remains unchanged.
- APIM continues using managed identity for Foundry transport. Customer tokens are not sent as Foundry transport credentials.
- Request quotas use validated issuer plus subject, avoiding collisions between customers and employees with the same subject.
- CORS allows the configured C2 origin in addition to the POS origins. CORS is a browser rule, not an authentication boundary.
- With explicit `c2Origin: "*"`, any browser origin is allowed. Both wrappers render a single `*` origin because APIM forbids combining it with other origins. Direct ARM callers must do the same when supplying policies. The policies keep `allow-credentials="false"`; browser requests must not use credential mode `include`. JWT authentication is still required. Prefer an exact C2 origin for production.
- Correlation IDs and timing continue to work. Logs do not include tokens, customer claims, device credentials, or request/response bodies.

## Anonymous chat

Set `anonymousEnabled` to `true` (named value `anonymous-enabled`) to let signed-out shoppers use the chat operation:

- Only requests with no `Authorization` token are anonymous. A supplied token is still fully validated, and an invalid one still returns 401.
- No `Authorization` header is sent to the inline Commerce MCP tool, so only tools that permit anonymous callers succeed.
- Quotas are keyed by `anonymous|` plus the client IP address.
- The agent instructions tell the model that the shopper is not signed in.
- Anonymous requests with attachments return 401. The attachment upload and delete operations always require sign-in.

## Deployment acceptance checks

Local repository tests check XML/ARM consistency, compile and exercise the routing/claim expressions, and test deployment input validation with Azure mocked. They do **not** run APIM's policy compiler or cryptographically validate real provider tokens.

After deployment, test all three operations:

1. Existing Commerce POS and workforce Entra POS tokens still work; device credentials still reach CSU when supplied.
2. Each enabled customer's valid CSU-accepted token works without `DeviceToken`, including an MCP call on chat.
3. Expired, unsigned, tampered, wrong-issuer, and wrong-audience tokens fail with 401 before Foundry.
4. A customer token with another provider's audience fails, even when both providers are enabled.
5. Disable a customer provider and confirm its formerly valid token fails.
6. When configured, wrong/missing B2C policy and wrong/missing scope fail; valid exact claims succeed.
7. Browser preflight works for the configured C2 origin and not an unlisted origin. Invalid uploads still return 413/415 for both POS and C2.
8. Responses retain `x-correlation-id` and `x-apim-request-id`, including authentication failures; no credentials appear in diagnostics.

Do not paste tokens into source files, screenshots, logs, or PR comments.

References: [APIM validate-jwt](https://learn.microsoft.com/en-us/azure/api-management/validate-jwt-policy), [B2C tokens](https://learn.microsoft.com/en-us/azure/active-directory-b2c/tokens-overview).
