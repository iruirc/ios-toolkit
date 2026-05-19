---
name: workflow-bug
description: |
  BUG profile workflow: Reproduce → Diagnose → Plan → Fix → Validation → Review → Done. Activated by swift-toolkit:orchestrator; not invoked by the user directly.
  Use when (en): orchestrator dispatches a task with [TASK_TYPE]=BUG
  Use when (ru): оркестратор диспетчеризует задачу с [TASK_TYPE]=BUG
stack_axes_envelope: { may: [ui, async, di, architecture, platform, tests], never: [] }
---

# Workflow Bug

The profile workflow for tasks with `[TASK_TYPE] = BUG`. Implements the sequence of stages; the result of each stage is an artifact file inside the task folder. The skill receives an already-resolved contract from the orchestrator and does not try to re-resolve any parameter on its own.

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

The field structure is documented in `swift-toolkit:orchestrator` (section **Outbound Contract**). Workflow-bug accepts every field already filled — invariant.

If a required field arrives empty — workflow-bug does not try to recover. It returns `{status: error, reason: status_error_empty_required_field}` (the `reason` value is taken from the locale key in `locales/<lang>.md`) back to the orchestrator.

The fields that directly drive this workflow's behavior:
- `start_stage`, `end_stage`, `stage_scope` — determine which stages run.
- `start_phase` — entry point inside a stage (e.g. `Fix:phase=2.3`).
- `mode` — `manual` / `auto` (see sections 3 and 4).
- `stack` — passed to subagents as context.
- `lang` — project language for artifact prose + the final report; artifact structure (headings, field labels, status enums) stays EN. See `conventions/i18n.md` → "Artifact authoring rule". Passed through to every subagent.
- `need_test`, `need_review` — gate the inclusion of `swift-toolkit:swift-tester` and `swift-toolkit:swift-reviewer`.
- `archive_paths` — paths to backups already created (the orchestrator made them BEFORE the call; workflow-bug does not create them).

**Execution range.** Stages run in the order Reproduce → Diagnose → Plan → Fix → Validation → Review → Done, starting at `start_stage` and continuing through `end_stage` inclusive. If `end_stage=null` — through the end of the profile. If `end_stage` is set but precedes `start_stage` in order, that is a contract error: return `{status: error, reason: "end_stage before start_stage"}`.

**Scope.** `stage_scope` controls execution width:
- `single` — only `start_stage` runs; afterwards the workflow returns `{status: ok, last_completed_stage: <start_stage>, next_recommended_action: stop}`. Used for `action=redo`.
- `forward` — `start_stage` plus every subsequent stage up to `end_stage` (or to the end of the profile). Used for `action=run`/`continue`/`restart`.
- `all` — equivalent to `forward` with `start_stage = first stage of the profile`. Used for `action=restart-full`.

## 2. Stages

- **Reproduce** — `swift-toolkit:swift-diagnostics`. Artifact: `Reproduce.md` (or a section in `Research.md`) with reproduction steps, a minimal reproducer, and the manifestation frequency (always / sometimes / under condition X). Goal: pin down a deterministic scenario that Validation can later rely on.

  Apply the `feature-requirements` skill (Secondary checklist only) to enumerate which Secondary states the bug touches — error / loading / empty / offline / a11y / deeplink / push / i18n / analytics / lifecycle / cancellation. A bug often hides not in the happy path but in one of these states; explicit enumeration prevents "fixed the happy path, broke offline" regressions.

- **Diagnose** — a panel: `swift-toolkit:swift-diagnostics` + `swift-toolkit:swift-architect` (via the Task tool, in parallel or sequentially as the orchestrator decides). Artifact: `Research.md` with root cause analysis, a map of affected components, an estimate of fix scope, and the related risks.

- **Plan** — `swift-toolkit:swift-architect`. Artifact: `Plan.md` with **two layers of progress tracking**:
  1. **Top-level phase progress table** (see `State Detection` in orchestrator: statuses ✅/🔄/⬜/⏸/🚫/⊘) — one row per phase, coarse-grained completion.
  2. **Per-phase detail section** for each phase — actionable items rendered as **markdown checkboxes** `- [ ] <item>`. Granularity: one checkbox per file to edit, per acceptance criterion, per regression-test case, per verification step. Granular enough to be ticked individually as the Fix stage progresses. Static prose (root-cause analysis, decisions) stays as plain bullets — only **action items** become checkboxes.

  The plan covers: the focused fix, a regression test (if `need_test=true`), and migration / compatibility steps if needed.

- **Fix** — `swift-toolkit:swift-developer` + `swift-toolkit:swift-tester` (if `need_test=true` — for a bug, a regression test is mandatory: it locks in the scenario from `Reproduce.md` and prevents recurrence). Implements the phases from `Plan.md` step by step, updating both progress layers as work proceeds. **MUST create one git commit per green phase** — autonomously, without a user prompt.

  Per-item flow inside a phase: complete one actionable item → tick its checkbox `- [ ]` → `- [x]` in the per-phase detail section of Plan.md. Per-phase flow: when all the phase's checkboxes are `- [x]` → build → run tests for the touched scope → flip the phase's row in the top-level progress table ⬜→✅ → `git add` the phase's files (including the Plan.md updates — both checkboxes and table) → `git commit`. Commit message format: `<task_id>: phase <N> — <short description>` (e.g. `bug-042: phase 1 — root-cause fix in AuthMiddleware`). If `git log` shows the project uses a different convention for similar tasks, follow that convention instead.

  **A phase is not "done" (✅ in the top table) until ALL its granular checkboxes are `- [x]` AND the phase is committed.** Partial completion stays at 🔄 in the top table with the un-ticked checkboxes still `- [ ]`. Artifacts: source code in the project + a regression test + the resulting commit history.

  **Comment hygiene (hard rule, enforced by `swift-developer`):** NEVER embed task/phase/EPIC/bug references in production code comments (`// Bug123 fix`, `// EPIC X §Y Phase Z — …`, `// Fixes #042`). Bug provenance lives in the per-phase git commit message + `Reproduce.md` + the regression test name itself — duplicating it inline rots and crowds out the evergreen invariant the fix encodes. See `agents/swift-developer.md → ## Comment Policy`.

  If `start_phase=<phase_id>` was passed in args — `swift-toolkit:swift-developer` receives that phase as the start point in the Task-tool prompt. Already-completed phases (status `✅` in `Plan.md`) are skipped, not redone. The progress table is updated only for new / changed phases.

- **Validation** — `swift-toolkit:swift-validator`. Artifact: `Validation.md`, **first line is required** to be `[VALIDATION_STATUS] = PASSED | FAILED | FLAKY` (the shared contract between `swift-validator`, every `workflow-*`, and the orchestrator; analogous to `[REVIEW_STATUS]`). For the BUG profile, the validator runs XcodeBuildMCP `build_sim` + `test_sim` mandatorily AND mobile MCP mandatorily (regardless of layer) to replay the reproduction scenario from `Reproduce.md`. Validation is not considered PASSED without an explicit agent-composed statement that the bug no longer reproduces — surfaced in the return digest as `reproduction_status: fixed`. Detailed behavior (replay procedure, return-digest format) lives in `agents/swift-validator.md`.

  The validator MUST apply the `mobile-ops-checklist` skill, scoped to the categories the bug touched (per `Reproduce.md`'s Secondary enumeration). Output: `OpsChecklist.md` in the task folder, marking only the touched categories — full-checklist coverage is not required for BUG. Goal: catch regressions in adjacent ops behaviors (e.g. a fix for a network bug must not break the offline / cancellation behavior).

- **Review** — `swift-toolkit:swift-reviewer` (if `need_review=true` in args). Artifact: `Review.md`, **first line is required** to be `[REVIEW_STATUS] = APPROVED | CHANGES_REQUESTED | DISCUSSION` (this field is the shared contract between workflow-* and the orchestrator; it is also used by `swift-toolkit:workflow-review` for auto-move into DONE/).

- **Done** — final report `Done.md`: what was fixed, which regression test was added, validation status (build/test result + outcome of the reproduction replay), and objections (if the user insisted on a contested decision).

## 3. Manual mode

After each completed stage the orchestrator asks the user via the structured question mechanism using the `stage_done_prompt` key from `locales/<lang>.md`, with placeholder `{stage}`.

Workflow-bug **does NOT ask the user itself** — it returns control to the orchestrator after a stage completes (see section 5, Output Contract) with `next_recommended_action`. The decision to pause, continue, or capture discussions in `Questions.md` is the orchestrator's responsibility.

If the active host has no structured question tool, the orchestrator uses a textual fallback (numbered options + reply parsing). That is the orchestrator's responsibility, not workflow-bug's.

## 4. Auto mode

No pauses between stages. Workflow-bug runs the stages sequentially within `stage_scope` and returns the final result to the orchestrator in a single output.

**Per-phase commits inside the Fix stage are autonomous** — created without a user prompt, in both manual and auto modes. The only commit that always requires confirmation regardless of mode is a flow-level wrap commit (squash, merge, push) when the orchestrator initiates one. That confirmation is the orchestrator's responsibility, not workflow-bug's.

## 5. Output Contract

After each stage (in `manual` mode) or after a full pass (in `auto` mode), workflow-bug returns a JSON-like structure to the orchestrator:

```
{
  status: ok | error | cancelled | interrupted,
  last_completed_stage: Reproduce | Diagnose | Plan | Fix | Validation | Review | Done,
  artifact_path: <path to the final artifact, e.g. Tasks/ACTIVE/001-bug/Done.md>,
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
- `artifact_path` — path to the key artifact of the last stage (`Reproduce.md`, `Research.md`, `Plan.md`, `Validation.md`, `Review.md`, `Done.md`).
- `next_recommended_action=continue` — the next stage may start immediately; `stop` — natural finish (Done) or a fatal error; `ask_user` — confirmation is needed before continuing (e.g. after a Validation with `[VALIDATION_STATUS] = FAILED | FLAKY`, or after a Review with `[REVIEW_STATUS] = CHANGES_REQUESTED`).
- `notes` — short free-form description (e.g. the example in locale key `notes_build_failed_example`).

Based on this, the orchestrator decides: continue, abort, or ask the user.

## 6. What workflow-bug does NOT do

- Does NOT route — profile selection happens in the orchestrator before the call.
- Does NOT read `Task.md` to determine stack/mode — everything arrives in `args`.
- Does NOT trigger `task-new` or `task-move` — that is not its scope.
- Does NOT decide to skip stages — the orchestrator already passed `start_stage`, `end_stage`, `stage_scope`.
- Does NOT create backups in `_archive/` — the orchestrator did so before handing off control; the paths are already in `archive_paths`.
- Does NOT ask the user — the orchestrator does that between stages in `manual` mode.
- Does NOT **ask** the user before per-phase commits — workflow-bug creates them autonomously after each green phase, with no user prompt. The orchestrator handles user-facing commit confirmation only for any flow-level wrap commit it initiates (squash, merge, push). **"Does NOT confirm with user" means "does not interrupt to ask", NOT "does not commit".** Failing to commit per phase loses incremental progress on interrupt; the regression test, in particular, MUST be in its own commit so it can be cherry-picked or reverted independently of the fix.
