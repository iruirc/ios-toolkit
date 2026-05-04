## description
Add a new package or incorporate an existing standalone package into the workspace; regenerates derived artifacts.

## qa_mode
Mode:

## qa_mode_new
new — create a fresh package

## qa_mode_incorporate
incorporate — pull an existing standalone repo in

## qa_path
Path to existing package repo:

## qa_archetype
Archetype:

## qa_group
Group:

## qa_allowed_deps
Allowed deps (default = archetype rule):

## warn_existing_claude_md
warning: {path}/CLAUDE.md already exists; not overwritten.
to bring it under toolkit management: workspace-docs-regen --repair --pkg {name}

## report_success_new
Package {name} created at {path}. Workspace artifacts regenerated.

## report_success_incorporate
Package {name} incorporated from {original_path}. Workspace artifacts regenerated.

## error_validation
workspace.yml validation failed after add; rolled back.

## error_fs
filesystem error: {details}
