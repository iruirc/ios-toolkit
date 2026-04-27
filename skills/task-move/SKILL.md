---
name: task-move
description: |
  Moves a root task between status folders (physical mv) or changes the [STATUS] field of a step task inside an epic.
  Use when (en): "move task to DONE", "move task to ACTIVE", "task 038 to DONE", "step 2 of epic 137 to DONE", "step composition-model of task 137 to DEFERRED"
  Use when (ru): "перемести задачу в DONE", "move task to ACTIVE", "задачу 038 в DONE", "2.step задачи 137 в DONE", "шаг 1 эпика 137 в BLOCKED", "шаг composition-model задачи 137 в DEFERRED"
---

# Task Move

Moves a root task between STATUS subdirectories in `Tasks/`, or changes the `[STATUS]` field of a step task (no physical move for steps).

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

Bilingual triggers are listed in the frontmatter `description:`. Both EN and RU phrasings activate the skill regardless of the project's active language.

Root task moves (physical) cover variants like: "move task to DONE/ACTIVE/TODO/BACKLOG/CHECK/RESEARCH/UNABLE_FIX", with the task identified by number, slug, or "this task" (current conversation context). Batch form is also accepted: "move 008, 011 to DONE".

Step status changes (field update) cover variants like: "step 2 of epic 137 to DONE", "step composition-model of epic 137 to DEFERRED".

## Available Root Statuses (folders)

| Folder | Meaning |
|--------|---------|
| `TODO` | Planned, not started |
| `ACTIVE` | In progress |
| `DONE` | Completed |
| `RESEARCH` | Research / analysis phase, often epics |
| `BACKLOG` | Deferred, low priority |
| `CHECK` | Awaiting review/verification |
| `UNABLE_FIX` | Blocked / unfixable |
| root (`Tasks/`) | Unclassified |

## Available Step Statuses (`[STATUS]` field)

`PENDING | IN_PROGRESS | DONE | DEFERRED | BLOCKED | SKIPPED`

## Process — root task

1. **Identify the task** by number, slug, or current context. Ambiguous → ask.
2. **Find the task folder** by searching `Tasks/*/NNN-slug/` across every status subfolder (and `Tasks/NNN-slug/` at root). If no match → render the error using key `error_task_not_found` with placeholder `{task_id}`.
3. **Identify the target status** from the user's message. Missing → ask. Unknown value → render the error using key `error_invalid_status` with placeholder `{status}`.
4. **Move**: `mv Tasks/<source>/NNN-slug Tasks/<target>/`.
   - If the target is "root" → `mv Tasks/<source>/NNN-slug Tasks/`.
5. **If the root task is an epic**, its nested `.step` folders move with it (they are inside the epic folder — no extra action needed).
6. **If the target is DONE and Plan.md still has unchecked phases**, warn the user but still move if the original request confirmed it.
7. **Report** the move using key `report_moved_root` with placeholders `{task_id}`, `{from}`, `{to}`.

## Process — step

1. **Locate the step folder** — find the parent epic first, then the `.step` inside it.
   Path example: `Tasks/ACTIVE/137-cross-platform-roadmap/2.step/`.
2. **Open the step's Task.md**.
3. **Update the `[STATUS]` line** to the new value. Preserve the rest of the file.
4. **Update the parent epic's Plan.md** — find the progress table row for this step, update the status cell and icon (see icon map).
5. **Report** the change using key `report_moved_step` with placeholders `{step_id}`, `{parent_id}`, `{from}`, `{to}`.

### Icon Map for Plan.md progress table

| STATUS | Icon |
|--------|------|
| PENDING | ⬜ |
| IN_PROGRESS | 🔄 |
| DONE | ✅ |
| DEFERRED | ⏸ |
| BLOCKED | 🚫 |
| SKIPPED | ⊘ |

## Rules

- If the task is already at the target status — report and do nothing.
- Support both Russian and English status names — bilingual triggers in the frontmatter cover the natural-language matching; the `STATUS` value itself is always one of the literal English enum values listed above.
- Batch: when several tasks are mentioned in one command — move them all and report each result.
- For steps, never move the physical folder — steps live inside their parent epic.
- Never ask for confirmation before moving — just do it and report.
- Do NOT modify any file other than the step's `Task.md` and its parent's `Plan.md` (when a step status changes).
