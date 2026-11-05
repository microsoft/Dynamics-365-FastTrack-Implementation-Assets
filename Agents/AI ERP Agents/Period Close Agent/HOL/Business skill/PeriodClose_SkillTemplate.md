---
name: PeriodClose_<YourSkillName>
description: <One paragraph the agent reads first. Say what the skill does, which closing schedule task names it matches (exact words), which Area corroborates it, what it excludes, and whether it is read-only, draft-only or allowed to post.>
---

# <Skill title>

<One or two sentences: what the procedure does and what the accountant receives.>

> **Owned by the Period Close business owner.** Edit the policy sections marked *edit to change the policy*.

## Classification

- `procedureClass`: `task-execution`
- `postingPolicy`: `DraftOnly` | `PostAuthorized`   *(DraftOnly for anything that creates journals for review or is read-only)*
- `supportedExecutionModes`: `Foreground` | `Batch` | both
- `defaultExecutionMode`: `<Foreground or Batch>`
- `executionModeRequestPolicy`: <which explicit mode requests are accepted or rejected, and why>
- Role: <short role description>

## Routing contract

Task **Name** must explicitly contain `<word or phrase 1>` or `<word or phrase 2>`.
**Area = <closing schedule area>** corroborates only and never creates a match.
Exclude: <task types this skill must never pick up>.

## Required data source

- Use **<Dynamics 365 ERP MCP | Dynamics 365 ERP Analytics MCP | SharePoint>** for every read and write.
- Name the exact entity, form (menu item) or SharePoint path. Confirm field names from metadata before querying; never guess.
- If the source is unavailable or the read fails, report the error and stop. Never use cached or remembered results.

## Scope

- **Legal entity** and **period** come from the close run. If either is missing, ask.
- <Which records, accounts, books or folders are in scope.>

## Date policy

- <Which date to use, normally the last calendar day of the closing period. Never today's date.>

## Policy — *edit to change the policy*

| Rule | Value |
|---|---|
| <threshold, account range, book, tolerance> | <value> |

## Report

**Columns:** <column list>.
**Summary:** <one-line summary format>.

## Business outcome (pick exactly one)

- **✅ <Success outcome>** — <condition and what happens next>.
- **⚠️ <Needs attention outcome>** — <condition; who is contacted>.
- **🛑 <Blocked outcome>** — <condition; nothing is changed>.

## Ground rules

- Report only figures from a live read.
- <Hard limits: never post, never change master data, never touch records the skill did not create.>
- The agent owns task status and notifications; this skill never changes task status.
