---
description: Показать прогресс задачи (или всех ACTIVE)
argument-hint: [id]
---

Активируй `swift-toolkit:task-status`.

Парсинг $ARGUMENTS:
- Если не пусто — показать прогресс конкретной задачи (task_id = $ARGUMENTS)
- Если пусто — показать compact-таблицу всех задач в `Tasks/ACTIVE/`
