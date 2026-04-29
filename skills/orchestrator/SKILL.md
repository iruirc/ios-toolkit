---
name: orchestrator
description: |
  Routes a user request to the appropriate profile workflow (FEATURE/BUG/REFACTOR/TEST/REVIEW/EPIC), resolves missing parameters (profile, mode, stack, start point), and manages stages and artifact archival.
  Use when (en): "run N", "do N", "execute N", "continue N", "only <stage> for N", "up to <stage> for N", "start from <stage> for N", "redo <stage> for N", "start from phase N.N for X", "redo phase N.N for X", "start over for N", "rerun validation for N"
  Use when (ru): "запусти N", "сделай N", "выполни N", "продолжи N", "только <stage> для N", "до <stage> для N", "начни с <stage> для N", "переделай <stage> для N", "начни с фазы N.N для X", "переделай фазу N.N для X", "начни заново для N", "перезапусти валидацию для N"
---

# Orchestrator

Single entry point for routing tasks from `Tasks/<STATUS>/<task_id>-*/` into the corresponding profile workflow. The skill accepts a minimal input (only `task_id`), fills in the remaining parameters via a deterministic algorithm, and hands control to `swift-toolkit:workflow-*` via a structured contract.

The skill itself does not perform the work of stages — it only resolves parameters, validates the command, confirms with the user (in `manual` mode), and dispatches control to the profile workflow.

## Language Resolution

Before producing any user-facing string:

1. Read `CLAUDE-swift-toolkit.md` from the project root.
2. Find the `## Language` section.
3. Take the first non-empty line in that section, lowercase and trim it. That is `<lang>`.
4. If `<lang>` is `en` or `ru`, use it. Otherwise default to `en`.
5. Read this skill's `locales/<lang>.md`. Look up keys by H2 header.
6. If a key is missing, fall back to the same key in `locales/en.md`. If still missing, that's a bug — fail loudly with key name.

Caching: resolve `<lang>` once per skill invocation; do not re-read CLAUDE-swift-toolkit.md per string.

## Tool Loading (preamble)

`AskUserQuestion` in the current Claude Code is loaded lazily. The **first action** the orchestrator performs on any run:

```
ToolSearch select:AskUserQuestion
```

Once the schema is loaded, `AskUserQuestion` may be called. If loading fails for any reason (older environment, tool missing), use a textual fallback: ask the question with numbered options in a regular message and parse the user's reply. Use the `fallback_profile_question` locale key for the prompt text.

Reply parsing: a digit, the profile name, or an unambiguous prefix (`bug`, `ref`, `test`).

## Resilient Input Contract

The minimum viable input is just `task_id`. All other fields are optional and resolved in the Resolution Algorithm.

| Field | Type | Source | Default / Error |
|---|---|---|---|
| `task_id` | string | NL/$ARGUMENTS (e.g. `026`, `137`, `001-foo`) | **required** — error using key `error_no_task_id` |
| `action` | enum: `run` / `continue` / `redo` / `restart` / `restart-full` | parsed from the command (see triggers table) | `run` for a bare "run/do/execute N", `continue` for "continue N" |
| `stage_target` | string (profile stage name) | required for `redo` / `restart`, or for `--from` / `--to` modifiers under `run` | not needed for `run` / `continue` / `restart-full` without modifiers |
| `mode_override` | enum: `manual` / `auto` | explicit "automatically" / "step-by-step" in the request | resolved from Task.md → CLAUDE-swift-toolkit.md → `manual` |
| `stack_override` | string | stack explicitly named in the request | resolved from Task.md → CLAUDE-swift-toolkit.md → imports → AskUserQuestion |

**Invariant:** the orchestrator does NOT crash on missing optional fields. It resolves them in the Resolution Algorithm and only then hands the fully populated contract to workflow-*.

## Routing

The orchestrator does not activate on every user request — light commands bypass it. Order of checks (first match wins):

1. **Project initialization** — "create project" / "initialize" / no `.xcodeproj` and no `Package.swift` → remind about agent `swift-toolkit:swift-init` (invocation: `@swift-toolkit:swift-init` or slash command `/swift-init`). Orchestrator does not run.
2. **Task management** — "create task" / "new task" / "ft" / "create sub-task for N" → skill `task-new`. "Move task" / "to DONE" / "step N of epic M to <STATUS>" → skill `task-move`. Orchestrator does not run.
3. **Micro-edit** — "fix" / "rename" / "change" + ≤2 files with no interface changes → execute directly with a quick check via XcodeBuildMCP. Orchestrator does not run.
4. **Otherwise** — this is task work. The orchestrator runs:
   - Is there a `Task.md` for `task_id`? Yes → read `[TASK_TYPE]`, `[WORKFLOW_MODE]` (if present), `## 4. [Stack]` (if present), `[STATUS]` (for steps).
   - No → run `task-new`, then continue.
   - Determine the profile from `[TASK_TYPE]` (see Dispatch).
   - Confirmation/skip is governed in Resolution Algorithm, step 6 (single source of truth).

## State Detection

The source of truth is `Plan.md` (the progress table with checkboxes `⬜ 🔄 ✅ ⏸ 🚫 ⊘`).

Checkbox legend: `⬜` = todo (planned), `🔄` = in progress, `✅` = done, `⏸` = paused, `🚫` = blocked, `⊘` = skipped.

State Detection is **profile-aware** and **purely file-existence driven** — the orchestrator never parses inline content of `Task.md`. Per-profile mapping from filesystem markers in the task folder to a `start_stage`:

| Profile | `Plan.md` exists | `Research.md` exists | `Reproduce.md` exists | None of the above |
|---|---|---|---|---|
| FEATURE | first `⬜` phase | `Plan` | n/a | `Research` |
| EPIC | first `⬜` phase | `Plan` | n/a | `Research` |
| BUG | first `⬜` phase | `Plan` | `Diagnose` | `Reproduce` |
| REFACTOR | first `⬜` phase | `Plan` | n/a | `Analyze` |
| TEST | first `⬜` phase | `Plan` | n/a | `Analyze` |
| REVIEW | n/a | n/a | n/a | `Review` (single-stage profile) |

Algorithm:

1. Task folder is in `Tasks/DONE/` OR `Done.md` exists → the task is considered finished. `AskUserQuestion`: confirm a full restart (=`action=restart-full`), reopen (move back into `ACTIVE/`), or exit.
2. Walk the columns of the row matching the current profile **left to right**; the first match determines `start_stage`. For BUG specifically: `Plan.md` wins over `Research.md`, which wins over `Reproduce.md`.
3. `Plan.md` exists but its progress table is missing or unparseable → consider stage `Plan` complete; start at the next stage in the profile's sequence (FEATURE/EPIC: `Execute`; BUG: `Fix`; REFACTOR: `Refactor`; TEST: `Write`); for REVIEW (no next stage), ask explicitly via `AskUserQuestion`. Add a warning to the user.
4. **Inline-content note.** If `Task.md` carries embedded reproduce/research/analyze material but no artifact files exist in the task folder, State Detection still picks the first stage of the profile (per the rightmost column of the table). The user can override via the `confirm_dispatch` picker (Resolution Algorithm step 6) or by passing `--from <stage>`.

**Invariant:** `start_stage` produced by State Detection is always a member of the target profile's stage list. Defense-in-depth validation runs in Resolution Algorithm step 5.5 regardless.

**De-sync:**
- `Task.md` is newer than `Plan.md` → warn that the task description may have changed after planning; suggest `redo Plan`.
- Git contains commits touching task files without checkbox updates in `Plan.md` → warn about the desync; do not block, but flag it in the outbound contract.

## Resolution Algorithm

```
1. Validate & find task folder:
   • If task_id is not provided → error using key `error_no_task_id` and stop.
   • Otherwise — locate the folder Tasks/<STATUS>/<task_id>-*/ (scan Tasks/**/<task_id>-* across all STATUS folders).
   • For steps: Tasks/**/<parent_id>-*/.../<step_id>.step/
   ↓ if not found → error using key `error_task_not_found` with placeholder `{task_id}`

2. Resolve TASK_TYPE → profile
   • Read Task.md, extract the [TASK_TYPE] field
   ↓ if missing → AskUserQuestion using key `fallback_profile_question`
   ↓ profile = workflow-<TASK_TYPE.lower()>

3. Resolve mode (priority high→low):
   mode_override (NL: "automatically" / "step-by-step")
   > Task.md [WORKFLOW_MODE]
   > CLAUDE-swift-toolkit.md "## Mode"
   > "manual" (default)

4. Resolve stack (priority high→low):
   stack_override (explicit in the request)
   > Task.md "## 4. [Stack]"
   > CLAUDE-swift-toolkit.md "## Modules" (if the task's files fall into one of the listed modules)
   > CLAUDE-swift-toolkit.md "## Stack"
   > auto-detection by imports of the affected files
   > AskUserQuestion (last fallback)

5. Resolve start_stage (depends on action):
   action=run, stage_target=null  → state-detection: first unfinished stage
   action=run, stage_target=X     → start at X (--from), do not touch previous stages
   action=continue                → state-detection (same as run without stage)
   action=redo, stage_target=X    → start at X, re-execute ONLY this stage
   action=restart, stage_target=X → start at X, re-execute X and all subsequent stages
   action=restart-full            → start at the profile's first stage, re-execute all

5.5. Validate start_stage against profile.stages:
   • profile_stages := ordered stage list of the target profile (canonical source: workflow-<profile> SKILL.md heading)
   • if start_stage ∈ profile_stages → continue
   • else (defense-in-depth — covers bugs in State Detection, user typos in `--from`, future code paths):
       if mode == manual:
           AskUserQuestion using key `auq_stage_recovery_question`
              placeholders: `{profile}`, `{invalid_stage}`, `{profile_stages_list}`
              options:
                  • one option per stage in profile_stages (in profile order)
                  • the stage State Detection (Section "State Detection") would have picked is annotated
                    with locale key `auq_stage_recovery_recommended_suffix`
                  • final option: locale key `confirm_dispatch_cancel`
           → user picks stage S → start_stage := S, continue
           → user picks Cancel → return {status: cancelled, reason: status_cancelled_user_no}
       if mode == auto:
           return {status: error, reason: error_stage_not_in_profile,
                   notes: locale `error_stage_not_in_profile` with placeholders filled}

6. Confirmation in manual mode:
   if mode == manual:
       AskUserQuestion using key `confirm_dispatch` with placeholders `{profile}`, `{mode}`, `{stack}`, `{start_stage}`
       options (in this order):
           1. locale key `confirm_dispatch_yes`     → dispatch as resolved
           2. locale key `auq_confirm_dispatch_pick_stage` → open the same picker as in step 5.5,
              but using locale key `auq_stage_override_question` for the title (no `{invalid_stage}`
              placeholder); on user pick, `start_stage := picked`, then dispatch
           3. locale key `confirm_dispatch_cancel`  → return {status: cancelled, reason: status_cancelled_user_no}
   else:
       skip confirmation, go straight to Dispatch

   Confirmation is also skipped if both key parameters (profile AND mode) are explicitly stated in the user's original command.
   "Explicitly stated" = present as literal keywords in the request text.
   Example: `run 026 as BUG automatically` — confirmation skipped (both "BUG" and "automatically" are present).
   Example: `run 026` — confirmation required (neither profile nor mode is explicit).
```

See also the "Stage Management" section — it details the semantics of `run --from` / `redo` / `restart` / `restart-full` and the "what gets archived" matrix.

## Outbound Contract

After Resolution, the orchestrator calls `Skill` with args in `key=value` form, **separated only by newlines** (a comma is NOT used as a field separator). **All fields are filled** — workflow-* never tries to recover anything.

Multi-valued fields (e.g. `archive_paths`) are encoded in **list syntax**: square brackets, commas inside.

```
task_id=001
profile=feature
action=run|continue|redo|restart|restart-full
start_stage=Plan
start_phase=2.3
end_stage=null
stage_scope=single|forward|all
mode=manual|auto
stack=swiftui+combine+swinject
need_test=true|false
need_review=true|false
archive_paths=[Tasks/ACTIVE/001-profile/_archive/Plan-2026-04-25T143022.md, Tasks/ACTIVE/001-profile/_archive/Research-2026-04-25T143022.md]
```

Semantics of `stage_scope`:
- `single` — only `start_stage` (for `redo`)
- `forward` — `start_stage` → end (for `run --from`, `continue`, `restart <stage>`)
- `all` — every stage of the profile, from first to last (for `restart-full`)

`end_stage` — filled only when `--to <stage>` is used (e.g. "do 026 up to plan"); otherwise `null`.

`start_phase` — for phase-level resume inside a stage (e.g. `Execute:phase=2.3`). Filled only when the trigger names a phase ("start from phase 2.3", "redo phase 2.3"); otherwise `null`.

`archive_paths` — list of paths to backups already created in `_archive/` for stages that will be overwritten (filled before handing off control). Format: `[path1, path2, path3]`. Empty list = `[]`.

**Invariant:** workflow-* never receives empty fields. If a field arrives empty — workflow-* returns an error to the orchestrator and does not try to recover.

## Dispatch

| TASK_TYPE | Workflow skill |
|---|---|
| FEATURE | `swift-toolkit:workflow-feature` |
| BUG | `swift-toolkit:workflow-bug` |
| REFACTOR | `swift-toolkit:workflow-refactor` |
| TEST | `swift-toolkit:workflow-test` |
| REVIEW | `swift-toolkit:workflow-review` |
| EPIC | `swift-toolkit:workflow-epic` |

Action after Resolution: invoke the `Skill` tool with `name` from the table and `args` in Outbound Contract format.

## Gating

**Manual** (default) — pause after each stage with an `AskUserQuestion` (use key `stage_done_prompt` with placeholder `{stage}`) confirming the move to the next; discussions that don't fit in a single reply are recorded in the task's `Questions.md`.

**Auto** — no pauses between stages. **The commit is always confirmed with the user** regardless of mode.

**Backup before overwriting / removing an artifact:** copy to `Tasks/<STATUS>/<task_id>-*/_archive/<stage>-<timestamp>.md`, where `<timestamp>` is ISO-8601 without colons (`2026-04-25T143022`). The orchestrator makes the backup BEFORE calling workflow-* and passes the paths via `archive_paths` in the outbound contract.

In `manual` mode, an `AskUserQuestion` confirmation is mandatory before the backup / removal.

## Stage Management

Triggers (free-form, parsed into `action` + `stage_target`):

| User text | action | stage_target | stage_scope |
|---|---|---|---|
| "run 026" / "do 026" / "execute 026" | `run` | null | `forward` (from the state-detection point) |
| "continue 026" | `continue` | null | `forward` |
| "do 026 up to plan" | `run` | null (`end_stage=Plan`) | `forward` (capped at the top) |
| "only plan for 026" / "only research for 026" | `run` | `<stage>` (`end_stage=<stage>`) | `single` |
| "start from Plan for 026" | `run` | `Plan` (as `--from`) | `forward` |
| "redo plan for 026" | `redo` | `Plan` | `single` |
| "start from phase 2.3 for 026" | `run` | `<stage>:phase=2.3` | `forward` (from the phase anchor) |
| "redo phase 2.3 for 026" | `redo` | `<stage>:phase=2.3` | `single` (at the phase level) |
| "rerun validation for 026" | `redo` | `Validation` | `single` |
| "start over for 026" | `restart-full` | null | `all` |

> Note on the semantics of "rerun": `rerun <stage>` = `redo` of a single stage (an atomic redo). Do not confuse it with `restart`, which resets `<stage>` AND every subsequent stage. The user verb "rerun" here is closer in meaning to "redo atomically" than to "reset and walk through to the end again".

Action and archival semantics:

| Action | Semantics | What gets archived in `_archive/` | Where it starts |
|---|---|---|---|
| `run --from <stage>` | Skip previous stages | nothing | from `<stage>` |
| `redo <stage>` | Redo one stage | `<stage>` artifact | from `<stage>`, after = untouched |
| `restart <stage>` | Reset and rerun from stage to end | `<stage>` and all subsequent | from `<stage>` to end of profile |
| `restart-full` | Full reset | all artifacts | from the profile's first stage |

**All redo / restart operations in manual mode require an `AskUserQuestion` BEFORE archiving.**

Command validation:
- "only Plan" / "start from Plan" without `Research.md` (for profiles that have a preceding `Research`) → error using key `error_research_required` with placeholder `{stage}`.
- "redo <stage>" with no `<stage>` artifact present → error using key `error_redo_no_artifact` with placeholder `{stage}`; suggest `run --from <stage>`.
- An out-of-profile stage name → handled centrally in Resolution Algorithm step 5.5 (manual: stage picker; auto: hard error using key `error_stage_not_in_profile`).

## Subagent Context

The workflow-* subagent receives:

1. The full text of the task's `Task.md` (as is).
2. A short summary of previous stages (1–3 paragraphs): what was done, key decisions, open questions. Pulled from the most recent artifacts (`Research.md`, `Plan.md`).
3. Stack: the `stack` value from the Outbound Contract.
4. Mode: `mode` from the Outbound Contract.

**The stack does not need to be re-sent in full text:** the skill does not `Read` `CLAUDE-swift-toolkit.md` — stack, mode, and paths come from the context Claude Code typically loads at session start (when `CLAUDE.md` is present at the project root and imports `CLAUDE-swift-toolkit.md` via `@./`). The orchestrator parses this already-loaded context to resolve priorities.
