---
name: workspace-init
description: |
  Bootstrap a new multi-package SPM workspace.
  Use when (en): "init workspace", "create workspace", "bootstrap multi-package", "/workspace-init"
  Use when (ru): "создай workspace", "новый workspace", "инициализируй workspace", "/workspace-init"
---

# workspace-init

Bootstraps a new multi-package SPM workspace from an interactive Q&A or a supplied `workspace.yml`. Strict trigger — only activates on the phrases listed in the `description` field.

## Language Resolution

Read `## Language` from `<workspace-parent>/<meta-repo>/CLAUDE-swift-toolkit.md` if it exists. Fallback: `CLAUDE-swift-toolkit.md` in the cwd. Fallback: `en`. Use the resolved language for all user-facing strings via `locales/<lang>.md`.

## Modes

- **Interactive** (no flags): full Q&A, render `workspace.yml`, ask for confirmation, then execute.
- **Batch** (`--from <path/to/workspace.yml>`): no Q&A, no confirmation. Validates and executes.
- **Resume** (`--resume`): re-uses persisted `workspace.yml` + state file; skips completed steps.

## Pre-flight

Always print the pre-flight summary first (using `preflight_*` locale keys):

1. Check `command -v yq` → emit `preflight_required_yq_ok` (with `yq --version`) or `preflight_required_yq_missing`. If missing, exit 3.
2. Check `command -v gh` → emit `preflight_optional_gh_ok` or `preflight_optional_gh_missing` (informational only).
3. Check `command -v xcodegen` → same pattern.

## Interactive flow

1. Ask `qa_workspace_name` (text). Validate against `[A-Za-z][A-Za-z0-9-]*` regex; reprompt on mismatch.
2. Ask `qa_project_block` (Y/N). If Y, ask `name`, `apps.ios?` (text optional), `apps.macos?` (text optional).
3. Ask `qa_groups` (Y/N). If Y, repeat-loop: ask `name` + `dir`. Empty `name` ends loop.
4. Ask `qa_remotes` (text, comma-separated). Split + trim.
5. Repeat-loop for packages: ask `qa_pkg_name`, `qa_pkg_archetype` (multi-choice), `group` (multi-choice from declared groups, if any), one git URL per declared remote, `qa_pkg_version`, `qa_pkg_deps` (multi-select from declared packages so far), external deps (Y/N → loop), `allowed_deps` (default = archetype rule, override Y/N), `qa_pkg_example_app`. Empty `qa_pkg_name` ends loop. Require ≥ 1 package.
6. Ask defaults overrides (Y/N) for `default_branch`, `push_remotes`, `release_strategy`.
7. Ask bootstrap (`qa_bootstrap_use_gh`, `qa_bootstrap_push_after_init`, `qa_bootstrap_commit_after_init`). Optional: `initial_commit_message` (default "Initial commit"), `git_author` (text, optional).
8. Render `workspace.yml` to chat (use yq from collected values). Print `confirm_summary_header` + summary table (meta-repo dir, package count, remote count, will-commit Y/N, will-push Y/N).
9. Ask `confirm_prompt` (Y/N). On N, emit `abort_no_changes`, exit 0. On Y, write `workspace.yml` to `<workspace-parent>/<workspace-name>-meta/workspace.yml` and continue to **shared execution**.

## Batch flow

1. Source `workspace-yml-parser.zsh`, `workspace-graph.zsh`. Run `wsyml::load`, `wsyml::validate`, `wsgraph::check_acyclic`. On any failure, emit `error_validation`, exit 2.
2. Continue to **shared execution**.

## Shared execution

Maintain `<workspace-parent>/.workspace-init.state` (newline-delimited list of completed step IDs). For each step below: skip if step ID is in state file OR if the idempotency check matches; otherwise execute and append step ID to state file on success. On any failure, emit `error_step_failed`, exit 1 (operational), 2 (schema), 3 (missing dep), 4 (FS).

| Step | Action | Idempotency check |
|------|--------|-------------------|
| s01_meta_dir | mkdir `<workspace-parent>/<workspace-name>-meta/` | dir exists |
| s02_meta_files | render meta-repo templates from `templates/workspace/meta-repo/`, recursively (preserves subdir layout). Substitutes `{{WORKSPACE_NAME}}`. Excludes `xcworkspace-contents.xml.tmpl` and `code-workspace.json.tmpl` — those are handled by s07 / s08 (NOT rendered by s02). | per-file `[[ -f ]]` |
| s03_meta_git | `git init -b <default-branch>` in meta-repo | `[[ -d .git ]]` |
| s04_meta_yml | copy `workspace.yml` into meta-repo | `[[ -f workspace.yml ]]` |
| s05_groups | mkdir each `package_groups[].dir` (or `packages/` if no groups) under workspace-parent | dir exists |
| s06_pkg_<name> | per-package: mkdir, render `templates/workspace/package/`, recursively. Rename directory components named `PACKAGE_NAME` → `<name>`, `PACKAGE_NAMETests` → `<name>Tests`. `git init`. | dir + `.git` exist |
| s07_xcworkspace | copy `templates/workspace/meta-repo/xcworkspace-contents.xml.tmpl` to `<workspace-name>.xcworkspace/contents.xcworkspacedata` and fill the `WORKSPACE_PKG_REFS` marker with one `<FileRef location="group:../<group_dir_or_packages>/<name>">` per package | always overwrite (derived) |
| s08_codeworkspace | copy `templates/workspace/meta-repo/code-workspace.json.tmpl` to `<workspace-name>.code-workspace`, then append one `{ "name": "<name>", "path": "../<group_dir_or_packages>/<name>" }` to `folders[]` per package | always overwrite |
| s09_tasks | create `<meta-repo>/Tasks` per `tasks.symlink_mode` (regular dir, gitignored symlink, or committed symlink) | path exists |
| s10_meta_initial_commit | iff `bootstrap.commit_after_init`: `git -c user.name=... -c user.email=... commit` | `git rev-list HEAD` non-empty |
| s11_pkg_initial_commit_<name> | same per package | as above |
| s12_gh_repos | iff `use_gh`: `gh repo create` for meta + each package, register `remotes[0]` URL | `git remote get-url <remotes[0]>` succeeds |
| s13_push | iff `push_after_init`: `git push -u remotes[0] <branch>` per repo | always idempotent |
| s14_local_skills | iff `generate_local_skills`: render `.claude/skills/v-*/SKILL.md` shims | per-file `[[ -f ]]` |

After s14, delete `.workspace-init.state`. Emit `report_success`.

## --resume

Read `.workspace-init.state`. If absent or malformed, emit error and exit 1. Otherwise, run the shared execution table — skipping completed step IDs and verifying idempotency for the rest.

## Templates path

`<toolkit-root>/templates/workspace/` — discoverable via plugin metadata. Skill body invokes zsh subshell to copy + interpolate placeholders (`{{WORKSPACE_NAME}}`, `{{PACKAGE_NAME}}`, etc.) using sed.

## Template substitution rules

- `*.tmpl` files are rendered to their target location with the `.tmpl` suffix stripped.
- The package template tree (`templates/workspace/package/`) is walked recursively. Directory components literally named `PACKAGE_NAME` are renamed to `<name>`, and `PACKAGE_NAMETests` to `<name>Tests` (the longer form must be substituted first).
- Inside each rendered file, `{{...}}` placeholders are substituted via `sed`.
- Known placeholders:
  - `{{WORKSPACE_NAME}}` — workspace name (`workspace.name` from `workspace.yml`).
  - `{{META_REPO_DIR}}` — `<workspace-name>-meta`.
  - `{{PACKAGE_NAME}}` — package name (per-package).
  - `{{ARCHETYPE}}` — package archetype (`feature` / `library` / `api-contract` / `engine-sdk`).
  - `{{GROUP}}` — package group name, or `—` if ungrouped.
  - `{{VERSION}}` — package version (semver-like string).
  - `{{ALLOWED_DEPS_CSV}}` — comma-separated list of archetype-allowed deps, or `—`.
  - `{{EXTERNAL_DEPS_CSV}}` — comma-separated list of external SPM deps, or `—`.
  - `{{ARCHETYPE_BOUNDARY_TEXT}}` — narrative paragraph from `wsarch::boundary_text` (archetype boundary contract).
