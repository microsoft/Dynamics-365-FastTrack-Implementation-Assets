"""
Project Operations / Dataverse Web API client for the Schedule APIs.

This client uses the documented Project schedule custom actions:

    msdyn_CreateProjectV1, msdyn_CreateTeamMemberV1,
    msdyn_ExecuteOperationSetV3

Authentication is a *bearer access token* supplied by the caller. The token
must belong to a **user who holds a Microsoft Project license** - application
(client-credentials) users cannot call the schedule APIs.

Reference:
https://learn.microsoft.com/dynamics365/project-operations/project-management/schedule-api-preview
"""
from __future__ import annotations

import json
import time
import uuid
from datetime import datetime, timezone
from dataclasses import dataclass, field
from threading import Lock
from typing import Any, Callable

import requests

API_VERSION = "v9.1"

# msdyn_LinkStatus / msdyn_linktype option set value used by the sample.
LINK_STATUS_LINKED = 192350000
LINK_TYPE_FINISH_TO_START = 192350000

# msdyn_linktype (Project Task Dependency) option set values, keyed by the
# friendly names used in the template's Dependencies sheet.
LINK_TYPE_VALUES: dict[str, int] = {
    "finishtostart": 192350000,
    "starttostart": 192350001,
    "finishtofinish": 192350002,
    "starttofinish": 192350003,
}


def link_type_value(name: str | None) -> int:
    """Map a friendly link-type name (e.g. 'FinishToStart') to its option value."""
    if not name:
        return LINK_TYPE_FINISH_TO_START
    key = "".join(ch for ch in str(name).lower() if ch.isalpha())
    if key not in LINK_TYPE_VALUES:
        raise ValueError(f"Unsupported dependency LinkType '{name}'.")
    return LINK_TYPE_VALUES[key]

# Maximum operations allowed in one OperationSet.
MAX_OPS_PER_SET = 200

OPSET_STATUS_OPEN = 192350000
OPSET_STATUS_PENDING = 192350001
OPSET_STATUS_ABANDONED = 192350002
OPSET_STATUS_COMPLETED = 192350003
OPSET_STATUS_FAILED = 192350004
OPSET_STATUS_LABELS = {
    OPSET_STATUS_OPEN: "Open",
    OPSET_STATUS_PENDING: "Pending",
    OPSET_STATUS_ABANDONED: "Abandoned",
    OPSET_STATUS_COMPLETED: "Completed",
    OPSET_STATUS_FAILED: "Failed",
}


class ProjectOperationsError(RuntimeError):
    """Raised when the Web API returns an error."""


class AuthorizationRequired(ProjectOperationsError):
    """Raised when Dataverse requires a new user access token."""


class AuthorizationExpiring(AuthorizationRequired):
    """Raised at a safe boundary before authorization expires."""


class ExecutionStopped(ProjectOperationsError):
    """Raised when the user requests a safe execution stop."""


class OperationSetOutcomeUnknown(ProjectOperationsError):
    """Raised when a submitted request cannot yet be reconciled safely."""


@dataclass
class SubmitResult:
    project_id: str = ""
    project_existed: bool = False
    bucket_id: str = ""
    task_ids: dict[str, str] = field(default_factory=dict)  # TaskKey -> GUID
    created_tasks: int = 0
    created_dependencies: int = 0
    created_team_members: int = 0
    created_assignments: int = 0
    operation_set_ids: list[str] = field(default_factory=list)
    logs: list[str] = field(default_factory=list)


def _clean_base_url(url: str) -> str:
    url = (url or "").strip().rstrip("/")
    if not url:
        raise ValueError("Environment URL is required.")
    if not url.startswith("http"):
        url = "https://" + url
    return url


class ProjectOperationsClient:
    def __init__(
        self,
        base_url: str,
        access_token: str,
        log: Callable[[str], None] | None = None,
        timeout: int = 300,
        token_refresh: Callable[[], str] | None = None,
        dataverse_requests: list[dict[str, Any]] | None = None,
        dataverse_requests_lock: Lock | None = None,
    ) -> None:
        self.base_url = _clean_base_url(base_url)
        self.api_root = f"{self.base_url}/api/data/{API_VERSION}"
        self.access_token = access_token.strip()
        self.timeout = timeout
        self.token_refresh = token_refresh
        self._log = log or (lambda _m: None)
        self.executed_v3_payloads: list[dict[str, Any]] = []
        self.executed_v3_responses: list[dict[str, Any]] = []
        self.execution_records: list[dict[str, Any]] = []
        self.dataverse_requests = (
            dataverse_requests if dataverse_requests is not None else []
        )
        self._dataverse_requests_lock = dataverse_requests_lock or Lock()
        self.session = self._new_session()

    def _new_session(self) -> requests.Session:
        session = requests.Session()
        session.headers.update(
            {
                "Authorization": f"Bearer {self.access_token}",
                "Accept": "application/json",
                "Content-Type": "application/json; charset=utf-8",
                "OData-MaxVersion": "4.0",
                "OData-Version": "4.0",
                "Prefer": 'odata.include-annotations="OData.Community.Display.V1.FormattedValue"',
            }
        )
        return session

    def reconnect(self) -> None:
        self.session.close()
        self.session = self._new_session()

    def set_access_token(self, access_token: str) -> None:
        self.access_token = access_token.strip()
        self.session.headers["Authorization"] = f"Bearer {self.access_token}"

    # ------------------------------------------------------------------ #
    # Low-level helpers
    # ------------------------------------------------------------------ #
    def _url(self, command: str) -> str:
        return f"{self.api_root}/{command.lstrip('/')}"

    def _send_recorded_request(
        self,
        method: str,
        url: str,
        body: dict | None,
        attempt: int,
    ) -> requests.Response:
        started_at = datetime.now(timezone.utc).isoformat()
        trace: dict[str, Any] = {
            "StartedAtUtc": started_at,
            "Method": method.upper(),
            "Url": url,
            "Attempt": attempt,
            "RequestBody": body,
        }
        try:
            response = self.session.request(
                method, url, json=body, timeout=self.timeout
            )
        except requests.RequestException as exc:
            trace["CompletedAtUtc"] = datetime.now(timezone.utc).isoformat()
            trace["TransportError"] = str(exc)
            with self._dataverse_requests_lock:
                self.dataverse_requests.append(trace)
            raise
        trace["CompletedAtUtc"] = datetime.now(timezone.utc).isoformat()
        trace["StatusCode"] = response.status_code
        try:
            trace["ResponseBody"] = response.json()
        except ValueError:
            trace["ResponseBody"] = response.text
        with self._dataverse_requests_lock:
            self.dataverse_requests.append(trace)
        return response

    def _request(self, method: str, command: str, body: dict | None = None) -> Any:
        url = self._url(command)
        attempts = 3 if method.upper() == "GET" else 1
        for attempt in range(1, attempts + 1):
            try:
                resp = self._send_recorded_request(
                    method, url, body, attempt
                )
                break
            except requests.RequestException as exc:
                if attempt == attempts:
                    raise
                self._log(
                    f"  ... {method.upper()} connection lost; reconnecting and "
                    f"retrying ({attempt}/{attempts - 1}): {exc}"
                )
                self.reconnect()
        if resp.status_code in (401, 403):
            if self.token_refresh is None:
                raise AuthorizationRequired(self._format_error(method, url, resp))
            try:
                self.set_access_token(self.token_refresh())
            except Exception as exc:
                raise AuthorizationRequired(
                    f"Automatic authorization refresh failed: {exc}"
                ) from exc
            resp = self._send_recorded_request(
                method, url, body, attempts + 1
            )
            if resp.status_code in (401, 403):
                raise AuthorizationRequired(self._format_error(method, url, resp))
        if resp.status_code >= 400:
            raise ProjectOperationsError(self._format_error(method, url, resp))
        if resp.status_code == 204 or not resp.content:
            return {}
        try:
            return resp.json()
        except ValueError:
            return {"raw": resp.text}

    @staticmethod
    def _format_error(method: str, url: str, resp: requests.Response) -> str:
        detail = resp.text
        try:
            payload = resp.json()
            err = payload.get("error", {})
            detail = err.get("message", detail)
        except ValueError:
            pass
        return f"{method} {url} -> HTTP {resp.status_code}: {detail}"

    def get(self, command: str) -> Any:
        return self._request("GET", command)

    def post(self, command: str, body: dict) -> Any:
        return self._request("POST", command, body)

    @staticmethod
    def _odata_str(value: str) -> str:
        """Single-quote escape a value for an OData $filter string literal."""
        return value.replace("'", "''")

    # ------------------------------------------------------------------ #
    # Identity / validation
    # ------------------------------------------------------------------ #
    def who_am_i(self) -> dict:
        return self.get("WhoAmI")

    def validate_migration_parameters(self) -> list[str]:
        expected = {
            "msdyn_estimatepricing": (
                "Estimate pricing options",
                "On-demand pricing",
            ),
            "msdyn_projecttasktimetracking": (
                "Project task time tracking",
                "Delayed update",
            ),
            "msdyn_projectactualstracking": (
                "Project actual values tracking",
                "On-demand update",
            ),
        }
        result = self.get(
            "msdyn_projectparameters?$select=" + ",".join(expected) + "&$top=1"
        )
        records = list(result.get("value", []))
        if not records:
            return [
                "No Project Operations Parameters record was found. Open "
                "Parameters in the Project Operations app and verify the migration "
                "settings."
            ]

        record = records[0]
        mismatches = []
        for field, (field_label, expected_label) in expected.items():
            formatted_key = (
                field + "@OData.Community.Display.V1.FormattedValue"
            )
            actual_label = str(record.get(formatted_key) or "Not set")
            if actual_label.casefold() != expected_label.casefold():
                mismatches.append(
                    f"{field_label}: Recommended value is '{expected_label}', "
                    f"current value is '{actual_label}'. Change can be made "
                    "through Project Parameters in the Project Operations app."
                )
        return mismatches

    def validate_contracting_units(self, names: list[str]) -> list[str]:
        messages = []
        for name in sorted({value.strip() for value in names if value.strip()}):
            if not self.find_contracting_unit_id(name):
                messages.append(
                    f"Contracting unit '{name}': No matching organizational unit "
                    "was found in Project Operations. Correct ContractingUnit in "
                    "the Projects sheet or create the organizational unit before "
                    "submitting."
                )
        return messages

    def validate_project_references(
        self,
        projects: list[tuple[str, str, str, str, str, str]],
    ) -> list[str]:
        messages = []
        for key, customer, company, contracting_unit, calendar, manager in projects:
            try:
                self.resolve_project_references(
                    customer=customer,
                    company=company,
                    contracting_unit=contracting_unit,
                    calendar=calendar,
                    manager=manager,
                )
            except ProjectOperationsError as exc:
                messages.append(f"Project {key}: {exc}")
        return messages

    def validate_assignment_roles(
        self,
        assignments: list[tuple[str, str]],
    ) -> list[str]:
        resources: dict[str, tuple[str, set[str]]] = {}
        for resource_name, role_name in assignments:
            resource_name = resource_name.strip()
            role_name = role_name.strip()
            if not resource_name:
                continue
            resource_key = resource_name.casefold()
            if resource_key not in resources:
                resources[resource_key] = (resource_name, set())
            if role_name:
                resources[resource_key][1].add(role_name)

        messages = []
        resource_category_ids: dict[str, str | None] = {}
        for resource_name, explicit_roles in resources.values():
            bookable_resource_id = self.find_bookableresource_id(resource_name)
            if explicit_roles:
                for role_name in sorted(explicit_roles):
                    role_key = role_name.casefold()
                    if role_key not in resource_category_ids:
                        resource_category_ids[role_key] = (
                            self.find_resource_category_id(role_name)
                        )
                    if not resource_category_ids[role_key]:
                        messages.append(
                            f"Resource '{resource_name}': RoleName '{role_name}' "
                            "was not found in Project Operations resource "
                            "categories. Correct RoleName in the Assignments sheet "
                            "or create the resource category before "
                            "submitting."
                        )
                continue
            if not bookable_resource_id:
                messages.append(
                    f"Resource '{resource_name}': RoleName is blank and no matching "
                    "bookable resource was found, so a default role cannot be "
                    "resolved. Enter RoleName or correct ResourceName."
                )
                continue
            if not self.find_default_resource_category(bookable_resource_id):
                messages.append(
                    f"Resource '{resource_name}': RoleName is blank and the matching "
                    "bookable resource has no default role. Enter RoleName in the "
                    "Assignments sheet or configure a default resource category."
                )
        return messages

    # ------------------------------------------------------------------ #
    # Lookups
    # ------------------------------------------------------------------ #
    def _lookup_single(self, command: str, id_field: str) -> str | None:
        result = self.get(command)
        values = result.get("value", [])
        if len(values) >= 1:
            return values[0].get(id_field)
        return None

    def find_project_id(self, project_key: str) -> str | None:
        f = self._odata_str(project_key.strip())
        cmd = (
            "msdyn_projects?$select=msdyn_projectid"
            f"&$filter=msdyn_projectnumber eq '{f}'"
        )
        return self._lookup_single(cmd, "msdyn_projectid")

    def find_account_id(self, account_number: str) -> str | None:
        f = self._odata_str(account_number)
        return self._lookup_single(
            f"accounts?$select=accountid&$filter=accountnumber eq '{f}'",
            "accountid",
        )

    def find_workhourtemplate_id(self, name: str) -> str | None:
        f = self._odata_str(name)
        return self._lookup_single(
            "msdyn_workhourtemplates?$select=msdyn_workhourtemplateid"
            f"&$filter=msdyn_name eq '{f}'",
            "msdyn_workhourtemplateid",
        )

    def find_company_id(self, company_code: str) -> str | None:
        f = self._odata_str(company_code)
        return self._lookup_single(
            "cdm_companies?$select=cdm_companyid"
            f"&$filter=cdm_companycode eq '{f}'",
            "cdm_companyid",
        )

    def find_contracting_unit_id(self, name: str) -> str | None:
        f = self._odata_str(name)
        return self._lookup_single(
            "msdyn_organizationalunits?$select=msdyn_organizationalunitid"
            f"&$filter=msdyn_name eq '{f}'",
            "msdyn_organizationalunitid",
        )

    def find_systemuser_id(self, fullname: str) -> str | None:
        f = self._odata_str(fullname)
        return self._lookup_single(
            f"systemusers?$select=systemuserid&$filter=fullname eq '{f}'",
            "systemuserid",
        )

    def find_bookableresource_id(self, name: str) -> str | None:
        f = self._odata_str(name)
        return self._lookup_single(
            f"bookableresources?$select=bookableresourceid&$filter=name eq '{f}'",
            "bookableresourceid",
        )

    def find_resource_category_id(self, name: str) -> str | None:
        f = self._odata_str(name)
        return self._lookup_single(
            "bookableresourcecategories?$select=bookableresourcecategoryid"
            f"&$filter=name eq '{f}'",
            "bookableresourcecategoryid",
        )

    def find_default_resource_category(
        self,
        bookable_resource_id: str,
    ) -> tuple[str, str] | None:
        result = self.get(
            "bookableresourcecategoryassns?$select=_resourcecategory_value"
            f"&$filter=_resource_value eq {bookable_resource_id} "
            "and msdyn_isdefault eq true and statecode eq 0&$top=1"
        )
        records = list(result.get("value", []))
        if not records:
            return None
        record = records[0]
        resource_category_id = str(record.get("_resourcecategory_value") or "")
        if not resource_category_id:
            return None
        formatted_key = (
            "_resourcecategory_value"
            "@OData.Community.Display.V1.FormattedValue"
        )
        role_name = str(record.get(formatted_key) or "Default role")
        return resource_category_id, role_name

    def get_default_bucket_id(self, project_id: str) -> str | None:
        cmd = (
            "msdyn_projectbuckets?$select=msdyn_projectbucketid"
            f"&$filter=_msdyn_project_value eq {project_id}"
            "&$orderby=createdon asc&$top=1"
        )
        return self._lookup_single(cmd, "msdyn_projectbucketid")

    def get_project_buckets(self, project_id: str) -> list[tuple[str, str]]:
        result = self.get(
            "msdyn_projectbuckets?$select=msdyn_projectbucketid,msdyn_name"
            f"&$filter=_msdyn_project_value eq {project_id}"
            "&$orderby=createdon asc"
        )
        return [
            (
                str(record.get("msdyn_projectbucketid") or ""),
                str(record.get("msdyn_name") or ""),
            )
            for record in result.get("value", [])
            if record.get("msdyn_projectbucketid")
        ]

    def find_team_member_id(
        self,
        project_id: str,
        bookable_resource_id: str,
    ) -> str | None:
        cmd = (
            "msdyn_projectteams?$select=msdyn_projectteamid"
            f"&$filter=_msdyn_project_value eq {project_id} "
            f"and _msdyn_bookableresourceid_value eq {bookable_resource_id}"
        )
        return self._lookup_single(cmd, "msdyn_projectteamid")

    # ------------------------------------------------------------------ #
    # Project / team member creation
    # ------------------------------------------------------------------ #
    def resolve_project_references(
        self,
        *,
        customer: str = "",
        company: str = "",
        contracting_unit: str = "",
        calendar: str = "",
        manager: str = "",
    ) -> dict[str, str]:
        lookups = (
            ("customer", "customer account", customer, self.find_account_id),
            ("company", "company", company, self.find_company_id),
            (
                "contracting unit",
                "contracting unit",
                contracting_unit,
                self.find_contracting_unit_id,
            ),
            ("calendar", "calendar", calendar, self.find_workhourtemplate_id),
            (
                "project manager",
                "project manager",
                manager,
                self.find_systemuser_id,
            ),
        )
        references: dict[str, str] = {}
        unresolved = []
        for key, label, value, lookup in lookups:
            if not value:
                continue
            reference_id = lookup(value)
            if reference_id:
                references[key] = reference_id
            else:
                unresolved.append(f"{label} '{value}'")
        if unresolved:
            raise ProjectOperationsError(
                "Project was not submitted because these supplied values were "
                "not found in Dataverse: " + ", ".join(unresolved) + "."
            )
        return references

    def create_project(
        self,
        project_key: str,
        name: str,
        description: str = "",
        customer: str = "",
        company: str = "",
        contracting_unit: str = "",
        calendar: str = "",
        manager: str = "",
        start: str | None = None,
        resolved_references: dict[str, str] | None = None,
    ) -> str:
        project_key = project_key.strip()
        references = resolved_references or self.resolve_project_references(
            customer=customer,
            company=company,
            contracting_unit=contracting_unit,
            calendar=calendar,
            manager=manager,
        )
        project: dict[str, Any] = {
            "msdyn_projectnumber": project_key,
            "msdyn_subject": name,
            "msdyn_description": description or name,
        }
        if customer:
            project["msdyn_customer@odata.bind"] = (
                f"/accounts({references['customer']})"
            )
        if calendar:
            project["msdyn_workhourtemplate@odata.bind"] = (
                f"/msdyn_workhourtemplates({references['calendar']})"
            )
        if company:
            project["msdyn_OwningCompany@odata.bind"] = (
                f"/cdm_companies({references['company']})"
            )
        if contracting_unit:
            project["msdyn_ContractOrganizationalUnitId@odata.bind"] = (
                f"/msdyn_organizationalunits({references['contracting unit']})"
            )
        if manager:
            project["msdyn_projectmanager@odata.bind"] = (
                f"/systemusers({references['project manager']})"
            )
        if start:
            project["msdyn_scheduledstart"] = start

        result = self.post("msdyn_CreateProjectV1", {"Project": project})
        project_id = result.get("ProjectId")
        if not project_id:
            raise ProjectOperationsError(
                f"msdyn_CreateProjectV1 did not return a ProjectId: {result}"
            )
        return project_id

    def create_team_member(
        self,
        project_id: str,
        resource_name: str,
        role_name: str,
        resource_category_id: str | None = None,
        bookable_resource_id: str | None = None,
    ) -> str:
        resource_category_id = (
            resource_category_id or self.find_resource_category_id(role_name)
        )
        if not resource_category_id:
            raise ProjectOperationsError(
                f"RoleName '{role_name}' was not found in Dataverse resource "
                "categories."
            )
        team_member: dict[str, Any] = {
            "msdyn_name": resource_name,
            "msdyn_project@odata.bind": f"/msdyn_projects({project_id})",
            "msdyn_resourcecategory@odata.bind": (
                f"/bookableresourcecategories({resource_category_id})"
            ),
        }
        if bookable_resource_id:
            team_member["msdyn_bookableresourceid@odata.bind"] = (
                f"/bookableresources({bookable_resource_id})"
            )
        result = self.post("msdyn_CreateTeamMemberV1", {"TeamMember": team_member})
        team_id = result.get("TeamMemberId")
        if not team_id:
            raise ProjectOperationsError(
                f"msdyn_CreateTeamMemberV1 did not return a TeamMemberId: {result}"
            )
        return team_id

    # ------------------------------------------------------------------ #
    # OperationSet
    # ------------------------------------------------------------------ #
    def register_operation_set(
        self,
        project_id: str,
        description: str,
        entities: list[dict[str, Any]],
        project_name: str = "",
    ) -> dict[str, Any]:
        payload = {
            "ProjectId": project_id,
            "OperationSetDescription": description,
            "CreateEntityCollection": entities,
        }
        execution_record = {
            "Project": project_name,
            "ProjectId": project_id,
            "Payload": payload,
            "OperationSetId": "",
            "Response": {},
            "SubmissionRequest": {
                "Method": "POST",
                "Url": self._url("msdyn_ExecuteOperationSetV3"),
                "Payload": payload,
            },
            "SubmissionResponse": {},
            "PollingRequest": [],
            "PollingResponse": [],
            "Status": "Planned",
        }
        self.execution_records.append(execution_record)
        return execution_record

    def new_worker(self, log: Callable[[str], None] | None = None) -> ProjectOperationsClient:
        return ProjectOperationsClient(
            self.base_url,
            self.access_token,
            log=log,
            timeout=self.timeout,
            token_refresh=self.token_refresh,
            dataverse_requests=self.dataverse_requests,
            dataverse_requests_lock=self._dataverse_requests_lock,
        )

    def execute_operation_set(
        self,
        project_id: str,
        description: str,
        entities: list[dict[str, Any]],
        project_name: str = "",
        execution_record: dict[str, Any] | None = None,
    ) -> Any:
        payload = {
            "ProjectId": project_id,
            "OperationSetDescription": description,
            "CreateEntityCollection": entities,
        }
        if execution_record is None:
            execution_record = self.register_operation_set(
                project_id,
                description,
                entities,
                project_name,
            )
        execution_record["Status"] = "Sending"
        execution_record["SubmissionStartedAtUtc"] = datetime.now(
            timezone.utc
        ).isoformat()
        self.executed_v3_payloads.append(payload)
        try:
            response = self.post("msdyn_ExecuteOperationSetV3", payload)
        except Exception as exc:
            error_response = {"Error": str(exc)}
            self.executed_v3_responses.append(error_response)
            execution_record["Response"] = error_response
            execution_record["SubmissionResponse"] = error_response
            execution_record["Status"] = "Request failed or outcome unknown"
            execution_record["SubmissionFinishedAtUtc"] = datetime.now(
                timezone.utc
            ).isoformat()
            raise
        self.executed_v3_responses.append(response)
        execution_record["Response"] = response
        execution_record["SubmissionResponse"] = response
        execution_record["OperationSetId"] = (
            self.operation_set_id_from_response(response) or ""
        )
        execution_record["Status"] = (
            "Submitted" if execution_record["OperationSetId"] else "Response missing ID"
        )
        execution_record["SubmissionFinishedAtUtc"] = datetime.now(
            timezone.utc
        ).isoformat()
        return response

    @staticmethod
    def operation_set_id_from_response(response: dict[str, Any]) -> str | None:
        operation_set_id = response.get("OperationSetId")
        if operation_set_id:
            return str(operation_set_id)

        operation_set_response = response.get("OperationSetResponse")
        if isinstance(operation_set_response, str):
            try:
                operation_set_response = json.loads(operation_set_response)
            except json.JSONDecodeError:
                return None
        if not isinstance(operation_set_response, dict):
            return None

        entries = operation_set_response.get("<OperationSetResponses>k__BackingField", [])
        for entry in entries:
            if entry.get("Key") == "OperationSetId":
                return str(entry.get("Value") or "") or None
        return None

    def find_operation_sets_by_description(
        self, description: str
    ) -> list[dict[str, Any]]:
        escaped = self._odata_str(description)
        result = self.get(
            "msdyn_operationsets?"
            "$select=msdyn_operationsetid,msdyn_status,msdyn_description"
            f"&$filter=msdyn_description eq '{escaped}'"
            "&$orderby=createdon desc&$top=10"
        )
        return list(result.get("value", []))

    def recover_operation_set(
        self,
        description: str,
        attempts: int = 12,
        wait_seconds: int = 30,
    ) -> str | None:
        for attempt in range(1, attempts + 1):
            self.reconnect()
            lookup = {
                "Attempt": attempt,
                "AttemptedAtUtc": datetime.now(timezone.utc).isoformat(),
                "Description": description,
            }
            try:
                self.who_am_i()
                operation_sets = self.find_operation_sets_by_description(description)
            except requests.RequestException as exc:
                lookup["Result"] = "Connection error"
                lookup["Error"] = str(exc)
                self._record_recovery_lookup(description, lookup)
                self._log(
                    f"  ... reconnect attempt {attempt}/{attempts} failed: {exc}"
                )
            else:
                lookup["MatchCount"] = len(operation_sets)
                if len(operation_sets) > 1:
                    lookup["Result"] = "Ambiguous duplicate descriptions"
                    lookup["Matches"] = operation_sets
                    self._record_recovery_lookup(description, lookup)
                    raise ProjectOperationsError(
                        f"Found {len(operation_sets)} operation sets with description "
                        f"'{description}'. Refusing to guess or resend."
                    )
                if operation_sets:
                    operation_set = operation_sets[0]
                    operation_set_id = operation_set.get("msdyn_operationsetid")
                    if operation_set_id:
                        status = operation_set.get("msdyn_status")
                        lookup["Result"] = "Matched"
                        lookup["OperationSetId"] = str(operation_set_id)
                        lookup["Status"] = status
                        self._record_recovery_lookup(description, lookup)
                        self._recover_execution_record(
                            description,
                            str(operation_set_id),
                            status,
                        )
                        return str(operation_set_id)
                lookup["Result"] = "Not visible"
                self._record_recovery_lookup(description, lookup)
                self._log(
                    f"  ... connection restored; operation set '{description}' "
                    f"not visible ({attempt}/{attempts})"
                )
            if attempt < attempts:
                time.sleep(wait_seconds)
        return None

    def _record_recovery_lookup(
        self,
        description: str,
        lookup: dict[str, Any],
    ) -> None:
        for record in reversed(self.execution_records):
            payload = record.get("Payload", {})
            if payload.get("OperationSetDescription") == description:
                record.setdefault("RecoveryLookups", []).append(lookup)
                return

    def _recover_execution_record(
        self,
        description: str,
        operation_set_id: str,
        status: int | None,
    ) -> None:
        for record in reversed(self.execution_records):
            payload = record.get("Payload", {})
            if payload.get("OperationSetDescription") == description:
                record["OperationSetId"] = operation_set_id
                record["Status"] = (
                    "Recovered - "
                    + OPSET_STATUS_LABELS.get(status, f"status {status}")
                )
                response = dict(record.get("Response", {}))
                response["RecoveredOperationSetId"] = operation_set_id
                response["RecoveredStatus"] = status
                record["Response"] = response
                return

    def wait_for_operation_sets(
        self,
        operation_set_ids: list[str],
        poll_seconds: int = 5,
        timeout_seconds: int = 1800,
        stop_requested: Callable[[], bool] | None = None,
    ) -> dict[str, int | None]:
        pending = set(operation_set_ids)
        statuses: dict[str, int | None] = {
            operation_set_id: None for operation_set_id in operation_set_ids
        }
        deadline = time.time() + timeout_seconds
        while pending and time.time() < deadline:
            if stop_requested and stop_requested():
                raise ExecutionStopped(
                    "Execution stopped by the user. Submitted operation sets will "
                    "continue in Dataverse and be reconciled when resumed."
                )
            completed = set()
            for operation_set_id in pending:
                command = (
                    f"msdyn_operationsets({operation_set_id})?$select=msdyn_status"
                )
                polling_request = {
                    "Method": "GET",
                    "Url": self._url(command),
                }
                self._record_polling_attempt(
                    operation_set_id,
                    polling_request,
                )
                try:
                    operation_set = self.get(command)
                except requests.RequestException as exc:
                    self._record_polling_attempt(
                        operation_set_id,
                        response={"Error": str(exc)},
                    )
                    self._log(
                        f"  ... polling connection lost; reconnecting: {exc}"
                    )
                    self.reconnect()
                    continue
                self._record_polling_attempt(
                    operation_set_id,
                    response=operation_set,
                )
                status = operation_set.get("msdyn_status")
                statuses[operation_set_id] = status
                self._set_execution_status(
                    operation_set_id,
                    status,
                    operation_set,
                )
                if status not in (
                    OPSET_STATUS_OPEN,
                    OPSET_STATUS_PENDING,
                ):
                    self._log(
                        f"  ... operation set {operation_set_id} reached "
                        f"{OPSET_STATUS_LABELS.get(status, f'status {status}')} "
                        f"({status})"
                    )
                    completed.add(operation_set_id)
            pending -= completed
            if pending:
                self._log(
                    f"  ... waiting for {len(pending)} operation set(s) in this wave"
                )
                wait_until = min(deadline, time.time() + poll_seconds)
                while time.time() < wait_until:
                    if stop_requested and stop_requested():
                        raise ExecutionStopped(
                            "Execution stopped by the user. Submitted operation sets "
                            "will continue in Dataverse and be reconciled when resumed."
                        )
                    time.sleep(min(0.5, max(0, wait_until - time.time())))
        if pending:
            raise ProjectOperationsError(
                "Timed out waiting for operation sets: " + ", ".join(sorted(pending))
            )
        unsuccessful = {
            operation_set_id: status
            for operation_set_id, status in statuses.items()
            if status != OPSET_STATUS_COMPLETED
        }
        if unsuccessful:
            details = ", ".join(
                f"{operation_set_id}: "
                f"{OPSET_STATUS_LABELS.get(status, f'status {status}')}"
                for operation_set_id, status in unsuccessful.items()
            )
            self._log(
                "  !! Operation-set polling finished with an unsuccessful "
                f"terminal result: {details}"
            )
            raise ProjectOperationsError(
                "Operation set execution did not complete successfully: " + details
            )
        return statuses

    def _record_polling_attempt(
        self,
        operation_set_id: str,
        request: dict[str, Any] | None = None,
        response: dict[str, Any] | None = None,
    ) -> None:
        for record in self.execution_records:
            if record.get("OperationSetId") == operation_set_id:
                if request is not None:
                    record.setdefault("PollingRequest", []).append(request)
                if response is not None:
                    record.setdefault("PollingResponse", []).append(response)

    def _set_execution_status(
        self,
        operation_set_id: str,
        status: int | None,
        status_response: dict[str, Any],
    ) -> None:
        label = OPSET_STATUS_LABELS.get(status, f"Terminal ({status})")
        for record in self.execution_records:
            if record.get("OperationSetId") == operation_set_id:
                record["Status"] = f"{label} ({status})"
                record["PollingFinishedAtUtc"] = datetime.now(
                    timezone.utc
                ).isoformat()
                response = dict(record.get("Response", {}))
                response["StatusPollResponse"] = status_response
                record["Response"] = response

    # ------------------------------------------------------------------ #
    # Entity builders
    # ------------------------------------------------------------------ #
    @staticmethod
    def build_project_bucket_entity(
        project_id: str,
        bucket_id: str,
        name: str = "Bucket 1",
    ) -> dict[str, Any]:
        return {
            "@odata.type": "Microsoft.Dynamics.CRM.msdyn_projectbucket",
            "msdyn_projectbucketid": bucket_id,
            "msdyn_project@odata.bind": f"/msdyn_projects({project_id})",
            "msdyn_name": name,
        }

    @staticmethod
    def build_task_entity(
        project_id: str,
        bucket_id: str,
        task_id: str,
        subject: str,
        effort: float | None,
        start: str | None,
        end: str | None,
        parent_task_id: str | None,
        task_col1: str | None = None,
    ) -> dict[str, Any]:
        entity: dict[str, Any] = {
            "@odata.type": "Microsoft.Dynamics.CRM.msdyn_projecttask",
            "msdyn_project@odata.bind": f"/msdyn_projects({project_id})",
            "msdyn_projecttaskid": task_id,
            "msdyn_subject": subject,
            "msdyn_LinkStatus": LINK_STATUS_LINKED,
            "msdyn_projectbucket@odata.bind": f"/msdyn_projectbuckets({bucket_id})",
        }
        if effort is not None:
            entity["msdyn_effort"] = effort
        if start:
            entity["msdyn_scheduledstart"] = start
        if end:
            entity["msdyn_scheduledend"] = end
        if task_col1:
            entity["cr2e3_TaskCol1"] = task_col1
        if parent_task_id:
            entity["msdyn_parenttask@odata.bind"] = f"/msdyn_projecttasks({parent_task_id})"
        else:
            entity["msdyn_parenttask"] = None
            entity["msdyn_outlinelevel"] = 1
        return entity

    @staticmethod
    def build_dependency_entity(
        project_id: str,
        dependency_id: str,
        predecessor_task_id: str,
        successor_task_id: str,
        link_type: str | int | None = None,
    ) -> dict[str, Any]:
        lt = link_type if isinstance(link_type, int) else link_type_value(link_type)
        return {
            "@odata.type": "Microsoft.Dynamics.CRM.msdyn_projecttaskdependency",
            "msdyn_projecttaskdependencyid": dependency_id,
            "msdyn_Project@odata.bind": f"/msdyn_projects({project_id})",
            "msdyn_PredecessorTask@odata.bind": f"/msdyn_projecttasks({predecessor_task_id})",
            "msdyn_SuccessorTask@odata.bind": f"/msdyn_projecttasks({successor_task_id})",
            "msdyn_linktype": lt,
        }

    @staticmethod
    def build_resource_assignment_entity(
        project_id: str,
        assignment_id: str,
        task_id: str,
        team_member_id: str,
        name: str,
    ) -> dict[str, Any]:
        return {
            "@odata.type": "Microsoft.Dynamics.CRM.msdyn_resourceassignment",
            "msdyn_resourceassignmentid": assignment_id,
            "msdyn_projectid@odata.bind": f"/msdyn_projects({project_id})",
            "msdyn_taskid@odata.bind": f"/msdyn_projecttasks({task_id})",
            "msdyn_projectteamid@odata.bind": f"/msdyn_projectteams({team_member_id})",
            "msdyn_name": name,
        }

    @staticmethod
    def new_guid() -> str:
        return str(uuid.uuid4())
