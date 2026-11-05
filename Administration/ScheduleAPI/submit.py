"""
Orchestration: turn a parsed :class:`Workbook` into Project Operations records
using :class:`ProjectOperationsClient`.

The template is relational (Projects / Tasks / Assignments / Dependencies all
keyed by ``ProjectKey`` and ``TaskKey``). For each selected project we:

1. Find or create the project (+ default bucket).
2. (optional) Create team members for each distinct assigned resource.
3. Prepare tasks, dependencies and resource assignments in one collection.
4. Submit each size-limited collection directly with ExecuteOperationSetV3.
"""
from __future__ import annotations

from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass
from datetime import datetime, timezone
import time
from typing import Any, Callable

import requests

from excel_loader import ProjectInfo, Workbook
from po_client import (
    MAX_OPS_PER_SET,
    OPSET_STATUS_COMPLETED,
    AuthorizationExpiring,
    AuthorizationRequired,
    ExecutionStopped,
    OperationSetOutcomeUnknown,
    ProjectOperationsClient,
    ProjectOperationsError,
    SubmitResult,
    link_type_value,
)


def _chunked(items: list, size: int):
    for i in range(0, len(items), size):
        yield items[i : i + size]


def _bucket_key(name: str) -> str:
    return name.strip().casefold()


def _chunk_with_bucket_prerequisites(
    entities: list[dict[str, Any]],
    size: int,
) -> list[list[dict[str, Any]]]:
    buckets = [
        entity
        for entity in entities
        if entity.get("@odata.type")
        == "Microsoft.Dynamics.CRM.msdyn_projectbucket"
    ]
    schedule = [entity for entity in entities if entity not in buckets]
    return list(_chunked(buckets, size)) + list(_chunked(schedule, size))


def _require_authorization_window(
    settings_provider: Callable[[], dict[str, int | float]],
    log: Callable[[str], None],
    client: ProjectOperationsClient,
    authorization_refresh: Callable[[], dict[str, Any]] | None = None,
    minimum_seconds: int = 300,
) -> None:
    expires_at = float(settings_provider().get("authorization_expires_at") or 0)
    if not expires_at:
        return
    remaining = expires_at - time.time()
    remaining_seconds = int(remaining)
    if remaining <= minimum_seconds:
        if authorization_refresh is not None:
            try:
                authorization = authorization_refresh()
                client.set_access_token(str(authorization["access_token"]))
                renewed_expires_at = float(authorization.get("expires_at") or 0)
            except Exception as exc:
                log(f"Automatic authorization rotation failed: {exc}")
            else:
                renewed_seconds = int(renewed_expires_at - time.time())
                if renewed_expires_at and renewed_seconds > minimum_seconds:
                    log(
                        "Authorization rotated automatically; "
                        f"approximately {renewed_seconds // 60} minute(s) remain."
                    )
                    return
        log(
            f"Authorization pause: {max(0, remaining_seconds)} second(s) remain. "
            "No new operation set was started; reauthenticate to continue."
        )
        raise AuthorizationExpiring(
            "Authorization has five minutes or less remaining. In-flight operation "
            "sets were allowed to finish and were checkpointed. Reauthenticate, "
            "then continue the previous upload."
        )


def _parent_first(tasks: list) -> list:
    task_by_key = {task.task_key: task for task in tasks}
    ordered = []
    visited: set[str] = set()
    visiting: set[str] = set()

    def visit(task) -> None:
        if task.task_key in visited:
            return
        if task.task_key in visiting:
            raise ValueError(f"Task hierarchy contains a cycle at '{task.task_key}'.")
        visiting.add(task.task_key)
        parent = task_by_key.get(task.parent_task_key)
        if parent is not None:
            visit(parent)
        visiting.remove(task.task_key)
        visited.add(task.task_key)
        ordered.append(task)

    for task in tasks:
        visit(task)
    return ordered


def _chunk_schedule_entities(
    tasks: list,
    task_entities: list[dict[str, Any]],
    related_entities: list[dict[str, Any]],
    size: int,
) -> tuple[list[list[dict[str, Any]]], list[str]]:
    task_by_key = {task.task_key: task for task in tasks}
    groups: dict[str, list[dict[str, Any]]] = {}

    for task, entity in zip(tasks, task_entities):
        root = task
        while root.parent_task_key in task_by_key:
            root = task_by_key[root.parent_task_key]
        groups.setdefault(root.task_key, []).append(entity)

    batches: list[list[dict[str, Any]]] = []
    current: list[dict[str, Any]] = []
    split_roots: list[str] = []
    for root_key, group in groups.items():
        if len(group) > size:
            if current:
                batches.append(current)
                current = []
            batches.extend(_chunked(group, size))
            split_roots.append(root_key)
        else:
            if current and len(current) + len(group) > size:
                batches.append(current)
                current = []
            current.extend(group)

    for entity in related_entities:
        if len(current) == size:
            batches.append(current)
            current = []
        current.append(entity)
    if current:
        batches.append(current)
    return batches, split_roots


@dataclass
class PreparedProject:
    project: ProjectInfo
    client: ProjectOperationsClient
    result: SubmitResult
    batches: list[list[dict[str, Any]]]
    stamp: str
    logs: list[str]
    execution_records: list[dict[str, Any]]
    operations_per_set: int
    next_batch: int = 0

    @property
    def has_remaining_batches(self) -> bool:
        return self.next_batch < len(self.batches)


def _preflight_project_inputs(
    client: ProjectOperationsClient,
    project: ProjectInfo,
    tasks: list[Any],
    assignments: list[Any],
    dependencies: list[Any],
    *,
    create_resources: bool,
    create_dependencies: bool,
) -> tuple[dict[str, str], dict[str, tuple[str, str, str | None, str]]]:
    errors: list[str] = []
    try:
        project_references = client.resolve_project_references(
            customer=project.customer,
            company=project.company,
            contracting_unit=project.contracting_unit,
            calendar=project.calendar,
            manager=project.manager,
        )
    except ProjectOperationsError as exc:
        project_references = {}
        errors.append(str(exc))

    task_keys = [task.task_key for task in tasks if task.task_key]
    known_task_keys = set(task_keys)
    duplicate_task_keys = sorted({key for key in task_keys if task_keys.count(key) > 1})
    if duplicate_task_keys:
        errors.append("Duplicate TaskKey values: " + ", ".join(duplicate_task_keys))
    for task in tasks:
        if not task.task_key:
            errors.append("A task has no TaskKey.")
        if not task.name:
            errors.append(f"Task '{task.task_key or '(missing key)'}' has no TaskName.")
        if task.parent_task_key and task.parent_task_key not in known_task_keys:
            errors.append(
                f"Task '{task.task_key}' references missing parent "
                f"'{task.parent_task_key}'."
            )
    tasks_by_key = {task.task_key: task for task in tasks if task.task_key}
    summary_task_keys = {
        task.parent_task_key for task in tasks if task.parent_task_key
    }
    for task_key in summary_task_keys:
        summary_task = tasks_by_key.get(task_key)
        if summary_task and (
            summary_task.effort is not None
            or summary_task.start is not None
            or summary_task.end is not None
        ):
            errors.append(
                f"Summary task '{task_key}' supplies effort or scheduled dates; "
                "these values cannot be sent for a summary task."
            )

    visited: set[str] = set()
    visiting: set[str] = set()

    def visit_task(task_key: str) -> None:
        if task_key in visited:
            return
        if task_key in visiting:
            errors.append(f"Task hierarchy contains a cycle at '{task_key}'.")
            return
        visiting.add(task_key)
        parent_key = tasks_by_key[task_key].parent_task_key
        if parent_key in tasks_by_key:
            visit_task(parent_key)
        visiting.remove(task_key)
        visited.add(task_key)

    for task_key in tasks_by_key:
        visit_task(task_key)

    resources: dict[str, tuple[str, str]] = {}
    task_resource_pairs: set[tuple[str, str]] = set()
    if create_resources:
        for assignment in assignments:
            if not assignment.task_key or assignment.task_key not in known_task_keys:
                errors.append(
                    f"Assignment '{assignment.assignment_key}' references missing "
                    f"task '{assignment.task_key}'."
                )
            if not assignment.resource_name:
                errors.append(
                    f"Assignment '{assignment.assignment_key}' has no ResourceName."
                )
                continue
            resource_key = assignment.resource_name.casefold()
            task_resource_pair = (assignment.task_key, resource_key)
            if task_resource_pair in task_resource_pairs:
                errors.append(
                    f"Resource '{assignment.resource_name}' is assigned more than "
                    f"once to task '{assignment.task_key}'."
                )
            task_resource_pairs.add(task_resource_pair)
            existing = resources.get(resource_key)
            existing_role = existing[1] if existing else ""
            if (
                existing_role
                and assignment.role_name
                and existing_role.casefold() != assignment.role_name.casefold()
            ):
                errors.append(
                    f"Resource '{assignment.resource_name}' has conflicting "
                    f"RoleName values '{existing_role}' and "
                    f"'{assignment.role_name}'."
                )
            resources[resource_key] = (
                existing[0] if existing else assignment.resource_name,
                assignment.role_name or existing_role,
            )

    resolved_resources: dict[str, tuple[str, str, str | None, str]] = {}
    for resource_key, (resource_name, role_name) in sorted(resources.items()):
        bookable_resource_id = client.find_bookableresource_id(resource_name)
        if role_name:
            resource_category_id = client.find_resource_category_id(role_name)
            if not resource_category_id:
                errors.append(
                    f"RoleName '{role_name}' for resource '{resource_name}' was "
                    "not found in Dataverse resource categories."
                )
                continue
        else:
            if not bookable_resource_id:
                errors.append(
                    f"Resource '{resource_name}' has no supplied RoleName and no "
                    "matching bookable resource, so a default role cannot be "
                    "resolved."
                )
                continue
            default_category = client.find_default_resource_category(
                bookable_resource_id
            )
            if not default_category:
                errors.append(
                    f"Resource '{resource_name}' has no supplied RoleName and no "
                    "default Dataverse resource category."
                )
                continue
            resource_category_id, role_name = default_category
        resolved_resources[resource_key] = (
            resource_name,
            role_name,
            bookable_resource_id,
            resource_category_id,
        )

    if create_dependencies:
        for dependency in dependencies:
            if dependency.predecessor_task_key not in known_task_keys:
                errors.append(
                    f"Dependency predecessor '{dependency.predecessor_task_key}' "
                    "does not reference a project task."
                )
            if dependency.successor_task_key not in known_task_keys:
                errors.append(
                    f"Dependency successor '{dependency.successor_task_key}' does "
                    "not reference a project task."
                )
            if (
                dependency.predecessor_task_key
                == dependency.successor_task_key
            ):
                errors.append(
                    f"Dependency for task '{dependency.predecessor_task_key}' "
                    "references the same task as predecessor and successor."
                )
            try:
                link_type_value(dependency.link_type)
            except ValueError as exc:
                errors.append(str(exc))

    if errors:
        unique_errors = list(dict.fromkeys(errors))
        raise ProjectOperationsError(
            f"Project '{project.name}' was skipped before any Dataverse writes:\n- "
            + "\n- ".join(unique_errors)
        )
    return project_references, resolved_resources


def _prepare_project(
    client: ProjectOperationsClient,
    workbook: Workbook,
    project: ProjectInfo,
    *,
    create_resources: bool = True,
    create_dependencies: bool = True,
    reuse_existing_project: bool = True,
    operations_per_set: int = MAX_OPS_PER_SET,
    log: Callable[[str], None] | None = None,
) -> PreparedProject:
    """Create/reuse a project and prepare its schedule operation batches."""
    log = log or (lambda _m: None)
    result = SubmitResult()

    if not project.name:
        raise ValueError("Project name is required before submitting.")
    if not project.contracting_unit:
        raise ValueError(
            f"ContractingUnit is required for project '{project.name}'."
        )
    if not 1 <= operations_per_set <= MAX_OPS_PER_SET:
        raise ValueError(
            f"Operations per set must be between 1 and {MAX_OPS_PER_SET}."
        )

    pkey = project.key.strip()
    if not pkey:
        raise ValueError(
            f"ProjectKey is required for project '{project.name}'."
        )
    tasks = workbook.tasks_for(pkey) if pkey else workbook.tasks
    assignments = workbook.assignments_for(pkey) if pkey else workbook.assignments
    dependencies = workbook.dependencies_for(pkey) if pkey else workbook.dependencies

    if not tasks:
        raise ValueError(f"No tasks found for project '{project.name}'.")

    log(f"=== Project '{project.name}' (key={pkey or 'n/a'}) ===")
    project_references, resolved_resources = _preflight_project_inputs(
        client,
        project,
        tasks,
        assignments,
        dependencies,
        create_resources=create_resources,
        create_dependencies=create_dependencies,
    )
    log("  all supplied project, task, resource, role and dependency values validated")

    # ------------------------------------------------------------------ #
    # 1. Project + bucket
    # ------------------------------------------------------------------ #
    existing = client.find_project_id(pkey)
    if existing and reuse_existing_project:
        result.project_id = existing
        result.project_existed = True
        log(f"Using existing project ({existing}).")
    elif existing and not reuse_existing_project:
        raise ValueError(
            f"A project named '{project.name}' already exists. "
            "Enable 'reuse existing project' or rename it."
        )
    else:
        log("Creating project ...")
        result.project_id = client.create_project(
            project_key=pkey,
            name=project.name,
            description=project.name,
            customer=project.customer,
            company=project.company,
            contracting_unit=project.contracting_unit,
            calendar=project.calendar,
            manager=project.manager,
            start=project.start,
            resolved_references=project_references,
        )
        log(f"  created project {result.project_id}")

    existing_buckets = client.get_project_buckets(result.project_id)
    bucket_ids: dict[str, str] = {}
    for existing_bucket_id, existing_bucket_name in existing_buckets:
        bucket_ids.setdefault(_bucket_key(existing_bucket_name), existing_bucket_id)

    bucket_entities: list[dict[str, Any]] = []
    if existing_buckets:
        default_bucket_id = existing_buckets[0][0]
    else:
        default_bucket_id = client.new_guid()
        bucket_ids[_bucket_key("Bucket 1")] = default_bucket_id
        bucket_entities.append(
            client.build_project_bucket_entity(
                result.project_id,
                default_bucket_id,
            )
        )
        log("  no project bucket found; preparing default 'Bucket 1'")

    requested_bucket_names: dict[str, str] = {}
    for task in tasks:
        if task.project_bucket:
            requested_bucket_names.setdefault(
                _bucket_key(task.project_bucket),
                task.project_bucket.strip(),
            )
    for bucket_key, bucket_name in requested_bucket_names.items():
        if bucket_key in bucket_ids:
            continue
        bucket_id = client.new_guid()
        bucket_ids[bucket_key] = bucket_id
        bucket_entities.append(
            client.build_project_bucket_entity(
                result.project_id,
                bucket_id,
                bucket_name,
            )
        )
        log(f"  project bucket '{bucket_name}' not found; preparing it")
    result.bucket_id = default_bucket_id

    # Pre-generate stable GUIDs keyed by TaskKey so parent/dependency links
    # resolve regardless of creation order inside the operation set.
    task_guid: dict[str, str] = {t.task_key: client.new_guid() for t in tasks}
    result.task_ids = {t.task_key: task_guid[t.task_key] for t in tasks}

    # ------------------------------------------------------------------ #
    # 2. Team members (optional)
    # ------------------------------------------------------------------ #
    team_member_ids: dict[str, str] = {}
    if create_resources and resolved_resources:
        for resource_key in sorted(resolved_resources):
            (
                res_name,
                role_name,
                bookable,
                resource_category_id,
            ) = resolved_resources[resource_key]
            for attempt in range(1, 4):
                try:
                    existing_tm = (
                        client.find_team_member_id(result.project_id, bookable)
                        if bookable
                        else None
                    )
                    if existing_tm:
                        team_member_ids[resource_key] = existing_tm
                        log(f"  reuse team member '{res_name}' as '{role_name}'")
                    else:
                        tm_id = client.create_team_member(
                            result.project_id,
                            res_name,
                            role_name,
                            resource_category_id,
                            bookable,
                        )
                        team_member_ids[resource_key] = tm_id
                        result.created_team_members += 1
                        log(f"  created team member '{res_name}' as '{role_name}'")
                    break
                except requests.RequestException as exc:
                    if attempt == 3:
                        raise
                    log(
                        f"  ! Connection lost setting up resource '{res_name}'; "
                        f"reconnecting and retrying ({attempt}/2): {exc}"
                    )
                    client.reconnect()
                    time.sleep(5)
                except ProjectOperationsError:
                    raise
                except Exception as exc:  # noqa: BLE001
                    raise ProjectOperationsError(
                        f"Could not set up resource '{res_name}': {exc}"
                    ) from exc

    # ------------------------------------------------------------------ #
    # 3. Tasks (+ assignments)
    # ------------------------------------------------------------------ #
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    summary_task_keys = {
        task.parent_task_key for task in tasks if task.parent_task_key
    }
    ordered_tasks = _parent_first(tasks)
    task_entities = []
    for t in ordered_tasks:
        parent_id = task_guid.get(t.parent_task_key) if t.parent_task_key else None
        is_summary = t.task_key in summary_task_keys
        task_bucket_id = (
            bucket_ids[_bucket_key(t.project_bucket)]
            if t.project_bucket
            else default_bucket_id
        )
        task_entities.append(
            client.build_task_entity(
                project_id=result.project_id,
                bucket_id=task_bucket_id,
                task_id=task_guid[t.task_key],
                subject=t.name,
                effort=None if is_summary else t.effort,
                start=None if is_summary else t.start,
                end=None if is_summary else t.end,
                parent_task_id=parent_id,
                task_col1=t.task_col1,
            )
        )

    assignment_entities = []
    if create_resources:
        for a in assignments:
            tm_id = team_member_ids[a.resource_name.casefold()]
            target_task = task_guid[a.task_key]
            assignment_entities.append(
                client.build_resource_assignment_entity(
                    project_id=result.project_id,
                    assignment_id=client.new_guid(),
                    task_id=target_task,
                    team_member_id=tm_id,
                    name=a.resource_name,
                )
            )

    dependency_entities = []
    if create_dependencies:
        for d in dependencies:
            dependency_entities.append(
                client.build_dependency_entity(
                    result.project_id,
                    client.new_guid(),
                    task_guid[d.predecessor_task_key],
                    task_guid[d.successor_task_key],
                    d.link_type,
                )
            )

    log(f"Prepared {len(task_entities)} task(s)"
        + (f", {len(dependency_entities)} dependency link(s)" if dependency_entities else "")
        + (f" and {len(assignment_entities)} assignment(s)" if assignment_entities else "")
        + " ...")
    result.created_tasks = len(task_entities)
    result.created_dependencies = len(dependency_entities)
    result.created_assignments = len(assignment_entities)
    batches, split_roots = _chunk_schedule_entities(
        ordered_tasks,
        task_entities,
        dependency_entities + assignment_entities,
        operations_per_set,
    )
    bucket_batches = list(_chunked(bucket_entities, operations_per_set))
    batches = bucket_batches + batches
    if split_roots:
        log(
            "  ! Task trees larger than the operation-set limit were split: "
            + ", ".join(split_roots)
        )
    execution_records = [
        client.register_operation_set(
            result.project_id,
            f"{project.name}-schedule-{stamp}-{batch_number}",
            batch,
            project.name,
        )
        for batch_number, batch in enumerate(batches, start=1)
    ]
    for record in execution_records:
        record["ProjectTaskCount"] = len(task_entities)
        record["ProjectAssignmentCount"] = len(assignment_entities)
        record["ProjectDependencyCount"] = len(dependency_entities)
    return PreparedProject(
        project=project,
        client=client,
        result=result,
        batches=batches,
        stamp=stamp,
        logs=[],
        execution_records=execution_records,
        operations_per_set=operations_per_set,
    )


def _resize_unsent_batches(
    prepared: PreparedProject,
    size: int,
    master_records: list[dict[str, Any]],
) -> None:
    if size == prepared.operations_per_set or not prepared.has_remaining_batches:
        return
    remaining_entities = [
        entity
        for batch in prepared.batches[prepared.next_batch:]
        for entity in batch
    ]
    resized_batches = _chunk_with_bucket_prerequisites(remaining_entities, size)
    old_records = prepared.execution_records[prepared.next_batch:]
    resized_records: list[dict[str, Any]] = []
    for offset, batch in enumerate(resized_batches):
        batch_number = prepared.next_batch + offset + 1
        description = (
            f"{prepared.project.name}-schedule-{prepared.stamp}-{batch_number}"
        )
        if offset < len(old_records):
            record = old_records[offset]
            payload = {
                "ProjectId": prepared.result.project_id,
                "OperationSetDescription": description,
                "CreateEntityCollection": batch,
            }
            record["Payload"] = payload
            record["SubmissionRequest"]["Payload"] = payload
            record["Status"] = "Planned"
        else:
            record = prepared.client.register_operation_set(
                prepared.result.project_id,
                description,
                batch,
                prepared.project.name,
            )
            master_records.append(record)
        record["ProjectTaskCount"] = prepared.result.created_tasks
        record["ProjectAssignmentCount"] = prepared.result.created_assignments
        record["ProjectDependencyCount"] = prepared.result.created_dependencies
        resized_records.append(record)
    for record in old_records[len(resized_records):]:
        record["Status"] = "Superseded before submission"
    prepared.batches = (
        prepared.batches[:prepared.next_batch] + resized_batches
    )
    prepared.execution_records = (
        prepared.execution_records[:prepared.next_batch] + resized_records
    )
    prepared.operations_per_set = size
    prepared.logs.append(
        f"  project '{prepared.project.name}' "
        f"(key={prepared.project.key or 'n/a'}, id={prepared.result.project_id}): "
        f"resized remaining batches to at most {size} operation(s)"
    )


def _execute_next_batch(prepared: PreparedProject) -> str:
    batch_number = prepared.next_batch + 1
    batch = prepared.batches[prepared.next_batch]
    execution_record = prepared.execution_records[prepared.next_batch]
    description = (
        f"{prepared.project.name}-schedule-{prepared.stamp}-{batch_number}"
    )
    try:
        response = prepared.client.execute_operation_set(
            prepared.result.project_id,
            description,
            batch,
            project_name=prepared.project.name,
            execution_record=execution_record,
        )
        operation_set_id = prepared.client.operation_set_id_from_response(response)
    except requests.RequestException as exc:
        prepared.logs.append(
            f"  connection lost submitting batch {batch_number}; recovering: {exc}"
        )
        operation_set_id = prepared.client.recover_operation_set(
            description,
            attempts=24,
            wait_seconds=5,
        )
        if operation_set_id:
            prepared.logs.append(
                f"  recovered batch {batch_number} as operation set "
                f"{operation_set_id}"
            )
        else:
            execution_record["Status"] = "Outcome unknown - awaiting reconciliation"
            prepared.logs.append(
                f"  batch {batch_number} remains outcome-unknown after description "
                "reconciliation; it will not be resent"
            )
            raise OperationSetOutcomeUnknown(
                f"Operation set '{description}' is not visible after the recovery "
                "window. Its outcome is unknown, so the payload was not resent."
            )
            operation_set_id = prepared.client.operation_set_id_from_response(response)
    if not operation_set_id:
        raise RuntimeError(
            f"msdyn_ExecuteOperationSetV3 did not return an OperationSetId: {response}"
        )
    prepared.result.operation_set_ids.append(operation_set_id)
    prepared.next_batch += 1
    submitted_at = str(
        execution_record.get("SubmissionFinishedAtUtc")
        or datetime.now(timezone.utc).isoformat()
    )
    prepared.logs.append(
        f"  [{submitted_at}] project '{prepared.project.name}' "
        f"(key={prepared.project.key or 'n/a'}, id={prepared.result.project_id}): "
        f"submitted batch "
        f"{batch_number}/{len(prepared.batches)} "
        f"with {len(batch)} operation(s), operationSetId={operation_set_id}"
    )
    return operation_set_id


def submit_project(
    client: ProjectOperationsClient,
    workbook: Workbook,
    project: ProjectInfo,
    *,
    create_resources: bool = True,
    create_dependencies: bool = True,
    reuse_existing_project: bool = True,
    operations_per_set: int = MAX_OPS_PER_SET,
    polling_wait_seconds: int = 30,
    log: Callable[[str], None] | None = None,
) -> SubmitResult:
    """Submit one project sequentially, polling between operation batches."""
    log = log or (lambda _m: None)
    prepared = _prepare_project(
        client,
        workbook,
        project,
        create_resources=create_resources,
        create_dependencies=create_dependencies,
        reuse_existing_project=reuse_existing_project,
        operations_per_set=operations_per_set,
        log=log,
    )
    while prepared.has_remaining_batches:
        operation_set_id = _execute_next_batch(prepared)
        for message in prepared.logs:
            log(message)
        prepared.logs.clear()
        client.wait_for_operation_sets(
            [operation_set_id],
            poll_seconds=polling_wait_seconds,
        )

    log("Project done.")
    return prepared.result


def resume_execution_records(
    client: ProjectOperationsClient,
    records: list[dict[str, Any]],
    *,
    polling_wait_seconds: int = 30,
    log: Callable[[str], None] | None = None,
    settings_provider: Callable[[], dict[str, int]] | None = None,
    checkpoint: Callable[[list[dict[str, Any]]], None] | None = None,
    authorization_refresh: Callable[[], dict[str, Any]] | None = None,
    stop_requested: Callable[[], bool] | None = None,
) -> dict[str, int]:
    """Reconcile and continue retained operation sets in project-aware waves."""
    log = log or (lambda _m: None)
    settings_provider = settings_provider or (lambda: {
        "concurrent_operation_sets": 1,
        "operations_per_set": MAX_OPS_PER_SET,
        "polling_wait_seconds": polling_wait_seconds,
    })
    client.execution_records = records
    initial_completed = sum(
        str(record.get("Status") or "").startswith("Completed")
        for record in records
    )
    completed = initial_completed
    submitted = 0
    skipped = sum(
        str(record.get("Status") or "").startswith("Superseded")
        for record in records
    )
    wave_number = 0
    continuation_operations_per_set = int(
        settings_provider()["operations_per_set"]
    )
    log(
        "Reconciliation started: "
        f"{len(records)} retained operation set(s), "
        f"{initial_completed} already completed, {skipped} superseded."
    )
    for index, record in enumerate(records, start=1):
        log(
            f"  Reconciliation inventory {index}/{len(records)}: "
            f"project='{record.get('Project', '')}', "
            f"key={record.get('ProjectKey', '') or 'n/a'}, "
            f"batch={record.get('Batch', 'n/a')}, "
            f"operationSetId={record.get('OperationSetId', '') or 'none'}, "
            f"retainedStatus={record.get('Status', '') or 'unknown'}."
        )

    def resize_confirmed_unsent(size: int) -> None:
        projects: dict[str, list[dict[str, Any]]] = {}
        for record in records:
            if (
                str(record.get("Status") or "") == "Planned"
                and not record.get("OperationSetId")
            ):
                projects.setdefault(str(record.get("Project") or ""), []).append(record)
        for project_name, project_records in projects.items():
            current_sizes = [
                len(record.get("Payload", {}).get("CreateEntityCollection", []))
                for record in project_records
            ]
            already_sized = all(
                count == size for count in current_sizes[:-1]
            ) and (not current_sizes or current_sizes[-1] <= size)
            if already_sized:
                continue
            for record in project_records:
                if record.get("ConfirmedAbsentFromDataverse"):
                    continue
                description = str(
                    record.get("Payload", {}).get("OperationSetDescription") or ""
                )
                operation_set_id = client.recover_operation_set(
                    description,
                    attempts=24,
                    wait_seconds=5,
                ) or ""
                if operation_set_id:
                    record["OperationSetId"] = operation_set_id
                    record["Status"] = "Recovered during continuation"
                    log(
                        f"Recovered '{description}' as {operation_set_id}; "
                        "excluded it from resizing."
                    )
                else:
                    record["ConfirmedAbsentFromDataverse"] = True

            mutable = [
                record for record in project_records
                if record.get("ConfirmedAbsentFromDataverse")
                and str(record.get("Status") or "") == "Planned"
            ]
            if not mutable:
                continue
            entities = [
                entity
                for record in mutable
                for entity in record.get("Payload", {}).get(
                    "CreateEntityCollection", []
                )
            ]
            resized_batches = _chunk_with_bucket_prerequisites(entities, size)
            base_description = str(
                mutable[0].get("Payload", {}).get("OperationSetDescription") or ""
            ).rsplit("-", 1)[0]
            project_id = str(
                mutable[0].get("ProjectId")
                or mutable[0].get("Payload", {}).get("ProjectId")
                or ""
            )
            for offset, batch in enumerate(resized_batches):
                description = f"{base_description}-continuation-{wave_number + offset + 1}"
                payload = {
                    "ProjectId": project_id,
                    "OperationSetDescription": description,
                    "CreateEntityCollection": batch,
                }
                if offset < len(mutable):
                    record = mutable[offset]
                    record["Payload"] = payload
                    record.setdefault("SubmissionRequest", {})["Payload"] = payload
                    record["OperationCount"] = len(batch)
                else:
                    record = client.register_operation_set(
                        project_id,
                        description,
                        batch,
                        project_name,
                    )
                    record["ConfirmedAbsentFromDataverse"] = True
            for record in mutable[len(resized_batches):]:
                record["Status"] = "Superseded before submission"
            log(
                f"Project '{project_name}': resized confirmed-unsent work to "
                f"at most {size} operation(s) per set."
            )

    while True:
        if stop_requested and stop_requested():
            raise ExecutionStopped("Execution stopped by the user.")
        _require_authorization_window(
            settings_provider,
            log,
            client,
            authorization_refresh,
        )
        settings = settings_provider()
        requested_operations_per_set = int(settings["operations_per_set"])
        if requested_operations_per_set != continuation_operations_per_set:
            resize_confirmed_unsent(requested_operations_per_set)
            continuation_operations_per_set = requested_operations_per_set
        pending_by_project: dict[str, list[dict[str, Any]]] = {}
        for index, record in enumerate(records, start=1):
            status_text = str(record.get("Status") or "")
            if status_text.startswith(("Completed", "Superseded")):
                continue
            if status_text.startswith((
                "Failed", "Abandoned", "Reconciliation error"
            )):
                continue
            pending_by_project.setdefault(
                str(record.get("Project") or ""), []
            ).append(record)
        if not pending_by_project:
            break

        concurrency = settings["concurrent_operation_sets"]
        operations_per_set = settings["operations_per_set"]
        poll_seconds = settings["polling_wait_seconds"]
        wave_records = [
            project_records[0]
            for project_records in pending_by_project.values()
        ][:concurrency]
        wave_number += 1
        log(
            f"Continuing wave {wave_number} with {len(wave_records)} project(s): "
            f"concurrency={concurrency}, operationsPerSet={operations_per_set}, "
            f"pollingWait={poll_seconds}s."
        )

        def continue_record(record: dict[str, Any]):
            worker_logs: list[str] = []
            worker = client.new_worker(log=worker_logs.append)
            try:
                worker.execution_records = records
                payload = record.get("Payload", {})
                description = str(payload.get("OperationSetDescription") or "")
                project_id = str(
                    record.get("ProjectId") or payload.get("ProjectId") or ""
                )
                operation_set_id = str(record.get("OperationSetId") or "")
                was_submitted = False
                worker_logs.append(
                    f"Reconciling project '{record.get('Project', '')}', "
                    f"batch {record.get('Batch', 'n/a')}, description='{description}', "
                    f"operationSetId={operation_set_id or 'unknown'}."
                )
                if not operation_set_id:
                    operation_set_id = worker.recover_operation_set(
                        description,
                        attempts=24,
                        wait_seconds=5,
                    ) or ""
                    if operation_set_id:
                        record["OperationSetId"] = operation_set_id
                        record["Status"] = "Recovered during continuation"
                        worker_logs.append(
                            f"Recovered '{description}' as {operation_set_id}; "
                            "polling only."
                        )
                if not operation_set_id:
                    status_text = str(record.get("Status") or "")
                    if "unknown" in status_text.lower() or status_text.startswith(
                        ("Sending", "Request failed", "Response missing")
                    ):
                        record["Status"] = "Outcome unknown - awaiting reconciliation"
                        raise OperationSetOutcomeUnknown(
                            f"Operation set '{description}' is still not visible after "
                            "the reconciliation window. It was not resent."
                        )
                    record["ConfirmedAbsentFromDataverse"] = True
                    worker_logs.append(
                        f"'{description}' was absent throughout the reconciliation "
                        "window; submitting once."
                    )
                    response = worker.execute_operation_set(
                        project_id,
                        description,
                        payload.get("CreateEntityCollection", []),
                        project_name=str(record.get("Project") or ""),
                        execution_record=record,
                    )
                    operation_set_id = (
                        worker.operation_set_id_from_response(response) or ""
                    )
                    if not operation_set_id:
                        raise ProjectOperationsError(
                            f"Continuation request '{description}' did not return an "
                            "OperationSetId."
                        )
                    was_submitted = True
                worker.wait_for_operation_sets(
                    [operation_set_id],
                    poll_seconds=poll_seconds,
                    stop_requested=stop_requested,
                )
                worker_logs.append(
                    f"Reconciled project '{record.get('Project', '')}', "
                    f"batch {record.get('Batch', 'n/a')}: "
                    f"status={record.get('Status', '')}, "
                    f"operationSetId={operation_set_id}."
                )
                error: Exception | None = None
            except Exception as exc:  # noqa: BLE001
                error = exc
                record["ReconciliationError"] = str(exc)
                if not str(record.get("Status") or "").startswith((
                    "Failed", "Abandoned"
                )):
                    record["Status"] = "Reconciliation error - paused"
                worker_logs.append(
                    f"Reconciliation failed for project "
                    f"'{record.get('Project', '')}', batch "
                    f"{record.get('Batch', 'n/a')}: {exc}"
                )
            return (
                record,
                was_submitted,
                worker_logs,
                worker.executed_v3_payloads,
                worker.executed_v3_responses,
                error,
            )

        with ThreadPoolExecutor(max_workers=len(wave_records)) as executor:
            futures = [executor.submit(continue_record, record) for record in wave_records]
            reconciliation_errors: list[Exception] = []
            for future in as_completed(futures):
                (
                    record,
                    was_submitted,
                    worker_logs,
                    payloads,
                    responses,
                    reconciliation_error,
                ) = future.result()
                submitted += int(was_submitted)
                completed += int(reconciliation_error is None)
                client.executed_v3_payloads.extend(payloads)
                client.executed_v3_responses.extend(responses)
                for message in worker_logs:
                    log(message)
                if reconciliation_error is not None:
                    reconciliation_errors.append(reconciliation_error)
        if checkpoint:
            checkpoint(records)
        if reconciliation_errors:
            raise reconciliation_errors[0]

    skipped = sum(
        str(record.get("Status") or "").startswith("Superseded")
        for record in records
    )
    reconciled = len(records) - submitted
    final_completed = sum(
        str(record.get("Status") or "").startswith("Completed")
        for record in records
    )
    failed = sum(
        str(record.get("Status") or "").startswith(("Failed", "Abandoned"))
        for record in records
    )
    unresolved = len(records) - final_completed - skipped - failed
    log(
        "Reconciliation finished: "
        f"{final_completed} completed, {failed} failed/abandoned, "
        f"{skipped} superseded, {unresolved} unresolved, "
        f"{submitted} submitted during continuation."
    )
    return {
        "completed": final_completed,
        "submitted": submitted,
        "reconciled": reconciled,
        "superseded": skipped,
    }


def submit_workbook(
    client: ProjectOperationsClient,
    workbook: Workbook,
    *,
    project_keys: list[str] | None = None,
    create_resources: bool = True,
    create_dependencies: bool = True,
    reuse_existing_project: bool = True,
    concurrent_operation_sets: int = 10,
    operations_per_set: int = MAX_OPS_PER_SET,
    polling_wait_seconds: int = 30,
    log: Callable[[str], None] | None = None,
    checkpoint: Callable[[list[dict[str, Any]]], None] | None = None,
    settings_provider: Callable[[], dict[str, int]] | None = None,
    authorization_refresh: Callable[[], dict[str, Any]] | None = None,
    stop_requested: Callable[[], bool] | None = None,
) -> list[tuple[ProjectInfo, SubmitResult | None, str]]:
    """
    Submit every selected project. Returns a list of
    ``(project, result_or_None, error_message)`` so the UI can report
    per-project outcomes without one failure aborting the rest.
    """
    log = log or (lambda _m: None)
    settings_provider = settings_provider or (lambda: {
        "concurrent_operation_sets": concurrent_operation_sets,
        "operations_per_set": operations_per_set,
        "polling_wait_seconds": polling_wait_seconds,
    })
    selected = workbook.projects
    if project_keys is not None:
        selected = [p for p in workbook.projects if p.key in project_keys]
    if not 1 <= concurrent_operation_sets <= 10:
        raise ValueError("Concurrent operation sets must be between 1 and 10.")
    if not 1 <= operations_per_set <= MAX_OPS_PER_SET:
        raise ValueError(
            f"Operations per set must be between 1 and {MAX_OPS_PER_SET}."
        )
    if polling_wait_seconds < 1:
        raise ValueError("Polling wait time must be greater than 0 seconds.")

    outcomes_by_project: dict[int, tuple[ProjectInfo, SubmitResult | None, str]] = {}
    waiting_projects = iter(selected)
    active: list[PreparedProject] = []

    def prepare(project: ProjectInfo):
        current_operations_per_set = settings_provider()["operations_per_set"]
        worker_logs: list[str] = []
        worker = client.new_worker(log=worker_logs.append)
        for attempt in range(1, 4):
            try:
                prepared = _prepare_project(
                    worker,
                    workbook,
                    project,
                    create_resources=create_resources,
                    create_dependencies=create_dependencies,
                    reuse_existing_project=reuse_existing_project,
                    operations_per_set=current_operations_per_set,
                    log=worker_logs.append,
                )
                return project, prepared, "", worker_logs
            except AuthorizationRequired:
                raise
            except requests.RequestException as exc:
                if attempt == 3:
                    worker_logs.append(
                        f"  !! Project '{project.name}' connection recovery "
                        f"failed after {attempt} attempts: {exc}"
                    )
                    raise
                worker_logs.append(
                    f"  ! Project '{project.name}' connection lost during "
                    f"preparation; reconnecting and retrying ({attempt}/2): {exc}"
                )
                worker.reconnect()
                time.sleep(5)
            except Exception as exc:  # noqa: BLE001
                worker_logs.append(
                    f"  !! Project '{project.name}' (key={project.key}) failed: {exc}"
                )
                return project, None, str(exc), worker_logs
        raise RuntimeError("Project preparation retry loop ended unexpectedly.")

    def fill_available_slots() -> None:
        if stop_requested and stop_requested():
            raise ExecutionStopped("Execution stopped by the user.")
        _require_authorization_window(
            settings_provider,
            log,
            client,
            authorization_refresh,
        )
        current_limit = settings_provider()["concurrent_operation_sets"]
        while len(active) < current_limit:
            candidates = []
            for _ in range(current_limit - len(active)):
                project = next(waiting_projects, None)
                if project is None:
                    break
                candidates.append(project)
            if not candidates:
                return
            with ThreadPoolExecutor(max_workers=len(candidates)) as executor:
                preparation_results = list(executor.map(prepare, candidates))
            for project, prepared, error, worker_logs in preparation_results:
                for message in worker_logs:
                    log(message)
                if prepared is None:
                    outcomes_by_project[id(project)] = (project, None, error)
                else:
                    active.append(prepared)
                    client.execution_records.extend(prepared.execution_records)
            if checkpoint and client.execution_records:
                checkpoint(client.execution_records)

    fill_available_slots()
    round_number = 0
    while active:
        if stop_requested and stop_requested():
            raise ExecutionStopped("Execution stopped by the user.")
        _require_authorization_window(
            settings_provider,
            log,
            client,
            authorization_refresh,
        )
        for prepared in active:
            prepared.client.set_access_token(client.access_token)
        round_number += 1
        current_settings = settings_provider()
        current_limit = current_settings["concurrent_operation_sets"]
        for prepared in active:
            _resize_unsent_batches(
                prepared,
                current_settings["operations_per_set"],
                client.execution_records,
            )
        round_active = active[:current_limit]
        deferred = active[current_limit:]
        log(
            f"Submitting round {round_number} for {len(round_active)} active "
            f"project(s) with concurrency={current_limit}, "
            f"operationsPerSet={current_settings['operations_per_set']}."
        )
        for slot_number, prepared in enumerate(round_active, start=1):
            execution_record = prepared.execution_records[prepared.next_batch]
            execution_record["Round"] = round_number
            execution_record["Slot"] = slot_number
            execution_record["ProjectKey"] = prepared.project.key
            execution_record["Batch"] = prepared.next_batch + 1
            execution_record["TotalBatches"] = len(prepared.batches)
            execution_record["OperationCount"] = len(
                prepared.batches[prepared.next_batch]
            )
            execution_record["ScheduledAtUtc"] = datetime.now(
                timezone.utc
            ).isoformat()
        if checkpoint:
            checkpoint(client.execution_records)

        def execute_batch(prepared: PreparedProject):
            payload_start = len(prepared.client.executed_v3_payloads)
            response_start = len(prepared.client.executed_v3_responses)
            try:
                operation_set_id = _execute_next_batch(prepared)
                error = ""
            except (AuthorizationRequired, requests.RequestException):
                raise
            except Exception as exc:  # noqa: BLE001
                operation_set_id = ""
                error = str(exc)
            return (
                prepared,
                operation_set_id,
                error,
                prepared.client.executed_v3_payloads[payload_start:],
                prepared.client.executed_v3_responses[response_start:],
            )

        with ThreadPoolExecutor(max_workers=len(round_active)) as executor:
            futures = [
                executor.submit(execute_batch, prepared)
                for prepared in round_active
            ]
            execution_results = []
            for future in as_completed(futures):
                execution_results.append(future.result())
                if checkpoint:
                    checkpoint(client.execution_records)

        submitted: list[PreparedProject] = []
        operation_set_ids: list[str] = []
        for (
            prepared,
            operation_set_id,
            error,
            payloads,
            responses,
        ) in execution_results:
            client.executed_v3_payloads.extend(payloads)
            client.executed_v3_responses.extend(responses)
            for message in prepared.logs:
                log(message)
            prepared.logs.clear()
            if error:
                log(
                    f"  !! Project '{prepared.project.name}' "
                    f"(key={prepared.project.key}) failed: {error}"
                )
                outcomes_by_project[id(prepared.project)] = (
                    prepared.project,
                    None,
                    error,
                )
            else:
                submitted.append(prepared)
                operation_set_ids.append(operation_set_id)

        if operation_set_ids:
            polling_started_at = datetime.now(timezone.utc).isoformat()
            for prepared in submitted:
                execution_record = prepared.execution_records[prepared.next_batch - 1]
                execution_record["PollingStartedAtUtc"] = polling_started_at
                log(
                    f"  [{polling_started_at}] project "
                    f"'{prepared.project.name}' "
                    f"(key={prepared.project.key or 'n/a'}, "
                    f"id={prepared.result.project_id}): polling batch "
                    f"{execution_record.get('Batch', prepared.next_batch)} "
                    f"in round {round_number}, slot "
                    f"{execution_record.get('Slot', 'n/a')}, "
                    f"operationSetId={execution_record.get('OperationSetId', '')}"
                )
            current_polling_wait = settings_provider()["polling_wait_seconds"]
            log(f"  Next polling wait is {current_polling_wait} second(s).")
            client.wait_for_operation_sets(
                operation_set_ids,
                poll_seconds=current_polling_wait,
                stop_requested=stop_requested,
            )
            for prepared in submitted:
                execution_record = prepared.execution_records[prepared.next_batch - 1]
                polling_finished_at = str(
                    execution_record.get("PollingFinishedAtUtc")
                    or datetime.now(timezone.utc).isoformat()
                )
                log(
                    f"  [{polling_finished_at}] project "
                    f"'{prepared.project.name}' "
                    f"(key={prepared.project.key or 'n/a'}, "
                    f"id={prepared.result.project_id}): polling completed for batch "
                    f"{execution_record.get('Batch', prepared.next_batch)}, "
                    f"status={execution_record.get('Status', '')}, "
                    f"operationSetId={execution_record.get('OperationSetId', '')}"
                )
            if checkpoint:
                checkpoint(client.execution_records)

        active = deferred
        for prepared in submitted:
            if prepared.has_remaining_batches:
                active.append(prepared)
            else:
                log(
                    f"Project '{prepared.project.name}' "
                    f"(key={prepared.project.key}) complete."
                )
                outcomes_by_project[id(prepared.project)] = (
                    prepared.project,
                    prepared.result,
                    "",
                )
        fill_available_slots()

    return [outcomes_by_project[id(project)] for project in selected]
