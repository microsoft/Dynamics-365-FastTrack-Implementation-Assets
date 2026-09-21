"""
Streamlit UI for importing a Project Operations schedule template
(Projects / Tasks / Assignments / Dependencies sheets) into Microsoft
Project Operations via the Dataverse Schedule Web APIs.

Run with:
    streamlit run app.py
"""
from __future__ import annotations

import json
import hashlib
import os
import re
import tempfile
import time
from datetime import datetime, timezone
from pathlib import Path
from threading import Lock, RLock

import pandas as pd
import requests
import streamlit as st

from auth import (
    DEFAULT_CLIENT_ID,
    AuthError,
    access_token_expires_at,
    acquire_token_interactively,
    acquire_token_by_password,
    refresh_access_token,
    tenant_from_username,
)
from excel_loader import Workbook, load_workbook, validate_workbook
from po_client import (
    MAX_OPS_PER_SET,
    AuthorizationRequired,
    ExecutionStopped,
    ProjectOperationsClient,
    ProjectOperationsError,
)
from runtime_controller import RuntimeController
from submit import resume_execution_records, submit_workbook

DEFAULT_ENV_URL = os.getenv("DATAVERSE_ENVIRONMENT_URL", "")
DEFAULT_USERNAME = os.getenv("DATAVERSE_USERNAME", "")
VALIDATION_RULE_VERSION = 5
CHECKPOINT_DIR = Path(__file__).resolve().parent / "execution_records"
ACTIVE_CHECKPOINT_PATH = CHECKPOINT_DIR / "active-upload.json"
CHECKPOINT_FILE_LOCK = RLock()
RECONCILIATION_ERROR_PAUSE_REASON = (
    "Reconciliation completed with project errors - user confirmation required"
)


@st.cache_resource
def get_runtime_controller() -> RuntimeController:
    return RuntimeController()


@st.cache_data(show_spinner=False)
def load_uploaded_workbook(uploaded_bytes: bytes) -> Workbook:
    return load_workbook(uploaded_bytes)


runtime_controller = get_runtime_controller()

st.set_page_config(page_title="Project Operations - Project tasks Import", page_icon="📅", layout="wide")

st.title("📅 Project Operations - Project tasks Import")
st.caption(
    "Upload a schedule template (Projects, Tasks, Assignments, Dependencies sheets) "
    "and create the projects, tasks, hierarchy, assignments and dependencies in "
    "Microsoft Project Operations using the Dataverse Schedule APIs."
)

if "logs" not in st.session_state:
    st.session_state.logs = []
if "workbook" not in st.session_state:
    st.session_state.workbook = None
if "token" not in st.session_state:
    st.session_state.token = ""
if "refresh_token" not in st.session_state:
    st.session_state.refresh_token = ""
if "token_expires_at" not in st.session_state:
    st.session_state.token_expires_at = 0.0
if "auth_context" not in st.session_state:
    st.session_state.auth_context = {}
if "executed_v3_payloads" not in st.session_state:
    st.session_state.executed_v3_payloads = []
if "show_v3_payloads" not in st.session_state:
    st.session_state.show_v3_payloads = False
if "executed_v3_responses" not in st.session_state:
    st.session_state.executed_v3_responses = []
if "show_v3_responses" not in st.session_state:
    st.session_state.show_v3_responses = False
if "execution_records" not in st.session_state:
    st.session_state.execution_records = []
if "reauthentication_required" not in st.session_state:
    st.session_state.reauthentication_required = False
if "resume_after_reauthentication" not in st.session_state:
    st.session_state.resume_after_reauthentication = False
if "checkpoint_environment" not in st.session_state:
    st.session_state.checkpoint_environment = ""
if "active_checkpoint_checked" not in st.session_state:
    st.session_state.active_checkpoint_checked = False
if "uploaded_file_name" not in st.session_state:
    st.session_state.uploaded_file_name = ""
if "uploaded_file_bytes" not in st.session_state:
    st.session_state.uploaded_file_bytes = b""
if "uploaded_file_hash" not in st.session_state:
    st.session_state.uploaded_file_hash = (
        hashlib.sha256(st.session_state.uploaded_file_bytes).hexdigest()
        if st.session_state.uploaded_file_bytes
        else ""
    )
if "uploader_has_file" not in st.session_state:
    st.session_state.uploader_has_file = False
if "uploader_version" not in st.session_state:
    st.session_state.uploader_version = 0
if "execution_directory" not in st.session_state:
    st.session_state.execution_directory = ""
if "selected_project_manifest" not in st.session_state:
    st.session_state.selected_project_manifest = []
if "validated_file_hash" not in st.session_state:
    st.session_state.validated_file_hash = ""
if "validation_issues" not in st.session_state:
    st.session_state.validation_issues = []
if "parameter_validation_messages" not in st.session_state:
    st.session_state.parameter_validation_messages = []
if "validated_environment" not in st.session_state:
    st.session_state.validated_environment = ""
if "validated_rule_version" not in st.session_state:
    st.session_state.validated_rule_version = 0

initial_runtime_snapshot = runtime_controller.snapshot()
if (
    not initial_runtime_snapshot["running"]
    and not ACTIVE_CHECKPOINT_PATH.exists()
    and not st.session_state.uploaded_file_name
    and not st.session_state.selected_project_manifest
):
    runtime_controller.reset()


def add_log(message: str) -> None:
    st.session_state.logs.append(message)


def write_execution_checkpoint(
    reason: str,
    environment_url: str,
    execution_directory: str,
    original_file_name: str,
    records: list[dict],
    logs: list[str],
    selected_projects: list[dict],
    execution_started_at: str = "",
) -> Path:
    existing_started_at = ""
    if ACTIVE_CHECKPOINT_PATH.exists():
        try:
            existing_checkpoint = json.loads(
                ACTIVE_CHECKPOINT_PATH.read_text(encoding="utf-8")
            )
            if str(existing_checkpoint.get("ExecutionDirectory") or "") == str(
                execution_directory
            ):
                existing_started_at = str(
                    existing_checkpoint.get("ExecutionStartedAtUtc") or ""
                )
        except (OSError, ValueError, json.JSONDecodeError):
            pass
    is_active = reason in {"Upload in progress", "Continuation in progress"}
    checkpoint = {
        "Reason": reason,
        "RecordedAtUtc": datetime.now(timezone.utc).isoformat(),
        "ExecutionStartedAtUtc": execution_started_at or existing_started_at,
        "ExecutionEndedAtUtc": (
            "" if is_active else datetime.now(timezone.utc).isoformat()
        ),
        "EnvironmentUrl": environment_url,
        "ExecutionDirectory": execution_directory,
        "OriginalFileName": original_file_name,
        "SelectedProjects": selected_projects,
        "ExecutionRecords": records,
        "Logs": logs,
    }
    CHECKPOINT_DIR.mkdir(exist_ok=True)
    checkpoint_json = json.dumps(checkpoint, indent=2, ensure_ascii=False)
    temporary_path: Path | None = None
    with CHECKPOINT_FILE_LOCK:
        try:
            with tempfile.NamedTemporaryFile(
                mode="w",
                encoding="utf-8",
                dir=CHECKPOINT_DIR,
                prefix="active-upload-",
                suffix=".json.tmp",
                delete=False,
            ) as temporary_file:
                temporary_file.write(checkpoint_json)
                temporary_file.flush()
                os.fsync(temporary_file.fileno())
                temporary_path = Path(temporary_file.name)
            for attempt in range(10):
                try:
                    os.replace(temporary_path, ACTIVE_CHECKPOINT_PATH)
                    temporary_path = None
                    break
                except PermissionError:
                    if attempt == 9:
                        raise
                    time.sleep(0.1 * (attempt + 1))
        finally:
            if temporary_path is not None:
                temporary_path.unlink(missing_ok=True)
    return ACTIVE_CHECKPOINT_PATH


def read_execution_checkpoint() -> dict:
    with CHECKPOINT_FILE_LOCK:
        return json.loads(ACTIVE_CHECKPOINT_PATH.read_text(encoding="utf-8"))


def save_execution_checkpoint(reason: str, environment_url: str = "") -> Path:
    return write_execution_checkpoint(
        reason,
        environment_url,
        st.session_state.execution_directory,
        st.session_state.uploaded_file_name,
        st.session_state.execution_records,
        st.session_state.logs,
        st.session_state.selected_project_manifest,
    )


def clear_execution_checkpoint() -> None:
    with CHECKPOINT_FILE_LOCK:
        ACTIVE_CHECKPOINT_PATH.unlink(missing_ok=True)


def execution_error_rows(records: list[dict]) -> list[dict]:
    rows = []
    seen = set()
    for record in records:
        status = str(record.get("Status") or "")
        response = record.get("Response") or {}
        error = str(
            record.get("ReconciliationError")
            or response.get("Error")
            or record.get("Error")
            or ""
        )
        if not error and (
            status.startswith(("Failed", "Abandoned", "Reconciliation error"))
            or "unknown" in status.lower()
        ):
            error = status
        if not error:
            continue
        row = {
            "Project ID": record.get("ProjectKey") or record.get("ProjectId") or "Unknown",
            "Project name": record.get("Project") or "Unknown",
            "Error": error,
        }
        identity = tuple(row.values())
        if identity not in seen:
            seen.add(identity)
            rows.append(row)
    return rows


def preparation_error_rows(logs: list[str]) -> list[dict]:
    """Extract keyed failures that occurred before operation-set creation."""
    failures: dict[str, dict[str, str]] = {}
    pattern = re.compile(
        r"^\s*!! Project '(?P<name>.+)' \(key=(?P<key>[^)]+)\) failed: "
        r"(?P<error>.+)$"
    )
    for message in logs:
        match = pattern.match(str(message))
        if match:
            failures[match.group("key")] = {
                "Project ID": match.group("key"),
                "Project name": match.group("name"),
                "Error": match.group("error"),
            }
    return list(failures.values())


def append_performance_summary(
    controller: RuntimeController,
    records: list[dict],
    execution_started_at: str,
    execution_ended_at: str,
) -> None:
    def parse_timestamp(value: object) -> datetime | None:
        try:
            return datetime.fromisoformat(str(value).replace("Z", "+00:00"))
        except (TypeError, ValueError):
            return None

    def duration_seconds(start: object, end: object) -> float | None:
        start_time = parse_timestamp(start)
        end_time = parse_timestamp(end)
        if start_time is None or end_time is None:
            return None
        return max(0.0, (end_time - start_time).total_seconds())

    def percentile(values: list[float], percentage: float) -> float:
        ordered = sorted(values)
        if not ordered:
            return 0.0
        index = min(len(ordered) - 1, int((len(ordered) - 1) * percentage))
        return ordered[index]

    active_records = [
        record for record in records
        if not str(record.get("Status") or "").startswith("Superseded")
    ]
    completed = sum(
        str(record.get("Status") or "").startswith("Completed")
        for record in active_records
    )
    errors = execution_error_rows(active_records)
    submission_timings = []
    polling_timings = []
    project_timings: dict[tuple[str, str], float] = {}
    for record in active_records:
        submission_duration = duration_seconds(
            record.get("SubmissionStartedAtUtc"),
            record.get("SubmissionFinishedAtUtc"),
        )
        if submission_duration is not None:
            submission_timings.append(submission_duration)
        polling_duration = duration_seconds(
            record.get("PollingStartedAtUtc"),
            record.get("PollingFinishedAtUtc"),
        )
        if polling_duration is not None:
            polling_timings.append(polling_duration)
        total_duration = duration_seconds(
            record.get("ScheduledAtUtc") or record.get("SubmissionStartedAtUtc"),
            record.get("PollingFinishedAtUtc")
            or record.get("SubmissionFinishedAtUtc"),
        )
        if total_duration is not None:
            project_identity = (
                str(record.get("ProjectKey") or record.get("ProjectId") or "Unknown"),
                str(record.get("Project") or "Unknown"),
            )
            project_timings[project_identity] = max(
                project_timings.get(project_identity, 0.0), total_duration
            )

    total_duration = duration_seconds(execution_started_at, execution_ended_at)
    controller.add_log("=== Execution performance summary ===")
    controller.add_log(
        f"Start={execution_started_at or 'Unknown'}; "
        f"end={execution_ended_at}; "
        f"elapsed={total_duration:.1f}s."
        if total_duration is not None
        else f"Start={execution_started_at or 'Unknown'}; end={execution_ended_at}."
    )
    controller.add_log(
        f"Operation sets: {len(active_records)} known, {completed} completed, "
        f"{len(errors)} project error(s)."
    )
    if submission_timings:
        controller.add_log(
            "Submission response latency: "
            f"average={sum(submission_timings) / len(submission_timings):.1f}s, "
            f"p95={percentile(submission_timings, 0.95):.1f}s, "
            f"maximum={max(submission_timings):.1f}s."
        )
    if polling_timings:
        controller.add_log(
            "Dataverse execution/polling time: "
            f"average={sum(polling_timings) / len(polling_timings):.1f}s, "
            f"p95={percentile(polling_timings, 0.95):.1f}s, "
            f"maximum={max(polling_timings):.1f}s."
        )
    if project_timings:
        controller.add_log("Slowest projects observed:")
        for (project_id, project_name), seconds in sorted(
            project_timings.items(), key=lambda item: item[1], reverse=True
        )[:10]:
            controller.add_log(
                f"  SLOW | {project_id} - {project_name} | {seconds:.1f}s"
            )

    settings = controller.settings()
    recommendations = []
    if submission_timings and max(submission_timings) >= 30:
        recommendations.append(
            "Dataverse POST response latency exceeded 30s. Keep automatic "
            "reconnection enabled and compare concurrency 5 versus 10 if long "
            "responses recur; lower concurrency may reduce service contention."
        )
    if polling_timings and int(settings["polling_wait_seconds"]) > 60:
        recommendations.append(
            "Reduce polling wait to 30-60s for faster status visibility. This "
            "does not make Dataverse execute faster, but reduces detection delay."
        )
    if any(int(record.get("OperationCount") or 0) >= 180 for record in active_records):
        recommendations.append(
            "Some operation sets are near the 200-operation limit. Keep 200 for "
            "throughput unless those large sets show repeated timeouts or failures."
        )
    if errors:
        recommendations.append(
            "Correct the listed project data errors before retrying those projects; "
            "continue only never-started projects to avoid duplicate work."
        )
    if not recommendations:
        recommendations.append(
            "No dominant client-side bottleneck was detected. Keep concurrency at "
            f"{settings['concurrent_operation_sets']} and monitor Dataverse latency."
        )
    controller.add_log("Recommendations:")
    for index, recommendation in enumerate(recommendations, start=1):
        controller.add_log(f"  {index}. {recommendation}")
    controller.add_log(f"=== Performance summary ended at {execution_ended_at} ===")


def write_execution_history(
    records: list[dict],
    environment_url: str,
    execution_directory: str,
    original_file_name: str,
    logs: list[str],
    selected_projects: list[dict],
    dataverse_requests: list[dict] | None = None,
) -> Path:
    timestamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    run_dir = Path(execution_directory) if (
        execution_directory
    ) else CHECKPOINT_DIR / timestamp
    run_dir.mkdir(parents=True, exist_ok=True)
    dataverse_requests = list(dataverse_requests or [])
    diagnostics_path = run_dir / "execution-diagnostics.json"
    diagnostics_path.write_text(
        json.dumps({
            "CompletedAtUtc": datetime.now(timezone.utc).isoformat(),
            "EnvironmentUrl": environment_url,
            "OriginalFileName": original_file_name,
            "SelectedProjects": selected_projects,
            "DataverseRequests": dataverse_requests,
            "ExecutionRecords": records,
        }, indent=2, ensure_ascii=False),
        encoding="utf-8",
    )
    (run_dir / "dataverse-requests.json").write_text(
        json.dumps(dataverse_requests, indent=2, ensure_ascii=False),
        encoding="utf-8",
    )
    history_rows = []
    for record in records:
        recovery_lookups = list(record.get("RecoveryLookups") or [])
        latest_recovery = recovery_lookups[-1] if recovery_lookups else {}
        history_rows.append({
            "Round": record.get("Round"),
            "Slot": record.get("Slot"),
            "Project": record.get("Project", ""),
            "ProjectKey": record.get("ProjectKey", ""),
            "ProjectId": record.get("ProjectId", ""),
            "Batch": record.get("Batch"),
            "OperationCount": record.get("OperationCount"),
            "OperationSetDescription": record.get("Payload", {}).get(
                "OperationSetDescription", ""
            ),
            "OperationSetId": record.get("OperationSetId", ""),
            "Status": record.get("Status", ""),
            "ScheduledAtUtc": record.get("ScheduledAtUtc", ""),
            "SubmissionStartedAtUtc": record.get("SubmissionStartedAtUtc", ""),
            "SubmissionFinishedAtUtc": record.get("SubmissionFinishedAtUtc", ""),
            "PollingStartedAtUtc": record.get("PollingStartedAtUtc", ""),
            "PollingFinishedAtUtc": record.get("PollingFinishedAtUtc", ""),
            "RecoveryAttempts": len(recovery_lookups),
            "LatestRecoveryResult": latest_recovery.get("Result", ""),
            "LatestRecoveryAtUtc": latest_recovery.get("AttemptedAtUtc", ""),
            "RecoveredOperationSetId": latest_recovery.get(
                "OperationSetId", ""
            ),
            "RecoveredStatus": latest_recovery.get("Status", ""),
        })
    pd.DataFrame(history_rows).to_csv(run_dir / "execution-history.csv", index=False)
    (run_dir / "activity-log.txt").write_text(
        "\n".join(logs),
        encoding="utf-8",
    )
    return run_dir


def archive_execution_history(
    records: list[dict],
    environment_url: str,
) -> Path:
    return write_execution_history(
        records,
        environment_url,
        st.session_state.execution_directory,
        st.session_state.uploaded_file_name,
        st.session_state.logs,
        st.session_state.selected_project_manifest,
    )


def archive_discarded_checkpoint(checkpoint: dict) -> Path:
    discarded_at = datetime.now(timezone.utc).isoformat()
    logs = list(checkpoint.get("Logs") or [])
    logs.append(f"Execution discarded by user at {discarded_at}")
    return write_execution_history(
        list(checkpoint.get("ExecutionRecords") or []),
        str(checkpoint.get("EnvironmentUrl") or ""),
        str(checkpoint.get("ExecutionDirectory") or ""),
        str(checkpoint.get("OriginalFileName") or ""),
        logs,
        list(checkpoint.get("SelectedProjects") or []),
    )


def archive_current_execution_for_discard(
    checkpoint: dict | None = None,
    environment_url: str = "",
) -> None:
    retained_checkpoint = checkpoint
    if retained_checkpoint is None and ACTIVE_CHECKPOINT_PATH.exists():
        retained_checkpoint = read_execution_checkpoint()
    if retained_checkpoint is None:
        retained_checkpoint = {
            "EnvironmentUrl": (
                st.session_state.checkpoint_environment or environment_url
            ),
            "ExecutionDirectory": st.session_state.execution_directory,
            "OriginalFileName": st.session_state.uploaded_file_name,
            "SelectedProjects": st.session_state.selected_project_manifest,
            "ExecutionRecords": st.session_state.execution_records,
            "Logs": st.session_state.logs,
        }

    has_execution_trace = bool(
        retained_checkpoint.get("ExecutionRecords")
        or retained_checkpoint.get("Logs")
        or retained_checkpoint.get("ExecutionDirectory")
    )
    if has_execution_trace:
        archive_discarded_checkpoint(retained_checkpoint)

    if ACTIVE_CHECKPOINT_PATH.exists():
        discarded_at = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
        with CHECKPOINT_FILE_LOCK:
            if ACTIVE_CHECKPOINT_PATH.exists():
                ACTIVE_CHECKPOINT_PATH.replace(
                    CHECKPOINT_DIR / f"discarded-upload-{discarded_at}.json"
                )


def reset_upload_state(*, rotate_uploader: bool) -> None:
    runtime_controller.reset()
    st.session_state.workbook = None
    st.session_state.uploaded_file_name = ""
    st.session_state.uploaded_file_bytes = b""
    st.session_state.uploaded_file_hash = ""
    st.session_state.uploader_has_file = False
    if rotate_uploader:
        st.session_state.uploader_version += 1
    st.session_state.logs = []
    st.session_state.execution_records = []
    st.session_state.executed_v3_payloads = []
    st.session_state.executed_v3_responses = []
    st.session_state.show_v3_payloads = False
    st.session_state.show_v3_responses = False
    st.session_state.selected_project_manifest = []
    st.session_state.execution_directory = ""
    st.session_state.checkpoint_environment = ""
    st.session_state.reauthentication_required = False
    st.session_state.resume_after_reauthentication = False
    st.session_state.validated_file_hash = ""
    st.session_state.validation_issues = []
    st.session_state.parameter_validation_messages = []
    st.session_state.validated_environment = ""
    st.session_state.validated_rule_version = 0


def project_completeness(
    selected_projects: list[dict],
    records: list[dict],
) -> list[dict]:
    status_rows = []
    for project in selected_projects:
        project_key = str(project.get("ProjectKey") or "")
        project_name = str(project.get("ProjectName") or "")
        project_records = [
            record for record in records
            if str(record.get("ProjectKey") or "") == project_key
            and not str(record.get("Status") or "").startswith("Superseded")
        ]
        completed = sum(
            str(record.get("Status") or "").startswith("Completed")
            for record in project_records
        )
        if not project_records:
            status = "Not started"
        elif completed == len(project_records):
            status = "Completed"
        else:
            status = "Incomplete"
        status_rows.append({
            "ProjectKey": project_key,
            "ProjectName": project_name,
            "Status": status,
            "CompletedOperationSets": completed,
            "KnownOperationSets": len(project_records),
        })
    return status_rows


def determine_run_status(
    *,
    running: bool,
    finished: bool,
    error: str,
    stopped: bool,
    reauthentication_required: bool,
    selected_projects: list[dict],
    records: list[dict],
    checkpoint_exists: bool,
) -> tuple[str, list[dict]]:
    completeness = project_completeness(selected_projects, records)
    if selected_projects and not records and not running and not checkpoint_exists:
        return "IDLE", completeness
    incomplete = [row for row in completeness if row["Status"] != "Completed"]
    failed_records = [
        record for record in records
        if str(record.get("Status") or "").startswith(("Failed", "Abandoned"))
    ]
    if selected_projects and not incomplete and not failed_records:
        return "COMPLETE", completeness
    if running:
        return (
            "STOPPING - CHECKPOINTING" if stopped else "RUNNING",
            completeness,
        )
    if stopped:
        return "PAUSED - STOPPED BY USER", completeness
    if reauthentication_required:
        return "PAUSED - AUTHORIZATION REQUIRED", completeness
    if error or failed_records:
        return "FAILED", completeness
    if incomplete:
        if checkpoint_exists:
            return "PAUSED - CONTINUATION REQUIRED", completeness
        return "INCOMPLETE", completeness
    if selected_projects:
        return "FINALIZING", completeness
    return "IDLE", completeness


if not st.session_state.active_checkpoint_checked:
    st.session_state.active_checkpoint_checked = True
    if ACTIVE_CHECKPOINT_PATH.exists() and not st.session_state.execution_records:
        try:
            active_checkpoint = read_execution_checkpoint()
            retained_records = active_checkpoint.get("ExecutionRecords", [])
            if not isinstance(retained_records, list) or not retained_records:
                raise ValueError("Checkpoint contains no execution records.")
            st.session_state.execution_records = retained_records
            st.session_state.logs = list(active_checkpoint.get("Logs", []))
            st.session_state.checkpoint_environment = str(
                active_checkpoint.get("EnvironmentUrl") or ""
            )
            st.session_state.execution_directory = str(
                active_checkpoint.get("ExecutionDirectory")
                or active_checkpoint.get("ExecutionLogDirectory")
                or ""
            )
            st.session_state.uploaded_file_name = str(
                active_checkpoint.get("OriginalFileName") or ""
            )
            st.session_state.selected_project_manifest = list(
                active_checkpoint.get("SelectedProjects") or []
            )
            runtime_controller.restore(
                logs=st.session_state.logs,
                execution_records=st.session_state.execution_records,
            )
            st.session_state.reauthentication_required = True
        except (OSError, ValueError, json.JSONDecodeError) as exc:
            st.warning(f"Could not load the active upload checkpoint: {exc}")


# --------------------------------------------------------------------------- #
# Sidebar: connection + options
# --------------------------------------------------------------------------- #
with st.sidebar:
    st.header("1. Connection")
    env_url = st.text_input(
        "Environment URL",
        value=st.session_state.checkpoint_environment or DEFAULT_ENV_URL,
        placeholder="https://yourorg.crm.dynamics.com",
        help="The Dataverse org URL, e.g. https://yourorg.crm.dynamics.com",
    )

    auth_method = st.radio(
        "Authentication",
        [
            "Microsoft sign-in (automatic)",
            "Username / password",
            "Paste access token",
        ],
        help=(
            "Microsoft sign-in opens a secure browser and supports MFA. The app "
            "discovers the tenant and renews the token for the Environment URL."
        ),
    )

    if auth_method == "Microsoft sign-in (automatic)":
        st.caption(
            "Uses the Environment URL to discover its Microsoft Entra tenant. "
            "Sign in through the secure browser window; MFA is supported."
        )
        if st.button(
            "🔑 Sign in with Microsoft",
            disabled=not env_url.strip(),
            width="stretch",
        ):
            try:
                with st.spinner("Waiting for Microsoft sign-in ..."):
                    result = acquire_token_interactively(env_url)
                st.session_state.token = result.access_token
                st.session_state.refresh_token = ""
                st.session_state.token_expires_at = time.time() + result.expires_in
                st.session_state.auth_context = {
                    "method": "interactive",
                    "resource": env_url,
                }
                st.success("Microsoft authorization acquired.")
            except AuthError as exc:
                st.session_state.token = ""
                st.error(f"Authorization failed: {exc}")
        if st.session_state.token and st.session_state.auth_context.get("method") == "interactive":
            st.caption("✅ Microsoft authorization acquired.")
    elif auth_method == "Username / password":
        username = st.text_input("Username (UPN)", value=DEFAULT_USERNAME)
        password = st.text_input("Password", type="password")
        with st.expander("Advanced (tenant / client id)"):
            tenant = st.text_input(
                "Tenant",
                value=tenant_from_username(username),
                help="Defaults to the domain of your username. Can be a GUID.",
            )
            client_id = st.text_input(
                "Client (application) ID",
                value=DEFAULT_CLIENT_ID,
                help=(
                    "A public-client AAD app with delegated Dynamics CRM "
                    "permission and 'Allow public client flows' enabled."
                ),
            )
        if st.button("🔑 Sign in", width="stretch"):
            if not username or not password:
                st.error("Enter your username and password.")
            else:
                try:
                    with st.spinner("Signing in ..."):
                        result = acquire_token_by_password(
                            tenant=tenant or tenant_from_username(username),
                            client_id=client_id or DEFAULT_CLIENT_ID,
                            username=username,
                            password=password,
                            resource=env_url,
                        )
                    st.session_state.token = result.access_token
                    st.session_state.refresh_token = result.refresh_token
                    st.session_state.token_expires_at = time.time() + result.expires_in
                    st.session_state.auth_context = {
                        "method": "password",
                        "tenant": tenant or tenant_from_username(username),
                        "client_id": client_id or DEFAULT_CLIENT_ID,
                        "resource": env_url,
                    }
                    mins = result.expires_in // 60
                    st.success(f"Signed in. Token valid ~{mins} min.")
                except AuthError as exc:
                    st.session_state.token = ""
                    st.error(f"Sign-in failed: {exc}")
        if st.session_state.token:
            st.caption("✅ Token acquired.")
    else:
        pasted = st.text_input(
            "Access token (Bearer)",
            type="password",
            help=(
                "Paste a Dataverse access token for a USER who holds a Microsoft "
                "Project license."
            ),
        )
        if pasted:
            st.session_state.token = pasted
            st.session_state.refresh_token = ""
            st.session_state.token_expires_at = access_token_expires_at(pasted)
            st.session_state.auth_context = {}

    token = st.session_state.token

    def refresh_session_token() -> str:
        context = st.session_state.auth_context
        if context.get("method") == "interactive":
            result = acquire_token_interactively(context["resource"])
        else:
            result = refresh_access_token(
                tenant=context["tenant"],
                client_id=context["client_id"],
                refresh_token=st.session_state.refresh_token,
                resource=context["resource"],
            )
        st.session_state.token = result.access_token
        st.session_state.refresh_token = result.refresh_token
        st.session_state.token_expires_at = time.time() + result.expires_in
        return result.access_token

    refresh_state = {
        "access_token": token,
        "refresh_token": st.session_state.refresh_token,
        "expires_at": st.session_state.token_expires_at,
        "last_refresh_at": 0.0,
    }
    worker_auth_context = dict(st.session_state.auth_context)
    refresh_lock = Lock()

    def refresh_worker_token(force: bool = False) -> str:
        with refresh_lock:
            if not force and refresh_state["last_refresh_at"] > time.time() - 30:
                return str(refresh_state["access_token"])
            if worker_auth_context.get("method") == "interactive":
                result = acquire_token_interactively(worker_auth_context["resource"])
            else:
                result = refresh_access_token(
                    tenant=worker_auth_context["tenant"],
                    client_id=worker_auth_context["client_id"],
                    refresh_token=str(refresh_state["refresh_token"]),
                    resource=worker_auth_context["resource"],
                )
            refresh_state["access_token"] = result.access_token
            refresh_state["refresh_token"] = (
                result.refresh_token or refresh_state["refresh_token"]
            )
            refresh_state["expires_at"] = time.time() + result.expires_in
            refresh_state["last_refresh_at"] = time.time()
            return result.access_token

    renewable_authorization = bool(
        st.session_state.refresh_token
        or st.session_state.auth_context.get("method") == "interactive"
    )
    token_refresh = refresh_worker_token if renewable_authorization else None
    authorization_near_expiry = bool(
        token
        and st.session_state.token_expires_at
        and st.session_state.token_expires_at <= time.time() + 300
    )
    if token and st.session_state.token_expires_at:
        remaining_seconds = max(0, int(st.session_state.token_expires_at - time.time()))
        st.caption(f"Authorization expires in about {remaining_seconds // 60} minute(s).")
        if authorization_near_expiry and token_refresh is None:
            st.warning(
                "Authorization has five minutes or less remaining. Reauthenticate "
                "before starting or continuing another operation-set wave."
            )
        elif authorization_near_expiry:
            st.info(
                "Authorization is near expiry and will rotate automatically before "
                "the next operation-set wave."
            )
    if st.button(
        "Refresh authorization",
        disabled=token_refresh is None,
        width="stretch",
        help=(
            "Silently renews Microsoft sign-in or username/password "
            "authorization. Pasted access tokens must be replaced manually."
        ),
    ):
        try:
            refresh_session_token()
        except AuthError as exc:
            st.error(f"Authorization refresh failed: {exc}")
        else:
            token = st.session_state.token
            st.success("Authorization refreshed.")

    if st.button("🔌 Test connection", width="stretch"):
        if not token:
            st.error("Sign in or paste a token first.")
        else:
            try:
                who = ProjectOperationsClient(
                    env_url,
                    token,
                    token_refresh=token_refresh,
                ).who_am_i()
                st.success(f"Connected. UserId: {who.get('UserId', 'n/a')}")
            except Exception as exc:  # noqa: BLE001
                st.error(f"Connection failed: {exc}")

    st.divider()
    if st.button("Manage operation sets", width="stretch"):
        st.switch_page("pages/abandon_operation_sets.py")

    st.divider()
    st.header("Options")
    reuse_existing = st.checkbox("Reuse project if it already exists", value=True)
    create_resources = st.checkbox(
        "Create team members & resource assignments", value=True,
        help="Looks up bookable resources by name from the Assignments sheet.",
    )
    create_dependencies = st.checkbox("Create task dependencies", value=True)
    operations_per_set = st.number_input(
        "Operations per set",
        min_value=1,
        max_value=MAX_OPS_PER_SET,
        value=MAX_OPS_PER_SET,
        step=1,
        help=(
            "Maximum tasks, dependencies, and assignments included in each "
            "OperationSet. Dataverse allows at most 200."
        ),
    )
    concurrent_operation_sets_text = st.text_input(
        "Concurrent operation sets",
        value="10",
        help=(
            "Projects are submitted in waves of this size. The next wave starts "
            "after every operation set in the current wave completes. Maximum: 10."
        ),
    )
    concurrent_operation_sets = 0
    concurrency_error = ""
    try:
        concurrent_operation_sets = int(concurrent_operation_sets_text)
        if not 1 <= concurrent_operation_sets <= 10:
            concurrency_error = "Enter a whole number from 1 to 10."
    except ValueError:
        concurrency_error = "Enter a whole number from 1 to 10."
    if concurrency_error:
        st.error(concurrency_error)

    polling_wait_text = st.text_input(
        "Wait time for execution polling",
        value="30",
        key="polling_wait_seconds_input_v3",
        help="Number of seconds to wait between operation-set status checks.",
    )
    polling_wait_seconds = 0
    polling_wait_error = ""
    try:
        polling_wait_seconds = int(polling_wait_text)
        if polling_wait_seconds < 1:
            polling_wait_error = "Enter a whole number greater than 0."
    except ValueError:
        polling_wait_error = "Enter a whole number greater than 0."
    if polling_wait_error:
        st.error(polling_wait_error)

    if not concurrency_error and not polling_wait_error:
        runtime_controller.update_settings(
            concurrent_operation_sets=concurrent_operation_sets,
            operations_per_set=int(operations_per_set),
            polling_wait_seconds=polling_wait_seconds,
            authorization_expires_at=st.session_state.token_expires_at,
        )


# --------------------------------------------------------------------------- #
# Step 2: Upload & parse
# --------------------------------------------------------------------------- #
st.header("2. Upload template")
uploaded = st.file_uploader(
    "Excel template (Projects, Tasks, Assignments, Dependencies sheets)",
    type=["xlsx", "xlsm"],
    key=f"workbook_uploader_{st.session_state.uploader_version}",
)

if uploaded is not None:
    try:
        new_uploader_selection = not st.session_state.uploader_has_file
        uploaded_bytes = uploaded.getvalue()
        uploaded_hash = hashlib.sha256(uploaded_bytes).hexdigest()
        uploaded_workbook = load_uploaded_workbook(uploaded_bytes)
        uploaded_manifest = [
            {"ProjectKey": project.key, "ProjectName": project.name}
            for project in uploaded_workbook.projects
        ]
        prior_file_exists = bool(
            st.session_state.uploaded_file_name
            or st.session_state.selected_project_manifest
        )
        runtime_before_upload = runtime_controller.snapshot()
        prior_execution_visible = bool(
            st.session_state.logs
            or st.session_state.execution_records
            or runtime_before_upload["logs"]
            or runtime_before_upload["execution_records"]
            or runtime_before_upload["finished"]
            or runtime_before_upload["error"]
        )
        file_identity_changed = prior_file_exists and (
            Path(uploaded.name).name != st.session_state.uploaded_file_name
            or bool(st.session_state.uploaded_file_hash)
            and uploaded_hash != st.session_state.uploaded_file_hash
        )
        is_new_file = file_identity_changed or (
            new_uploader_selection and prior_execution_visible
        )
        if is_new_file:
            runtime_controller.reset()
            if ACTIVE_CHECKPOINT_PATH.exists():
                replaced_at = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
                with CHECKPOINT_FILE_LOCK:
                    ACTIVE_CHECKPOINT_PATH.replace(
                        CHECKPOINT_DIR / f"replaced-upload-{replaced_at}.json"
                    )
            st.session_state.logs = []
            st.session_state.execution_records = []
            st.session_state.executed_v3_payloads = []
            st.session_state.executed_v3_responses = []
            st.session_state.show_v3_payloads = False
            st.session_state.show_v3_responses = False
            st.session_state.selected_project_manifest = []
            st.session_state.execution_directory = ""
            st.session_state.reauthentication_required = False
            st.session_state.resume_after_reauthentication = False
            st.session_state.validated_file_hash = ""
            st.session_state.validation_issues = []
            st.session_state.parameter_validation_messages = []
            st.session_state.validated_environment = ""
            st.session_state.validated_rule_version = 0
        st.session_state.workbook = uploaded_workbook
        st.session_state.uploaded_file_name = Path(uploaded.name).name
        st.session_state.uploaded_file_bytes = uploaded_bytes
        st.session_state.uploaded_file_hash = uploaded_hash
        if is_new_file or not st.session_state.selected_project_manifest:
            st.session_state.selected_project_manifest = uploaded_manifest
        st.session_state.uploader_has_file = True
        if is_new_file:
            st.rerun()
    except RuntimeError as exc:
        st.error(str(exc))
    except Exception as exc:  # noqa: BLE001
        st.error(f"Could not read the workbook: {exc}")
        st.session_state.workbook = None
else:
    if st.session_state.uploader_has_file:
        if runtime_controller.snapshot()["running"]:
            st.warning(
                "The execution is still running. Stop it safely before removing "
                "the uploaded file."
            )
        else:
            try:
                archive_current_execution_for_discard(environment_url=env_url)
                reset_upload_state(rotate_uploader=True)
            except (OSError, RuntimeError) as exc:
                st.error(
                    "Could not clear the current upload. Its execution state was "
                    f"preserved: {exc}"
                )
            else:
                st.rerun()

if st.session_state.uploaded_file_bytes and st.session_state.uploaded_file_name:
    st.download_button(
        "Download original uploaded workbook",
        data=st.session_state.uploaded_file_bytes,
        file_name=st.session_state.uploaded_file_name,
        mime=(
            "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
        ),
        width="stretch",
    )

wb: Workbook | None = st.session_state.workbook

if wb is not None:
    for warning in wb.warnings:
        st.warning(warning)

    # --- Step 3: Review --------------------------------------------------- #
    st.header("3. Review")
    if st.button(
        "Validate",
        type="primary",
        width="stretch",
        disabled=not token,
    ):
        st.session_state.validation_issues = validate_workbook(wb)
        validation_client = ProjectOperationsClient(env_url, token)
        try:
            st.session_state.parameter_validation_messages = (
                validation_client.validate_migration_parameters()
            )
            st.session_state.parameter_validation_messages.extend(
                validation_client.validate_project_references(
                    [
                        (
                            project.key,
                            project.customer,
                            project.company,
                            project.contracting_unit,
                            project.calendar,
                            project.manager,
                        )
                        for project in wb.projects
                    ]
                )
            )
            st.session_state.parameter_validation_messages.extend(
                validation_client.validate_assignment_roles(
                    [
                        (assignment.resource_name, assignment.role_name)
                        for assignment in wb.assignments
                    ]
                )
            )
        except Exception as exc:  # noqa: BLE001
            st.session_state.parameter_validation_messages = [
                "Could not validate Project Operations Parameters: " + str(exc)
            ]
        st.session_state.validated_file_hash = st.session_state.uploaded_file_hash
        st.session_state.validated_environment = env_url
        st.session_state.validated_rule_version = VALIDATION_RULE_VERSION

    validation_is_current = (
        bool(st.session_state.uploaded_file_hash)
        and st.session_state.validated_file_hash
        == st.session_state.uploaded_file_hash
        and st.session_state.validated_environment == env_url
        and st.session_state.validated_rule_version == VALIDATION_RULE_VERSION
    )
    st.subheader("Live validation")
    if not validation_is_current and not token:
        st.info(
            "Sign in and run validation for the currently uploaded file and "
            "environment."
        )
    if validation_is_current:
        combined_validation_issues = []
        template_project_keys = {
            f"Project {project.key}": project.key
            for project in wb.projects
            if project.key
        }
        for message in st.session_state.parameter_validation_messages:
            item, separator, issue = message.partition(": ")
            combined_validation_issues.append(
                {
                    "Sheet": "Project Operations Parameters",
                    "ProjectKey": template_project_keys.get(item, ""),
                    "Item": item if separator else "Project parameters",
                    "Issue": issue if separator else message,
                }
            )
        combined_validation_issues.extend(st.session_state.validation_issues)

    if validation_is_current and combined_validation_issues:
        numbered_issues = []
        for validation_number, issue in enumerate(
            combined_validation_issues,
            start=1,
        ):
            numbered_issues.append({"Validation": validation_number, **issue})
        st.warning(
            f"Validation issues found ({len(numbered_issues)}). It is recommended "
            "to fix issues before submitting the execution to Project Operations."
        )
        st.dataframe(
            pd.DataFrame(numbered_issues),
            hide_index=True,
            width="stretch",
            column_config={
                "Validation": st.column_config.NumberColumn(width="small"),
                "Sheet": st.column_config.TextColumn(width="small"),
                "ProjectKey": st.column_config.TextColumn(width="small"),
                "Item": st.column_config.TextColumn(width="medium"),
                "Issue": st.column_config.TextColumn(width="large"),
            },
        )
    elif validation_is_current:
        st.success("Validation passed. The current file is ready to submit.")

    if not wb.projects:
        st.error("No projects detected in the 'Projects' sheet.")
    else:
        st.subheader("Projects")
        projects_df = pd.DataFrame(
            [
                {
                    "ProjectKey": p.key,
                    "ProjectName": p.name,
                    "Company": p.company,
                    "ContractingUnit": p.contracting_unit,
                    "Customer": p.customer,
                    "Calendar": p.calendar,
                    "ProjectManager": p.manager,
                    "Start": p.start,
                    "Tasks": len(wb.tasks_for(p.key)),
                    "Assignments": len(wb.assignments_for(p.key)),
                    "Dependencies": len(wb.dependencies_for(p.key)),
                }
                for p in wb.projects
            ]
        )
        st.dataframe(projects_df, width="stretch", hide_index=True)

        options = [f"{p.key} - {p.name}" for p in wb.projects]
        selected_labels = st.multiselect(
            "Projects to submit", options=options, default=options
        )
        selected_keys = [
            p.key for p, label in zip(wb.projects, options) if label in selected_labels
        ]
        selected_key_set = set(selected_keys)
        selected_tasks = [
            task for task in wb.tasks if task.project_key in selected_key_set
        ]
        selected_assignments = [
            assignment
            for assignment in wb.assignments
            if assignment.project_key in selected_key_set
        ]
        selected_dependencies = [
            dependency
            for dependency in wb.dependencies
            if dependency.project_key in selected_key_set
        ]
        if (
            not runtime_controller.snapshot()["running"]
            and not ACTIVE_CHECKPOINT_PATH.exists()
        ):
            st.session_state.selected_project_manifest = [
                {"ProjectKey": project.key, "ProjectName": project.name}
                for project in wb.projects
                if project.key in selected_keys
            ]

        st.caption(
            f"Selected: {len(selected_keys)} project(s), "
            f"{len(selected_tasks)} task(s), "
            f"{len(selected_assignments)} assignment(s), and "
            f"{len(selected_dependencies)} dependency record(s)."
        )

        with st.expander(f"Tasks ({len(selected_tasks)})", expanded=False):
            st.dataframe(
                pd.DataFrame([t.__dict__ for t in selected_tasks]),
                width="stretch", hide_index=True,
            )
        with st.expander(
            f"Assignments ({len(selected_assignments)})", expanded=False
        ):
            st.dataframe(
                pd.DataFrame([a.__dict__ for a in selected_assignments]),
                width="stretch", hide_index=True,
            )
        with st.expander(
            f"Dependencies ({len(selected_dependencies)})", expanded=False
        ):
            st.dataframe(
                pd.DataFrame([d.__dict__ for d in selected_dependencies]),
                width="stretch", hide_index=True,
            )

        # --- Step 4: Submit ----------------------------------------------- #
        st.header("4. Submit to Project Operations")
        disabled = (
            not token
            or not selected_keys
            or bool(concurrency_error)
            or bool(polling_wait_error)
            or (authorization_near_expiry and token_refresh is None)
        )
        runtime_snapshot = runtime_controller.snapshot()
        submit_run_status, _ = determine_run_status(
            running=runtime_snapshot["running"],
            finished=runtime_snapshot["finished"],
            error=str(runtime_snapshot["error"] or ""),
            stopped=bool(
                runtime_snapshot["stopped"]
                or runtime_snapshot["stop_requested"]
            ),
            reauthentication_required=st.session_state.reauthentication_required,
            selected_projects=st.session_state.selected_project_manifest,
            records=runtime_snapshot["execution_records"],
            checkpoint_exists=ACTIVE_CHECKPOINT_PATH.exists(),
        )
        execution_actively_running = submit_run_status in {
            "RUNNING", "STOPPING - CHECKPOINTING"
        }
        if disabled and not execution_actively_running:
            if not token or not selected_keys:
                st.info(
                    "Provide a token and select at least one project to enable "
                    "submit."
                )

        disabled = disabled or execution_actively_running
        if st.button("🚀 Submit", type="primary", disabled=disabled, width="stretch"):
            st.session_state.logs = []
            st.session_state.executed_v3_payloads = []
            st.session_state.show_v3_payloads = False
            st.session_state.executed_v3_responses = []
            st.session_state.show_v3_responses = False
            st.session_state.execution_records = []
            st.session_state.reauthentication_required = False
            clear_execution_checkpoint()
            execution_started_at = datetime.now(timezone.utc).isoformat()
            run_timestamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
            run_dir = CHECKPOINT_DIR / run_timestamp
            run_dir.mkdir(parents=True, exist_ok=True)
            st.session_state.execution_directory = str(run_dir)
            if st.session_state.uploaded_file_bytes:
                (run_dir / st.session_state.uploaded_file_name).write_bytes(
                    st.session_state.uploaded_file_bytes
                )
            try:
                worker_token = token
                worker_workbook = wb
                worker_project_keys = list(selected_keys)
                worker_project_manifest = [
                    {"ProjectKey": project.key, "ProjectName": project.name}
                    for project in wb.projects
                    if project.key in worker_project_keys
                ]
                st.session_state.selected_project_manifest = worker_project_manifest
                worker_execution_directory = str(run_dir)
                worker_file_name = st.session_state.uploaded_file_name
                worker_execution_started_at = execution_started_at

                def run_upload(controller: RuntimeController) -> dict:
                    controller.add_log(
                        f"=== Execution started at {worker_execution_started_at} ==="
                    )
                    client = ProjectOperationsClient(
                        env_url,
                        worker_token,
                        log=controller.add_log,
                        token_refresh=token_refresh,
                    )

                    def worker_settings() -> dict[str, int | float]:
                        settings = controller.settings()
                        settings["authorization_expires_at"] = float(
                            refresh_state.get("expires_at")
                            or settings.get("authorization_expires_at")
                            or 0
                        )
                        return settings

                    def rotate_worker_authorization() -> dict[str, Any]:
                        access_token = refresh_worker_token(force=True)
                        return {
                            "access_token": access_token,
                            "expires_at": refresh_state["expires_at"],
                        }

                    def persist_upload_checkpoint(records: list[dict]) -> None:
                        controller.set_execution_records(records)
                        snapshot = controller.snapshot()
                        try:
                            write_execution_checkpoint(
                                "Upload in progress",
                                env_url,
                                worker_execution_directory,
                                worker_file_name,
                                records,
                                snapshot["logs"],
                                worker_project_manifest,
                                worker_execution_started_at,
                            )
                        except OSError as checkpoint_error:
                            controller.add_log(
                                "  ! Local checkpoint save failed; Dataverse "
                                "execution continues and the next round will retry: "
                                f"{checkpoint_error}"
                            )

                    try:
                        outcomes = submit_workbook(
                            client,
                            worker_workbook,
                            project_keys=worker_project_keys,
                            create_resources=create_resources,
                            create_dependencies=create_dependencies,
                            reuse_existing_project=reuse_existing,
                            concurrent_operation_sets=concurrent_operation_sets,
                            operations_per_set=int(operations_per_set),
                            polling_wait_seconds=polling_wait_seconds,
                            log=controller.add_log,
                            checkpoint=persist_upload_checkpoint,
                            settings_provider=worker_settings,
                            authorization_refresh=(
                                rotate_worker_authorization
                                if token_refresh is not None
                                else None
                            ),
                            stop_requested=controller.stop_requested,
                        )
                    except ExecutionStopped as exc:
                        controller.set_execution_records(client.execution_records)
                        controller.add_log(str(exc))
                        execution_ended_at = datetime.now(timezone.utc).isoformat()
                        controller.add_log(
                            f"=== Execution paused at {execution_ended_at} ==="
                        )
                        append_performance_summary(
                            controller,
                            client.execution_records,
                            worker_execution_started_at,
                            execution_ended_at,
                        )
                        snapshot = controller.snapshot()
                        write_execution_checkpoint(
                            "Stopped by user",
                            env_url,
                            worker_execution_directory,
                            worker_file_name,
                            client.execution_records,
                            snapshot["logs"],
                            worker_project_manifest,
                            worker_execution_started_at,
                        )
                        return {
                            "stopped": True,
                            "execution_records": client.execution_records,
                            "executed_v3_payloads": client.executed_v3_payloads,
                            "executed_v3_responses": client.executed_v3_responses,
                            "outcomes": [],
                        }
                    except Exception as exc:
                        controller.set_execution_records(client.execution_records)
                        controller.add_log(f"Execution failed and stopped: {exc}")
                        execution_ended_at = datetime.now(timezone.utc).isoformat()
                        controller.add_log(
                            f"=== Execution failed/paused at {execution_ended_at} ==="
                        )
                        append_performance_summary(
                            controller,
                            client.execution_records,
                            worker_execution_started_at,
                            execution_ended_at,
                        )
                        snapshot = controller.snapshot()
                        write_execution_checkpoint(
                            str(exc),
                            env_url,
                            worker_execution_directory,
                            worker_file_name,
                            client.execution_records,
                            snapshot["logs"],
                            worker_project_manifest,
                            worker_execution_started_at,
                        )
                        raise
                    snapshot = controller.snapshot()
                    completeness = project_completeness(
                        worker_project_manifest,
                        client.execution_records,
                    )
                    incomplete_projects = [
                        row for row in completeness
                        if row["Status"] != "Completed"
                    ]
                    execution_ended_at = datetime.now(timezone.utc).isoformat()
                    controller.add_log(
                        "=== Execution paused at "
                        f"{execution_ended_at} ==="
                        if incomplete_projects
                        else f"=== Execution finished at {execution_ended_at} ==="
                    )
                    append_performance_summary(
                        controller,
                        client.execution_records,
                        worker_execution_started_at,
                        execution_ended_at,
                    )
                    snapshot = controller.snapshot()
                    history_path = write_execution_history(
                        client.execution_records,
                        env_url,
                        worker_execution_directory,
                        worker_file_name,
                        snapshot["logs"],
                        worker_project_manifest,
                        getattr(client, "dataverse_requests", []),
                    )
                    if incomplete_projects:
                        checkpoint_reason = (
                            "Project preparation failed"
                            if not client.execution_records
                            else "Selected projects remain incomplete"
                        )
                        write_execution_checkpoint(
                            checkpoint_reason,
                            env_url,
                            worker_execution_directory,
                            worker_file_name,
                            client.execution_records,
                            snapshot["logs"],
                            worker_project_manifest,
                            worker_execution_started_at,
                        )
                    else:
                        clear_execution_checkpoint()
                    return {
                        "execution_records": client.execution_records,
                        "executed_v3_payloads": client.executed_v3_payloads,
                        "executed_v3_responses": client.executed_v3_responses,
                        "outcomes": outcomes,
                        "history_path": str(history_path),
                        "completeness": completeness,
                    }

                runtime_controller.start(run_upload)
                st.rerun()
            except Exception as exc:  # noqa: BLE001
                st.error(f"Could not start submission: {exc}")

        runtime_snapshot = runtime_controller.snapshot()
        if runtime_snapshot["finished"] and runtime_snapshot["error"]:
            st.error(f"Submission stopped: {runtime_snapshot['error']}")

        st.session_state.logs = runtime_snapshot["logs"]
        st.session_state.execution_records = runtime_snapshot["execution_records"]
        st.session_state.executed_v3_payloads = runtime_snapshot[
            "executed_v3_payloads"
        ]
        st.session_state.executed_v3_responses = runtime_snapshot[
            "executed_v3_responses"
        ]

        if st.session_state.executed_v3_payloads:
            if st.button("Show V3 request data", width="stretch"):
                st.session_state.show_v3_payloads = not st.session_state.show_v3_payloads

            if st.session_state.show_v3_payloads:
                payload_json = json.dumps(
                    st.session_state.executed_v3_payloads,
                    indent=2,
                    ensure_ascii=False,
                )
                st.caption(
                    f"{len(st.session_state.executed_v3_payloads)} request payload(s) sent "
                    "to msdyn_ExecuteOperationSetV3"
                )
                st.code(payload_json, language="json")

        if st.session_state.executed_v3_responses:
            if st.button("Show V3 response data", width="stretch"):
                st.session_state.show_v3_responses = not st.session_state.show_v3_responses

            if st.session_state.show_v3_responses:
                response_json = json.dumps(
                    st.session_state.executed_v3_responses,
                    indent=2,
                    ensure_ascii=False,
                )
                st.caption(
                    f"{len(st.session_state.executed_v3_responses)} response(s) from "
                    "msdyn_ExecuteOperationSetV3"
                )
                st.code(response_json, language="json")

runtime_snapshot = runtime_controller.snapshot()
previous_upload_available = (
    ACTIVE_CHECKPOINT_PATH.exists() and not runtime_snapshot["running"]
)
if previous_upload_available and not st.session_state.execution_records:
    try:
        paused_checkpoint = read_execution_checkpoint()
        st.session_state.execution_records = list(
            paused_checkpoint.get("ExecutionRecords") or []
        )
        st.session_state.logs = list(paused_checkpoint.get("Logs") or [])
        st.session_state.selected_project_manifest = list(
            paused_checkpoint.get("SelectedProjects") or []
        )
        st.session_state.execution_directory = str(
            paused_checkpoint.get("ExecutionDirectory") or ""
        )
        st.session_state.uploaded_file_name = str(
            paused_checkpoint.get("OriginalFileName") or ""
        )
        runtime_controller.restore(
            logs=st.session_state.logs,
            execution_records=st.session_state.execution_records,
        )
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        st.error(f"Could not load the paused execution checkpoint: {exc}")

if previous_upload_available:
    st.session_state.reauthentication_required = bool(
        not token or (authorization_near_expiry and token_refresh is None)
    )
    paused_checkpoint = {}
    try:
        paused_checkpoint = read_execution_checkpoint()
        paused_reason = str(paused_checkpoint.get("Reason") or "")
        paused_records = list(paused_checkpoint.get("ExecutionRecords") or [])
        paused_manifest = list(paused_checkpoint.get("SelectedProjects") or [])
    except (OSError, ValueError, json.JSONDecodeError):
        paused_reason = ""
        paused_records = []
        paused_manifest = []
    paused_completeness = project_completeness(paused_manifest, paused_records)
    paused_completed = sum(
        row["Status"] == "Completed" for row in paused_completeness
    )
    paused_not_started = sum(
        row["Status"] == "Not started" for row in paused_completeness
    )
    paused_started_at = str(
        paused_checkpoint.get("ExecutionStartedAtUtc") or ""
    )
    paused_ended_at = str(paused_checkpoint.get("ExecutionEndedAtUtc") or "")
    if not paused_started_at:
        known_starts = sorted(
            str(record.get("SubmissionStartedAtUtc") or "")
            for record in paused_records
            if record.get("SubmissionStartedAtUtc")
        )
        paused_started_at = known_starts[0] if known_starts else "Unknown"
    st.caption(
        f"Execution started: {paused_started_at} | "
        f"Last ended/paused: {paused_ended_at or 'Not recorded'}"
    )
    if paused_reason == "Stopped by user":
        st.warning(
            "This execution was stopped safely. Continue to reconcile submitted "
            "operation sets and process the retained plan. If the workbook itself "
            "must be corrected, discard this execution and upload the corrected file."
        )
    elif paused_reason == "Project preparation failed":
        st.warning(
            f"The latest execution could not prepare any operation sets "
            f"({paused_completed}/{len(paused_manifest)} projects complete). "
            "Review the activity log for the preparation error. Continue to retry "
            "the project after correcting the Dataverse issue, or discard this "
            "execution to start over."
        )
    elif paused_reason == "Selected projects remain incomplete after reconciliation":
        st.warning(
            f"Reconciliation finished: {paused_completed}/{len(paused_manifest)} "
            f"project(s) are complete and {paused_not_started} were not started. "
            "Continue to submit the projects that were never started, or discard "
            "the checkpoint to start over."
        )
    elif paused_reason == RECONCILIATION_ERROR_PAUSE_REASON:
        st.warning(
            "Reconciliation finished with project errors, so execution is paused. "
            "Errored projects will not be retried. Review them below and choose "
            "whether to continue with projects that were never started."
        )
    elif st.session_state.reauthentication_required:
        st.warning(
            "A previous upload has a recoverable checkpoint. Reauthenticate, then "
            "continue it. Known operation sets will be reconciled before projects "
            "that were never started are submitted."
        )
    else:
        st.warning(
            f"A previous upload has a recoverable checkpoint ({paused_completed}/"
            f"{len(paused_manifest)} projects complete). Continue to reconcile known "
            "operation sets and submit projects that were never started, or discard "
            "the checkpoint to start over."
        )
    paused_error_rows = execution_error_rows(paused_records)
    if paused_error_rows:
        st.subheader("Projects with errors")
        st.dataframe(
            pd.DataFrame(paused_error_rows), hide_index=True, width="stretch"
        )
    continue_column, discard_column = st.columns(2)
    with continue_column:
        if st.button(
            "Continue remaining projects"
            if paused_reason in {
                "Selected projects remain incomplete after reconciliation",
                RECONCILIATION_ERROR_PAUSE_REASON,
            }
            else (
                "Continue stopped execution"
                if paused_reason == "Stopped by user"
                else "Continue previous upload"
            ),
            disabled=(
                not st.session_state.token
                or (authorization_near_expiry and token_refresh is None)
            ),
            type="primary",
            width="stretch",
        ):
            st.session_state.resume_after_reauthentication = True
            st.rerun()
    with discard_column:
        if st.button(
            "Discard and start over" if paused_reason == "Stopped by user"
            else "Discard previous upload",
            width="stretch",
        ):
            try:
                archive_current_execution_for_discard(paused_checkpoint)
                reset_upload_state(rotate_uploader=True)
            except (OSError, RuntimeError) as exc:
                st.error(
                    "Could not archive the previous execution. Nothing was "
                    f"discarded: {exc}"
                )
            else:
                st.rerun()

if (
    st.session_state.resume_after_reauthentication
    and st.session_state.token
    and st.session_state.execution_records
):
    st.session_state.resume_after_reauthentication = False
    st.session_state.reauthentication_required = False
    resume_token = st.session_state.token
    resume_records = st.session_state.execution_records
    resume_manifest = list(st.session_state.selected_project_manifest)
    resume_directory = st.session_state.execution_directory
    resume_file_name = st.session_state.uploaded_file_name
    resume_create_resources = create_resources
    resume_create_dependencies = create_dependencies
    resume_reuse_existing = reuse_existing
    resume_reason = paused_reason
    resume_execution_started_at = paused_started_at

    def run_continuation(controller: RuntimeController) -> dict:
        started_at = datetime.now(timezone.utc).isoformat()
        controller.add_log(
            f"=== User restarted previous execution at {started_at} ==="
        )
        controller.add_log(
            f"Restart reason='{resume_reason or 'not recorded'}'; "
            f"selectedProjects={len(resume_manifest)}; "
            f"retainedOperationSets={len(resume_records)}; "
            f"concurrency={controller.settings()['concurrent_operation_sets']}; "
            f"operationsPerSet={controller.settings()['operations_per_set']}; "
            f"pollingWait={controller.settings()['polling_wait_seconds']}s."
        )
        controller.add_log(
            f"Original execution start remains {resume_execution_started_at}."
        )
        existing_dataverse_requests: list[dict] = []
        dataverse_requests_path = Path(resume_directory) / "dataverse-requests.json"
        if dataverse_requests_path.is_file():
            try:
                existing_dataverse_requests = list(
                    json.loads(dataverse_requests_path.read_text(encoding="utf-8"))
                )
            except (OSError, TypeError, ValueError, json.JSONDecodeError):
                controller.add_log(
                    "  ! Existing Dataverse request history could not be loaded; "
                    "continuation requests will still be recorded."
                )
        resume_client = ProjectOperationsClient(
            env_url,
            resume_token,
            log=controller.add_log,
            token_refresh=token_refresh,
            dataverse_requests=existing_dataverse_requests,
        )
        def continuation_settings() -> dict[str, int | float]:
            settings = controller.settings()
            settings["authorization_expires_at"] = float(
                refresh_state.get("expires_at")
                or settings.get("authorization_expires_at")
                or 0
            )
            return settings

        def rotate_continuation_authorization() -> dict[str, Any]:
            access_token = refresh_worker_token(force=True)
            return {
                "access_token": access_token,
                "expires_at": refresh_state["expires_at"],
            }

        def persist_continuation_checkpoint(records: list[dict]) -> None:
            controller.set_execution_records(records)
            try:
                write_execution_checkpoint(
                    "Continuation in progress",
                    env_url,
                    resume_directory,
                    resume_file_name,
                    records,
                    controller.logs(),
                    resume_manifest,
                )
            except OSError as checkpoint_error:
                controller.add_log(
                    "  ! Local continuation checkpoint save failed; execution "
                    f"continues and the next wave will retry: {checkpoint_error}"
                )

        try:
            resume_summary = resume_execution_records(
                resume_client,
                resume_records,
                polling_wait_seconds=controller.settings()[
                    "polling_wait_seconds"
                ],
                log=controller.add_log,
                settings_provider=continuation_settings,
                checkpoint=persist_continuation_checkpoint,
                authorization_refresh=(
                    rotate_continuation_authorization
                    if token_refresh is not None
                    else None
                ),
                stop_requested=controller.stop_requested,
            )
            reconciliation_errors = execution_error_rows(
                resume_client.execution_records
            )
            if (
                reconciliation_errors
                and resume_reason != RECONCILIATION_ERROR_PAUSE_REASON
            ):
                controller.add_log(
                    f"Reconciliation completed with {len(reconciliation_errors)} "
                    "project error(s). Errored projects will not be retried."
                )
                for error_row in reconciliation_errors:
                    controller.add_log(
                        f"  ERROR | {error_row['Project ID']} - "
                        f"{error_row['Project name']} | {error_row['Error']}"
                    )
                execution_ended_at = datetime.now(timezone.utc).isoformat()
                controller.add_log(
                    "Execution is paused. User confirmation is required before "
                    "never-started projects are submitted."
                )
                controller.add_log(
                    f"=== Execution paused at {execution_ended_at} ==="
                )
                append_performance_summary(
                    controller,
                    resume_client.execution_records,
                    resume_execution_started_at,
                    execution_ended_at,
                )
                controller.set_execution_records(resume_client.execution_records)
                write_execution_checkpoint(
                    RECONCILIATION_ERROR_PAUSE_REASON,
                    env_url,
                    resume_directory,
                    resume_file_name,
                    resume_client.execution_records,
                    controller.logs(),
                    resume_manifest,
                    resume_execution_started_at,
                )
                return {
                    "execution_records": resume_client.execution_records,
                    "executed_v3_payloads": resume_client.executed_v3_payloads,
                    "executed_v3_responses": resume_client.executed_v3_responses,
                    "paused_after_reconciliation": True,
                }
            reconciled_completeness = project_completeness(
                resume_manifest,
                resume_client.execution_records,
            )
            not_started_keys = [
                str(row.get("ProjectKey") or "")
                for row in reconciled_completeness
                if row["Status"] == "Not started" and row.get("ProjectKey")
            ]
            if not_started_keys:
                workbook_path = Path(resume_directory) / resume_file_name
                if not workbook_path.is_file():
                    raise FileNotFoundError(
                        "Cannot continue unstarted projects because the saved "
                        f"workbook was not found: {workbook_path}"
                    )
                controller.add_log(
                    f"Reconciliation complete. Submitting {len(not_started_keys)} "
                    "project(s) that were never started."
                )
                resume_workbook = load_workbook(str(workbook_path))
                remaining_outcomes = submit_workbook(
                    resume_client,
                    resume_workbook,
                    project_keys=not_started_keys,
                    create_resources=resume_create_resources,
                    create_dependencies=resume_create_dependencies,
                    reuse_existing_project=resume_reuse_existing,
                    concurrent_operation_sets=controller.settings()[
                        "concurrent_operation_sets"
                    ],
                    operations_per_set=controller.settings()["operations_per_set"],
                    polling_wait_seconds=controller.settings()[
                        "polling_wait_seconds"
                    ],
                    log=controller.add_log,
                    checkpoint=persist_continuation_checkpoint,
                    settings_provider=continuation_settings,
                    authorization_refresh=(
                        rotate_continuation_authorization
                        if token_refresh is not None
                        else None
                    ),
                    stop_requested=controller.stop_requested,
                )
                resume_summary["remaining_projects_attempted"] = len(
                    remaining_outcomes
                )
            else:
                controller.add_log(
                    "Reconciliation found no never-started projects to submit."
                )
        except ExecutionStopped as exc:
            controller.set_execution_records(resume_client.execution_records)
            controller.add_log(str(exc))
            execution_ended_at = datetime.now(timezone.utc).isoformat()
            controller.add_log(
                f"=== Execution paused at {execution_ended_at} ==="
            )
            append_performance_summary(
                controller,
                resume_client.execution_records,
                resume_execution_started_at,
                execution_ended_at,
            )
            snapshot = controller.snapshot()
            write_execution_checkpoint(
                "Stopped by user",
                env_url,
                resume_directory,
                resume_file_name,
                resume_client.execution_records,
                snapshot["logs"],
                resume_manifest,
                resume_execution_started_at,
            )
            return {
                "stopped": True,
                "execution_records": resume_client.execution_records,
                "executed_v3_payloads": resume_client.executed_v3_payloads,
                "executed_v3_responses": resume_client.executed_v3_responses,
            }
        except Exception as exc:
            controller.add_log(f"Continuation failed and stopped: {exc}")
            execution_ended_at = datetime.now(timezone.utc).isoformat()
            controller.add_log(
                f"=== Execution failed/paused at {execution_ended_at} ==="
            )
            append_performance_summary(
                controller,
                resume_client.execution_records,
                resume_execution_started_at,
                execution_ended_at,
            )
            snapshot = controller.snapshot()
            write_execution_checkpoint(
                str(exc),
                env_url,
                resume_directory,
                resume_file_name,
                resume_client.execution_records,
                snapshot["logs"],
                resume_manifest,
                resume_execution_started_at,
            )
            raise
        controller.set_execution_records(resume_client.execution_records)
        completeness = project_completeness(
            resume_manifest,
            resume_client.execution_records,
        )
        incomplete_projects = [
            row for row in completeness if row["Status"] != "Completed"
        ]
        completed_projects = len(completeness) - len(incomplete_projects)
        controller.add_log(
            f"Continuation finished: {completed_projects}/{len(completeness)} "
            f"selected project(s) complete; {len(incomplete_projects)} incomplete."
        )
        execution_ended_at = datetime.now(timezone.utc).isoformat()
        controller.add_log(
            "=== Execution paused at "
            f"{execution_ended_at} ==="
            if incomplete_projects
            else f"=== Execution finished at {execution_ended_at} ==="
        )
        append_performance_summary(
            controller,
            resume_client.execution_records,
            resume_execution_started_at,
            execution_ended_at,
        )
        snapshot = controller.snapshot()
        history_path = write_execution_history(
            resume_client.execution_records,
            env_url,
            resume_directory,
            resume_file_name,
            snapshot["logs"],
            resume_manifest,
            getattr(resume_client, "dataverse_requests", []),
        )
        if incomplete_projects:
            write_execution_checkpoint(
                "Selected projects remain incomplete after reconciliation",
                env_url,
                resume_directory,
                resume_file_name,
                resume_client.execution_records,
                snapshot["logs"],
                resume_manifest,
            )
        else:
            clear_execution_checkpoint()
        return {
            "execution_records": resume_client.execution_records,
            "executed_v3_payloads": resume_client.executed_v3_payloads,
            "executed_v3_responses": resume_client.executed_v3_responses,
            "completeness": completeness,
            "history_path": str(history_path),
            "resume_summary": resume_summary,
        }

    try:
        runtime_controller.start(run_continuation, preserve_state=True)
    except RuntimeError:
        pass
    st.rerun()

runtime_snapshot = runtime_controller.snapshot()
if runtime_snapshot["logs"] or runtime_snapshot["execution_records"]:
    st.session_state.logs = runtime_snapshot["logs"]
    st.session_state.execution_records = runtime_snapshot["execution_records"]
    st.session_state.executed_v3_payloads = runtime_snapshot[
        "executed_v3_payloads"
    ]
    st.session_state.executed_v3_responses = runtime_snapshot[
        "executed_v3_responses"
    ]
if runtime_snapshot["finished"] and runtime_snapshot["error"]:
    st.session_state.reauthentication_required = ACTIVE_CHECKPOINT_PATH.exists()


live_refresh_interval = "5s" if runtime_snapshot["running"] else None


@st.fragment(run_every=live_refresh_interval)
def show_live_execution() -> None:
    snapshot = runtime_controller.snapshot()
    if live_refresh_interval and not snapshot["running"]:
        # The worker completed after this fragment was created. Re-run the
        # full app once so the next fragment is rendered without a timer.
        st.rerun()
    records = snapshot["execution_records"]
    logs = snapshot["logs"]
    if not records and ACTIVE_CHECKPOINT_PATH.exists():
        try:
            checkpoint = read_execution_checkpoint()
            records = list(checkpoint.get("ExecutionRecords") or [])
            logs = list(checkpoint.get("Logs") or [])
        except (OSError, ValueError, json.JSONDecodeError):
            return
    selected_projects = st.session_state.selected_project_manifest
    if not records and not logs and not selected_projects:
        return

    preparation_errors = preparation_error_rows(logs)
    preparation_errors_by_key = {
        row["Project ID"]: row for row in preparation_errors
    }

    run_status, completeness = determine_run_status(
        running=snapshot["running"],
        finished=snapshot["finished"],
        error=str(snapshot["error"] or ""),
        stopped=bool(snapshot["stopped"] or snapshot["stop_requested"]),
        reauthentication_required=st.session_state.reauthentication_required,
        selected_projects=selected_projects,
        records=records,
        checkpoint_exists=ACTIVE_CHECKPOINT_PATH.exists(),
    )
    completed_projects = sum(
        row["Status"] == "Completed" for row in completeness
    )
    total_projects = len(completeness)
    remaining_projects = total_projects - completed_projects

    status_message = (
        f"{run_status} | Projects: {completed_projects}/{total_projects} complete"
        f" | Remaining: {remaining_projects}"
    )
    if run_status == "COMPLETE":
        st.success(
            status_message
            + " | The entire selected file has been processed successfully."
        )
    elif run_status == "RUNNING":
        st.info(status_message + " | Execution is still in progress.")
        if not st.session_state.uploader_has_file:
            st.warning(
                "The workbook is not selected in this browser session, but the "
                "execution is retained and continues in the background. Opening "
                "another tab or reconnecting does not cancel submitted Dataverse "
                "work; use Stop execution safely to pause it."
            )
        if st.button(
            "⏹ Stop execution safely",
            key="stop_execution_live",
            type="primary",
            width="stretch",
        ):
            runtime_controller.request_stop()
            st.warning(
                "Stop requested. No further operation sets will be submitted. "
                "Current work is being checkpointed."
            )
    elif run_status == "STOPPING - CHECKPOINTING":
        st.warning(status_message + " | Stop requested; checkpointing now.")
    elif run_status.startswith("PAUSED"):
        st.warning(status_message + " | User action is required to continue.")
    elif run_status in {"FAILED", "INCOMPLETE"}:
        st.error(status_message + " | The entire selected file was not processed.")
    else:
        st.info(status_message)

    visible_records = [
        record for record in records
        if record.get("Round") is not None
        or str(record.get("Status") or "") != "Planned"
    ]
    project_counts: dict[tuple[str, str], dict[str, int]] = {}
    for record in records:
        if str(record.get("Status") or "").startswith("Superseded"):
            continue
        project_identity = (
            str(record.get("ProjectKey") or ""),
            str(record.get("Project") or ""),
        )
        counts = project_counts.setdefault(
            project_identity,
            {"Tasks": 0, "Assignments": 0, "Dependencies": 0},
        )
        if record.get("ProjectTaskCount") is not None:
            counts["Tasks"] = max(
                counts["Tasks"], int(record.get("ProjectTaskCount") or 0)
            )
            counts["Assignments"] = max(
                counts["Assignments"],
                int(record.get("ProjectAssignmentCount") or 0),
            )
            counts["Dependencies"] = max(
                counts["Dependencies"],
                int(record.get("ProjectDependencyCount") or 0),
            )
            continue
        for entity in record.get("Payload", {}).get(
            "CreateEntityCollection", []
        ):
            entity_type = str(entity.get("@odata.type") or "").lower()
            if entity_type.endswith("msdyn_projecttask"):
                counts["Tasks"] += 1
            elif entity_type.endswith("msdyn_resourceassignment"):
                counts["Assignments"] += 1
            elif entity_type.endswith("msdyn_projecttaskdependency"):
                counts["Dependencies"] += 1
    live_rows = []
    for record in visible_records:
        recovery_lookups = list(record.get("RecoveryLookups") or [])
        latest_recovery = recovery_lookups[-1] if recovery_lookups else {}
        counts = project_counts.get(
            (
                str(record.get("ProjectKey") or ""),
                str(record.get("Project") or ""),
            ),
            {"Tasks": 0, "Assignments": 0, "Dependencies": 0},
        )
        live_rows.append({
            "Round": record.get("Round"),
            "Slot": record.get("Slot"),
            "Project": record.get("Project", ""),
            "ProjectKey": record.get("ProjectKey", ""),
            "ProjectId": record.get("ProjectId", ""),
            "Batch": record.get("Batch"),
            "Operations": record.get("OperationCount"),
            "Tasks": counts["Tasks"],
            "Assignments": counts["Assignments"],
            "Dependencies": counts["Dependencies"],
            "OperationSetId": record.get("OperationSetId", ""),
            "Status": record.get("Status", ""),
            "Error": str(record.get("Error") or ""),
            "SubmittedAtUtc": record.get("SubmissionFinishedAtUtc", ""),
            "PollingStartedAtUtc": record.get("PollingStartedAtUtc", ""),
            "PollingFinishedAtUtc": record.get("PollingFinishedAtUtc", ""),
            "RecoveryAttempts": len(recovery_lookups),
            "LatestRecoveryResult": latest_recovery.get("Result", ""),
            "LatestRecoveryAtUtc": latest_recovery.get("AttemptedAtUtc", ""),
        })
    recorded_project_keys = {
        str(record.get("ProjectKey") or "") for record in records
    }
    completeness_by_key = {
        str(row.get("ProjectKey") or ""): row for row in completeness
    }
    for project in selected_projects:
        project_key = str(project.get("ProjectKey") or "")
        if project_key in recorded_project_keys:
            continue
        failure = preparation_errors_by_key.get(project_key)
        status = str(
            completeness_by_key.get(project_key, {}).get("Status") or "Not started"
        )
        if failure:
            status = "Failed during preparation"
        elif snapshot["running"]:
            status = "Preparing / not yet submitted"
        live_rows.append({
            "Round": None,
            "Slot": None,
            "Project": project.get("ProjectName", ""),
            "ProjectKey": project_key,
            "ProjectId": "",
            "Batch": None,
            "Operations": 0,
            "Tasks": 0,
            "Assignments": 0,
            "Dependencies": 0,
            "OperationSetId": "",
            "Status": status,
            "Error": failure["Error"] if failure else "",
            "SubmittedAtUtc": "",
            "PollingStartedAtUtc": "",
            "PollingFinishedAtUtc": "",
            "RecoveryAttempts": 0,
            "LatestRecoveryResult": "",
            "LatestRecoveryAtUtc": "",
        })
    live_rows.sort(
        key=lambda row: (
            row["Round"] if row["Round"] is not None else float("inf"),
            row["Slot"] if row["Slot"] is not None else float("inf"),
            str(row["Project"]).casefold(),
        )
    )

    completed = sum(
        str(record.get("Status") or "").startswith("Completed")
        for record in records
    )
    pending = sum(
        not str(record.get("Status") or "").startswith((
            "Completed", "Superseded", "Failed", "Abandoned"
        ))
        for record in records
    )
    execution_is_live = snapshot["running"]
    st.header("Live execution" if execution_is_live else "Execution summary")
    st.caption(
        f"{run_status} | {completed} operation sets completed | {pending} pending | "
        f"{len(records)} known operation set(s) | {len(logs)} log entries"
    )
    if live_rows:
        st.dataframe(
            pd.DataFrame(live_rows),
            hide_index=True,
            width="stretch",
            column_config={
                "Round": st.column_config.NumberColumn(width="small"),
                "Slot": st.column_config.NumberColumn(width="small"),
                "Project": st.column_config.TextColumn(width="medium"),
                "ProjectKey": st.column_config.TextColumn(width="small"),
                "ProjectId": st.column_config.TextColumn(width="medium"),
                "Batch": st.column_config.NumberColumn(width="small"),
                "Operations": st.column_config.NumberColumn(width="small"),
                "Tasks": st.column_config.NumberColumn(width="small"),
                "Assignments": st.column_config.NumberColumn(width="small"),
                "Dependencies": st.column_config.NumberColumn(width="small"),
                "OperationSetId": st.column_config.TextColumn(width="medium"),
                "Status": st.column_config.TextColumn(width="medium"),
                "Error": st.column_config.TextColumn(width="large"),
                "RecoveryAttempts": st.column_config.NumberColumn(width="small"),
                "LatestRecoveryResult": st.column_config.TextColumn(width="medium"),
            },
        )
    error_rows = execution_error_rows(records)
    known_error_projects = {
        str(row.get("Project ID") or "") for row in error_rows
    }
    error_rows.extend(
        row for row in preparation_errors
        if row["Project ID"] not in known_error_projects
    )
    if error_rows:
        st.subheader("Projects with errors")
        st.dataframe(
            pd.DataFrame(error_rows), hide_index=True, width="stretch"
        )
    if logs:
        activity_log = "\n".join(logs)
        st.subheader("Activity log (live)" if execution_is_live else "Activity log")
        st.caption(
            f"All {len(logs)} messages are shown. Use the copy control in the "
            "log or download the text file for external review."
        )
        st.markdown(
            """
            <style>
            div[data-testid="stCode"] button {
                right: 1.75rem !important;
            }
            div[data-testid="stCode"] pre {
                padding-right: 4rem !important;
                overflow: auto !important;
            }
            </style>
            """,
            unsafe_allow_html=True,
        )
        st.code(activity_log, language="text", height=500, wrap_lines=True)
        st.download_button(
            "Download current activity log",
            data=activity_log,
            file_name="schedule-import-activity-log.txt",
            mime="text/plain",
            width="stretch",
            key="download-live-activity-log",
        )


show_live_execution()
