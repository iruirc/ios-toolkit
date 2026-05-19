---
description: "Redo a single stage or phase of a task / Переделать одну стадию или фазу задачи"
argument-hint: <id> <stage|phase>
---

Activate `swift-toolkit:orchestrator` with action=redo, stage_scope=single.

$ARGUMENTS parsing:
- First token — task_id
- Second token — stage (e.g., `Plan`) or phase (e.g., `2.3`)

The orchestrator archives the indicated stage's/phase's artifact under `_archive/` and re-runs only that stage/phase. Subsequent stages are not touched.

In manual mode — structured confirmation before archiving.
