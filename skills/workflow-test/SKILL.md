---
name: workflow-test
description: |
  TEST profile workflow: Analyze → Plan → Write → Validation → Review → Done. Activated by swift-toolkit:orchestrator; not invoked by the user directly.
  Use when (en): orchestrator dispatches a task with [TASK_TYPE]=TEST
  Use when (ru): оркестратор диспетчеризует задачу с [TASK_TYPE]=TEST
---

# Workflow Test

The profile workflow for tasks with `[TASK_TYPE] = TEST` — used when writing tests is the primary goal of the task (not part of FEATURE/BUG, where tests ship alongside the implementation). Implements the sequence of stages; the result of each stage is an artifact file inside the task folder. The skill receives an already-resolved contract from the orchestrator and does not try to re-resolve any parameter on its own.

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

The field structure is documented in `swift-toolkit:orchestrator` (section **Outbound Contract**). Workflow-test accepts every field already filled — invariant.

If a required field arrives empty — workflow-test does not try to recover. It returns `{status: error, reason: status_error_empty_required_field}` (the `reason` value is taken from the locale key in `locales/<lang>.md`) back to the orchestrator.

The fields that directly drive this workflow's behavior:
- `start_stage`, `end_stage`, `stage_scope` — determine which stages run.
- `start_phase` — entry point inside a stage (e.g. `Write:phase=2.3`).
- `mode` — `manual` / `auto` (see sections 3 and 4).
- `stack` — passed to subagents as context (including the chosen test framework, if already determined).
- `need_review` — gates the inclusion of `swift-toolkit:swift-reviewer` (the `need_test` flag is meaningless for the TEST profile: tests ARE the primary artifact).
- `archive_paths` — paths to backups already created (the orchestrator made them BEFORE the call; workflow-test does not create them).

**Execution range.** Stages run in the order Analyze → Plan → Write → Validation → Review → Done, starting at `start_stage` and continuing through `end_stage` inclusive. If `end_stage=null` — through the end of the profile. If `end_stage` is set but precedes `start_stage` in order, that is a contract error: return `{status: error, reason: "end_stage before start_stage"}`.

**Scope.** `stage_scope` controls execution width:
- `single` — only `start_stage` runs; afterwards the workflow returns `{status: ok, last_completed_stage: <start_stage>, next_recommended_action: stop}`. Used for `action=redo`.
- `forward` — `start_stage` plus every subsequent stage up to `end_stage` (or to the end of the profile). Used for `action=run`/`continue`/`restart`.
- `all` — equivalent to `forward` with `start_stage = first stage of the profile`. Used for `action=restart-full`.

## 2. Stages

- **Analyze** — a panel: `swift-toolkit:swift-architect` + `swift-toolkit:swift-tester` (via the Task tool, in parallel or sequentially as the orchestrator decides). Artifact: `Research.md`. Goal: determine **what to test** (uncovered code, critical paths, regression scenarios), **what test level** (unit / integration / UI / snapshot), **which frameworks** (XCTest / Quick+Nimble / ViewInspector / SnapshotTesting). Additionally, `swift-toolkit:swift-architect` evaluates the testability of existing code: whether dependency injection, mocks, or protocols for abstracting external dependencies are required.

- **Plan** — `swift-toolkit:swift-tester`. Artifact: `Plan.md` with a phase progress table (see `State Detection` in orchestrator: statuses ✅/🔄/⬜/⏸/🚫/⊘). The plan decomposes tests into phases — usually by groups (one phase per testable component / module / use case). Each phase is assigned a priority `P0` (critical, blocks release) / `P1` (important) / `P2` (nice-to-have).

- **Write** — `swift-toolkit:swift-tester`. Implements the phases from `Plan.md` step by step, updating the progress table after each phase. Artifacts: test code in the project + test helpers/fixtures/mocks where needed. **Does NOT modify production code.** If the code under test turns out to be untestable without refactoring (tight coupling, singletons, missing protocols for mocking) — returns `{status: error, reason: refactor_required, notes: "<what specifically blocks, which component>"}` so the orchestrator/user can decide to create a separate REFACTOR task.

  If `start_phase=<phase_id>` was passed in args — `swift-toolkit:swift-tester` receives that phase as the start point in the Task-tool prompt. Already-completed phases (status `✅` in `Plan.md`) are skipped, not redone. The progress table is updated only for new / changed phases.

- **Validation** — XcodeBuildMCP `test_sim` is **mandatory** (run all newly added tests). Every added test must pass on first run (green). If a flaky test is detected — re-run 3 times; the instability is recorded in `Validation.md` (test name, failure rate, hypothesized cause). mobile MCP is optional — only for UI tests requiring visual verification. Artifact: `Validation.md` with the test log, flaky-test stats, and the final verdict.

- **Review** — `swift-toolkit:swift-reviewer` (if `need_review=true` in args). **Special case for the TEST profile:** the review evaluates the quality of the **tests**, not production code — edge-case coverage, meaningful assertions (no "assert true == true"), absence of mocks for logic that should be tested directly, isolation of tests from each other, readability and maintainability. Artifact: `Review.md`, **first line is required** to be `[REVIEW_STATUS] = APPROVED | CHANGES_REQUESTED | DISCUSSION` (this field is the shared contract between workflow-* and the orchestrator; it is also used by `swift-toolkit:workflow-review` for auto-move into DONE/).

- **Done** — final report `Done.md`: what is now covered (list of components and scenarios), what coverage was achieved (if measured), the list of frameworks used, validation status (are all added tests green, any flaky), and objections (if the user insisted on a contested decision — e.g. declining to test a critical path).

## 3. Manual mode

After each completed stage the orchestrator asks the user via `AskUserQuestion` using the `stage_done_prompt` key from `locales/<lang>.md`, with placeholder `{stage}`.

Workflow-test **does NOT call `AskUserQuestion` itself** — it returns control to the orchestrator after a stage completes (see section 5, Output Contract) with `next_recommended_action`. The decision to pause, continue, or capture discussions in `Questions.md` is the orchestrator's responsibility.

If the host CLI does not support `AskUserQuestion`, the orchestrator uses a textual fallback (numbered options + reply parsing). That is the orchestrator's responsibility, not workflow-test's.

## 4. Auto mode

No pauses between stages. Workflow-test runs the stages sequentially within `stage_scope` and returns the final result to the orchestrator in a single output.

The only step that always requires confirmation regardless of mode is the final commit, when the orchestrator initiates the commit flow. That is again the orchestrator's responsibility, not workflow-test's.

## 5. Output Contract

After each stage (in `manual` mode) or after a full pass (in `auto` mode), workflow-test returns a JSON-like structure to the orchestrator:

```
{
  status: ok | error | cancelled | interrupted,
  last_completed_stage: Analyze | Plan | Write | Validation | Review | Done,
  artifact_path: <path to the final artifact, e.g. Tasks/ACTIVE/001-test/Done.md>,
  next_recommended_action: continue | stop | ask_user,
  notes: <free-form text, optional>
}
```

Field semantics:
- `status=ok` — the stage finished correctly.
- `status=error` — an error occurred (including reasons such as the locale key `status_error_empty_required_field`, an invalid contract, a fatal subagent failure, or `refactor_required` from the Write stage).
- `status=cancelled` — the user explicitly declined to continue (the orchestrator forwarded a `No` from its AUQ; rendered to the user via locale key `status_cancelled_user_no`). A normal outcome, not an error.
- `status=interrupted` — execution was interrupted by a technical fault or external signal (not by user decision): subagent disconnect, timeout, tool unavailable. Requires diagnostics on the orchestrator side.
- `last_completed_stage` — the last stage that actually finished (not the one execution stopped on with an error).
- `artifact_path` — path to the key artifact of the last stage (`Research.md`, `Plan.md`, `Validation.md`, `Review.md`, `Done.md`). The Write stage has no dedicated `.md` artifact — points to `Plan.md` (with the updated progress table).
- `next_recommended_action=continue` — the next stage may start immediately; `stop` — natural finish (Done) or a fatal error; `ask_user` — confirmation is needed before continuing (e.g. after a Review with `CHANGES_REQUESTED`, or after `refactor_required` from Write).
- `notes` — short free-form description (e.g. the examples in locale keys `notes_test_failed_example` and `notes_refactor_required_example`).

Based on this, the orchestrator decides: continue, abort, or ask the user.

## 6. What workflow-test does NOT do

- Does NOT route — profile selection happens in the orchestrator before the call.
- Does NOT read `Task.md` to determine stack/mode — everything arrives in `args`.
- Does NOT trigger `task-new` or `task-move` — that is not its scope.
- Does NOT decide to skip stages — the orchestrator already passed `start_stage`, `end_stage`, `stage_scope`.
- Does NOT create backups in `_archive/` — the orchestrator did so before handing off control; the paths are already in `archive_paths`.
- Does NOT call `AskUserQuestion` — the orchestrator does that between stages in `manual` mode.
- Does NOT confirm the commit with the user — the orchestrator handles that after a `next_recommended_action` return.
- Does NOT modify production code. If the code under test is not testable without refactoring — returns `{status: error, reason: refactor_required}`; does not patch on its own.
- Does NOT decide on coverage metrics (coverage thresholds, target percentages) — that's the orchestrator's / user's domain; workflow-test only writes tests per the plan and records the actual coverage in `Done.md`.
