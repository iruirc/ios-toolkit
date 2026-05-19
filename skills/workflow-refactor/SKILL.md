---
name: workflow-refactor
description: |
  REFACTOR profile workflow: Analyze → Plan → Refactor → Validation → Review → Done. Activated by swift-toolkit:orchestrator; not invoked by the user directly.
  Use when (en): orchestrator dispatches a task with [TASK_TYPE]=REFACTOR
  Use when (ru): оркестратор диспетчеризует задачу с [TASK_TYPE]=REFACTOR
stack_axes_envelope: { may: [ui, async, di, architecture, platform, tests], never: [] }
---

# Workflow Refactor

The profile workflow for tasks with `[TASK_TYPE] = REFACTOR`. Implements the sequence of stages; the result of each stage is an artifact file inside the task folder. The skill receives an already-resolved contract from the orchestrator and does not try to re-resolve any parameter on its own.

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

The field structure is documented in `swift-toolkit:orchestrator` (section **Outbound Contract**). Workflow-refactor accepts every field already filled — invariant.

If a required field arrives empty — workflow-refactor does not try to recover. It returns `{status: error, reason: status_error_empty_required_field}` (the `reason` value is taken from the locale key in `locales/<lang>.md`) back to the orchestrator.

The fields that directly drive this workflow's behavior:
- `start_stage`, `end_stage`, `stage_scope` — determine which stages run.
- `start_phase` — entry point inside a stage (e.g. `Refactor:phase=2.3`).
- `mode` — `manual` / `auto` (see sections 3 and 4).
- `stack` — passed to subagents as context.
- `lang` — project language for artifact prose + the final report; artifact structure (headings, field labels, status enums) stays EN. See `conventions/i18n.md` → "Artifact authoring rule". Passed through to every subagent.
- `need_test`, `need_review` — gate the inclusion of `swift-toolkit:swift-tester` and `swift-toolkit:swift-reviewer`.
- `archive_paths` — paths to backups already created (the orchestrator made them BEFORE the call; workflow-refactor does not create them).

**Execution range.** Stages run in the order Analyze → Plan → Refactor → Validation → Review → Done, starting at `start_stage` and continuing through `end_stage` inclusive. If `end_stage=null` — through the end of the profile. If `end_stage` is set but precedes `start_stage` in order, that is a contract error: return `{status: error, reason: "end_stage before start_stage"}`.

**Scope.** `stage_scope` controls execution width:
- `single` — only `start_stage` runs; afterwards the workflow returns `{status: ok, last_completed_stage: <start_stage>, next_recommended_action: stop}`. Used for `action=redo`.
- `forward` — `start_stage` plus every subsequent stage up to `end_stage` (or to the end of the profile). Used for `action=run`/`continue`/`restart`.
- `all` — equivalent to `forward` with `start_stage = first stage of the profile`. Used for `action=restart-full`.

## 2. Stages

- **Analyze** — `swift-toolkit:swift-architect`. Artifact: `Research.md` describing the current state (what is bad, why, what risks the refactor carries), a map of affected components, and the target state. Goal: refactor **without changing external behavior** — only structure, readability, maintainability, type/module boundaries, naming, and dependency isolation change. The public API/behavior contract is preserved as an invariant.

  The architect MUST apply the `feature-landscape` skill **twice**: once to draw the **current** entity graph + layer map + integration points (the as-is landscape), and once to draw the **target** landscape after refactor. `Research.md` gets two sections: `## Landscape (current)` and `## Landscape (target)`. The diff between them IS the refactor scope; per-phase work items in `Plan.md` are derived from this diff.

- **Plan** — `swift-toolkit:swift-architect`. Artifact: `Plan.md` with **two layers of progress tracking**:
  1. **Top-level phase progress table** (see `State Detection` in orchestrator: statuses ✅/🔄/⬜/⏸/🚫/⊘) — one row per phase, captures coarse-grained completion.
  2. **Per-phase detail section** for each phase — actionable items rendered as **markdown checkboxes** `- [ ] <item>`. Granularity: one checkbox per file to edit, per acceptance criterion, per test to add, per verification command to run. The checkboxes MUST be granular enough that they can be ticked individually as work progresses inside the phase (the Refactor stage will tick them — see Refactor below). Static prose inside per-phase sections (rationale, rollback markers, decisions) stays as plain bullets/text — only **action items** become checkboxes.

  Each phase MUST be **independently buildable, test-passing, AND physically committed by the Refactor stage** — that is the requirement of incremental refactoring. "Commit-ready" is NOT enough — an interrupt or rollback destroys all uncommitted work. The Refactor stage produces one git commit per green phase (see Refactor below).

- **Refactor** — `swift-toolkit:swift-refactorer` (see `agents/swift-refactorer.md`). Applies the refactor phase by phase from `Plan.md`, updating both progress layers as work proceeds. Where possible, runs local tests after each phase. **MUST create one git commit per green phase** — autonomously, without a user prompt.

  Per-item flow inside a phase: complete one actionable item → tick its checkbox `- [ ]` → `- [x]` in the per-phase detail section of Plan.md. Per-phase flow: when all the phase's checkboxes are `- [x]` → build → run targeted tests → flip the phase's row in the top-level progress table ⬜→✅ → `git add` the phase's files (including the Plan.md updates — both checkboxes and table) → `git commit`. Commit message format: `<task_id>: phase <N> — <short description>` (e.g. `145/1.step/1.5a: phase 3 — facade sync impl`). If `git log` shows the project uses a different convention for similar tasks, follow that convention instead.

  **A phase is not "done" (✅ in the top table) until ALL its granular checkboxes are `- [x]` AND the phase is committed.** Partial completion stays at 🔄 in the top table with the un-ticked checkboxes still `- [ ]`. The stage's artifact is the source-code changes + the resulting commit history; Refactor does not produce a dedicated `.md`. **No external behavior changes** — that invariant is verified in Validation.

  **Comment hygiene during refactor (hard rule, enforced by `swift-refactorer`):** NEVER embed task/phase/EPIC references in production code comments (`// EPIC X §Y Phase Z — …`, `// Task N phase M — …`, `// Bug123 fix`). Phase provenance lives in (a) the Plan.md per-phase checkbox + table row and (b) the per-phase git commit message — duplicating it inline rots and crowds out evergreen WHY-comments. See `agents/swift-refactorer.md → ## Comment Policy` for the full rule and acceptable shapes. This applies to file headers too — no `// Created for EPIC X / Phase Y` lines.

  If `start_phase=<phase_id>` was passed in args — `swift-toolkit:swift-refactorer` receives that phase as the start point in the Task-tool prompt. Already-completed phases (status `✅` in `Plan.md`) are skipped, not redone. The progress table is updated only for new / changed phases.

- **Validation** — `swift-toolkit:swift-validator`. Artifact: `Validation.md`, **first line is required** to be `[VALIDATION_STATUS] = PASSED | FAILED | FLAKY` (the shared contract between `swift-validator`, every `workflow-*`, and the orchestrator; analogous to `[REVIEW_STATUS]`). For the REFACTOR profile, the validator runs XcodeBuildMCP `test_sim` mandatorily as a regression check (every pre-existing test must pass **without modification** — touching a test during a refactor is itself a finding), `build_sim` is optional, and mobile MCP runs only when the refactor touched a UI layer (SwiftUI/UIKit views, screens, or navigation) — purely domain/infrastructure refactors skip mobile MCP. Detailed behavior lives in `agents/swift-validator.md`.

  The validator MUST apply the `mobile-ops-checklist` skill in **regression mode**: only items that were Applicable for the affected area pre-refactor are re-checked. Output: `OpsChecklist.md` in the task folder. A previously-Applicable item that no longer has verifiable evidence after the refactor is itself a finding — a violation of the refactor invariant (the refactor changed observable behavior). Pure additive items (new ops concerns introduced by the refactor) are flagged but do not block PASSED.

- **Review** — `swift-toolkit:swift-reviewer` (if `need_review=true` in args). Artifact: `Review.md`, **first line is required** to be `[REVIEW_STATUS] = APPROVED | CHANGES_REQUESTED | DISCUSSION` (this field is the shared contract between workflow-* and the orchestrator; it is also used by `swift-toolkit:workflow-review` for auto-move into DONE/).

- **Done** — final report `Done.md`: what was refactored, why it is now better (readability, separation of concerns, reduced coupling), measurable metrics where available (file size, cyclomatic complexity of key functions, dependency count), validation status (build/test result), and objections (if the user insisted on a contested decision).

## 3. Manual mode

After each completed stage the orchestrator asks the user via the structured question mechanism using the `stage_done_prompt` key from `locales/<lang>.md`, with placeholder `{stage}`.

Workflow-refactor **does NOT ask the user itself** — it returns control to the orchestrator after a stage completes (see section 5, Output Contract) with `next_recommended_action`. The decision to pause, continue, or capture discussions in `Questions.md` is the orchestrator's responsibility.

If the active host has no structured question tool, the orchestrator uses a textual fallback (numbered options + reply parsing). That is the orchestrator's responsibility, not workflow-refactor's.

## 4. Auto mode

No pauses between stages. Workflow-refactor runs the stages sequentially within `stage_scope` and returns the final result to the orchestrator in a single output.

**Per-phase commits inside the Refactor stage are autonomous** — created without a user prompt, in both manual and auto modes. The only commit that always requires confirmation regardless of mode is a flow-level wrap commit (squash, merge, push) when the orchestrator initiates one. That confirmation is the orchestrator's responsibility, not workflow-refactor's.

## 5. Output Contract

After each stage (in `manual` mode) or after a full pass (in `auto` mode), workflow-refactor returns a JSON-like structure to the orchestrator:

```
{
  status: ok | error | cancelled | interrupted,
  last_completed_stage: Analyze | Plan | Refactor | Validation | Review | Done,
  artifact_path: <path to the key artifact, e.g. Tasks/ACTIVE/001-refactor/Done.md>,
  next_recommended_action: continue | stop | ask_user,
  notes: <free-form text, optional>
}
```

Field semantics:
- `status=ok` — the stage finished correctly.
- `status=error` — an error occurred (including reasons such as the locale key `status_error_empty_required_field`, an invalid contract, a fatal subagent failure, or a required behavior change being detected — see section 6).
- `status=cancelled` — the user explicitly declined to continue (the orchestrator forwarded a `No` from its AUQ; rendered to the user via locale key `status_cancelled_user_no`). A normal outcome, not an error.
- `status=interrupted` — execution was interrupted by a technical fault or external signal (not by user decision): subagent disconnect, timeout, tool unavailable. Requires diagnostics on the orchestrator side.
- `last_completed_stage` — the last stage that actually finished (not the one execution stopped on with an error).
- `artifact_path` — path to the key artifact of the last stage: `Research.md` (after Analyze), `Plan.md` (after Plan and after Refactor — Refactor has no dedicated `.md` artifact), `Validation.md`, `Review.md`, `Done.md`.
- `next_recommended_action=continue` — the next stage may start immediately; `stop` — natural finish (Done) or a fatal error; `ask_user` — confirmation is needed before continuing (e.g. after a Validation with `[VALIDATION_STATUS] = FAILED | FLAKY`, or after a Review with `[REVIEW_STATUS] = CHANGES_REQUESTED`).
- `notes` — short free-form description (e.g. the example in locale key `notes_test_failed_example`).

Based on this, the orchestrator decides: continue, abort, or ask the user.

## 6. What workflow-refactor does NOT do

- **Does NOT change external behavior — that is the refactor invariant.** If during the work a bug is discovered whose remediation requires a change in observable behavior (logic fix, API contract fix, UX change), workflow-refactor returns `{status: error, reason: behavior_change_required}` and the user decides whether to create a separate BUG task.
- Does NOT route — profile selection happens in the orchestrator before the call.
- Does NOT read `Task.md` to determine stack/mode — everything arrives in `args`.
- Does NOT trigger `task-new` or `task-move` — that is not its scope.
- Does NOT decide to skip stages — the orchestrator already passed `start_stage`, `end_stage`, `stage_scope`.
- Does NOT create backups in `_archive/` — the orchestrator did so before handing off control; the paths are already in `archive_paths`.
- Does NOT ask the user — the orchestrator does that between stages in `manual` mode.
- Does NOT **ask** the user before per-phase commits — workflow-refactor creates them autonomously after each green phase, with no user prompt. The orchestrator handles user-facing commit confirmation only for any flow-level wrap commit it initiates (squash, merge, push). **"Does NOT confirm with user" means "does not interrupt to ask", NOT "does not commit".** Failing to commit per phase violates the Refactor invariant — an interrupt loses everything since the last commit, defeating the point of phase-by-phase decomposition.
