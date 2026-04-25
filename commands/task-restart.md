---
description: Перезапустить задачу с этапа до конца (с архивацией)
argument-hint: <id> <stage> | --full
---

Активируй `swift-toolkit:orchestrator` с action=restart.

Парсинг $ARGUMENTS:
- `<id> <stage>` → start_stage = <stage>, stage_scope=forward (архивирует stage и все последующие)
- `<id> --full` → action=restart-full, stage_scope=all (полный сброс, архивирует ВСЕ артефакты включая Done.md)

В manual режиме — AskUserQuestion перед архивированием. Для `--full` дополнительное подтверждение если задача в DONE/.
