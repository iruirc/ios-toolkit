---
name: task-status
description: |
  Show task progress: current stage, phase, checkboxes, resume point. Read-only.
  Use when (en): "task status N", "where did we stop in N", "what's done in N", "show progress N", "/task-status N", "status of active tasks", "what's in progress"
  Use when (ru): "статус задачи N", "где остановились в N", "что готово в N", "покажи прогресс N", "/task-status N", "статус активных задач", "что в работе"
---

# Task Status

Read-only overview of task progress in `Tasks/`. Shows the current stage, phase progress from `Plan.md`, the resume point, and a list of existing artifacts. Without `task_id` — a compact summary of every task in `Tasks/ACTIVE/`.

## Language Resolution

Before producing any user-facing string:

1. Read `CLAUDE-swift-toolkit.md` from the project root.
2. Find the `## Language` section.
3. Take the first non-empty line in that section, lowercase and trim it. That is `<lang>`.
4. If `<lang>` is `en` or `ru`, use it. Otherwise default to `en`.
5. Read this skill's `locales/<lang>.md`. Look up keys by H2 header.
6. If a key is missing, fall back to the same key in `locales/en.md`. If still missing, that's a bug — fail loudly with key name.

Caching: resolve `<lang>` once per skill invocation; do not re-read CLAUDE-swift-toolkit.md per string.

## Triggers

Bilingual triggers are listed in the frontmatter `description:`. The skill is invoked either via the `/task-status` slash command or directly by NL phrases that match those triggers.

## Input

| Field | Type | Description |
|---|---|---|
| `task_id` | string, optional | Task number or slug (e.g. `026`, `001-profile-screen`). If absent — produce a summary across every `Tasks/ACTIVE/*/`. |

## Algorithm

```
1. If task_id is provided:
   a. Locate Tasks/<STATUS>/<task_id>-*/ (scan every STATUS folder + Tasks/<task_id>-*).
      ↓ if the folder is not found → render the error using key `error_task_not_found` with placeholder {task_id}.
   b. Read Task.md → [TASK_TYPE], [WORKFLOW_MODE] (if present), [NEED_TEST], [NEED_REVIEW], [STATUS] (for steps).
   c. If Done.md exists → the task is complete; render the card using key `card_done_template` with placeholders {task_id}, {profile}, {mode}, {date}, {artifacts}.
   d. If Plan.md exists → parse:
      - The phase progress table (status symbols: ✅ 🔄 ⬜ ⏸ 🚫 ⊘).
      - Count: completed ✅ / in progress 🔄 / pending ⬜ / other (⏸ 🚫 ⊘).
      - Find the first unfinished phase (🔄, otherwise the first ⬜) — that is the Resume point.
      - Inside the phase, find the first unticked checkbox `- [ ]` and extract its label (text after the checkbox) for the Resume field.
      - If the progress table is missing or unparseable → see Edge cases.
      Render the card using key `card_active_template` with placeholders {task_id}, {profile}, {mode}, {done}, {total}, {in_progress}, {pending}, {stage}, {phase}, {resume}, {artifacts}.
   e. If only Research.md exists (no Plan.md) → the Plan stage has not yet run;
      Resume = value from key `resume_plan_stage`.
   f. If neither Research.md nor Plan.md exists → the Research stage has not yet run;
      Resume = value from key `resume_first_stage_research`.

2. If task_id is not provided:
   a. List every Tasks/ACTIVE/*/.
      ↓ if empty → render the error using key `error_no_active_tasks`.
   b. For each folder, run steps 1.b–1.f and collect rows for the table.
   c. Render the compact table:
      - Heading using key `table_header_active`.
      - Column header line using key `table_header_columns`.
      - One row per task.
```

The progress symbols are aligned with the orchestrator's State Detection: `⬜` todo, `🔄` in progress, `✅` done, `⏸` paused, `🚫` blocked, `⊘` skipped.

## Output templates

User-facing card and table layouts are defined as locale keys (see `locales/<lang>.md`):

- `card_active_template` — single task with `Plan.md` present.
- `card_todo_template` — single task with only `Task.md` present (just created).
- `card_done_template` — single task with `Done.md` present.
- `table_header_active` + `table_header_columns` — compact table for the all-ACTIVE summary.

## Edge cases

- `Task.md` without `[TASK_TYPE]` → render the error using key `error_profile_undefined`.
- `Plan.md` without a progress table or with a corrupted one → render Progress as `error_plan_unparseable`; Resume = `resume_dash`.
- Task folder not found → render the error using key `error_task_not_found` with placeholder `{task_id}`.
- `Tasks/ACTIVE/` is empty → render the error using key `error_no_active_tasks`.
- Step task (`<id>.step` inside an epic) → search by the full path `Tasks/**/<parent>-*/.../<id>.step/`; in the status row also display the step's `[STATUS]` (PENDING / IN_PROGRESS / DONE / DEFERRED / BLOCKED / SKIPPED).
- Multiple tasks match `task_id` (should not happen in practice) → list the matching paths and ask the user to disambiguate.

## What this skill does NOT do

- Does NOT modify files — only reads `Task.md` / `Plan.md` / `Done.md` / `Research.md`.
- Does NOT start workflows and does not call workflow-* or orchestrator — informational only.
- Does NOT resolve stack / mode (that is the orchestrator's job); shows only what is physically recorded in the task files and/or `CLAUDE-swift-toolkit.md`.
- Does NOT create backups and does not touch `_archive/`.
