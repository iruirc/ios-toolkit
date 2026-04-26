---
name: swift-setup
description: "Настраивает swift-toolkit в существующем Swift-проекте: копирует CLAUDE.md из шаблона, заполняет стек через AskUserQuestion, создаёт Tasks/ структуру. Use when: 'настрой swift-toolkit', 'подключи swift-toolkit', 'установи toolkit в проект', 'добавь swift-toolkit к проекту', '/swift-setup'. Для генерации **нового** Swift-проекта с нуля используй `@swift-init`."
---

# Swift Setup

Бутстраппинг swift-toolkit в **уже существующем** Swift-проекте: копирует шаблон `CLAUDE.md` из плагина, через `AskUserQuestion` спрашивает стек, заполняет плейсхолдеры и (по желанию) создаёт `Tasks/` структуру.

Скилл НЕ создаёт Xcode-проект, НЕ модифицирует Swift-код, НЕ запускает воркфлоу. Это разовая настройка инфраструктуры toolkit-а.

Для генерации проекта с нуля используй агент `@swift-init` (через slash `/swift-init`).

## Triggers

- "настрой swift-toolkit", "подключи swift-toolkit", "установи toolkit в проект"
- "добавь swift-toolkit к проекту", "инициализируй toolkit здесь"
- "swift-toolkit setup", "toolkit init"
- Slash: `/swift-setup`

## Preconditions

- Текущая рабочая директория — корень существующего Swift-проекта (есть `.xcodeproj`, `.xcworkspace` или `Package.swift`).
- Если `CLAUDE.md` уже есть в корне — спросить пользователя через `AskUserQuestion` (Overwrite / Backup-and-overwrite / Cancel).
- Если `Tasks/` уже есть — не перезаписывать; пропустить шаг создания.

## Tool Loading (preamble)

`AskUserQuestion` в текущем Claude Code загружается отложенно. **Первое действие** скилла:

```
ToolSearch select:AskUserQuestion
```

После загрузки схемы можно вызывать `AskUserQuestion`. Если загрузка не удалась (старая среда, отсутствует тул) — текстовый fallback: пронумерованные варианты в обычном сообщении и парсинг ответа (цифра, имя варианта или однозначный префикс).

## Algorithm

```
1. Detect project state:
   a. Проверить наличие .xcodeproj / .xcworkspace / Package.swift в корне.
      ↓ если ничего нет → ошибка: "Не Swift-проект. Для генерации нового проекта используй @swift-init."
   b. Проверить наличие CLAUDE.md в корне.
      ↓ если есть → AskUserQuestion: Overwrite / Backup-and-overwrite / Cancel.
        - Overwrite: продолжить, перезаписать.
        - Backup-and-overwrite: переименовать в CLAUDE.md.bak (если .bak уже существует — добавить timestamp), продолжить.
        - Cancel: остановить скилл, отчитаться пользователю.
   c. Проверить наличие Tasks/ в корне.
      ↓ если есть → запомнить флаг tasks_exist=true, пропустить шаг 5.

2. Locate plugin CLAUDE.md template (lookup strategy, Read первой существующей):
   a. ~/.claude/plugins/cache/swift-toolkit/swift-toolkit/<version>/CLAUDE.md
      (последняя версия — выбрать самый свежий каталог, если их несколько)
   b. ~/.claude/plugins/marketplaces/swift-toolkit/CLAUDE.md
   c. Если ни один путь не доступен → ошибка с инструкцией:
      "Шаблон CLAUDE.md плагина не найден. Проверь установку swift-toolkit
       (`~/.claude/plugins/cache/` или `~/.claude/plugins/marketplaces/`)."

3. Stack questions (AUQ, последовательно или одной мульти-формой):
   q1. UI: SwiftUI / UIKit / AppKit
   q2. Async: async/await / Combine / RxSwift
   q3. DI: Swinject / Factory / manual
   q4. Архитектура: MVVM+Coordinator / VIPER / Clean Architecture / MVC
   q5. Платформа: iOS 17+ / iOS 16+ / macOS 14+ / macOS 13+ / iOS+macOS
   q6. Тесты: XCTest / Quick+Nimble
   q7. Режим: manual (по умолчанию) / auto
       — можно опустить и оставить `manual`.

4. Write CLAUDE.md в корень проекта:
   - Прочитать содержимое шаблона из шага 2.
   - Заменить плейсхолдеры (см. таблицу Placeholder Replacements).
   - Подставить выбранный режим в секцию `## Режим`.
   - Записать результат в <project>/CLAUDE.md.

5. Optional Tasks/ structure:
   Если tasks_exist=false:
     AUQ: "Создать Tasks/ структуру для управления задачами? [Yes / No]"
     ↓ Yes →
       mkdir -p Tasks/{TODO,ACTIVE,DONE,BACKLOG,RESEARCH,CHECK,UNABLE_FIX}
       Создать .gitkeep в каждой подпапке (чтобы пустые папки попали в git).
     ↓ No → пропустить.

6. Report (см. Output report).
```

## Placeholder Replacements

| Плейсхолдер в шаблоне                                | Заполняется из ответа |
|------------------------------------------------------|------------------------|
| `<SwiftUI \| UIKit \| AppKit>`                       | q1 — UI               |
| `<async/await \| Combine \| RxSwift>`                | q2 — Async            |
| `<Swinject \| Factory \| manual>`                    | q3 — DI               |
| `<MVVM+Coordinator \| VIPER \| Clean Architecture \| MVC>` | q4 — Архитектура |
| `<iOS 16+ \| macOS 13+ \| iOS+macOS>`                | q5 — Платформа        |
| `<XCTest \| Quick+Nimble>`                           | q6 — Тесты            |
| `manual` в `## Режим`                                | q7 — Режим (или оставить `manual`) |

Замены строгие — только перечисленные плейсхолдеры в `## Стек`/`## Режим`. Остальное содержимое шаблона (Персонализация, Оркестрация, Модули, Пути) копируется без изменений.

## Output report

```
✅ swift-toolkit настроен в этом проекте.

CLAUDE.md создан с заполненным стеком:
  - UI: <q1>
  - Async: <q2>
  - DI: <q3>
  - Архитектура: <q4>
  - Платформа: <q5>
  - Тесты: <q6>
  - Режим: <q7|manual>

Tasks/ структура: <создана | уже существовала | пропущена>

Следующие шаги:
  - создать первую задачу: /task-new <описание>
  - запустить задачу: /task-run <id>
  - посмотреть статус: /task-status
```

## Edge cases

- **CLAUDE.md уже существует** → `AskUserQuestion` (Overwrite / Backup-and-overwrite / Cancel). Backup создаёт `CLAUDE.md.bak`; при коллизии — `CLAUDE.md.bak.YYYYMMDD-HHMMSS`.
- **Не Swift-проект** (нет `.xcodeproj` / `.xcworkspace` / `Package.swift`) → ошибка с подсказкой: "Похоже, это не Swift-проект. Для создания нового используй `@swift-init`."
- **Шаблон плагина не найден** ни в `cache`, ни в `marketplaces` → ошибка с указанием обоих проверенных путей и инструкцией переустановить плагин.
- **Tasks/ уже есть** → не перезаписывать, не предлагать создание; в отчёте указать "уже существовала".
- **AUQ недоступен** → текстовый fallback с пронумерованными опциями для каждого вопроса; парсинг ответа (цифра / имя / префикс).
- **Пользователь отменил настройку** (Cancel на шаге CLAUDE.md) → выйти без изменений на диске.

## Что этот скилл НЕ делает

- НЕ создаёт Xcode-проект, `Package.swift`, исходники, `.swiftlint.yml`, `README.md` — это работа `@swift-init`.
- НЕ модифицирует Swift-код и не правит существующие конфиги (Info.plist, Build Settings и т.п.).
- НЕ запускает воркфлоу (`workflow-feature` и т.д.) и не вызывает `orchestrator`.
- НЕ инициализирует git и не делает коммитов.
- НЕ устанавливает зависимости (SPM, CocoaPods, Carthage).
- НЕ создаёт первую задачу — это делается отдельно через `/task-new`.
