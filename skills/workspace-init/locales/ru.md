## description
Создаёт новый multi-package SPM workspace через интерактивный Q&A или из готового workspace.yml.

## preflight_header
workspace-init pre-flight:

## preflight_required_yq_ok
- required: yq        ✓ (v{version})

## preflight_required_yq_missing
- required: yq        ✗ (установи: brew install yq)

## preflight_optional_gh_ok
- optional: gh        ✓

## preflight_optional_gh_missing
- optional: gh        ✗ (нужен для use_gh: true)

## preflight_optional_xcodegen_ok
- optional: xcodegen  ✓

## preflight_optional_xcodegen_missing
- optional: xcodegen  ✗ (нужен для example_app: true)

## qa_workspace_name
Имя workspace (формат [A-Za-z][A-Za-z0-9-]*):

## qa_project_block
Добавить блок `project` (host-приложение)?

## qa_groups
Использовать группы пакетов (разнести пакеты по поддиректориям)?

## qa_remotes
Имена top-level remote (через запятую, ≥1):

## qa_pkg_name
Имя пакета:

## qa_pkg_archetype
Архетип:

## qa_pkg_version
Версия (по умолчанию 0.1.0):

## qa_pkg_deps
Workspace-зависимости (мультивыбор):

## qa_pkg_example_app
Генерировать Example/ (xcodegen, Cluster 3)?

## qa_bootstrap_use_gh
Создавать GitHub-репо через gh?

## qa_bootstrap_push_after_init
Пушить initial-коммиты на remote?

## qa_bootstrap_commit_after_init
Авто-коммитить initial scaffolding?

## confirm_summary_header
Будет создано:

## confirm_prompt
Продолжить? (Y/N)

## abort_no_changes
Отменено; изменения файловой системы не выполнены.

## error_validation
Валидация workspace.yml упала; см. ошибки выше. exit 2.

## error_step_failed
ошибка на шаге {step}: {details}
для продолжения после исправления: workspace-init --resume

## report_success
Workspace готов. Дальше: открой {workspace_name}.xcworkspace

## qa_project_name
Имя project'а (используется для именования app-таргетов):

## qa_app_platform
Какая платформа? (или 'end' чтобы закончить)

## qa_app_repo_name
Имя репо для {platform} (по умолчанию {default}):

## report_app_swift_init_pending
Будут запущены /swift-init для: {apps_csv}

## error_app_swift_init_failed
swift-init упал для {app}: {details}

## error_xcodegen_missing
xcodegen не найден в PATH (нужен для генерации project'а при наличии project-блока). Установка: brew install xcodegen
