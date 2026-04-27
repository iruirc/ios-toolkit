---
name: workflow-review
description: |
  REVIEW profile workflow: a single pass through swift-toolkit:swift-reviewer plus auto-move into DONE/ on APPROVED. Activated by swift-toolkit:orchestrator; not invoked by the user directly.
  Use when (en): orchestrator dispatches a task with [TASK_TYPE]=REVIEW
  Use when (ru): оркестратор диспетчеризует задачу с [TASK_TYPE]=REVIEW
---

# Workflow Review

The profile workflow for tasks with `[TASK_TYPE] = REVIEW`. Structurally simpler than the others: a single substantive stage (Review) and a deterministic post-stage Auto-move that routes by the `[REVIEW_STATUS]` field. The skill receives an already-resolved contract from the orchestrator and does not try to re-resolve any parameter on its own.

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

The field structure is documented in `swift-toolkit:orchestrator` (section **Outbound Contract**). Workflow-review accepts every field already filled — invariant.

If a required field arrives empty — workflow-review does not try to recover. It returns `{status: error, reason: status_error_empty_required_field}` (the `reason` value is taken from a locale key) back to the orchestrator.

REVIEW-profile specifics (differences from other workflows):
- `start_stage` — always `Review` (no other stages exist; any other value is a contract error).
- `end_stage` — always `Review` or `null` (auto-move is not a profile stage but a post-processing step on the artifact).
- `stage_scope` — always `single` (the workflow never "continues" further; auto-move applies automatically based on the Review result, see section 2).
- `start_phase` — not used (Review has no phases).
- `need_test`, `need_review` — ignored: this profile IS the review; `swift-toolkit:swift-reviewer` does not call itself recursively, and tests run inside the donor workflows (FEATURE/BUG/REFACTOR/TEST).
- `mode` — `manual` / `auto` (see sections 3 and 4): only affects whether auto-move is confirmed with the user.
- `stack`, `archive_paths` — standard (context for `swift-toolkit:swift-reviewer` and information about backups created by the orchestrator).

## 2. Stages

- **Review** — `swift-toolkit:swift-reviewer`. Artifact: `Review.md` in the task folder. **Mandatory first line** of the artifact: `[REVIEW_STATUS] = APPROVED | CHANGES_REQUESTED | DISCUSSION` — this is the contract shared with every workflow and the orchestrator. Body of `Review.md`: what was done well, what needs changes (by severity), open questions. The detailed output format is described in `agents/swift-reviewer.md`.

- **Auto-move** — a deterministic post-stage. The workflow reads the first line of `Review.md` strictly as the field `[REVIEW_STATUS] = <value>` (regex: starts with `[REVIEW_STATUS] =`, value parsed by `=`). Substring search inside the body of `Review.md` is forbidden. Possible values and actions:
  - `APPROVED` → call `swift-toolkit:task-move` to relocate the task folder into `Tasks/DONE/`. If the task is already in `Tasks/DONE/` — leave it (idempotent).
  - `CHANGES_REQUESTED` → the task stays in `Tasks/ACTIVE/`. A section is added to `Done.md` (or, if `Done.md` is absent, to a separate `ChangesRequested.md` next to `Review.md`), listing the concrete points (Critical/Major severity) from `Review.md`. **CRITICAL — DO NOT TRANSLATE THE HEADING.** The heading is the byte-for-byte literal `## Awaiting changes`, written exactly that way regardless of the active language. Do not translate, localize, or adapt it — it is a machine-parsed structural anchor, not a human-facing label. The bullet items below it ARE agent-composed prose and DO follow the user's natural language.
  - `DISCUSSION` → the task stays in `Tasks/ACTIVE/`. A `Questions.md` is created (or extended) with a section `## <ISO-date> — Discussion from Review` quoting/linking the disputed points from `Review.md`.
  - Any other value, or missing first line in the required format → `{status: error, reason: "invalid or missing [REVIEW_STATUS] in Review.md"}`.

## 3. Manual mode

After the Review stage completes, the orchestrator asks the user via `AskUserQuestion` using the `auto_move_prompt` key from `locales/<lang>.md`, with placeholder `{status}` (the parsed `[REVIEW_STATUS]` value).

- `Yes` — workflow-review performs auto-move per section 2.
- `Modify` — the user edits `Review.md` (e.g. changes the status or wording); the orchestrator then re-runs workflow-review starting at the Review stage (`action=redo`, `stage_scope=single`).
- `No` — auto-move is skipped; the task stays where it is, with no entries written to `Done.md` / `Questions.md`. The output records `notes` rendered from key `status_cancelled_user_no`.

Workflow-review **does NOT call `AskUserQuestion` itself** — after Review it returns control to the orchestrator with `next_recommended_action=ask_user`. The decision to pause or fall back to text input is the orchestrator's domain.

## 4. Auto mode

No pauses. Auto-move runs immediately after Review per section 2, with no user confirmation. Workflow-review returns a single final result with auto-move already applied.

The final commit, if the orchestrator initiates the commit flow, is confirmed with the user regardless of mode — that is the orchestrator's responsibility.

## 5. Output Contract

After Review (in `manual` mode) and after Auto-move (in both modes), workflow-review returns a JSON-like structure to the orchestrator:

```
{
  status: ok | error | cancelled | interrupted,
  last_completed_stage: Review | AutoMove,
  artifact_path: <path to Review.md>,
  next_recommended_action: stop,
  notes: rendered from locale key `notes_template` with placeholders {status}, {action} where {action} ∈ {moved-to-DONE | kept-in-ACTIVE-with-ChangesRequested | kept-in-ACTIVE-with-Questions | skipped-by-user | not-yet-applied}
}
```

Field semantics:
- `status=ok` — the stage finished correctly.
- `status=error` — a contract error (e.g. invalid `start_stage`, missing/invalid `[REVIEW_STATUS]`, fatal failure of `swift-toolkit:swift-reviewer` or `task-move`).
- `status=cancelled` — the user explicitly declined to continue (rendered to the user via locale key `status_cancelled_user_no`). A normal outcome.
- `status=interrupted` — execution was interrupted by a technical fault or external signal.
- `last_completed_stage` — `Review` if auto-move has not yet been applied (manual pause before AUQ); `AutoMove` if auto-move has been applied or explicitly skipped by the user.
- `artifact_path` — path to `Review.md` (which remains the profile's key artifact even after the folder is moved into `Tasks/DONE/`).
- `next_recommended_action` — **always `stop`**: REVIEW concludes its cycle and never hands control to another workflow.
- `notes` — the actual `[REVIEW_STATUS]` value and the auto-move action taken (or the reason it was skipped), rendered from `notes_template` in the locale.

## 6. What workflow-review does NOT do

- Does NOT start other workflows. If `[REVIEW_STATUS] = CHANGES_REQUESTED`, workflow-review **does not initiate** workflow-feature / workflow-bug / workflow-refactor to address the comments — that decision is the user's (e.g. through `task-new` or `action=redo` on the original task).
- Does NOT modify project code. The only filesystem changes allowed are `Review.md`, `Done.md` / `ChangesRequested.md`, `Questions.md`, and moving the task folder via `task-move`.
- Does NOT parse `Review.md` by content — auto-move decides only by the structured `[REVIEW_STATUS]` field on the first line. Substring search ("approved", "LGTM", "changes requested" in the body) is forbidden as unreliable.
- Does NOT switch its `stage_scope` — it is always `single`. Any `forward` / `all` from the orchestrator is ignored (return `{status: error, reason: "stage_scope must be single for REVIEW"}`).
- Does NOT route — profile selection happens in the orchestrator before the call.
- Does NOT read `Task.md` to determine stack/mode — everything arrives in `args`.
- Does NOT create backups in `_archive/` — the orchestrator did so before handing off control; the paths are already in `archive_paths`.
- Does NOT call `AskUserQuestion` — the orchestrator does that before auto-move in `manual` mode.
- Does NOT confirm the commit with the user — the orchestrator handles that after a `next_recommended_action` return.
