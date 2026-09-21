This solution and code are provided as-is. This is not first-party Microsoft product or code, and should not be treated as such. Always test in a non-production environment. This solution is intended to be adjustable and extendable by end customers based on their business requirement.


# Project Operations – Schedule Import (Streamlit)

A simple Streamlit app that reads a **Project Operations schedule template**
(`Projects`, `Tasks`, `Assignments`, `Dependencies` sheets) and creates the
projects, tasks, WBS hierarchy, resource assignments and dependencies in
**Microsoft Dynamics 365 Project Operations** via the Dataverse **Schedule
Web APIs**. Multiple projects per workbook are supported.

Use this application for data migration or as a local, single-user tool. Each
user can run an independent copy on their workstation. Shared multi-user
hosting is not supported or tested because execution state is held in the
application process.


It is a Python port of the Microsoft FastTrack
[Schedule API PowerShell sample](https://learn.microsoft.com/dynamics365/project-operations/project-management/schedule-api-preview).

## How it works

| Step | Web API call |
|------|--------------|
| Validate token | `GET WhoAmI` |
| Find existing project | `GET msdyn_projects` filtered by `msdyn_projectnumber` |
| Create project + default bucket | `POST msdyn_CreateProjectV1` |
| Find or create buckets | One `GET msdyn_projectbuckets` per project; create each distinct missing task bucket in prerequisite V3 OperationSets |
| Create project team member | Resolve an explicit `RoleName`, or the bookable resource's default role when blank, then `POST msdyn_CreateTeamMemberV1` with the resource and `msdyn_resourcecategory` bindings |
| Create schedule records | Prepare tasks, dependencies, and assignments in `CreateEntityCollection`, then `POST msdyn_ExecuteOperationSetV3` |

Task GUIDs are generated client‑side so parent/child and dependency links
resolve across operation sets. Tasks, dependencies, and assignments are
batched at the service limit of 200 operations per OperationSet.
The **Operations per set** option defaults to 200 and can be reduced to any
value from 1 through 200 when smaller OperationSets are preferred.

The **Concurrent operation sets** option controls how many projects are
active at once (default 10, maximum 10). Each active project submits one
OperationSet, then the app polls the full round. When a project finishes, the
next waiting project fills its slot in the following round while unfinished
projects continue with their next OperationSet.

The **Wait time for execution polling** option controls the number of seconds
between Dataverse status checks (default 30, minimum 1). The app checks each
submitted OperationSet immediately, waits only while one or more sets remain
open or pending, and then checks those remaining sets again. A shorter interval
updates the UI sooner but makes more Dataverse requests; it does not make the
OperationSets execute faster. A longer interval reduces polling traffic but can
delay detection of completion by up to approximately that interval. Changes to
this option apply to a future operation-set wave, not a polling loop already in
progress.

If a V3 submission loses its HTTP connection, the app opens a fresh session
and searches Dataverse for the uniquely described OperationSet. If found, it
resumes polling that OperationSet without resending the payload. If repeated
lookups cannot establish the submission outcome, the app pauses rather than
risk sending the payload twice. Transient connection failures during status
polling reconnect automatically. If multiple OperationSets match the same
description, recovery also pauses rather than guessing which one to use.

## Durable execution & recovery

Execution runs in a background runtime (`runtime_controller.py`) that keeps
processing across Streamlit page reruns, so navigating the UI or a browser
refresh does not interrupt an import.

Every run writes durable artifacts under a timestamped folder in
`execution_records/<run-id>/`:

- `original-workbook.xlsx` – the uploaded template
- `execution-history.csv` – per-OperationSet outcomes
- `execution-diagnostics.json` – detailed diagnostics
- `activity-log.txt` – the full activity log

An `active-upload.json` checkpoint tracks recoverable state during a run. A run
that successfully completes every selected project writes its final artifacts
and clears the active checkpoint. Incomplete runs retain it; discarded and
replaced checkpoints are archived for troubleshooting. Each OperationSet
carries a unique, immutable description, which enables exactly-once
reconciliation after a lost response, restart, or safe stop.

Before each new operation-set wave, the app checks whether authorization has at
least five minutes remaining. Microsoft sign-in and username/password sessions
attempt silent rotation. A pasted token cannot be renewed, so the app finishes
the current wave, checkpoints, and pauses before submitting another wave.

Use the **Manage operation sets** page (opened from the sidebar) to abandon
open OperationSets by ID when needed.

## Workstation requirements

Install these before opening the application:

- **Windows 10 or Windows 11** with PowerShell.
- **Visual Studio Code**. To launch by typing a request in Chat, install the
  **GitHub Copilot** extension and sign in to an account with Copilot access.
- **Python 3.11 or later**, with **Add Python to PATH** selected during
  installation.
- A modern web browser.
- Network access to Python package downloads, Microsoft Entra ID, and the
  target Dataverse environment. A corporate proxy or software-installation
  policy may require assistance from your IT administrator.
- A Project Operations account with a Microsoft Project license and permission
  to read and update the target environment.

The first VS Code launch creates a project-local `.venv` and automatically
installs the packages listed in `requirements.txt`: Streamlit, pandas,
openpyxl, requests, and Azure Identity. Internet access is required for this
initial package installation. Git, a separate database, and a separate web
server are not required when the repository is downloaded as a ZIP. Microsoft
Excel is optional but recommended for editing the workbook templates.

## Run in Visual Studio Code

1. Download and extract the repository folder.
2. Install Python 3.11 or later from <https://www.python.org/downloads/>. On the
  Windows installer, select **Add Python to PATH**.
3. In Visual Studio Code, select **File > Open Folder**, then choose the
  extracted repository folder.
4. Open GitHub Copilot Chat in Visual Studio Code.
5. Enter `launch the application` in Chat and allow it to run the workspace's
   **Launch Streamlit application** task.

Without GitHub Copilot Chat, select **Terminal > Run Build Task**, or press
**Ctrl+Shift+B**, to run the same task directly.

The first launch creates a private `.venv` environment and installs the required
packages automatically. Later launches reuse that environment and check that
its packages are current. Streamlit opens the application in the default
browser. Keep the VS Code task terminal open while using the application; stop
the task to shut it down.

## Included sample files

After launching the application, use the two included sample workbooks to
become familiar with the import process:

- `sample_template.xlsx` is a valid example to populate with your own sandbox
  data and use for an end-to-end test. Replace its sample values with records
  that exist in your target Project Operations environment before submitting.
- `sample_template - validation testing.xlsx` intentionally contains examples
  of data that should not be populated. Upload it to understand the validation
  rules already built into the application and review the resulting validation
  messages. Correct those issues before submission; do not submit this workbook
  as supplied.

Always test with non-production data and a sandbox environment first.

To modify the template mapping or add and remove columns, update the application
code and validation rules together.

## Manual developer setup

```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install --upgrade pip
pip install -r requirements.txt
```

Optional local defaults can be set before launching the app. Do not put access
tokens or passwords in environment variables or committed files.

```powershell
$env:DATAVERSE_ENVIRONMENT_URL = "https://yourorg.crm.dynamics.com"
$env:DATAVERSE_USERNAME = "user@contoso.com" # Legacy ROPC flow only
$env:AZURE_CLIENT_ID = "your-public-client-application-id" # Legacy ROPC only
```

Run the application manually with:

```powershell
.\.venv\Scripts\python.exe -m streamlit run app.py
```

Then in the browser:

1. **Connection** (sidebar) – enter the Environment URL, then use the default
  **Microsoft sign-in (automatic)** authorization, username/password, or a
  pasted access token. Click **Test connection**.
2. **Upload** the `.xlsx` template.
3. **Review** the detected projects, row counts, tasks, assignments, and
  dependencies, then choose the projects to submit. The displayed tables are
  read-only; correct source data in the workbook and upload it again when
  changes are needed.
4. **Validate** the current file and environment. Validation checks required
  tabs and values, duplicate keys, cross-tab references, task hierarchy,
  dependencies, parent-task restrictions, and every supplied Dataverse lookup
  value. Every issue is numbered in one table with Project Operations parameter
  differences.
5. **Submit** after validation completes.

The execution settings in the sidebar remain available while processing. The
app reads **Operations per set**, **Concurrent operation sets**, and **Wait time
for execution polling** before a future wave, so changes affect work that has
not yet been submitted. They do not alter OperationSets already submitted to
Dataverse. During continuation, changing **Operations per set** re-batches only
confirmed-unsent planned work; submitted or outcome-unknown work is never
resized.

Each selected project is preflighted as one unit before any write is sent to
Dataverse. If a supplied customer, company, contracting unit, calendar, project
manager, role, task reference, or dependency cannot be represented, that project
is logged as skipped and receives no project, team-member, or OperationSet POST.
A ResourceName that does not match a bookable resource is sent as a generic team
member when an explicit RoleName is supplied. Lookup GET requests are still
recorded because they are required to resolve workbook names and codes to
Dataverse IDs.

Validation also checks the Project Operations Parameters record and recommends
the migration settings `msdyn_estimatepricing = On-demand pricing`,
`msdyn_projecttasktimetracking = Delayed update`, and
`msdyn_projectactualstracking = On-demand update`. These settings can be changed
under **Parameters** in the Project Operations app.

During execution, select **Stop execution safely** to prevent additional
OperationSets from being submitted. OperationSets already sent to Dataverse
continue there and are retained in the local checkpoint. After stopping:

- Select **Continue stopped execution** to reconcile submitted work and resume
  the unchanged retained plan.
- If workbook data must be corrected, select **Discard and start over**, upload
  the corrected workbook, and submit again. The discarded run is saved in local
  execution history before the file, validation results, logs, and execution UI
  are cleared. Discarding does not delete projects, tasks, or OperationSets
  already created in Dataverse.

Removing the selected file from **Upload template** performs the same clean
reset only when execution is not running. During an active run, removing the
file from the picker does not cancel or clear the background execution; the app
retains the execution summary and live activity log. Select **Stop execution
safely**, wait for checkpointing to finish, and then use **Discard and start
over** when the retained plan should be cleared. Authorization remains separate
from upload state and may stay active after a file is removed.

## Understanding execution status

| Status | Meaning |
|--------|---------|
| `IDLE` | No active or retained execution exists. |
| `RUNNING` | The background worker is preparing, submitting, or polling work. |
| `STOPPING - CHECKPOINTING` | A safe stop was requested; no new work will be submitted. |
| `PAUSED - STOPPED BY USER` | The safe stop completed and the retained plan can be continued or discarded. |
| `PAUSED - AUTHORIZATION REQUIRED` | Reauthenticate before continuing the retained plan. |
| `PAUSED - CONTINUATION REQUIRED` | A recoverable checkpoint requires an explicit Continue action. |
| `INCOMPLETE` | One or more selected projects remain unfinished without an active checkpoint. |
| `FAILED` | A project or OperationSet failed; review the error table and activity log. |
| `COMPLETE` | Every selected project and its non-superseded OperationSets completed. |

While the worker is active, the page shows **Live execution** and **Activity log
(live)**. Once it stops, these become **Execution summary** and **Activity log**.
The detailed CSV, diagnostics, and log files remain under `execution_records/`.

## Authentication / token

The Schedule APIs can **only be called by a user who holds a Microsoft Project
license** – application / client‑secret users are rejected by the service.
The app offers three ways to authenticate:

### Microsoft sign-in (automatic, recommended)

Click **Sign in with Microsoft**. The app discovers the Microsoft Entra tenant
directly from the configured Environment URL and opens a secure Microsoft
sign-in window. MFA is supported. The credential remains cached in the running
application and renews the access token automatically during long uploads.

### Username / password

This legacy option uses the OAuth 2.0 ROPC flow. Microsoft has deprecated ROPC
because the application handles the user's password and the flow is incompatible
with MFA, passwordless authentication, and many Conditional Access policies.
Use **Microsoft sign-in (automatic)** unless no more secure flow is viable.

If ROPC is required, enter the UPN and password and click **Sign in**. Under
*Advanced* you can override the tenant (defaults to the domain of the username)
and client application ID.

* Requires a public‑client Azure AD app registration with delegated Dynamics
  CRM permission and **Allow public client flows** enabled. Set
  `AZURE_CLIENT_ID` or enter your tenant-owned application ID in the UI.
* **ROPC does not support MFA or guest accounts.** If your account requires
  MFA, use Microsoft sign-in (automatic), or paste a delegated user token.

### Paste an access token

Get a token with the Azure CLI (resource = your environment URL):

```powershell
az login
az account get-access-token --resource https://YOURORG.crm.dynamics.com --query accessToken -o tsv
```

Tokens last ~1 hour. Paste only the token string (no `Bearer ` prefix).

## Security and data handling

- Run the app only on a trusted workstation and bind Streamlit to localhost.
- Never commit or share tokens, passwords, tenant URLs, user identifiers, or
  `.streamlit/secrets.toml`.
- **Customer data warning:** treat `execution_records/` as sensitive customer
  data. It can contain uploaded workbooks, request and response bodies, project
  details, Dataverse record identifiers, diagnostics, and activity logs. The
  directory contents are excluded by `.gitignore`, except for its explanatory
  `README.md`, but generated records remain on the workstation. GitHub Actions
  rejects a pull request if any other file in this directory is tracked.
- The application never deletes execution records automatically. The user or
  organization controls retention and cleanup. Before manually deleting old
  records, stop the application and confirm that no interrupted upload needs
  recovery. Preserve `active-upload.json` and its referenced run folder while
  recovery may still be required.
- Review and redact diagnostics before attaching them to an issue.
- Use least-privilege delegated access and test against a sandbox before using
  the application with production data.

See [SECURITY.md](SECURITY.md) for vulnerability reporting and
[SUPPORT.md](SUPPORT.md) for support boundaries.

## Tests

Run the local smoke suite with:

```powershell
python -m py_compile app.py auth.py excel_loader.py po_client.py runtime_controller.py submit.py pages/abandon_operation_sets.py
python -m unittest discover -s tests -v
```

GitHub Actions runs these checks on Python 3.11 and 3.13 for every push and pull
request.

## Excel template format

The loader detects columns by **header name** (case/punctuation‑insensitive),
so minor layout differences are tolerated. It is a small relational model keyed
by `ProjectKey` and `TaskKey`:

**Projects sheet** – one row per project:
`ProjectKey, ProjectName, CompanyName, ContractingUnit, CustomerName, CalendarName, ProjectManager, ProjectStart`

`ProjectKey` maps to Dataverse `msdyn_projectnumber` and is used to find an
existing project before creating a new one.
`ContractingUnit` is required and must match an organizational unit name in
Project Operations. Live validation checks the value before submission, and
new projects bind it to `msdyn_contractorganizationalunitid`.

**Tasks sheet** – one row per task (`ParentTaskKey` references another row's `TaskKey`):

| Column | Maps to |
|--------|---------|
| ProjectKey | links the task to a project |
| TaskKey | unique task id (used by parents & dependencies) |
| TaskName | `msdyn_subject` |
| ProjectBucket | `msdyn_projectbucket`; matched case-insensitively or created once per distinct name. Blank uses the project's first/default bucket. |
| ParentTaskKey | parent task's **TaskKey** (WBS hierarchy) |
| EffortHours | `msdyn_effort` |
| ScheduledStart | `msdyn_scheduledstart` |
| ScheduledEnd | `msdyn_scheduledend` |
| OutlineLevel | informational (hierarchy derives from ParentTaskKey) |

**Assignments sheet** – `ProjectKey, AssignmentKey, TaskKey, ResourceName, RoleName`.
`ResourceName` is matched to a bookable resource by name. When supplied,
`RoleName` is matched by name to a `bookableresourcecategory` and is sent to
`msdyn_projectteam.msdyn_resourcecategory`. When `RoleName` is blank, the
matched bookable resource's active default resource category is used.
Submission fails if neither an explicit resource category nor a configured
default is available. A resource must use one `RoleName` within a project.
Legacy templates whose column is named `Role` remain supported.

**Dependencies sheet** – `ProjectKey, PredecessorTaskKey, SuccessorTaskKey, LinkType`
where `LinkType` is one of `FinishToStart`, `StartToStart`, `FinishToFinish`,
`StartToFinish`.

An `Instructions` sheet, if present, is ignored.

> **Note on sensitivity labels:** if the supplied
> `ProjectOperationsScheduleImportTemplate.xlsx` carries a Microsoft Purview /
> IRM encryption label, its bytes can't be read programmatically. Remove or
> downgrade the label (or upload an unprotected copy) so the app can read it.
> Use `python make_sample.py` to create a `sample_template.xlsx` for testing.

## Files

| File | Purpose |
|------|---------|
| `app.py` | Streamlit UI, authentication, validation, execution controls, checkpoint/archive |
| `auth.py` | User-token acquisition: interactive Microsoft sign-in, username/password (ROPC), silent refresh, tenant discovery |
| `excel_loader.py` | Parse and validate Projects / Tasks / Assignments / Dependencies sheets |
| `po_client.py` | Dataverse / Schedule Web API client (submit, poll, exactly-once recovery) |
| `submit.py` | Orchestration: OperationSet wave planning, rolling concurrency, reconciliation and continuation |
| `runtime_controller.py` | Background execution runtime that survives Streamlit page reruns |
| `pages/abandon_operation_sets.py` | Utility page to abandon open OperationSets by ID |
| `make_sample.py` | Generate a test workbook |
| `execution_records/` | Durable per-run artifacts: checkpoint, history CSV, diagnostics JSON, activity log |

## Disclaimer

Sample/reference code provided **as‑is**, without warranty. Test against a
sandbox environment before using against production.
