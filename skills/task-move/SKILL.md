---
name: task-move
description: "Moves a root task between status folders (physical mv) or changes the [STATUS] field of a step task inside an epic. Use when: user says 'перемести задачу в DONE', 'move task to ACTIVE', 'задачу 038 в DONE', '2.step задачи 137 в DONE', 'шаг 1 эпика 137 в BLOCKED'."
---

# Task Move

Moves a root task between STATUS subdirectories in `Tasks/`, or changes the `[STATUS]` field of a step task (no physical move for steps).

## Triggers

Root task moves (physical):
- "перемести задачу в DONE", "move task to ACTIVE", "в TODO", "в BACKLOG", "в CHECK", "в RESEARCH", "в UNABLE_FIX"
- "задачу 038 в DONE", "move 038 to CHECK"
- "эту задачу в DONE" (current conversation context)
- Batch: "перемести 008, 011 в DONE"

Step status change (field update):
- "2.step задачи 137 в DONE", "шаг 2 эпика 137 в DONE"
- "1.step задачи 137 в BLOCKED"
- "шаг composition-model задачи 137 в DEFERRED"

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

1. **Identify task** by number, slug, or current context. Ambiguous → ask.
2. **Find task folder** by searching `Tasks/*/NNN-slug/` across all status subfolders (and `Tasks/NNN-slug/` at root).
3. **Identify target status** from the user's message. Missing → ask.
4. **Move**: `mv Tasks/<source>/NNN-slug Tasks/<target>/`.
   - If target is "root" or "корень" → `mv Tasks/<source>/NNN-slug Tasks/`.
5. **If the root task is an epic**, its nested `.step` folders move with it (they are inside the epic folder — no extra action needed).
6. **If the target is DONE and Plan.md has unchecked phases**, warn the user but still move if confirmed in the original request.
7. **Report** the move to the user as `<source>/NNN-slug → <target>/NNN-slug`.

## Process — step

1. **Locate the step folder** — find parent epic first, then the `.step` inside it.
   Path example: `Tasks/ACTIVE/137-cross-platform-roadmap/2.step/`.
2. **Open the step's Task.md**.
3. **Update the `[STATUS]` line** to the new value. Preserve the rest of the file.
4. **Update parent epic's Plan.md** — find the progress table row for this step, update the status cell and icon (see icon map).
5. **Report** the change: `Tasks/.../137/2.step [STATUS]: <old> → <new>`.

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
- Support both Russian and English status names (`"в DONE"` === `"to DONE"`).
- Batch: multiple tasks in one command — move them all, report each result.
- For steps, never move the physical folder — steps live inside their parent epic.
- Never ask for confirmation before moving — just do it and report (per original design of v-task-move).
- Do NOT modify any file other than the step's Task.md and its parent's Plan.md (when step status changes).
