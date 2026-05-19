---
description: "Restart a task from a stage to the end (with archival) / Перезапустить задачу с этапа до конца (с архивацией)"
argument-hint: <id> <stage> | --full
---

Activate `swift-toolkit:orchestrator` with action=restart.

$ARGUMENTS parsing:
- `<id> <stage>` → start_stage = <stage>, stage_scope=forward (archives stage and all subsequent)
- `<id> --full` → action=restart-full, stage_scope=all (full reset, archives ALL artifacts including Done.md)

In manual mode — structured confirmation before archiving. For `--full` an additional confirmation if the task is in DONE/.
