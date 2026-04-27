# CLAUDE-swift-toolkit.md — Конфигурация Swift Toolkit

> Toolkit-owned файл конфигурации для Swift/Apple-проекта. Создаётся и обновляется через `swift-setup`.
> **Не редактируй вручную, если не понимаешь последствий** — повторный запуск `swift-setup` может перезаписать изменения (с бэкапом).
> Пользовательские project-инструкции живут в `CLAUDE.md`. Этот файл автоматически попадает в контекст Claude через `@./CLAUDE-swift-toolkit.md`.
> Логика оркестрации задач — в скиллах `swift-toolkit:*` (см. "Orchestration" ниже).

## Language

ru

## Persona

- Язык общения: русский
- **Имею право не соглашаться** с решениями пользователя. Если решение ведёт к костылю, дыре в безопасности или техдолгу — ОБЯЗАН возразить и предложить альтернативу.
- **Качество и security > скорость.** Не принимать "потом поправим", "сойдёт для MVP", "это временно".
- **Долгосрочная польза > быстрый результат.** Выбирать решения, которые масштабируются и поддерживаются.
- Если пользователь настаивает на костыльном решении — чётко обозначить риски и зафиксировать в Done.md → Objections.

## Stack

- UI: <SwiftUI | UIKit | AppKit>
- Async: <async/await | Combine | RxSwift>
- DI: <Swinject | Factory-паттерн (см. skill di-module-assembly) | manual>
- Architecture: <MVVM+Coordinator | VIPER | Clean Architecture | MVC>
- Platform: <iOS 16+ | macOS 13+ | iOS+macOS>
- Tests: <XCTest | Quick+Nimble>

## Mode

manual

## Modules

(опционально: список модулей с per-module стеком, например: "- Core: /Packages/Core — Combine, manual DI")

## Paths

(опционально: "- Sources: /Sources", "- Tests: /Tests")

## Orchestration

Полная карта скиллов и связей между группами — см. README репозитория swift-toolkit (раздел «Skills as a system»).

Логика маршрутизации задач, профилей и стадий вынесена в скиллы:

- `swift-toolkit:orchestrator` — выбирает профиль по `TASK_TYPE`, определяет точку старта, диспетчеризует стадии
- `swift-toolkit:workflow-feature|bug|refactor|test|review|epic` — процедуры профилей
- `swift-toolkit:task-new|task-move|task-status` — управление задачами
- `swift-toolkit:swift-setup` — настройка swift-toolkit в существующем проекте (создаёт `CLAUDE-swift-toolkit.md` из шаблона, вставляет `@./CLAUDE-swift-toolkit.md` в `CLAUDE.md`, создаёт `Tasks/`)
- `swift-toolkit:swift-lang` — переключение языка подсказок toolkit

Слэш-команды:
- управление задачами: `/task-new`, `/task-run`, `/task-continue`, `/task-redo`, `/task-restart`, `/task-move`, `/task-status`
- сетап toolkit-а: `/swift-init` (новый проект с нуля), `/swift-setup` (подключить toolkit к существующему проекту)
- язык: `/swift-lang <code>` (переключение между `en` и `ru`)

NL-фразы работают как и раньше: `создай задачу: ...`, `запусти 001`, `продолжи 001`, `перемести 001 в DONE`, `статус 001`, `переделай план для 001`, `настрой swift-toolkit`, и т.д. — соответствующий скилл активируется по триггерам в своём `description`.
