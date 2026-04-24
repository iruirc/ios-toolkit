---
name: task-new
description: "Creates and fills a Task.md scaffold in Tasks/<STATUS>/NNN-slug/ (or nested as .step inside an epic). Use when: user says 'создай задачу', 'new task', 'ft', 'создай под-задачу для N', 'step для N'. Formalizes the user's description and fills sections; does not implement anything or research the codebase."
---

# Task New

Creates a numbered task folder + Task.md scaffold, and fills it with the user's formalized description. Single action (no separate scaffold vs fill stages).

## Triggers

Root task:
- "создай задачу", "новая задача", "new task", "ft" + description
- Explicit status: "создай задачу в TODO", "в BACKLOG", "в RESEARCH"

Step task (sub-task of an epic):
- "создай под-задачу для 137", "step для 137", "шаг к эпику 137"
- Named step: "создай шаг composition-model для 137"

## Task.md Template

```markdown
**Дата:** YYYY-MM-DD
# NNN-slug

[TASK_TYPE] = [FEATURE]       # FEATURE | BUG | REFACTOR | REVIEW | TEST | EPIC
[NEED_TEST] = [true]
[NEED_REVIEW] = [true]

# Только для step задач (внутри эпика):
[STATUS] = [PENDING]          # PENDING | IN_PROGRESS | DONE | DEFERRED | BLOCKED | SKIPPED

# Опционально (только если переопределяет проектный дефолт из CLAUDE.md):
# [WORKFLOW_MODE] = [auto]    # manual | auto

## 1. [Files]

## 2. [Description]

## 3. [Task]

## 4. [Stack]

## 5. [Logs]

## 6. [StackTrace]
```

## Process — root task

1. **Choose start status** by keywords (default `ACTIVE/`):
   - "запланируй" / "в TODO" / "на потом" → `TODO/`
   - "в беклог" / "идея на будущее" → `BACKLOG/`
   - "эпик для исследования" / "долгий research" → `RESEARCH/`
   - "в UNABLE_FIX" (rare; usually set later) → `UNABLE_FIX/`
   - Default → `ACTIVE/`
   - Explicit "создай в <STATUS>" → that STATUS folder
2. **Get next NNN**: scan all of `Tasks/**/` for folders matching `^\d{3}-`, find max, increment by 1.
3. **Make folder**: `Tasks/<STATUS>/NNN-slug/`.
4. **Create Task.md** with the template above.
5. **Formalize user input** (no codebase research) and fill sections:
   - File paths, screenshot paths → `## 1. [Files]`
   - Context / current behavior / problem → `## 2. [Description]`
   - What to do / questions / reproduction steps → `## 3. [Task]`
   - Logs → `## 5. [Logs]` (only if present in request)
   - Stack traces / crashlogs → `## 6. [StackTrace]` (only if present)
6. **Set `[TASK_TYPE]`** by keywords:
   - "баг" / "краш" / "не работает" / "регрессия" → `BUG`
   - "эпик" / "roadmap" / "исследуй большую область" → `EPIC`
   - "рефактор" / "вынеси" / "разбей на модули" → `REFACTOR`
   - "проверь" / "ревью" / "посмотри диф" → `REVIEW`
   - "напиши тесты" / "покрой тестами" / "unit-тесты" → `TEST`
   - Default → `FEATURE`
7. **Flags `[NEED_TEST]` / `[NEED_REVIEW]`** — default `true`/`true`. Flip to `false` when:
   - Visual/cosmetic ("поменяй цвет", "сдвинь кнопку", "обнови иконку", "обнови строку локализации") → `NEED_TEST = false`
   - `TASK_TYPE` is `REVIEW`, `TEST`, or `EPIC` → both flags become `false` (not applicable)
   - User explicitly asked "без тестов" or "без ревью"
8. **`[WORKFLOW_MODE]`** — add ONLY if user explicitly asked for a mode different from project's `## Режим`. Otherwise omit.
9. **Report** the created folder path to the user. Do not start the workflow.

## Process — step task (sub-task of an epic)

1. **Identify parent** — by number ("для 137"), slug ("для cross-platform-roadmap"), or current conversation context. Ambiguous → ask.
2. **Find parent folder**: `Tasks/**/137-*` (any STATUS).
3. **Choose step name**:
   - Numeric: find max existing `N.step` in the parent (including nested epics siblings), increment by 1 → `<N+1>.step`
   - Named: user said "шаг composition-model" → `composition-model.step`
4. **Create** `parent/<name>.step/Task.md` using the same template, but `[STATUS]` is always included (default `PENDING`). Step tasks do NOT have their own STATUS-subfolder — they inherit their parent's folder.
5. Formalize and fill exactly like root tasks.
6. Report the created path.

## Rules

- Do NOT research the codebase (no file reads, no grep, no glob beyond folder discovery)
- Do NOT add information that isn't in the user's request
- Do NOT propose architecture or a plan — that is the job of later workflow stages
- Sections Logs / StackTrace / Stack are created only if the user's request contains that data
- For steps, `[STATUS] = [PENDING]` by default; any other starting status requires explicit user statement
- Language of formalized text matches the language of the request (Russian in → Russian out; English in → English out)
