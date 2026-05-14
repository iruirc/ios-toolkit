## description
Bootstrap a new multi-package SPM workspace from an interactive Q&A or a supplied workspace.yml.

## preflight_header
workspace-init pre-flight:

## preflight_required_yq_ok
- required: yq        ✓ (v{version})

## preflight_required_yq_missing
- required: yq        ✗ (install: brew install yq)

## preflight_optional_gh_ok
- optional: gh        ✓

## preflight_optional_gh_missing
- optional: gh        ✗ (install for use_gh: true)

## preflight_optional_xcodegen_ok
- optional: xcodegen  ✓

## preflight_optional_xcodegen_missing
- optional: xcodegen  ✗ (install for example_app: true)

## qa_workspace_name
Workspace name (must match [A-Za-z][A-Za-z0-9-]*):

## qa_project_block
Include a `project` block (host app)?

## qa_groups
Use package groups (split packages across subdirs)?

## qa_remotes
Top-level remote names (comma-separated, ≥1):

## qa_pkg_name
Package name:

## qa_pkg_archetype
Archetype:

## qa_pkg_version
Version (default 0.1.0):

## qa_pkg_deps
Workspace-internal deps (multiselect):

## qa_pkg_example_app
Generate Example/ (xcodegen, Cluster 3)?

## qa_tasks_enabled
Provision a shared Tasks/ repo at the workspace-parent level (sibling to packages and project repos)? (Y/N, default Y)

## qa_tasks_path
Tasks/ directory path (relative to workspace-parent, default ./Tasks):

## qa_bootstrap_use_gh
Create GitHub repos via gh?

## qa_bootstrap_push_after_init
Push initial commits to remotes?

## qa_bootstrap_commit_after_init
Auto-commit initial scaffolding?

## confirm_summary_header
Will create:

## confirm_prompt
Proceed? (Y/N)

## abort_no_changes
Aborted; no filesystem changes made.

## error_validation
workspace.yml validation failed; see errors above. exit 2.

## error_step_failed
error at step {step}: {details}
to resume after fixing: workspace-init --resume

## report_success
Workspace bootstrapped. Next: open {workspace_name}.xcworkspace

## qa_project_name
Project name (used for app target naming):

## qa_app_platform
Which platform? (or 'end' to stop)

## qa_app_repo_name
Repo name for {platform} (default: {default}):

## report_app_swift_init_pending
Will trigger /swift-init for: {apps_csv}

## error_app_swift_init_failed
swift-init failed for {app}: {details}

## error_xcodegen_missing
xcodegen not on PATH (required for project generation when project block is present). Install: brew install xcodegen
