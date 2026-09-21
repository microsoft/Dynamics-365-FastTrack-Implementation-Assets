"""
Excel loader for the Project Operations Schedule Import template.

The template is a small relational model spread across four data sheets
(plus an ``Instructions`` sheet that is ignored):

* ``Projects``     - one row per project (keyed by ``ProjectId``)
* ``Tasks``        - one row per task (keyed by ``ProjectId`` + ``TaskKey``)
* ``Assignments``  - task <-> resource assignments
* ``Dependencies`` - task predecessor/successor links

Columns are detected by *header name* (case-insensitive, punctuation-insensitive)
so the loader keeps working if column order changes between template versions.
"""
from __future__ import annotations

import io
import re
from dataclasses import dataclass, field
from datetime import datetime, date
from typing import Any

import pandas as pd

# --------------------------------------------------------------------------- #
# Header aliasing
# --------------------------------------------------------------------------- #

_PROJECT_ALIASES: dict[str, list[str]] = {
    "key": ["projectid", "project id", "projectkey", "project key", "key"],
    "name": ["projectname", "project name", "name", "subject"],
    "company": ["owningcompany", "owning company", "companyname", "company name", "company", "company code"],
    "contracting_unit": [
        "contractingunit",
        "contracting unit",
        "organizationalunit",
        "organizational unit",
    ],
    "customer": ["customeraccount", "customer account", "customername", "customer name", "customer", "account", "account name"],
    "calendar": ["calendarname", "calendar name", "calendar", "work hour template", "workhourtemplate"],
    "manager": ["projectmanager", "project manager", "manager", "pm"],
    "start": ["projectstart", "project start", "scheduled start", "scheduledstart", "start date", "start"],
}

_TASK_ALIASES: dict[str, list[str]] = {
    "project_key": ["projectid", "project id", "projectkey", "project key", "project"],
    "task_key": ["taskkey", "task key", "key", "taskid", "task id", "nr", "number"],
    "name": ["taskname", "task name", "task", "name", "subject"],
    "task_col1": ["taskcol1", "task col1"],
    "project_bucket": ["projectbucket", "project bucket", "bucket"],
    "parent_task_key": ["parenttaskkey", "parent task key", "parent task", "parenttask", "parent", "parent key"],
    "effort": ["efforthours", "effort hours", "effort", "hours", "work"],
    "start": ["scheduledstart", "scheduled start", "start date", "start"],
    "end": ["scheduledend", "scheduled end", "end date", "end", "finish"],
    "outline_level": ["outlinelevel", "outline level", "level", "outline"],
}

_ASSIGNMENT_ALIASES: dict[str, list[str]] = {
    "project_key": ["projectid", "project id", "projectkey", "project key", "project"],
    "assignment_key": ["assignmentkey", "assignment key", "key", "assignment"],
    "task_key": ["taskkey", "task key", "task"],
    "resource_name": ["resourcename", "resource name", "resource", "assigned to", "assignedto"],
    "role_name": [
        "rolename",
        "role name",
        "role",
        "projectrole",
        "project role",
        "resourcerole",
        "resource role",
    ],
}

_DEPENDENCY_ALIASES: dict[str, list[str]] = {
    "project_key": ["projectid", "project id", "projectkey", "project key", "project"],
    "predecessor_task_key": ["predecessortaskkey", "predecessor task key", "predecessor", "predecessortask", "from", "from task"],
    "successor_task_key": ["successortaskkey", "successor task key", "successor", "successortask", "to", "to task"],
    "link_type": ["linktype", "link type", "type", "dependency type"],
}


def _norm(text: Any) -> str:
    if text is None:
        return ""
    s = str(text).strip().lower()
    s = re.sub(r"[\s_\-/().]+", " ", s)
    return s.strip()


def _match_field(value: str, aliases: dict[str, list[str]]) -> str | None:
    n = _norm(value)
    if not n:
        return None
    for logical, names in aliases.items():
        if n in names:
            return logical
    for logical, names in aliases.items():
        for name in names:
            if n == name or n.startswith(name) or name.startswith(n):
                return logical
    return None


# --------------------------------------------------------------------------- #
# Data structures
# --------------------------------------------------------------------------- #

@dataclass
class ProjectInfo:
    key: str = ""
    name: str = ""
    company: str = ""
    contracting_unit: str = ""
    customer: str = ""
    calendar: str = ""
    manager: str = ""
    start: str | None = None


@dataclass
class TaskRow:
    project_key: str
    task_key: str
    name: str
    task_col1: str | None = None
    parent_task_key: str | None = None
    effort: float | None = None
    start: str | None = None
    end: str | None = None
    outline_level: int | None = None
    project_bucket: str | None = None


@dataclass
class AssignmentRow:
    project_key: str
    assignment_key: str
    task_key: str
    resource_name: str
    role_name: str = ""


@dataclass
class DependencyRow:
    project_key: str
    predecessor_task_key: str
    successor_task_key: str
    link_type: str = "FinishToStart"


@dataclass
class Workbook:
    projects: list[ProjectInfo] = field(default_factory=list)
    tasks: list[TaskRow] = field(default_factory=list)
    assignments: list[AssignmentRow] = field(default_factory=list)
    dependencies: list[DependencyRow] = field(default_factory=list)
    warnings: list[str] = field(default_factory=list)

    def tasks_for(self, project_key: str) -> list[TaskRow]:
        return [t for t in self.tasks if t.project_key == project_key]

    def assignments_for(self, project_key: str) -> list[AssignmentRow]:
        return [a for a in self.assignments if a.project_key == project_key]

    def dependencies_for(self, project_key: str) -> list[DependencyRow]:
        return [d for d in self.dependencies if d.project_key == project_key]


def validate_workbook(workbook: Workbook) -> list[dict[str, str]]:
    """Return workbook validation findings in a UI-friendly shape."""
    issues: list[dict[str, str]] = []
    seen_issues: set[tuple[str, str, str, str]] = set()

    def add(
        sheet: str,
        item: str,
        issue: str,
        project_key: str = "",
    ) -> None:
        identity = (sheet, project_key, item, issue)
        if identity not in seen_issues:
            seen_issues.add(identity)
            issues.append(
                {
                    "Sheet": sheet,
                    "ProjectKey": project_key,
                    "Item": item,
                    "Issue": issue,
                }
            )

    for warning in workbook.warnings:
        add("Workbook", "Structure", warning)

    project_keys: set[str] = set()
    for row_number, project in enumerate(workbook.projects, start=2):
        item = f"Row {row_number}"
        if not project.key:
            add("Projects", item, "ProjectId is required.")
        elif project.key in project_keys:
            add(
                "Projects",
                item,
                f"Duplicate ProjectId '{project.key}'.",
                project.key,
            )
        else:
            project_keys.add(project.key)
        if not project.name:
            add("Projects", item, "ProjectName is required.", project.key)
        if not project.contracting_unit:
            add("Projects", item, "ContractingUnit is required.", project.key)

    tasks_by_project: dict[str, dict[str, TaskRow]] = {}
    duplicate_task_keys: set[tuple[str, str]] = set()
    pending_parent_by_project: dict[str, tuple[int, str]] = {}
    for row_number, task in enumerate(workbook.tasks, start=2):
        item = f"Row {row_number}"
        if not task.project_key:
            add("Tasks", item, "ProjectId is required.")
        elif task.project_key not in project_keys:
            add(
                "Tasks",
                item,
                f"ProjectId '{task.project_key}' does not exist in Projects.",
                task.project_key,
            )
        if not task.task_key:
            add("Tasks", item, "TaskKey is required.", task.project_key)
        if not task.name:
            add("Tasks", item, "TaskName is required.", task.project_key)
        if task.start is not None and task.end is not None:
            add(
                "Tasks",
                item,
                "Specify either ScheduledStart or ScheduledEnd, not both.",
                task.project_key,
            )
        if task.project_key:
            if task.outline_level is None:
                pending_parent_by_project.pop(task.project_key, None)
            else:
                previous_parent = pending_parent_by_project.get(task.project_key)
                if previous_parent is not None:
                    previous_row, previous_task_key = previous_parent
                    add(
                        "Tasks",
                        item,
                        f"Outlined parent task '{previous_task_key}' on row "
                        f"{previous_row} must be followed by a child task before "
                        "another outlined parent task.",
                        task.project_key,
                    )
                pending_parent_by_project[task.project_key] = (
                    row_number,
                    task.task_key,
                )
        if task.project_key and task.task_key:
            project_tasks = tasks_by_project.setdefault(task.project_key, {})
            identity = (task.project_key, task.task_key)
            if task.task_key in project_tasks:
                duplicate_task_keys.add(identity)
                add(
                    "Tasks",
                    item,
                    f"Duplicate TaskKey '{task.task_key}' for project "
                    f"'{task.project_key}'.",
                    task.project_key,
                )
            else:
                project_tasks[task.task_key] = task

    for project_key, project_tasks in tasks_by_project.items():
        for task_key, task in project_tasks.items():
            item = f"{project_key} / {task_key}"
            if (
                task.parent_task_key
                and task.parent_task_key not in project_tasks
            ):
                add(
                    "Tasks",
                    item,
                    f"ParentTaskKey '{task.parent_task_key}' does not exist in "
                    "the same project.",
                    task.project_key,
                )

        visited: set[str] = set()
        visiting: set[str] = set()

        def visit(task_key: str) -> None:
            if task_key in visited:
                return
            if task_key in visiting:
                add(
                    "Tasks",
                    f"{project_key} / {task_key}",
                    "Task hierarchy contains a parent cycle.",
                    project_key,
                )
                return
            visiting.add(task_key)
            parent_key = project_tasks[task_key].parent_task_key
            if parent_key in project_tasks:
                visit(parent_key)
            visiting.remove(task_key)
            visited.add(task_key)

        for task_key in project_tasks:
            visit(task_key)

    summary_tasks = {
        (task.project_key, task.parent_task_key)
        for task in workbook.tasks
        if task.project_key and task.parent_task_key
    }
    for task in workbook.tasks:
        identity = (task.project_key, task.task_key)
        if identity not in summary_tasks:
            continue
        item = f"{task.project_key} / {task.task_key}"
        if task.project_bucket:
            add(
                "Tasks",
                item,
                "Parent tasks must not have a ProjectBucket.",
                task.project_key,
            )
        if task.effort is not None:
            add(
                "Tasks",
                item,
                "Parent tasks must not have effort hours.",
                task.project_key,
            )
        if task.start is not None or task.end is not None:
            add(
                "Tasks",
                item,
                "Parent tasks must not have scheduled dates.",
                task.project_key,
            )

    assignment_keys: set[tuple[str, str]] = set()
    task_resource_rows: dict[tuple[str, str, str], int] = {}
    resource_roles: dict[tuple[str, str], str] = {}
    for row_number, assignment in enumerate(workbook.assignments, start=2):
        item = f"Row {row_number}"
        if not assignment.project_key:
            add("Assignments", item, "ProjectId is required.")
        elif assignment.project_key not in project_keys:
            add(
                "Assignments",
                item,
                f"ProjectId '{assignment.project_key}' does not exist in Projects.",
                assignment.project_key,
            )
        project_tasks = tasks_by_project.get(assignment.project_key, {})
        if not assignment.task_key:
            add("Assignments", item, "TaskKey is required.", assignment.project_key)
        elif assignment.task_key not in project_tasks:
            add(
                "Assignments",
                item,
                f"TaskKey '{assignment.task_key}' does not exist in Tasks for "
                f"project '{assignment.project_key}'.",
                assignment.project_key,
            )
        if not assignment.resource_name:
            add(
                "Assignments",
                item,
                "ResourceName is required.",
                assignment.project_key,
            )
        if (
            assignment.project_key
            and assignment.task_key
            and assignment.resource_name
        ):
            task_resource_identity = (
                assignment.project_key,
                assignment.task_key,
                assignment.resource_name.casefold(),
            )
            original_row = task_resource_rows.get(task_resource_identity)
            if original_row is not None:
                add(
                    "Assignments",
                    item,
                    f"Resource '{assignment.resource_name}' is repeated for "
                    f"ProjectId '{assignment.project_key}' and TaskKey "
                    f"'{assignment.task_key}' (first assigned on row {original_row}).",
                    assignment.project_key,
                )
            else:
                task_resource_rows[task_resource_identity] = row_number
        if assignment.resource_name and assignment.role_name:
            resource_key = (
                assignment.project_key,
                assignment.resource_name.casefold(),
            )
            existing_role = resource_roles.get(resource_key)
            if existing_role and existing_role.casefold() != assignment.role_name.casefold():
                add(
                    "Assignments",
                    item,
                    f"Resource '{assignment.resource_name}' has conflicting RoleName values "
                    f"'{existing_role}' and '{assignment.role_name}' in project "
                    f"'{assignment.project_key}'.",
                    assignment.project_key,
                )
            else:
                resource_roles[resource_key] = assignment.role_name
        if assignment.assignment_key:
            identity = (assignment.project_key, assignment.assignment_key)
            if identity in assignment_keys:
                add(
                    "Assignments",
                    item,
                    f"Duplicate AssignmentKey '{assignment.assignment_key}' for "
                    f"project '{assignment.project_key}'.",
                    assignment.project_key,
                )
            assignment_keys.add(identity)
        if (assignment.project_key, assignment.task_key) in summary_tasks:
            add(
                "Assignments",
                item,
                "Parent tasks must not have resource assignments.",
                assignment.project_key,
            )

    valid_link_types = {
        "finishtostart",
        "starttostart",
        "finishtofinish",
        "starttofinish",
    }
    dependency_keys: set[tuple[str, str, str]] = set()
    for row_number, dependency in enumerate(workbook.dependencies, start=2):
        item = f"Row {row_number}"
        if not dependency.project_key:
            add("Dependencies", item, "ProjectId is required.")
        elif dependency.project_key not in project_keys:
            add(
                "Dependencies",
                item,
                f"ProjectId '{dependency.project_key}' does not exist in Projects.",
                dependency.project_key,
            )
        project_tasks = tasks_by_project.get(dependency.project_key, {})
        for label, task_key in (
            ("PredecessorTaskKey", dependency.predecessor_task_key),
            ("SuccessorTaskKey", dependency.successor_task_key),
        ):
            if not task_key:
                add(
                    "Dependencies",
                    item,
                    f"{label} is required.",
                    dependency.project_key,
                )
            elif task_key not in project_tasks:
                add(
                    "Dependencies",
                    item,
                    f"{label} '{task_key}' does not exist in Tasks for project "
                    f"'{dependency.project_key}'.",
                    dependency.project_key,
                )
        if (
            dependency.predecessor_task_key
            and dependency.predecessor_task_key == dependency.successor_task_key
        ):
            add(
                "Dependencies",
                item,
                "A task cannot depend on itself.",
                dependency.project_key,
            )
        link_type = "".join(
            character
            for character in dependency.link_type.lower()
            if character.isalpha()
        )
        if link_type not in valid_link_types:
            add(
                "Dependencies",
                item,
                f"LinkType '{dependency.link_type}' is not supported.",
                dependency.project_key,
            )
        identity = (
            dependency.project_key,
            dependency.predecessor_task_key,
            dependency.successor_task_key,
        )
        if identity in dependency_keys:
            add(
                "Dependencies",
                item,
                "Duplicate dependency.",
                dependency.project_key,
            )
        dependency_keys.add(identity)

    for project_key in project_keys:
        if not tasks_by_project.get(project_key):
            add(
                "Projects",
                project_key,
                "Project must have at least one task.",
                project_key,
            )

    return issues


# --------------------------------------------------------------------------- #
# Value coercion
# --------------------------------------------------------------------------- #

def _to_iso(value: Any) -> str | None:
    if value is None or (isinstance(value, float) and pd.isna(value)):
        return None
    if isinstance(value, (datetime, date, pd.Timestamp)):
        return pd.Timestamp(value).to_pydatetime().strftime("%Y-%m-%dT%H:%M:%S")
    s = str(value).strip()
    if not s:
        return None
    parsed = pd.to_datetime(s, errors="coerce")
    if pd.isna(parsed):
        return None
    return parsed.to_pydatetime().strftime("%Y-%m-%dT%H:%M:%S")


def _to_int(value: Any) -> int | None:
    if value is None or (isinstance(value, float) and pd.isna(value)):
        return None
    s = str(value).strip()
    if not s:
        return None
    try:
        return int(float(s))
    except ValueError:
        return None


def _to_float(value: Any) -> float | None:
    if value is None or (isinstance(value, float) and pd.isna(value)):
        return None
    s = str(value).strip()
    if not s:
        return None
    try:
        return float(s)
    except ValueError:
        return None


def _to_str(value: Any) -> str:
    if value is None or (isinstance(value, float) and pd.isna(value)):
        return ""
    return str(value).strip()


# --------------------------------------------------------------------------- #
# Generic sheet parsing
# --------------------------------------------------------------------------- #

def _find_sheet(sheet_names: list[str], wanted: list[str]) -> str | None:
    norm_map = {_norm(s): s for s in sheet_names}
    for w in wanted:
        if w in norm_map:
            return norm_map[w]
    for w in wanted:
        for n, original in norm_map.items():
            if w in n:
                return original
    return None


def _column_map(df: pd.DataFrame, aliases: dict[str, list[str]]) -> dict[str, int]:
    col_map: dict[str, int] = {}
    for idx, col in enumerate(df.columns):
        logical = _match_field(col, aliases)
        if logical and logical not in col_map:
            col_map[logical] = idx
    return col_map


def _iter_records(df: pd.DataFrame, col_map: dict[str, int]):
    for _, row in df.iterrows():
        cells = list(row.values)

        def cell(logical: str, _cells=cells) -> Any:
            i = col_map.get(logical)
            return _cells[i] if i is not None and i < len(_cells) else None

        yield cell


# --------------------------------------------------------------------------- #
# Sheet-specific parsing
# --------------------------------------------------------------------------- #

def _parse_projects(df: pd.DataFrame, warnings: list[str]) -> list[ProjectInfo]:
    col_map = _column_map(df, _PROJECT_ALIASES)
    if "name" not in col_map:
        warnings.append(
            "Could not find a 'ProjectName' column in the 'Projects' sheet. "
            f"Detected columns: {list(df.columns)}"
        )
        return []
    projects: list[ProjectInfo] = []
    for cell in _iter_records(df, col_map):
        name = _to_str(cell("name"))
        key = _to_str(cell("key"))
        company = _to_str(cell("company"))
        contracting_unit = _to_str(cell("contracting_unit"))
        customer = _to_str(cell("customer"))
        calendar = _to_str(cell("calendar"))
        manager = _to_str(cell("manager"))
        start = _to_iso(cell("start"))
        if not any(
            (
                name,
                key,
                company,
                contracting_unit,
                customer,
                calendar,
                manager,
                start,
            )
        ):
            continue
        projects.append(
            ProjectInfo(
                key=key,
                name=name,
                company=company,
                contracting_unit=contracting_unit,
                customer=customer,
                calendar=calendar,
                manager=manager,
                start=start,
            )
        )
    return projects


def _parse_tasks(df: pd.DataFrame, warnings: list[str]) -> list[TaskRow]:
    col_map = _column_map(df, _TASK_ALIASES)
    if "name" not in col_map or "task_key" not in col_map:
        warnings.append(
            "Could not find 'TaskName'/'TaskKey' columns in the 'Tasks' sheet. "
            f"Detected columns: {list(df.columns)}"
        )
        return []
    tasks: list[TaskRow] = []
    for cell in _iter_records(df, col_map):
        project_key = _to_str(cell("project_key"))
        name = _to_str(cell("name"))
        task_key = _to_str(cell("task_key"))
        task_col1 = _to_str(cell("task_col1")) or None
        project_bucket = _to_str(cell("project_bucket")) or None
        parent_task_key = _to_str(cell("parent_task_key")) or None
        effort = _to_float(cell("effort"))
        start = _to_iso(cell("start"))
        end = _to_iso(cell("end"))
        outline_level = _to_int(cell("outline_level"))
        if not any((project_key, name, task_key, task_col1, parent_task_key, start, end)) and (
            effort is None and outline_level is None
        ):
            continue
        tasks.append(
            TaskRow(
                project_key=project_key,
                task_key=task_key,
                name=name,
                task_col1=task_col1,
                project_bucket=project_bucket,
                parent_task_key=parent_task_key,
                effort=effort,
                start=start,
                end=end,
                outline_level=outline_level,
            )
        )
    return tasks


def _parse_assignments(df: pd.DataFrame, warnings: list[str]) -> list[AssignmentRow]:
    col_map = _column_map(df, _ASSIGNMENT_ALIASES)
    if "task_key" not in col_map or "resource_name" not in col_map:
        warnings.append(
            "Could not find 'TaskKey'/'ResourceName' columns in the 'Assignments' "
            f"sheet. Detected columns: {list(df.columns)}"
        )
        return []
    rows: list[AssignmentRow] = []
    for cell in _iter_records(df, col_map):
        project_key = _to_str(cell("project_key"))
        assignment_key = _to_str(cell("assignment_key"))
        task_key = _to_str(cell("task_key"))
        resource = _to_str(cell("resource_name"))
        role = _to_str(cell("role_name"))
        if not any((project_key, assignment_key, task_key, resource, role)):
            continue
        rows.append(
            AssignmentRow(
                project_key=project_key,
                assignment_key=assignment_key,
                task_key=task_key,
                resource_name=resource,
                role_name=role,
            )
        )
    return rows


def _parse_dependencies(df: pd.DataFrame, warnings: list[str]) -> list[DependencyRow]:
    col_map = _column_map(df, _DEPENDENCY_ALIASES)
    if "predecessor_task_key" not in col_map or "successor_task_key" not in col_map:
        warnings.append(
            "Could not find predecessor/successor columns in the 'Dependencies' "
            f"sheet. Detected columns: {list(df.columns)}"
        )
        return []
    rows: list[DependencyRow] = []
    for cell in _iter_records(df, col_map):
        project_key = _to_str(cell("project_key"))
        pred = _to_str(cell("predecessor_task_key"))
        succ = _to_str(cell("successor_task_key"))
        link_type = _to_str(cell("link_type"))
        if not any((project_key, pred, succ, link_type)):
            continue
        rows.append(
            DependencyRow(
                project_key=project_key,
                predecessor_task_key=pred,
                successor_task_key=succ,
                link_type=link_type or "FinishToStart",
            )
        )
    return rows


# --------------------------------------------------------------------------- #
# Public entry point
# --------------------------------------------------------------------------- #

def load_workbook(source: str | bytes | io.BytesIO) -> Workbook:
    """Parse an uploaded Project Operations schedule template."""
    if isinstance(source, bytes):
        source = io.BytesIO(source)

    xls = pd.ExcelFile(source, engine="openpyxl")
    warnings: list[str] = []
    wb = Workbook(warnings=warnings)

    def sheet_df(wanted: list[str]) -> pd.DataFrame | None:
        name = _find_sheet(xls.sheet_names, wanted)
        if name is None:
            return None
        return xls.parse(name, header=0, dtype=object)

    projects_df = sheet_df(["projects", "project"])
    if projects_df is None:
        warnings.append(f"No 'Projects' sheet found (sheets: {xls.sheet_names}).")
    else:
        wb.projects = _parse_projects(projects_df, warnings)

    tasks_df = sheet_df(["tasks", "task"])
    if tasks_df is None:
        warnings.append(f"No 'Tasks' sheet found (sheets: {xls.sheet_names}).")
    else:
        wb.tasks = _parse_tasks(tasks_df, warnings)

    assignments_df = sheet_df(["assignments", "assignment"])
    if assignments_df is None:
        warnings.append(
            f"No 'Assignments' sheet found (sheets: {xls.sheet_names})."
        )
    else:
        wb.assignments = _parse_assignments(assignments_df, warnings)

    dependencies_df = sheet_df(["dependencies", "dependency"])
    if dependencies_df is None:
        warnings.append(
            f"No 'Dependencies' sheet found (sheets: {xls.sheet_names})."
        )
    else:
        wb.dependencies = _parse_dependencies(dependencies_df, warnings)

    return wb
