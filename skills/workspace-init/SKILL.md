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
3. Check `command -v xcodegen` → same pattern (informational only at pre-flight time).

## Interactive flow

1. Ask `qa_workspace_name` (text). Validate against `[A-Za-z][A-Za-z0-9-]*` regex; reprompt on mismatch.
2. Ask `qa_project_block` (Y/N). If Y:
   1. Ask `qa_project_name` (text). Validate against `[A-Za-z][A-Za-z0-9-]*`; reprompt on mismatch.
   2. Repeat-loop:
      - Ask `qa_app_platform` (multi-choice from {`ios`, `macos`, `end`}).
      - If `end` → exit loop. After loop, validate ≥ 1 app declared.
      - Otherwise ask `qa_app_repo_name` (text). Default value = `{project-name}-{platform}`. Validate against `[A-Za-z][A-Za-z0-9-]*`.
   3. **Do NOT ask stack Q&A here.** swift-init Q&A (UI framework, DI, architecture, async, min-platform) runs per app during execution phase s06b. Interactive `/workspace-init` MUST delegate the full swift-init Q&A for each declared app — do NOT pass `--no-prompt` in interactive mode. Only batch mode (`--from <yml>`) applies stack defaults silently via `swift-init --no-prompt`.
3. Ask `qa_groups` (Y/N). If Y, repeat-loop: ask `name` + `dir`. Empty `name` ends loop.
4. Ask `qa_remotes` (text, comma-separated). Split + trim.
5. Packages — **iterative loop, ONE package at a time. Do NOT ask "how many packages?" upfront. Do NOT batch multiple package questions into a single prompt.** Each iteration:
   1. Ask `qa_pkg_name` as a free-text prompt that explicitly tells the user that an empty input ends the loop. The locale string already includes this hint — render it verbatim.
   2. If the input is empty:
      - If at least 1 package has been collected so far → exit the loop and continue to step 6.
      - If 0 packages so far → reprompt (Require ≥ 1 package, per P-rule).
   3. Otherwise, for THIS package only, ask in sequence: `qa_pkg_archetype` (multi-choice), `group` (multi-choice from declared groups, if any), one git URL per declared remote, `qa_pkg_version`, `qa_pkg_deps` (multi-select from packages declared in PRIOR iterations), external deps (Y/N → nested loop), `allowed_deps` (default = archetype rule, override Y/N), `qa_pkg_example_app`. Record the package.
   4. **Go back to step 5.i** (ask `qa_pkg_name` again, with the same empty-input-ends hint). The loop has no upper bound; the user keeps adding packages until they enter empty input.

   **Anti-pattern to avoid:** presenting "How many packages?" or "Add 1 / 2 / 3 packages?" as a single multi-choice question and then collecting that many in a fixed batch. Always loop with re-prompts.
6. Ask defaults overrides (Y/N) for `default_branch`, `push_remotes`, `release_strategy`.
7. Ask `qa_tasks_enabled` (Y/N, default Y). If Y, ask `qa_tasks_path` (text, default `./Tasks`). Validate path: must NOT be absolute (no leading `/`), must NOT contain `..` segments (avoid escaping workspace-parent). Reprompt on validation failure. Record into `workspace.tasks.enabled` / `workspace.tasks.path`. If N, set `tasks.enabled: false` and skip the path prompt (s09 will skip at execution).
8. Ask bootstrap (`qa_bootstrap_use_gh`, `qa_bootstrap_push_after_init`, `qa_bootstrap_commit_after_init`). Optional: `initial_commit_message` (default "Initial commit"), `git_author` (text, optional).
9. Render `workspace.yml` to chat (use yq from collected values). Print `confirm_summary_header` + summary table (meta-repo dir, package count, remote count, tasks-repo path or `disabled`, will-commit Y/N, will-push Y/N).

   When `project:` block is present, the summary additionally shows:
   - `{N} project repos: {ios=<repo>, macos=<repo>}`
   - `Will trigger /swift-init for: {apps_csv}` (interactive mode only — batch runs swift-init silently with `--no-prompt`)
10. Ask `confirm_prompt` (Y/N). On N, emit `abort_no_changes`, exit 0. On Y, write `workspace.yml` to `<workspace-parent>/<workspace-name>-meta/workspace.yml` and continue to **shared execution**.

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
| s06b_project_<app> | **Pre-condition:** `command -v xcodegen` — emit `error_xcodegen_missing` and exit 3 if missing. Then invoke `swift-init` per mode: **Interactive mode** — invoke `swift-init --platform=<key>` WITHOUT `--no-prompt` AND WITHOUT `--with-tasks`; the user goes through the full swift-init Q&A (UI framework, DI, architecture, async, min-platform). Stack overlay from `apps.<key>.stack` (if user pre-filled in `workspace.yml`) is NOT applied in interactive mode — swift-init owns those decisions. **Batch mode** — invoke `swift-init --no-prompt --platform=<key> [stack-flags]` with values from `apps.<key>.stack` or per-platform defaults (overlay); `--with-tasks` is NEVER passed by workspace-init. Output in `<workspace-parent>/<repo-name>/`. swift-init touches marker `.swift-init.done` in `<repo>/` on successful completion. main-target-name for downstream steps = `apps.<platform>.repo`. Per-project `Tasks/` MUST NOT be created — the shared `<workspace-parent>/Tasks/` repo is provisioned in s09 instead. | `[[ -f <repo>/project.yml ]] && [[ -f <repo>/.swift-init.done ]]` |
| s06c_project_inject_<app> | Source `wsproj::*` library. Read `wsyml::packages`. Run `wsproj::inject_deps <repo> <main-target-name>`. Run `xcodegen generate` in `<repo>/` (second xcodegen run regenerates `.xcodeproj` reflecting injected deps). | Always rerun (declarative; state file authoritative for skip — see "State file precedence" below) |
| s06d_project_workspace_meta_<app> | Run `wsproj::append_workspace_meta <repo>` to add `## Workspace meta` section to `<repo>/CLAUDE-swift-toolkit.md`. | `grep -q '^## Workspace meta' <repo>/CLAUDE-swift-toolkit.md` |
| s06e_project_git_<app> | `git init -b <default-branch>` in `<repo>`. | `[[ -d <repo>/.git ]]` |
| s07_xcworkspace | copy `templates/workspace/meta-repo/xcworkspace-contents.xml.tmpl` to `<workspace-name>.xcworkspace/contents.xcworkspacedata`, then fill **both** markers: (1) `WORKSPACE_PROJECT_REFS` — when `project:` block is present, write one `<FileRef location="group:../<app-repo>/<project.name>.xcodeproj"></FileRef>` per `project.apps.<key>.repo`. The `.xcodeproj` filename uses `project.name` (NOT the repo name), because `swift-init` names the generated Xcode project after the main target = `project.name`. Leave the marker empty when `project:` is absent. (2) `WORKSPACE_PKG_REFS` — one `<FileRef location="group:../<group_dir_or_packages>/<name>"></FileRef>` per package | always overwrite (derived) |
| s08_codeworkspace | copy `templates/workspace/meta-repo/code-workspace.json.tmpl` to `<workspace-name>.code-workspace`, then append to `folders[]`: (1) when `project:` is present, one `{ "name": "<app-repo>", "path": "../<app-repo>" }` per `project.apps.<key>.repo`; (2) one `{ "name": "<name>", "path": "../<group_dir_or_packages>/<name>" }` per package; (3) when `workspace.tasks.enabled` is true, one `{ "name": "Tasks", "path": "../<tasks-path-without-leading-./>" }` | always overwrite |
| s09_tasks | iff `workspace.tasks.enabled` (default `true`): mkdir `<workspace-parent>/<workspace.tasks.path>` (default `Tasks`) with subfolders `TODO/`, `ACTIVE/`, `DONE/`, render `templates/workspace/tasks-repo/` files (substitutes `{{WORKSPACE_NAME}}`), and `git init -b <default-branch>` inside it. Tasks/ is a **separate git repo** at workspace-parent level, sibling to packages and project repos — NOT inside the meta-repo. | `[[ -d <workspace-parent>/<tasks-path>/.git ]]` |
| s10_meta_initial_commit | iff `bootstrap.commit_after_init`: `git -c user.name=... -c user.email=... commit` | `git rev-list HEAD` non-empty |
| s10b_tasks_initial_commit | iff `workspace.tasks.enabled` AND `bootstrap.commit_after_init`: `git -C <workspace-parent>/<tasks-path> add -A && git -C <workspace-parent>/<tasks-path> commit -m <msg>` | `git -C <workspace-parent>/<tasks-path> rev-list HEAD` non-empty |
| s11_pkg_initial_commit_<name> | same per package | as above |
| s11b_project_initial_commit_<app> | Iff `bootstrap.commit_after_init`: `git -C <repo> add -A && git -C <repo> commit -m <msg>`. | `git -C <repo> rev-list HEAD` non-empty |
| s12_gh_repos | iff `use_gh`: `gh repo create` for meta + each package + tasks-repo (when `tasks.enabled`), register `remotes[0]` URL | `git remote get-url <remotes[0]>` succeeds |
| s12b_gh_project_<app> | Iff `bootstrap.use_gh`: `gh repo create` for `<repo>`, register `remotes[0]` URL. | `git -C <repo> remote get-url <remotes[0]>` succeeds |
| s13_push | iff `push_after_init`: `git push -u remotes[0] <branch>` per repo (meta + packages + tasks-repo) | always idempotent |
| s13b_push_project_<app> | Iff `bootstrap.push_after_init`: `git -C <repo> push -u remotes[0] <branch>`. | always idempotent |
| s14_local_skills | iff `generate_local_skills`: render `.claude/skills/v-*/SKILL.md` shims | per-file `[[ -f ]]` |

After s14, delete `.workspace-init.state`. Emit `report_success`.

### Per-app sequencing

When multiple apps are declared in `project.apps` (e.g. ios + macos), execute **per-app full chain** order: `s06b_ios → s06c_ios → s06d_ios → s06e_ios → s06b_macos → s06c_macos → ...`. NOT step-major (`s06b_ios → s06b_macos → s06c_ios → ...`). Reason: failure mid-chain leaves earlier apps in fully-completed state, simplifying recovery boundaries.

### State file precedence

The `.workspace-init.state` file is the authoritative record of completed steps. Idempotency checks in the table act as fallback when the state file is missing (e.g. manually deleted, or workspace migrated from Foundation Cluster 1 layout where state file did not yet exist).

Skip semantics:
- Step ID present in `.workspace-init.state` → skip.
- Step ID absent + idempotency check matches → mark as completed (write to state file) + skip.
- Otherwise → execute, then on success write step ID to state file.

State file is deleted only after `s14_local_skills` completes successfully (existing Foundation behavior).

## --resume

Read `.workspace-init.state`. If absent or malformed, emit error and exit 1. Otherwise, run the shared execution table — skipping completed step IDs and verifying idempotency for the rest.

For project-block workflows: interruption of swift-init Q&A (Ctrl-C during s06b interactive) leaves state file unmodified; `--resume` re-enters Q&A for the interrupted app. State file marks s06b done only after swift-init exits 0 AND `.swift-init.done` marker file exists in the project-repo.

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
