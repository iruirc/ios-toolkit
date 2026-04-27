---
name: workflow-refactor
description: |
  REFACTOR profile workflow: Analyze → Plan → Refactor → Validation → Review → Done. Activated by swift-toolkit:orchestrator; not invoked by the user directly.
  Use when (en): orchestrator dispatches a task with [TASK_TYPE]=REFACTOR
  Use when (ru): оркестратор диспетчеризует задачу с [TASK_TYPE]=REFACTOR
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
- `need_test`, `need_review` — gate the inclusion of `swift-toolkit:swift-tester` and `swift-toolkit:swift-reviewer`.
- `archive_paths` — paths to backups already created (the orchestrator made them BEFORE the call; workflow-refactor does not create them).

**Execution range.** Stages run in the order Analyze → Plan → Refactor → Validation → Review → Done, starting at `start_stage` and continuing through `end_stage` inclusive. If `end_stage=null` — through the end of the profile. If `end_stage` is set but precedes `start_stage` in order, that is a contract error: return `{status: error, reason: "end_stage before start_stage"}`.

**Scope.** `stage_scope` controls execution width:
- `single` — only `start_stage` runs; afterwards the workflow returns `{status: ok, last_completed_stage: <start_stage>, next_recommended_action: stop}`. Used for `action=redo`.
- `forward` — `start_stage` plus every subsequent stage up to `end_stage` (or to the end of the profile). Used for `action=run`/`continue`/`restart`.
- `all` — equivalent to `forward` with `start_stage = first stage of the profile`. Used for `action=restart-full`.

## 2. Stages

- **Analyze** — `swift-toolkit:swift-architect`. Artifact: `Research.md` describing the current state (what is bad, why, what risks the refactor carries), a map of affected components, and the target state. Goal: refactor **without changing external behavior** — only structure, readability, maintainability, type/module boundaries, naming, and dependency isolation change. The public API/behavior contract is preserved as an invariant.

- **Plan** — `swift-toolkit:swift-architect`. Artifact: `Plan.md` with a phase progress table (see `State Detection` in orchestrator: statuses ✅/🔄/⬜/⏸/🚫/⊘). Each phase MUST be **independently buildable and test-passing** — that is the requirement of incremental refactoring: in case execution is interrupted, after any completed phase the project remains in a working, commit-ready state.

- **Refactor** — `swift-toolkit:swift-refactorer` (see `agents/swift-refactorer.md`). Applies the refactor phase by phase from `Plan.md`, updating the progress table after each phase. Where possible, runs local tests after each phase and locks in the progress. The stage's artifact is the changes in the source files; Refactor does not produce a dedicated `.md`. **No external behavior changes** — that invariant is verified in Validation.

  If `start_phase=<phase_id>` was passed in args — `swift-toolkit:swift-refactorer` receives that phase as the start point in the Task-tool prompt. Already-completed phases (status `✅` in `Plan.md`) are skipped, not redone. The progress table is updated only for new / changed phases.

- **Validation** — XcodeBuildMCP `test_sim` is **mandatory** (regression check: every existing test must pass without modification), `build_sim` optional. mobile MCP **only when UI-layer changes were made** — if the refactor touched SwiftUI/UIKit views, screens, or navigation, a smoke check in the simulator is required to verify the UI is not visually broken. For purely domain/infrastructure refactors mobile MCP is skipped. Artifact: `Validation.md` with the log and the verdict.

- **Review** — `swift-toolkit:swift-reviewer` (if `need_review=true` in args). Artifact: `Review.md`, **first line is required** to be `[REVIEW_STATUS] = APPROVED | CHANGES_REQUESTED | DISCUSSION` (this field is the shared contract between workflow-* and the orchestrator; it is also used by `swift-toolkit:workflow-review` for auto-move into DONE/).

- **Done** — final report `Done.md`: what was refactored, why it is now better (readability, separation of concerns, reduced coupling), measurable metrics where available (file size, cyclomatic complexity of key functions, dependency count), validation status (build/test result), and objections (if the user insisted on a contested decision).

## 3. Manual mode

After each completed stage the orchestrator asks the user via `AskUserQuestion` using the `stage_done_prompt` key from `locales/<lang>.md`, with placeholder `{stage}`.

Workflow-refactor **does NOT call `AskUserQuestion` itself** — it returns control to the orchestrator after a stage completes (see section 5, Output Contract) with `next_recommended_action`. The decision to pause, continue, or capture discussions in `Questions.md` is the orchestrator's responsibility.

If the host CLI does not support `AskUserQuestion`, the orchestrator uses a textual fallback (numbered options + reply parsing). That is the orchestrator's responsibility, not workflow-refactor's.

## 4. Auto mode

No pauses between stages. Workflow-refactor runs the stages sequentially within `stage_scope` and returns the final result to the orchestrator in a single output.

The only step that always requires confirmation regardless of mode is the final commit, when the orchestrator initiates the commit flow. That is again the orchestrator's responsibility, not workflow-refactor's.

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
- `next_recommended_action=continue` — the next stage may start immediately; `stop` — natural finish (Done) or a fatal error; `ask_user` — confirmation is needed before continuing (e.g. after a Review with `CHANGES_REQUESTED`).
- `notes` — short free-form description (e.g. the example in locale key `notes_test_failed_example`).

Based on this, the orchestrator decides: continue, abort, or ask the user.

## 6. What workflow-refactor does NOT do

- **Does NOT change external behavior — that is the refactor invariant.** If during the work a bug is discovered whose remediation requires a change in observable behavior (logic fix, API contract fix, UX change), workflow-refactor returns `{status: error, reason: behavior_change_required}` and the user decides whether to create a separate BUG task.
- Does NOT route — profile selection happens in the orchestrator before the call.
- Does NOT read `Task.md` to determine stack/mode — everything arrives in `args`.
- Does NOT trigger `task-new` or `task-move` — that is not its scope.
- Does NOT decide to skip stages — the orchestrator already passed `start_stage`, `end_stage`, `stage_scope`.
- Does NOT create backups in `_archive/` — the orchestrator did so before handing off control; the paths are already in `archive_paths`.
- Does NOT call `AskUserQuestion` — the orchestrator does that between stages in `manual` mode.
- Does NOT confirm the commit with the user — the orchestrator handles that after a `next_recommended_action` return.
