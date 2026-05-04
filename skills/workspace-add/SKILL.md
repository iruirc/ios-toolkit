---
name: workspace-add
description: |
  Add a new package or incorporate an existing standalone package into the workspace.
  Use when (en): "add package", "incorporate package", "/workspace-add", "ws add"
  Use when (ru): "добавь пакет", "включи пакет", "/workspace-add", "пакет в workspace"
---

# workspace-add

Adds a package to an existing workspace. Two sub-modes:

- `--new <name>`: create a fresh package from templates.
- `--incorporate <path>`: register an existing standalone package repo.

## Language Resolution

Read `## Language` from meta-repo's `CLAUDE-swift-toolkit.md`. Fallback: `en`. All user-facing strings via `locales/<lang>.md`.

## Pre-flight

Verify caller cwd is inside a workspace meta-repo (look for `workspace.yml` in cwd or any ancestor up to workspace-parent). If absent, error and exit 1.

## --new <name>

1. Q&A: archetype, group (if `package_groups` non-empty), git URL per declared remote, version (default 0.1.0), deps (multi-select from existing packages), external_deps (Y/N → loop), allowed_deps (default = archetype rule), example_app + example_platform.
2. Backup current `workspace.yml` to `.workspace-add.backup.yml`.
3. Update `workspace.yml` (insert package entry under `packages:`).
4. `wsyml::validate` + `wsgraph::check_acyclic`. On failure: restore from backup, emit `error_validation`, exit 2.
5. Resolve target dir: `<workspace-parent>/<group-dir>/<name>/` (or `packages/<name>/` if no groups).
6. mkdir + render `templates/workspace/package/` with placeholder substitution.
7. `git init -b <default-branch>`. If `bootstrap.commit_after_init: true` (read from `workspace.yml`): `git add -A && git commit -m <msg>`.
8. Optional: if `--push` flag AND `bootstrap.use_gh: true`: `gh repo create` + `git push -u remotes[0]`.
9. Invoke `workspace-docs-regen` (subshell) to refresh `.xcworkspace`, `.code-workspace`, meta-repo README/ARCH marker sections.
10. Emit `report_success_new`.

## --incorporate <path>

1. Read target's `Package.swift` to extract package name. If `--name <override>` supplied, use that; else use parsed name.
2. Read target's `git remote -v` to detect existing remotes.
3. Q&A: archetype, group (if applicable), allowed_deps, additional remotes (if existing remote count < declared in workspace).
4. Backup `workspace.yml`. Update with new package entry.
5. `wsyml::validate` + `wsgraph::check_acyclic`. On failure: restore + exit 2.
6. Resolve target dir. If `--symlink` flag: create symlink. Else (default): `mv <original-path> <target-dir>`.
7. **Soft mutate** target package files:
   - If `<target-dir>/CLAUDE.md` does NOT exist → render template (with archetype boundary text), `git add` it (no commit).
   - If exists → emit `warn_existing_claude_md`.
8. Invoke `workspace-docs-regen` (subshell) for derived artifacts.
9. Emit `report_success_incorporate`.

## Failure recovery

`workspace-add` is single-shot (no state file). On any error: restore `workspace.yml` from `.workspace-add.backup.yml`. FS changes (created dirs) are kept; print FS-touch list. User can `rm -rf` and retry.
