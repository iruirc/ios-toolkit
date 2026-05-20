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
Next package name (leave EMPTY to finish adding packages):

## qa_pkg_archetype
Archetype:

## qa_pkg_version
Version (default 0.1.0):

## qa_pkg_deps
Workspace-internal deps (multiselect):

## qa_pkg_example_app
Generate Example/ (xcodegen, Cluster 3)?

## qa_tasks_enabled
Provision a shared Tasks/ folder at the workspace-parent level (sibling to packages and project repos)? (Y/N, default Y)

## qa_tasks_mode
How should Tasks/ be created? [sibling = mkdir + git init inside workspace-parent (default) | path = same, but at a custom relative path | symlink = ln -s to an external folder]

## qa_tasks_path
Tasks/ directory path (relative to workspace-parent, default ./Tasks):

## qa_tasks_symlink_target
Symlink target for Tasks/ (relative path with .. or absolute, e.g. ../../Tasks):

## qa_docs_enabled
Provision a shared Docs/ folder at the workspace-parent level (sibling to packages and project repos)? (Y/N, default Y)

## qa_docs_mode
How should Docs/ be created? [sibling = mkdir + git init inside workspace-parent (default) | path = same, but at a custom relative path | symlink = ln -s to an external folder]

## qa_docs_path
Docs/ directory path (relative to workspace-parent, default ./Docs):

## qa_docs_symlink_target
Symlink target for Docs/ (relative path with .. or absolute, e.g. ../../Docs):

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

## qa_add_ios_app
Add an iOS app to this project? (Y/N)

## qa_add_macos_app
Add a macOS app to this project? (Y/N)

## qa_app_repo_name
Repo name for {platform} (default: {default}):

## report_app_swift_init_pending
Will trigger /swift-init for: {apps_csv}

## error_app_swift_init_failed
swift-init failed for {app}: {details}

## error_xcodegen_missing
xcodegen not on PATH (required for project generation when project block is present). Install: brew install xcodegen
