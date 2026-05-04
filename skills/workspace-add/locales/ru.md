## description
Добавить новый пакет или включить существующий standalone-пакет в workspace; регенерит производные артефакты.

## qa_mode
Режим:

## qa_mode_new
new — создать новый пакет

## qa_mode_incorporate
incorporate — включить существующий standalone-репо

## qa_path
Путь к существующему репо пакета:

## qa_archetype
Архетип:

## qa_group
Группа:

## qa_allowed_deps
Разрешённые зависимости (по умолчанию — правила архетипа):

## warn_existing_claude_md
предупреждение: {path}/CLAUDE.md уже существует; не перезаписан.
чтобы взять под управление toolkit: workspace-docs-regen --repair --pkg {name}

## report_success_new
Пакет {name} создан в {path}. Артефакты workspace перегенерированы.

## report_success_incorporate
Пакет {name} включён из {original_path}. Артефакты workspace перегенерированы.

## error_validation
Валидация workspace.yml после добавления упала; изменения откатаны.

## error_fs
Ошибка файловой системы: {details}
