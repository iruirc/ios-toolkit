---
description: Переделать одну стадию или фазу задачи (остальные не трогать)
argument-hint: <id> <stage|phase>
---

Активируй `swift-toolkit:orchestrator` с action=redo, stage_scope=single.

Парсинг $ARGUMENTS:
- Первый токен — task_id
- Второй токен — stage (например, `Plan`) или фаза (например, `2.3`)

Оркестратор архивирует артефакт указанной стадии/фазы в `_archive/`, перезапускает только её. Стадии после неё не трогаются.

В manual режиме — AskUserQuestion перед архивированием.
