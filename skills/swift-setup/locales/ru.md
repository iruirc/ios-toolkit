# swift-setup — ru

## error_not_swift_project
Не Swift-проект (не найден `.xcodeproj`, `.xcworkspace` или `Package.swift`). Для генерации нового используй `@swift-toolkit:swift-init`.

## error_template_not_found
Шаблон CLAUDE-swift-toolkit.md не найден. Проверь `<toolkit-root>/templates/` или установленные plugin/cache-шаблоны текущего хоста.

## auq_create_tasks_structure
Создать `Tasks/` структуру для управления задачами? [Yes / No]

## auq_create_docs_structure
Создать `Docs/` структуру для документации проекта? [Yes / No]

## auq_q1_ui_label
UI-фреймворк

## auq_q2_async_label
Async-подход

## auq_q3_di_label
Dependency Injection

## auq_q4_arch_label
Архитектура

## auq_q5_platform_label
Платформа

## auq_q6_tests_label
Тестовый фреймворк

## auq_q7_mode_label
Режим воркфлоу

## report_success_template
✅ swift-toolkit настроен в этом проекте.

CLAUDE-swift-toolkit.md создан со стеком:
  - UI: {q1}
  - Async: {q2}
  - DI: {q3}
  - Архитектура: {q4}
  - Платформа: {q5}
  - Тесты: {q6}
  - Режим: {q7}
  - Язык: {lang}

Tasks/ структура: {tasks_status}
Docs/ структура: {docs_status}

Следующие шаги:
  - создать первую задачу: /task-new <описание>
  - запустить задачу: /task-run <id>
  - посмотреть статус: /task-status

## tasks_status_created
создана

## tasks_status_already_existed
уже существовала

## tasks_status_skipped
пропущена

## docs_status_created
создана

## docs_status_already_existed
уже существовала

## docs_status_skipped
пропущена

## auq_lang_label
Язык подсказок toolkit

## auq_lang_options
en | ru

## auq_reconfigure_toolkit
swift-toolkit уже настроен в проекте (`CLAUDE-swift-toolkit.md` существует). Что сделать?

## auq_reconfigure_toolkit_options
Overwrite | Backup-and-overwrite | Cancel

## auq_migrate_old_format
Обнаружен старый однофайловый формат (`CLAUDE.md` содержит toolkit-секции). Я перенесу его в двухфайловую раскладку: toolkit-секции уедут в `CLAUDE-swift-toolkit.md`, твои секции останутся в `CLAUDE.md`, добавится import-строка, оригинал сохранится в `CLAUDE.md.bak`. Продолжить?

## auq_migrate_old_format_options
Migrate-and-backup | Cancel

## report_migration_success
✅ Миграция в двухфайловую раскладку выполнена.

Перенесено в `CLAUDE-swift-toolkit.md`: {moved_sections}
Осталось в `CLAUDE.md`: {kept_sections}
Заполнено дефолтами: {filled_default_sections}
Предупреждения: {warnings}
Бэкап: {backup_path}

Откат: `mv {backup_path} CLAUDE.md && rm CLAUDE-swift-toolkit.md`

## error_no_toolkit_file
swift-toolkit не настроен в этом проекте (нет `CLAUDE-swift-toolkit.md`). Сначала запусти `/swift-setup`.
