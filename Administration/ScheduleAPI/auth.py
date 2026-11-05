"""
User-token acquisition for the Schedule APIs.

The Schedule APIs must be called by a *user* who holds a Microsoft Project
license. Interactive browser authorization is the default; the OAuth 2.0
Resource Owner Password Credentials (ROPC) flow remains available for non-MFA
accounts.

Requirements / caveats:
* An Azure AD app registration (public client) with delegated permission to
  the Dataverse / Dynamics CRM API and "Allow public client flows" enabled.
* ROPC does **not** support multi-factor authentication or guest accounts.
"""
from __future__ import annotations

import base64
import json
import os
import re
import time
from dataclasses import dataclass
from threading import Lock

import requests
from azure.core.exceptions import ClientAuthenticationError
from azure.identity import (
    CredentialUnavailableError,
    InteractiveBrowserCredential,
    TokenCachePersistenceOptions,
)

DEFAULT_CLIENT_ID = os.getenv("AZURE_CLIENT_ID", "")
_INTERACTIVE_CREDENTIALS: dict[tuple[str, str], InteractiveBrowserCredential] = {}
_INTERACTIVE_CREDENTIALS_LOCK = Lock()


class AuthError(RuntimeError):
    """Raised when token acquisition fails."""


@dataclass
class TokenResult:
    access_token: str
    expires_in: int = 0
    refresh_token: str = ""


def access_token_expires_at(access_token: str) -> float:
    """Return the JWT exp epoch, or 0 when the token has no readable expiry."""
    try:
        payload_segment = access_token.split(".")[1]
        padding = "=" * (-len(payload_segment) % 4)
        payload = json.loads(
            base64.urlsafe_b64decode(payload_segment + padding).decode("utf-8")
        )
        return float(payload.get("exp") or 0)
    except (IndexError, TypeError, ValueError, json.JSONDecodeError):
        return 0.0


def tenant_from_username(username: str) -> str:
    """Best-effort tenant = the domain part of a UPN (user@contoso.com)."""
    if username and "@" in username:
        return username.split("@", 1)[1].strip()
    return ""


def _resource_base(resource: str) -> str:
    resource = (resource or "").strip().rstrip("/")
    if not resource.startswith("http"):
        resource = "https://" + resource
    return resource


def acquire_token_interactively(
    resource: str,
    timeout: int = 60,
) -> TokenResult:
    """Sign in through a browser and cache the credential for silent renewal."""
    base = _resource_base(resource)
    tenant_id = _discover_dataverse_tenant(base, timeout=min(timeout, 15))
    cache_key = (tenant_id, base)
    with _INTERACTIVE_CREDENTIALS_LOCK:
        credential = _INTERACTIVE_CREDENTIALS.get(cache_key)
        if credential is None:
            credential = InteractiveBrowserCredential(
                tenant_id=tenant_id,
                timeout=timeout,
                cache_persistence_options=TokenCachePersistenceOptions(
                    name="project-operations-schedule-import",
                ),
            )
            _INTERACTIVE_CREDENTIALS[cache_key] = credential
    try:
        token = credential.get_token(f"{base}/.default")
    except (CredentialUnavailableError, ClientAuthenticationError) as exc:
        with _INTERACTIVE_CREDENTIALS_LOCK:
            if _INTERACTIVE_CREDENTIALS.get(cache_key) is credential:
                _INTERACTIVE_CREDENTIALS.pop(cache_key)
        raise AuthError(
            "Microsoft sign-in did not complete. Select 'Sign in with Microsoft' "
            "and sign in again."
        ) from exc
    return TokenResult(
        access_token=token.token,
        expires_in=max(0, int(token.expires_on - time.time())),
    )


def _discover_dataverse_tenant(resource: str, timeout: int = 15) -> str:
    """Read the tenant ID advertised by an unauthenticated Dataverse request."""
    try:
        response = requests.get(
            f"{resource}/api/data/v9.2/WhoAmI",
            timeout=timeout,
        )
    except requests.RequestException as exc:
        raise AuthError(f"Could not contact the Dataverse environment: {exc}") from exc
    challenge = response.headers.get("WWW-Authenticate", "")
    match = re.search(
        r"login\.microsoftonline\.com/([^/]+)/oauth2/(?:v2\.0/)?authorize",
        challenge,
        flags=re.IGNORECASE,
    )
    if not match:
        raise AuthError(
            "The Environment URL did not return a Microsoft Entra tenant challenge. "
            "Verify that it is the root URL of a Dataverse environment."
        )
    return match.group(1)


def acquire_token_by_password(
    tenant: str,
    client_id: str,
    username: str,
    password: str,
    resource: str,
    timeout: int = 30,
) -> TokenResult:
    """
    Acquire a Dataverse access token using the ROPC flow.

    ``resource`` is the environment URL (e.g. https://org.crm.dynamics.com);
    the scope requested is ``<resource>/.default``.
    """
    tenant = (tenant or "").strip() or tenant_from_username(username)
    if not tenant:
        raise AuthError("A tenant (or a user@domain username) is required.")
    if not client_id:
        raise AuthError("A client (application) ID is required.")
    if not username or not password:
        raise AuthError("Username and password are required.")

    base = _resource_base(resource)
    token_url = f"https://login.microsoftonline.com/{tenant}/oauth2/v2.0/token"
    data = {
        "grant_type": "password",
        "client_id": client_id,
        "username": username,
        "password": password,
        "scope": f"{base}/.default offline_access openid profile",
    }
    try:
        resp = requests.post(token_url, data=data, timeout=timeout)
    except requests.RequestException as exc:
        raise AuthError(f"Network error contacting Azure AD: {exc}") from exc

    if resp.status_code >= 400:
        raise AuthError(_format_aad_error(resp))

    payload = resp.json()
    token = payload.get("access_token")
    if not token:
        raise AuthError(f"No access_token in response: {payload}")
    return TokenResult(
        access_token=token,
        expires_in=int(payload.get("expires_in", 0)),
        refresh_token=str(payload.get("refresh_token") or ""),
    )


def refresh_access_token(
    tenant: str,
    client_id: str,
    refresh_token: str,
    resource: str,
    timeout: int = 30,
) -> TokenResult:
    if not refresh_token:
        raise AuthError("No refresh token is available; sign in again.")
    base = _resource_base(resource)
    token_url = f"https://login.microsoftonline.com/{tenant}/oauth2/v2.0/token"
    data = {
        "grant_type": "refresh_token",
        "client_id": client_id,
        "refresh_token": refresh_token,
        "scope": f"{base}/.default offline_access openid profile",
    }
    try:
        resp = requests.post(token_url, data=data, timeout=timeout)
    except requests.RequestException as exc:
        raise AuthError(f"Network error refreshing the Azure AD token: {exc}") from exc
    if resp.status_code >= 400:
        raise AuthError(_format_aad_error(resp))
    payload = resp.json()
    token = payload.get("access_token")
    if not token:
        raise AuthError(f"No access_token in refresh response: {payload}")
    return TokenResult(
        access_token=token,
        expires_in=int(payload.get("expires_in", 0)),
        refresh_token=str(payload.get("refresh_token") or refresh_token),
    )


def _format_aad_error(resp: requests.Response) -> str:
    try:
        payload = resp.json()
    except ValueError:
        return f"HTTP {resp.status_code}: {resp.text}"
    desc = payload.get("error_description", "")
    code = payload.get("error", "")
    # Surface the most useful first line of the AAD description.
    first_line = desc.splitlines()[0] if desc else ""
    hint = ""
    if "AADSTS50076" in desc or "AADSTS50079" in desc:
        hint = (
            " (MFA is required for this account - ROPC can't be used; "
            "use Microsoft sign-in instead.)"
        )
    elif "AADSTS65001" in desc or "AADSTS70011" in desc:
        hint = " (Consent/scope issue - check the app registration's API permissions.)"
    elif "AADSTS7000218" in desc:
        hint = " (Enable 'Allow public client flows' on the app registration.)"
    return f"{code}: {first_line}{hint}".strip()
