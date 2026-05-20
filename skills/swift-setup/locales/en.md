# swift-setup — en

## error_not_swift_project
Not a Swift project (no `.xcodeproj`, `.xcworkspace`, or `Package.swift` found). To create a new project use `@swift-toolkit:swift-init`.

## error_template_not_found
swift-toolkit CLAUDE-swift-toolkit.md template not found. Check `<toolkit-root>/templates/` or the active host's installed plugin/cache templates.

## auq_create_tasks_structure
Create `Tasks/` structure for managing tasks? [Yes / No]

## auq_create_docs_structure
Create `Docs/` structure for project documentation? [Yes / No]

## auq_q1_ui_label
UI framework

## auq_q2_async_label
Async approach

## auq_q3_di_label
Dependency Injection

## auq_q4_arch_label
Architecture

## auq_q5_platform_label
Platform

## auq_q6_tests_label
Test framework

## auq_q7_mode_label
Workflow mode

## report_success_template
✅ swift-toolkit configured in this project.

CLAUDE-swift-toolkit.md created with stack:
  - UI: {q1}
  - Async: {q2}
  - DI: {q3}
  - Architecture: {q4}
  - Platform: {q5}
  - Tests: {q6}
  - Mode: {q7}
  - Language: {lang}

Tasks/ structure: {tasks_status}
Docs/ structure: {docs_status}

Next steps:
  - create your first task: /task-new <description>
  - run a task: /task-run <id>
  - check status: /task-status

## tasks_status_created
created

## tasks_status_already_existed
already existed

## tasks_status_skipped
skipped

## docs_status_created
created

## docs_status_already_existed
already existed

## docs_status_skipped
skipped

## auq_lang_label
Toolkit language for prompts

## auq_lang_options
en | ru

## auq_reconfigure_toolkit
swift-toolkit is already configured (`CLAUDE-swift-toolkit.md` exists). What should I do?

## auq_reconfigure_toolkit_options
Overwrite | Backup-and-overwrite | Cancel

## auq_migrate_old_format
Detected old single-file format (`CLAUDE.md` contains toolkit sections). I will migrate to the two-file layout: move toolkit sections to `CLAUDE-swift-toolkit.md`, keep your sections in `CLAUDE.md`, insert the import line, and back up the original to `CLAUDE.md.bak`. Proceed?

## auq_migrate_old_format_options
Migrate-and-backup | Cancel

## report_migration_success
✅ Migrated to two-file layout.

Moved to `CLAUDE-swift-toolkit.md`: {moved_sections}
Kept in `CLAUDE.md`: {kept_sections}
Filled with defaults: {filled_default_sections}
Warnings: {warnings}
Backup: {backup_path}

To roll back: `mv {backup_path} CLAUDE.md && rm CLAUDE-swift-toolkit.md`

## error_no_toolkit_file
swift-toolkit is not configured in this project (no `CLAUDE-swift-toolkit.md`). Run `/swift-setup` first.
