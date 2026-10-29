---
name: PeriodClose_MonthlyDepreciation
description: Submits the monthly fixed asset depreciation proposal for the closing period as a batch job for accountant review and posting. Match when the task Name explicitly contains monthly depreciation; Fixed assets Area is corroborating only. Supplies a blocking precheck that refuses to run while unposted Post fixed assets journals exist for the legal entity, plus the period-end proposal date, one-period-per-run, scope, batch-only, never-post and review-handoff policy. Excludes acquisition, reconciliation, disposal, journal import, generic asset review, multi-period proposals and any posting request. Read-only for journals it did not create; never posts.
---

# Monthly fixed asset depreciation (lab skill)

Submits the monthly fixed asset depreciation proposal for the closing period as a batch job, so the
responsible accountant can review and post the resulting journal.
**Proposal only — never posted by the agent.**

> **Owned by the Period Close business owner.** This skill was added in Part 3 of the Period Close
> Agent hands-on lab. Edit the date policy, scope filter policy or outcomes below to change the behavior.

## Classification

- `procedureClass`: `task-execution`
- `postingPolicy`: `DraftOnly` *(structural — see Run policy)*
- `supportedExecutionModes`: `Batch` *(only)*
- `defaultExecutionMode`: `Batch`
- `executionModeRequestPolicy`: an explicit run-level `Batch` request is accepted — it matches the only
  supported mode. An explicit `Foreground` request is **rejected as unsupported**: the depreciation
  proposal is never run in session, and the agent fails the task closed rather than downgrading it.
- Role: monthly fixed-asset depreciation proposal procedure (lab skill)

## Routing contract

Task **Name** must explicitly contain `monthly depreciation`. **Area = Fixed assets** corroborates
only. Exclude acquisition, reconciliation, disposal, journal import, generic asset review,
multi-period proposals, and posting work.

## Scope

- **Period** — a calendar month, e.g. `April 2026`. It comes from the close run; if it is missing,
  ask. Never assume a period.
- **Legal entity** — already in scope from the close run.
- **Scope filter** *(optional)* — a book, depreciation layer or asset group the calling task passes
  through. If the task says nothing, run **unfiltered** so every asset and book due for the period
  is evaluated.

## Date policy

The **proposal date is the last calendar day of the period** (e.g. `2026-04-30` for April 2026). It
is the single date that decides which assets and books are in scope.

Never use the current date, the period's first day, or a quarter-end date.

## Blocking precheck — no unposted fixed asset journals

**Run this before anything else. If it fails, nothing is submitted.**

Depreciation must never be proposed while unposted fixed asset journals exist for the legal entity.
Those journals may already contain depreciation, adjustments or splits for the same assets and
period; proposing on top of them risks double depreciation and leaves the accountant with two
overlapping journals to untangle. Only a human decides what happens to them.

**Scope of the check.** Journals of journal **Type = `Post fixed assets`** in the legal entity in
scope, in any unposted state. Journal *names* vary by legal entity — resolve them from the
`JournalNames` entity where `Type` = `Post fixed assets` rather than assuming. In USMF these are
`FACur`, `FAOper` and `FATax`. Journal types `Fixed asset budget` and `Asset leasing` are **not** in
scope, and neither are general, vendor or customer journals.

**Where to read it.** The **Fixed asset journal** list — Display menu item `LedgerJournalTableAssets`
(form caption "Fixed asset journal"). Its **Show** filter has options `All`, `Not posted` and
`Posted`, and opens on **`Not posted`**. Confirm the filter actually reads `Not posted` before
trusting the grid; do not assume the default held.

> ⚠️ **Do not use the `LedgerJournalHeaders` data entity for this check.** Verified live in USMF: the
> form listed unposted `FACur` journals while `LedgerJournalHeaders` returned **zero rows** for the
> same journal names — even with no posted-state filter at all. That entity does not expose fixed
> asset journals, so it would report "nothing unposted" every time and silently wave the run
> through. A guard that cannot fail is worse than no guard.

**Decision.**

- **No unposted fixed asset journal** → precheck passes. Continue to the run policy.
- **One or more unposted fixed asset journals** → **stop. Submit nothing.** The proposal is not
  queued, no batch job is created, and the outcome is *Blocked — unposted fixed asset journals*. Ask
  the responsible person to **post or delete** each one, then re-run this task. Never post, delete,
  validate, modify or clear a journal to clear the block — that is the human's decision, and the
  agent has no authorization to touch a journal it did not create.

**Report, for each blocking journal:** journal batch number, journal name, description, and modified
by. Include a deep link to the Fixed asset journal list so the accountant lands on the exact list.
The grid returns at most 25 rows, so when 25 come back report the count as **"at least 25"** and
never as an exact total — the guard is binary and unaffected, but the number must not be overstated.

## Run policy

- **Posting policy — `DraftOnly`, and this one is structural, not a preference.** The proposal builds
  the journal only. The posting option stays off, and no separate posting step is ever taken from
  this task. If the posting option cannot be confirmed off, the run must not proceed — a
  posted-without-review journal is unacceptable.

  **Do not flip this to `PostingAllowed`.** The journal is built server-side *after* the batch is
  queued, and this skill explicitly never reads it back. The agent therefore has nothing to verify,
  and posting without a verified read-back would violate the re-read-proves-every-write rule.
  Enabling posting for depreciation would require redesigning this skill around a completion-aware,
  read-back-capable flow first.
- **Run as a batch job.** The proposal runs on the server so it scales and does not depend on the
  session. If it cannot be queued as a batch job, stop rather than running it in-session.
- **Hand-over, not completion.** Once the job is queued the task's automated work is done; the
  journal is built server-side afterwards. Do not wait for the job, and do not read back the
  journal's contents — there is nothing to verify. Proving that the batch framework accepted the job,
  and everything that follows from it, is governed by the local **execute-period-close-task**
  behavior ("The batch handover boundary"); this skill neither restates nor overrides it.
- **Defaults are the legal entity's.** Journal name, posting layer and depreciation summarization
  stay as the legal entity has them unless the calling task explicitly overrides them. **Record the
  journal name** — the reviewer needs it to find the journal.
- **One period, one run.** Never merge periods into a single proposal, and do not re-submit for a
  period already queued in the same closing cycle without an explicit instruction.

### Batch Task description

The batch **Task description** is what makes this submission findable and provable afterwards — the
agent's hand-over proof reads the batch job list by this exact text. The dialog default is useless
here: every depreciation proposal in the legal entity looks identical. Always replace it with:

```
FA monthly depreciation | <Period> | <LegalEntity> | <ClosingSchedule> | T<TaskSourceKey> | A<StartedDateTime>
```

For example: `FA monthly depreciation | April 2026 | USMF | 2026_04 | T5637144901 | A2026-04-30T22:18:04Z`.

- **`<Period>`** — the period in scope, e.g. `April 2026`, exactly as the close run established it.
  Use the period, not the resolved proposal date; the proposal date still governs the run itself and
  is reported separately.
- **`<LegalEntity>`** — the legal entity in scope, e.g. `USMF`.
- **`<ClosingSchedule>`** — the closing schedule name from the established close context, e.g.
  `2026_04`.
- **`T<TaskSourceKey>`** — the discriminator: the closing-schedule task's own `SourceKey`, prefixed
  `T`, taken from the established task snapshot the calling task already carries.
- **`A<StartedDateTime>`** — the attempt discriminator, prefixed `A`. Use the exact UTC ISO
  `StartedDateTime` returned by execute-period-close-task's live post-MarkStarted verification read.
  Do not generate a timestamp, use the current time, reformat the value, or reuse the pre-start
  timestamp. This makes a legitimate re-execution of a Returned task distinct from its prior batch
  attempt.

**Use only what the established close context and task snapshot already supply, and invent nothing.**
All five context values are required in the description. If the task `SourceKey`, verified
post-MarkStarted `StartedDateTime`, period, legal entity or closing schedule is unavailable,
ambiguous, unchanged from the pre-start value, or otherwise unusable, fail closed before submission
rather than substituting a timestamp, counter, GUID, default or shortened value.

`BatchJobs.JobDescription` has a verified maximum length of **200 characters**. Construct the full
text first and require its length to be `<= 200`. Confirm it was accepted unchanged — a silently
truncated description breaks the exact-match hand-over read. Never drop, abbreviate, shorten,
substitute or truncate any component to make it fit. If the complete description exceeds 200
characters, fail closed before submission and report that a unique provable Batch Task description
could not be supplied.

Proving the hand-over from this description — the exact-match read, what one row, no row or several
rows mean, and the one-occurrence/no-recurrence rule — is owned by the local
**execute-period-close-task** behavior ("The batch handover boundary"). This section supplies the
name and nothing more.

## What to report

- **Period** processed and the resolved **proposal date**.
- **Legal entity** and the **journal name** the depreciation journal will appear under.
- The **batch Task description** the job was submitted under, so the reviewer and the hand-over
  evidence name the same job.
- **Scope filter** applied, or "unfiltered".
- The **confirmation returned by D365**, verbatim.
- The **responsible person** who reviews, posts, and then closes the task.
- Optional Dynamics 365 ERP MCP `DeepLinks` returned by the live proposal operation, preserved as
  navigation metadata for the proposal/journal result.
- **Batch-submission evidence returned to execute-period-close-task:** always return
  `batchSubmissionAttempted` as an explicit boolean. Return `batchTaskDescription` as the exact text
  submitted when it is `true`; return `batchTaskDescription: null` when it is `false`. This skill
  does not read `BatchJobs` or decide whether the hand-over was proved.

**Example:** *"Submitted a fixed assets depreciation proposal for period `April 2026` (proposal date
`2026-04-30`) in `USMF` under journal `FACur`, unfiltered, as a batch job. **Started successfully —
not posted.** Once the batch completes, <responsible person> reviews the journal under `FACur`, posts
it, and marks the closing-schedule task complete."*

## Business outcome (pick exactly one)

- **✅ Started successfully** — the proposal was queued as a batch job with posting off, and the
  confirmation was captured. Return `batchSubmissionAttempted: true` and the exact
  `batchTaskDescription`. This is a **review handoff candidate, not a completion**; the local
  execute-period-close-task behavior performs the hand-over proof before notifying the reviewer.
- **🛑 Blocked — unposted fixed asset journals** — the precheck found one or more unposted journals
  of type `Post fixed assets` in the legal entity. **Nothing was submitted and no batch job was
  created.** Return `batchSubmissionAttempted: false` and `batchTaskDescription: null`. Report each
  blocking journal (batch number, name, description, modified by) with the deep link to the Fixed
  asset journal list, and ask the responsible person to post or delete them and then re-run the task.
  The close task stays open.
- **🛑 Submission blocked** — the proposal could not be submitted, posting could not be confirmed
  off, or batch processing could not be turned on. Report the cause with the proposal date, scope
  filter, journal name if known, and the message returned, and notify the responsible person. If no
  submission call was attempted, return `batchSubmissionAttempted: false` and
  `batchTaskDescription: null`. If the submission call was attempted, return
  `batchSubmissionAttempted: true` and the exact description used even when the call returned an
  error, so execute-period-close-task can apply the unproved-handoff boundary.

*There is no warning or "no depreciation" outcome at this point — the batch has not run yet, so
line-level results are only visible to the accountant when they open the journal.*

## Ground rules

- **Proposal only — the agent never posts.** Final posting is always the responsible accountant's
  action after review.
- **The task is never closed by this run.** The responsible accountant closes the closing-schedule
  task after reviewing and posting the journal.
- **Never clear the block yourself.** Posting, deleting, validating or editing an unposted fixed
  asset journal to get past the precheck is forbidden. The agent only ever creates a proposal; it
  never touches a journal it did not create.
- Report only what a live run returned — never cached asset balances, journal names or prior results.

## ERP DeepLinks contract

- Capture optional `DeepLinks` returned by the proposal form/data operation as exact `{Label, Url}`
  metadata with the originating operation and record/result-set scope.
- Never fabricate, reconstruct, normalize, shorten, decode, re-encode, trim, relabel, or alter any
  query-string component, including encoded `q=`.
- Return applicable links on the typed business outcome as ordered `erpDeepLinks`, filtered to this
  legal entity, period, task, and proposal/journal operation. Deduplicate only by exact
  case-sensitive `Url` equality, preserving the first occurrence, label, and order. Exclude
  irrelevant and configuration-marker links.
- A **Started successfully** outcome passes its proposal/journal-relevant links into the
  ReviewHandoff metadata. A **Blocked — unposted fixed asset journals** outcome carries the Fixed
  asset journal list link. A **Submission blocked** outcome carries only links relevant to the failed
  step or its verification evidence.
- In an interactive outcome, render retained items as `[returned Label](returned Url)` under a
  Dynamics 365 links section. Omit the section and `erpDeepLinks` when empty.
- Missing links are normal and never justify resubmitting the batch, changing the run mode, or
  changing the business outcome.
