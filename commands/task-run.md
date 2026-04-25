---
description: Запустить задачу с первой незавершённой стадии
argument-hint: <id> [--from <stage>] [--to <stage>]
---

Активируй `swift-toolkit:orchestrator` с action=run.

Парсинг $ARGUMENTS:
- Первый токен — task_id (обязательно)
- `--from <stage>` → start_stage = <stage>
- `--to <stage>` → end_stage = <stage>

Если task_id отсутствует — ошибка с подсказкой "укажи номер задачи, например `/task-run 001`".

Оркестратор сам резолвит профиль, режим, стек по своему Resilient Input Contract. В manual режиме спросит подтверждение перед стартом.
