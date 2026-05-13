---
name: workflow-feature
description: |
  FEATURE profile workflow: Research → Plan → Execute → Validation → Review → Done. Activated by swift-toolkit:orchestrator; not invoked by the user directly.
  Use when (en): orchestrator dispatches a task with [TASK_TYPE]=FEATURE
  Use when (ru): оркестратор диспетчеризует задачу с [TASK_TYPE]=FEATURE
---

# Workflow Feature

The profile workflow for tasks with `[TASK_TYPE] = FEATURE`. Implements the sequence of stages; the result of each stage is an artifact file inside the task folder. The skill receives an already-resolved contract from the orchestrator and does not try to re-resolve any parameter on its own.

## Language Resolution

Before producing any user-facing string:

1. Read `CLAUDE-swift-toolkit.md` from the project root.
2. Find the `## Language` section.
3. Take the first non-empty line in that section, lowercase and trim it. That is `<lang>`.
4. If `<lang>` is `en` or `ru`, use it. Otherwise default to `en`.
5. Read this skill's `locales/<lang>.md`. Look up keys by H2 header.
6. If a key is missing, fall back to the same key in `locales/en.md`. If still missing, that's a bug — fail loudly with key name.

Caching: resolve `<lang>` once per skill invocation; do not re-read CLAUDE-swift-toolkit.md per string.

## 1. Input Contract

The skill is invoked by `swift-toolkit:orchestrator` via the `Skill` tool with structured `args` in `key=value` form, separated only by newlines.

The field structure is documented in `swift-toolkit:orchestrator` (section **Outbound Contract**). Workflow-feature accepts every field already filled — invariant.

If a required field arrives empty — workflow-feature does not try to recover. It returns `{status: error, reason: status_error_empty_required_field}` (the `reason` value is taken from the locale key in `locales/<lang>.md`) back to the orchestrator.

The fields that directly drive this workflow's behavior:
- `start_stage`, `end_stage`, `stage_scope` — determine which stages run.
- `start_phase` — entry point inside a stage (e.g. `Execute:phase=2.3`).
- `mode` — `manual` / `auto` (see sections 3 and 4).
- `stack` — passed to subagents as context.
- `need_test`, `need_review` — gate the inclusion of `swift-toolkit:swift-tester` and `swift-toolkit:swift-reviewer`.
- `archive_paths` — paths to backups already created (the orchestrator made them BEFORE the call; workflow-feature does not create them).

**Execution range.** Stages run in the order Research → Plan → Execute → Validation → Review → Done, starting at `start_stage` and continuing through `end_stage` inclusive. If `end_stage=null` — through the end of the profile. If `end_stage` is set but precedes `start_stage` in order, that is a contract error: return `{status: error, reason: "end_stage before start_stage"}`.

**Scope.** `stage_scope` controls execution width:
- `single` — only `start_stage` runs; afterwards the workflow returns `{status: ok, last_completed_stage: <start_stage>, next_recommended_action: stop}`. Used for `action=redo`.
- `forward` — `start_stage` plus every subsequent stage up to `end_stage` (or to the end of the profile). Used for `action=run`/`continue`/`restart`.
- `all` — equivalent to `forward` with `start_stage = first stage of the profile`. Used for `action=restart-full`.

## 2. Stages

- **Research** — a panel: `swift-toolkit:swift-architect` + `swift-toolkit:swift-security` (via the Task tool, in parallel or sequentially as the orchestrator decides). Artifact: `Research.md` in the task folder. Goal: investigate the domain, surface risks, propose architectural options.

  The architect MUST apply the `feature-requirements` skill and then the `feature-landscape` skill, producing two H2 sections inside `Research.md`: `## Requirements` (Primary / Secondary / Designer questions / Backend questions / Known unknowns) and `## Landscape` (Entity graph / Layer map / Integration points / Work items / Implementation sequence). The `## Architectural Analysis` and other architect-output sections are appended after these two.

- **Plan** — `swift-toolkit:swift-architect`. Artifact: `Plan.md` with **two layers of progress tracking**:
  1. **Top-level phase progress table** (see `State Detection` in orchestrator: statuses ✅/🔄/⬜/⏸/🚫/⊘) — one row per phase, coarse-grained completion.
  2. **Per-phase detail section** for each phase — actionable items rendered as **markdown checkboxes** `- [ ] <item>`. Granularity: one checkbox per file to edit, per acceptance criterion, per test to add, per verification step. Granular enough to be ticked individually as the Execute stage progresses. Static prose (rationale, decisions, design notes) stays as plain bullets — only **action items** become checkboxes.

  The plan decomposes the feature into concrete phases and steps. Per-phase action items are seeded from the work-items list in `Research.md ## Landscape ### Work items`.

  The architect MUST apply the `feature-estimation` skill to produce an additional `## Estimation` section in `Plan.md` (baseline table + applied multipliers + range + assumptions + known unknowns). The estimation range is a hard-prerequisite for entering Execute — if Known Unknowns are still blocking, Plan stays open and the workflow returns `ask_user`.

- **Execute** — `swift-toolkit:swift-developer` + `swift-toolkit:swift-tester` (if `need_test=true` in args). Implements the phases from `Plan.md` step by step, updating both progress layers as work proceeds. **MUST create one git commit per green phase** — autonomously, without `AskUserQuestion`.

  Per-item flow inside a phase: complete one actionable item → tick its checkbox `- [ ]` → `- [x]` in the per-phase detail section of Plan.md. Per-phase flow: when all the phase's checkboxes are `- [x]` → build → run tests for the touched scope → flip the phase's row in the top-level progress table ⬜→✅ → `git add` the phase's files (including the Plan.md updates — both checkboxes and table) → `git commit`. Commit message format: `<task_id>: phase <N> — <short description>` (e.g. `001-feature: phase 2 — domain model`). If `git log` shows the project uses a different convention for similar tasks, follow that convention instead.

  **A phase is not "done" (✅ in the top table) until ALL its granular checkboxes are `- [x]` AND the phase is committed.** Partial completion stays at 🔄 in the top table with the un-ticked checkboxes still `- [ ]`. Artifacts: source code in the project + tests + the resulting commit history.

  If `start_phase=<phase_id>` was passed in args — `swift-toolkit:swift-developer` receives that phase as the start point in the Task-tool prompt. Already-completed phases (status `✅` in `Plan.md`) are skipped, not redone. The progress table is updated only for new / changed phases.

- **Validation** — `swift-toolkit:swift-validator`. Artifact: `Validation.md`, **first line is required** to be `[VALIDATION_STATUS] = PASSED | FAILED | FLAKY` (the shared contract between `swift-validator`, every `workflow-*`, and the orchestrator; analogous to `[REVIEW_STATUS]`). For the FEATURE profile, the validator runs XcodeBuildMCP `build_sim` + `test_sim` mandatorily, and mobile MCP mandatorily when there is a UI layer (SwiftUI/UIKit views, screens, navigation); mobile MCP is skipped for purely domain/infrastructure features. Detailed per-profile behavior (mandatory vs. optional MCP steps, log capture, return-digest format) lives in `agents/swift-validator.md`.

  In addition to `Validation.md`, the validator MUST produce a separate `OpsChecklist.md` artifact in the task folder by applying the `mobile-ops-checklist` skill. Each checklist item is marked **Applicable** (with verification evidence: file path, test name, commit ref), **N/A** (with reason), or **Pending**. A single Pending item is NOT itself a FAILED verdict — Pending items are surfaced to the Review stage, which decides whether they block APPROVED.

- **Review** — `swift-toolkit:swift-reviewer` (if `need_review=true` in args). Artifact: `Review.md`, **first line is required** to be `[REVIEW_STATUS] = APPROVED | CHANGES_REQUESTED | DISCUSSION` (this field is the shared contract between workflow-* and the orchestrator; it is also used by `swift-toolkit:workflow-review` for auto-move into DONE/).

  The reviewer cross-checks `OpsChecklist.md` from the Validation stage: every item marked **Applicable** must have implementation evidence visible in the diff or in test results. Applicable items without evidence are findings (severity per `swift-reviewer.md`) and typically yield `CHANGES_REQUESTED`. Pending items in `OpsChecklist.md` are surfaced as a `## Outstanding ops items` section in `Review.md` for explicit user-side accept/defer.

- **Done** — final report `Done.md`: what was done, which artifacts were produced, validation status (build/test result), and objections (if the user insisted on a contested decision).

## 3. Manual mode

After each completed stage the orchestrator asks the user via `AskUserQuestion` using the `stage_done_prompt` key from `locales/<lang>.md`, with placeholder `{stage}`.

Workflow-feature **does NOT call `AskUserQuestion` itself** — it returns control to the orchestrator after a stage completes (see section 5, Output Contract) with `next_recommended_action`. The decision to pause, continue, or capture discussions in `Questions.md` is the orchestrator's responsibility.

If the host CLI does not support `AskUserQuestion`, the orchestrator uses a textual fallback (numbered options + reply parsing). That is the orchestrator's responsibility, not workflow-feature's.

## 4. Auto mode

No pauses between stages. Workflow-feature runs the stages sequentially within `stage_scope` and returns the final result to the orchestrator in a single output.

**Per-phase commits inside the Execute stage are autonomous** — created without `AskUserQuestion`, in both manual and auto modes. The only commit that always requires confirmation regardless of mode is a flow-level wrap commit (squash, merge, push) when the orchestrator initiates one. That confirmation is the orchestrator's responsibility, not workflow-feature's.

## 5. Output Contract

After each stage (in `manual` mode) or after a full pass (in `auto` mode), workflow-feature returns a JSON-like structure to the orchestrator:

```
{
  status: ok | error | cancelled | interrupted,
  last_completed_stage: Research | Plan | Execute | Validation | Review | Done,
  artifact_path: <path to the final artifact, e.g. Tasks/ACTIVE/001-feature/Done.md>,
  next_recommended_action: continue | stop | ask_user,
  notes: <free-form text, optional>
}
```

Field semantics:
- `status=ok` — the stage finished correctly.
- `status=error` — an error occurred (including reasons such as the locale key `status_error_empty_required_field`, an invalid contract, or a fatal subagent failure).
- `status=cancelled` — the user explicitly declined to continue (the orchestrator forwarded a `No` from its AUQ; rendered to the user via locale key `status_cancelled_user_no`). A normal outcome, not an error.
- `status=interrupted` — execution was interrupted by a technical fault or external signal (not by user decision): subagent disconnect, timeout, tool unavailable. Requires diagnostics on the orchestrator side.
- `last_completed_stage` — the last stage that actually finished (not the one execution stopped on with an error).
- `artifact_path` — path to the key artifact of the last stage (`Research.md`, `Plan.md`, `Validation.md`, `Review.md`, `Done.md`).
- `next_recommended_action=continue` — the next stage may start immediately; `stop` — natural finish (Done) or a fatal error; `ask_user` — confirmation is needed before continuing (e.g. after a Validation with `[VALIDATION_STATUS] = FAILED | FLAKY`, or after a Review with `[REVIEW_STATUS] = CHANGES_REQUESTED`).
- `notes` — short free-form description (e.g. the example in locale key `notes_build_failed_example`).

Based on this, the orchestrator decides: continue, abort, or ask the user.

## 6. What workflow-feature does NOT do

- Does NOT route — profile selection happens in the orchestrator before the call.
- Does NOT read `Task.md` to determine stack/mode — everything arrives in `args`.
- Does NOT trigger `task-new` or `task-move` — that is not its scope.
- Does NOT decide to skip stages — the orchestrator already passed `start_stage`, `end_stage`, `stage_scope`.
- Does NOT create backups in `_archive/` — the orchestrator did so before handing off control; the paths are already in `archive_paths`.
- Does NOT call `AskUserQuestion` — the orchestrator does that between stages in `manual` mode.
- Does NOT **ask** the user before per-phase commits — workflow-feature creates them autonomously after each green phase, no `AskUserQuestion`. The orchestrator handles user-facing commit confirmation only for any flow-level wrap commit it initiates (squash, merge, push). **"Does NOT confirm with user" means "does not interrupt to ask", NOT "does not commit".** Failing to commit per phase loses incremental progress on interrupt and forces a re-do of the whole Execute stage.
