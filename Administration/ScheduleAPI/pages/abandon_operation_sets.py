from __future__ import annotations

import os
import re
import uuid

import pandas as pd
import streamlit as st

from po_client import ProjectOperationsClient, ProjectOperationsError


DEFAULT_ENV_URL = os.getenv("DATAVERSE_ENVIRONMENT_URL", "")

st.set_page_config(page_title="Abandon operation sets", page_icon="🗑️", layout="wide")

if st.button("Back to schedule import"):
    st.switch_page("app.py")

st.title("Abandon operation sets")

env_url = st.text_input(
    "Environment URL",
    value=st.session_state.get("env_url", DEFAULT_ENV_URL),
    placeholder="https://yourorg.crm.dynamics.com",
    help="The Dataverse organization URL.",
)
token = st.text_input(
    "Access token (Bearer)",
    value=st.session_state.get("token", ""),
    type="password",
    help="A Dataverse user access token. Do not include the Bearer prefix.",
)
raw_ids = st.text_area(
    "Operation set IDs",
    height=180,
    placeholder="Enter one GUID per line, or separate GUIDs with commas.",
)


def parse_operation_set_ids(value: str) -> tuple[list[str], list[str]]:
    valid: list[str] = []
    invalid: list[str] = []
    seen: set[str] = set()
    for candidate in re.split(r"[\s,;]+", value.strip()):
        if not candidate:
            continue
        try:
            operation_set_id = str(uuid.UUID(candidate.strip("{}")))
        except ValueError:
            invalid.append(candidate)
            continue
        if operation_set_id not in seen:
            seen.add(operation_set_id)
            valid.append(operation_set_id)
    return valid, invalid


operation_set_ids, invalid_ids = parse_operation_set_ids(raw_ids)
if invalid_ids:
    st.error("Invalid operation set ID(s): " + ", ".join(invalid_ids))
elif operation_set_ids:
    st.caption(f"{len(operation_set_ids)} unique operation set(s) ready.")

confirmed = st.checkbox("I understand these operation sets will be abandoned.")
disabled = not env_url or not token or not operation_set_ids or bool(invalid_ids) or not confirmed

if st.button("Abandon operation sets", type="primary", disabled=disabled):
    client = ProjectOperationsClient(env_url, token)
    results: list[dict[str, str]] = []
    progress = st.progress(0)

    for index, operation_set_id in enumerate(operation_set_ids, start=1):
        try:
            client.post(
                "msdyn_AbandonOperationSetV1",
                {"OperationSetId": operation_set_id},
            )
            results.append({"OperationSetId": operation_set_id, "Status": "Abandoned", "Error": ""})
        except ProjectOperationsError as exc:
            results.append({"OperationSetId": operation_set_id, "Status": "Failed", "Error": str(exc)})
        progress.progress(index / len(operation_set_ids))

    failed = sum(result["Status"] == "Failed" for result in results)
    if failed:
        st.error(f"{failed} of {len(results)} operation set(s) failed.")
    else:
        st.success(f"Abandoned {len(results)} operation set(s).")
    st.dataframe(pd.DataFrame(results), width="stretch", hide_index=True)