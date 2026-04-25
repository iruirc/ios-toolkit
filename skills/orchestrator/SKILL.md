---
name: orchestrator
description: "Маршрутизирует пользовательский запрос в нужный профильный воркфлоу (FEATURE/BUG/REFACTOR/TEST/REVIEW/EPIC), резолвит недостающие параметры (профиль, режим, стек, точку старта), управляет стадиями и архивацией артефактов. Use when: 'запусти/сделай/выполни N', 'продолжи N', 'только <stage> для N', 'до <stage> для N', 'начни с <stage> для N', 'переделай <stage> для N', 'начни с фазы N.N для X', 'переделай фазу N.N для X', 'начни заново для N', 'перезапусти валидацию для N'."
---

# Orchestrator

Единая точка входа для маршрутизации задач из `Tasks/<STATUS>/<task_id>-*/` в соответствующий профильный воркфлоу. Скилл принимает минимальный вход (только `task_id`), достраивает остальные параметры по детерминированному алгоритму и передаёт управление структурированным контрактом в `swift-toolkit:workflow-*`.

Скилл сам не выполняет работу стадий — только резолвит параметры, валидирует команду, согласует с пользователем (в `manual`) и передаёт управление профильному воркфлоу.

## Tool Loading (preamble)

`AskUserQuestion` в текущем Claude Code загружается отложенно. **Первое действие** оркестратора в любом запуске:

```
ToolSearch select:AskUserQuestion
```

После загрузки схемы можно вызывать `AskUserQuestion`. Если по какой-то причине загрузка не удалась (старая среда, отсутствует тул), используется текстовый fallback: вопрос с пронумерованными вариантами в обычном сообщении и парсинг ответа пользователя:

```
Какой профиль? (1) FEATURE (2) BUG (3) REFACTOR (4) TEST (5) REVIEW (6) EPIC
```

Парсинг ответа: цифра, имя профиля или однозначный префикс (`bug`, `ref`, `test`).

## Resilient Input Contract

Минимально жизнеспособный вход — только `task_id`. Все остальные поля опциональны и резолвятся в Resolution Algorithm.

| Поле | Тип | Откуда | Если нет |
|---|---|---|---|
| `task_id` | string | NL/$ARGUMENTS (например `026`, `137`, `001-foo`) | **обязательно** — ошибка с подсказкой `"Укажите номер задачи: 'запусти 026'"` |
| `action` | enum: `run` / `continue` / `redo` / `restart` / `restart-full` | парсинг команды (см. таблицу триггеров) | `run` для голого "запусти/сделай/выполни N", `continue` для "продолжи N" |
| `stage_target` | string (имя стадии профиля) | требуется для `redo` / `restart`, или для модификаторов `--from` / `--to` при `run` | не нужен для `run` / `continue` / `restart-full` без модификаторов |
| `mode_override` | enum: `manual` / `auto` | в запросе явно "автоматически" / "пошагово" | резолв из Task.md → CLAUDE.md → `manual` |
| `stack_override` | string | в запросе явно указан стек | резолв из Task.md → CLAUDE.md → импорты → AskUserQuestion |

**Инвариант:** оркестратор НЕ падает на отсутствии опциональных полей. Он резолвит их в Resolution Algorithm и только потом передаёт заполненный контракт в workflow-*.

## Routing

Оркестратор активируется не на любой пользовательский запрос — лёгкие команды отрабатывают мимо. Порядок проверок (первое совпадение выигрывает):

1. **Инициализация проекта** — "создай проект" / "инициализируй" / отсутствуют `.xcodeproj` и `Package.swift` → напомнить про агента `init-swift`. Оркестратор не запускается.
2. **Управление задачами** — "создай задачу" / "новая задача" / "ft" / "создай под-задачу для N" → скилл `task-new`. "Перемести задачу" / "в DONE" / "шаг N эпика M в <STATUS>" → скилл `task-move`. Оркестратор не запускается.
3. **Микро-правка** — "исправь" / "переименуй" / "поменяй" + ≤2 файла без изменений интерфейсов → выполнить напрямую с быстрой проверкой через XcodeBuildMCP. Оркестратор не запускается.
4. **Иначе** — это работа по задаче. Оркестратор запускается:
   - Есть `Task.md` для `task_id`? Да → читать `[TASK_TYPE]`, `[WORKFLOW_MODE]` (если есть), `## 4. [Stack]` (если есть), `[STATUS]` (для шагов).
   - Нет → запустить `task-new`, затем продолжить.
   - Определить профиль из `[TASK_TYPE]` (см. Dispatch).
   - Подтверждение/пропуск регулируется в Resolution Algorithm, шаг 6 (единственный источник правды).

## State Detection

Источник истины — `Plan.md` (прогресс-таблица с чекбоксами `⬜ 🔄 ✅ ⏸ 🚫 ⊘`).

Легенда чекбоксов: `⬜` = todo (запланировано), `🔄` = в работе, `✅` = готово, `⏸` = пауза, `🚫` = заблокировано, `⊘` = пропущено.

Алгоритм:

1. Папка задачи находится в `Tasks/DONE/` ИЛИ `Done.md` существует → задача считается завершённой. `AskUserQuestion`: подтвердить перезапуск (=`action=restart-full`), открыть заново (вернуть в `ACTIVE/`) или выйти.
2. `Plan.md` существует → распарсить прогресс-таблицу и чекбоксы фаз; резюмировать с первой незакрытой стадии (первый `⬜` или `🔄`).
   - Если прогресс-таблица не найдена или повреждена (Plan.md существует, но не парсится) — оркестратор считает стадию `Plan` завершённой, но точку резюме определить не может: стартует с `Execute` стадии профиля (если она есть) с предупреждением пользователю; иначе — спрашивает явно через `AskUserQuestion`.
3. `Plan.md` нет, `Research.md` есть → старт со стадии `Plan` профиля.
4. Ничего нет → старт с первой стадии профиля. Конкретное имя первой стадии определяется в соответствующем `swift-toolkit:workflow-<profile>` скилле; оркестратор не дублирует этот список.

**De-sync:**
- `Task.md` новее `Plan.md` → предупредить, что описание задачи могло измениться после планирования; предложить `redo Plan`.
- В git есть коммиты по файлам задачи без обновления чекбоксов в `Plan.md` → предупредить о рассинхроне; не блокировать, но пометить в выходном контракте.

## Resolution Algorithm

```
1. Validate & find task folder:
   • Если task_id не передан → ошибка "укажи номер задачи" и остановка.
   • Иначе — поиск папки Tasks/<STATUS>/<task_id>-*/ (сканировать Tasks/**/<task_id>-* по всем STATUS-папкам).
   • Для шагов: Tasks/**/<parent_id>-*/.../<step_id>.step/
   ↓ if not found → error "task <task_id> not found"

2. Resolve TASK_TYPE → profile
   • Read Task.md, extract [TASK_TYPE] поле
   ↓ if missing → AskUserQuestion с выбором: FEATURE / BUG / REFACTOR / TEST / REVIEW / EPIC
   ↓ profile = workflow-<TASK_TYPE.lower()>

3. Resolve mode (priority high→low):
   mode_override (NL: "автоматически" / "пошагово")
   > Task.md [WORKFLOW_MODE]
   > CLAUDE.md "## Режим"
   > "manual" (default)

4. Resolve stack (priority high→low):
   stack_override (явно в запросе)
   > Task.md "## 4. [Stack]"
   > CLAUDE.md "## Модули" (если файлы задачи попадают в перечисленный модуль)
   > CLAUDE.md "## Стек"
   > авто-детект по импортам затрагиваемых файлов
   > AskUserQuestion (последний fallback)

5. Resolve start_stage (зависит от action):
   action=run, stage_target=null  → state-detection: первая незакрытая стадия
   action=run, stage_target=X     → старт с X (--from), предыдущие не трогать
   action=continue                → state-detection (то же, что run без stage)
   action=redo, stage_target=X    → старт с X, перевыполнить ТОЛЬКО эту стадию
   action=restart, stage_target=X → старт с X, перевыполнить X и все последующие
   action=restart-full            → старт с первой стадии профиля, перевыполнить все

6. Confirmation в manual режиме:
   if mode == manual:
       AskUserQuestion: "Профиль: <profile>, режим: <mode>, стек: <stack>, старт: <start_stage>. Верно?"
   else:
       skip confirmation, go straight to Dispatch

   Confirmation также пропускается, если оба ключевых параметра (профиль И режим) явно указаны в исходной команде пользователя.
   "Явно указаны" = присутствуют как буквальные ключевые слова в тексте запроса.
   Пример: `запусти 026 как BUG автоматически` — confirmation пропускается (есть "BUG" и "автоматически").
   Пример: `запусти 026` — confirmation требуется (ни профиль, ни режим не указаны явно).
```

См. также раздел "Управление стадиями" — там подробности семантики `run --from` / `redo` / `restart` / `restart-full` и матрица "что архивируется".

## Outbound Contract

После Resolution оркестратор вызывает `Skill` с args в формате `key=value`, **разделённых только переводом строки** (запятая не используется как разделитель полей). **Все поля заполнены** — workflow-* не пытается ничего восстанавливать.

Многозначные поля (например, `archive_paths`) кодируются в **list syntax**: квадратные скобки, запятая внутри.

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

Семантика `stage_scope`:
- `single` — только `start_stage` (для `redo`)
- `forward` — `start_stage` → конец (для `run --from`, `continue`, `restart <stage>`)
- `all` — все стадии профиля от первой до последней (для `restart-full`)

`end_stage` — заполняется только при использовании `--to <stage>` (например, "сделай 026 до плана"); иначе `null`.

`start_phase` — для phase-level resume внутри стадии (например, `Execute:phase=2.3`). Заполняется только когда триггер указывает фазу ("начни с фазы 2.3", "переделай фазу 2.3"); иначе `null`.

`archive_paths` — список путей к уже созданным бэкапам в `_archive/` для стадий, которые будут переписаны (заполняется до передачи управления). Формат: `[path1, path2, path3]`. Пустой список = `[]`.

**Инвариант:** workflow-* никогда не получает пустых полей. Если поле приходит пустым — workflow-* возвращает ошибку оркестратору и не пытается восстанавливаться.

## Dispatch

| TASK_TYPE | Workflow skill |
|---|---|
| FEATURE | `swift-toolkit:workflow-feature` |
| BUG | `swift-toolkit:workflow-bug` |
| REFACTOR | `swift-toolkit:workflow-refactor` |
| TEST | `swift-toolkit:workflow-test` |
| REVIEW | `swift-toolkit:workflow-review` |
| EPIC | `swift-toolkit:workflow-epic` |

Действие после Resolution: вызвать `Skill` tool с `name` из таблицы и `args` в формате Outbound Contract.

## Gating

**Manual** (по умолчанию) — пауза после каждой стадии, `AskUserQuestion` с подтверждением перехода к следующей; обсуждения, которые не помещаются в одну реплику, фиксируются в `Questions.md` задачи.

**Auto** — без пауз между стадиями. **Коммит всегда согласуется с пользователем** независимо от режима.

**Бэкап перед перезаписью / удалением артефакта:** копия в `Tasks/<STATUS>/<task_id>-*/_archive/<stage>-<timestamp>.md`, где `<timestamp>` — ISO-8601 без двоеточий (`2026-04-25T143022`). Бэкап делает оркестратор ДО вызова workflow-* и передаёт пути в `archive_paths` outbound-контракта.

В `manual` режиме перед бэкапом / удалением — обязательный `AskUserQuestion` с подтверждением.

## Управление стадиями

Триггеры (произвольная форма, парсятся в `action` + `stage_target`):

| Команда | action | stage_target | stage_scope |
|---|---|---|---|
| "запусти 026" / "сделай 026" / "выполни 026" | `run` | null | `forward` (от state-detection точки) |
| "продолжи 026" | `continue` | null | `forward` |
| "сделай 026 до плана" | `run` | null (`end_stage=Plan`) | `forward` (с ограничением сверху) |
| "только план для 026" / "только исследование для 026" | `run` | `<stage>` (`end_stage=<stage>`) | `single` |
| "начни с Plan для 026" | `run` | `Plan` (как `--from`) | `forward` |
| "переделай план для 026" | `redo` | `Plan` | `single` |
| "начни с фазы 2.3 для 026" | `run` | `<stage>:phase=2.3` | `forward` (с фазового якоря) |
| "переделай фазу 2.3 для 026" | `redo` | `<stage>:phase=2.3` | `single` (на уровне фазы) |
| "перезапусти валидацию для 026" | `redo` | `Validation` | `single` |
| "начни заново для 026" | `restart-full` | null | `all` |

> Примечание по семантике "перезапусти": `перезапусти <stage>` = `redo` одной стадии (атомарное переделывание). Не путать с `restart`, который сбрасывает `<stage>` И все последующие. Пользовательский глагол "перезапусти" здесь ближе по смыслу к "переделай атомарно", а не к "сбросить и пройти заново до конца".

Семантика action и архивации:

| Action | Семантика | Что архивируется в `_archive/` | Где старт |
|---|---|---|---|
| `run --from <stage>` | Skip previous stages | nothing | from `<stage>` |
| `redo <stage>` | Redo one stage | `<stage>` artifact | from `<stage>`, after = untouched |
| `restart <stage>` | Reset and rerun from stage to end | `<stage>` and all subsequent | from `<stage>` to end of profile |
| `restart-full` | Full reset | all artifacts | from первой стадии профиля |

**Все redo / restart операции в manual режиме требуют `AskUserQuestion` ДО архивирования.**

Валидация команды:
- "только Plan" / "начни с Plan" без `Research.md` (для профилей с предшествующим `Research`) → ошибка с подсказкой "сначала запустите Research или используйте `--skip-research`".
- "переделай <stage>" при отсутствии артефакта `<stage>` → нечего переделывать; предложить `run --from <stage>`.
- Имя стадии не из текущего профиля → ошибка с перечислением допустимых стадий.

## Контекст для субагента

Workflow-* субагент получает:

1. Полный текст `Task.md` задачи (как есть).
2. Краткое summary предыдущих стадий (1–3 абзаца): что сделано, ключевые решения, открытые вопросы. Берётся из последних артефактов (`Research.md`, `Plan.md`).
3. Стек: значение `stack` из Outbound Contract.
4. Режим: `mode` из Outbound Contract.

**Стек не нужно переотдавать full-text:** скилл не выполняет `Read` для project-level `CLAUDE.md` — стек, режим и пути берутся из контекста, который Claude Code обычно загружает при старте сессии (если `CLAUDE.md` присутствует в корне проекта). Оркестратор парсит этот уже загруженный контекст для резолва приоритетов.
