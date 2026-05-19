---
name: swift-setup
description: |
  Configures swift-toolkit in an existing Swift project: creates CLAUDE-swift-toolkit.md from a template, inserts an @./ import line into CLAUDE.md, asks for the stack via structured questions, and creates the Tasks/ structure. Detects and migrates projects on the legacy single-file CLAUDE.md format.
  Use when (en): "set up swift-toolkit", "configure swift-toolkit", "install toolkit in project", "add swift-toolkit to project", "init toolkit here", "/swift-setup"
  Use when (ru): "настрой swift-toolkit", "подключи swift-toolkit", "установи toolkit в проект", "добавь swift-toolkit к проекту", "инициализируй toolkit здесь", "/swift-setup"
  For generating a NEW Swift project from scratch use `@swift-toolkit:swift-init`.
---

# Swift Setup

Bootstraps swift-toolkit in an **already existing** Swift project. Two-file layout:

- `CLAUDE-swift-toolkit.md` — toolkit-owned configuration (Language, Persona, Stack, Mode, Modules, Paths, Orchestration). Created and updated by this skill.
- `CLAUDE.md` — user-owned project instructions. Touched once to insert `@./CLAUDE-swift-toolkit.md` line; otherwise unchanged.

The skill does NOT create an Xcode project, does NOT modify Swift code, and does NOT start any workflow. It is a one-time setup of toolkit infrastructure inside the project.

To generate a project from scratch, use the `@swift-toolkit:swift-init` agent (via the `/swift-init` slash command).

## Language Resolution

Special case for `swift-setup`: `CLAUDE-swift-toolkit.md` does not yet exist on first install (we are creating it). The skill therefore asks for the language as the very first question (q0) using keys `auq_lang_label` and `auq_lang_options`. Until that answer arrives, the q0 prompt is shown bilingually (English label / Russian label). From q0 onward, `<lang>` is the chosen value (`en` or `ru`), and every subsequent AUQ / error / report uses `locales/<lang>.md`. If q0 is skipped (text fallback, harness limitation), default to `en`.

The full resolution procedure used elsewhere — read `CLAUDE-swift-toolkit.md → ## Language` — applies after `swift-setup` has finished.

## Triggers

Bilingual triggers are listed in the frontmatter `description:`. Both EN and RU phrases activate the skill.

## Agent Tooling

Use `conventions/agent-tooling.md` for host-neutral interaction and file-access
terms.

In this skill, `AUQ` means the structured question mechanism. If the active host
cannot provide a structured question tool, ask numbered options in a regular
message and parse the reply. Locale keys with the `auq_` prefix remain the
canonical prompt/option keys.

## State Detection

The skill's behavior is determined by the project state, computed from three checks:

1. Does `CLAUDE.md` exist in the project root?
2. Does `CLAUDE-swift-toolkit.md` exist in the project root?
3. Does `CLAUDE.md` contain any of `## Language`, `## Stack`, or `## Mode` headings? (Indicates legacy single-file format.)

| State | `CLAUDE.md` | `CLAUDE-swift-toolkit.md` | Toolkit sections in `CLAUDE.md`? | Action branch |
|---|---|---|---|---|
| **A · new_install** | absent | absent | — | Ask q1–q7. Create both files. |
| **B · existing_md** | present | absent | no | Ask q1–q7. Backup CLAUDE.md. Insert `@import` line. Create `CLAUDE-swift-toolkit.md`. |
| **C · already_configured** | present | present | no | AUQ `auq_reconfigure_toolkit` on `CLAUDE-swift-toolkit.md` only. Self-heal `CLAUDE.md` if `@import` is missing. |
| **D · old_format** | present | absent | yes | AUQ `auq_migrate_old_format`. Run migration algorithm (see below). |

### Edge sub-states

- `CLAUDE.md` has `@./CLAUDE-swift-toolkit.md` import line, but `CLAUDE-swift-toolkit.md` is absent: route to **state A** (ask q1–q7, create toolkit file). Do not modify `CLAUDE.md`.
- `CLAUDE-swift-toolkit.md` exists but `CLAUDE.md` is absent: create stub `CLAUDE.md` from `templates/claude-md-stub/<lang>.md`. Toolkit file untouched.

## Algorithm

```
0. Ask the language (q0):
   AskUserQuestion using key `auq_lang_label` with options from `auq_lang_options` (`en` / `ru`).
   Store answer as <lang>; subsequent prompts/reports use locales/<lang>.md.
   Q0 is shown bilingually. If skipped, default <lang> = `en`.

1. Detect Swift project:
   Check for .xcodeproj / .xcworkspace / Package.swift in the root.
   ↓ if none → render `error_not_swift_project`. Stop.

2. Compute state (see State Detection table).

3. Locate templates:
   a. `templates/claude-toolkit-md/en.md` — toolkit file template (English-only; the file body is always EN regardless of `<lang>`).
   b. `templates/claude-md-stub/<lang>.md` — minimal CLAUDE.md stub (localized; body comment is in the user's language).
   Lookup paths (try in order):
     - `<toolkit-root>/templates/...` (see `conventions/agent-tooling.md`)
     - host-installed plugin/cache template paths
     - Claude Code compatibility paths:
       `~/.claude/plugins/cache/swift-toolkit/swift-toolkit/<latest-version>/templates/...`
       or `~/.claude/plugins/marketplaces/swift-toolkit/templates/...`
   ↓ if neither path is available → render `error_template_not_found`. Stop.

4. Branch by state:

   STATE A (new_install):
     a. Ask q1–q7 (stack questions; details below).
     b. Render `templates/claude-toolkit-md/en.md` with placeholder values from q1–q7 plus `<lang>` from q0. Write to <project>/CLAUDE-swift-toolkit.md.
     c. **If CLAUDE.md does NOT exist**: Render `templates/claude-md-stub/<lang>.md` with `{project_name}` derived from the project directory name. Write to <project>/CLAUDE.md.
     **If CLAUDE.md DOES exist** (the broken-state edge sub-state — CLAUDE.md already has the @import line but toolkit file was missing): SKIP this sub-step. Do not overwrite the user's CLAUDE.md.

   STATE B (existing_md):
     a. Ask q1–q7.
     b. Render toolkit template with q1–q7 values. Write to <project>/CLAUDE-swift-toolkit.md.
     c. Backup CLAUDE.md → CLAUDE.md.bak (collision suffix: .bak.YYYYMMDD-HHMMSS).
     d. Insert `@./CLAUDE-swift-toolkit.md` as a new line:
        - if first non-empty line is an H1 (`# ...`), insert immediately after H1 (with one blank line before and after).
        - otherwise, insert at the very top of the file (with one blank line after).
        - if the line already exists anywhere in the file → skip insertion (idempotent).

   STATE C (already_configured):
     a. AUQ using key `auq_reconfigure_toolkit` with options `auq_reconfigure_toolkit_options` (Overwrite / Backup-and-overwrite / Cancel).
        - Cancel → stop, no disk changes.
        - Backup-and-overwrite → rename CLAUDE-swift-toolkit.md → CLAUDE-swift-toolkit.md.bak (timestamp on collision). Continue.
        - Overwrite → continue.
     b. Ask q1–q7.
     c. Render toolkit template with q1–q7. Write to CLAUDE-swift-toolkit.md (overwrite).
     d. Self-heal CLAUDE.md: if `@./CLAUDE-swift-toolkit.md` line is missing, run insertion logic from State B step (d), with backup.

   STATE D (old_format):
     a. Run migration parser on CLAUDE.md. Compute moved/kept/defaulted/warning section sets.
     b. Show summary preview (sections to move, kept, defaulted, warnings, backup path).
     c. AUQ `auq_migrate_old_format` with options `auq_migrate_old_format_options` (Migrate-and-backup / Cancel).
        - Cancel → stop, no disk changes.
        - Migrate-and-backup → continue.
     d. Backup CLAUDE.md → CLAUDE.md.bak (timestamp on collision).
     e. Build new CLAUDE-swift-toolkit.md (toolkit_sections in canonical order; missing sections filled from template defaults).
     f. Build new CLAUDE.md (preamble [stub or preserved] + @import line + user_sections in original order).
     g. Atomic write: write to *.new temp files, then rename.

5. Optional Tasks/ structure (orthogonal to state):
   If Tasks/ does not exist:
     AUQ using key `auq_create_tasks_structure`.
     ↓ Yes → mkdir -p Tasks/{TODO,ACTIVE,DONE,BACKLOG,RESEARCH,CHECK,UNABLE_FIX}; create .gitkeep in each.
     ↓ No → skip.
   If Tasks/ exists → tasks_status = `tasks_status_already_existed`.

6. Render report:
   - States A/B/C → key `report_success_template` with placeholders {q1..q7}, {lang}, {tasks_status}.
   - State D → key `report_migration_success` with placeholders {moved_sections}, {kept_sections}, {filled_default_sections}, {warnings}, {backup_path}.
```

## Migration Algorithm (state D)

### Parser

Splits CLAUDE.md into sequence of `[(heading, body), ...]` plus a `preamble` string.

Rules:
- Section boundary = a line that starts with literal `## ` (h2). H1, h3+, indented `##` are NOT boundaries.
- A `## ` line inside a fenced code block (` ``` `) is NOT a boundary. The parser tracks fenced state.
- The `preamble` is everything before the first valid `## ` line (may be empty).
- Section body includes all lines until the next `## ` boundary (exclusive) or EOF.

### Section classification

Canonical toolkit headings (case-insensitive **exact** match, not prefix):

```
Language, Persona, Stack, Mode, Modules, Paths, Orchestration
```

- `toolkit_sections` = sections whose heading matches the canonical list.
- `user_sections` = everything else, in original order.
- `unknown_warnings` = headings that look toolkit-like but don't match exactly (e.g., `Stacks`, `Mode (custom)`). Kept in `user_sections`. Surfaced in the report.

Exact match only — no prefix-matching. `## Stack Cookbook` is NOT classified as `Stack`.

### Preamble handling

- **Toolkit preamble detected** if the H1 (first non-empty `# ...` line) matches any of these canonical strings (exact match, case-sensitive):
  - `# CLAUDE.md — Swift Toolkit` (legacy template — both EN and RU legacy templates used the same H1 string; only the body was localized)
  - `# CLAUDE-swift-toolkit.md — Swift Toolkit Configuration` (current — toolkit file is now EN-only, single H1 for all languages)
  → Discard preamble, replace with rendered `templates/claude-md-stub/<lang>.md`.
- **Otherwise**: preserve preamble as-is. Insert `@./CLAUDE-swift-toolkit.md` after the H1 (or at very top if no H1) before the first user section.

### Output assembly

`CLAUDE-swift-toolkit.md`:
```
<H1 + intro from templates/claude-toolkit-md/en.md>

<toolkit_sections in canonical order>
```

For canonical sections missing from the source: fill from the template default (e.g., `## Mode\n\nmanual`). Track in `filled_default_sections` for the report.

`CLAUDE.md`:
```
<preamble: stub or preserved>

@./CLAUDE-swift-toolkit.md

<user_sections in original order>
```

Empty `user_sections` → file ends at the `@import` line (with trailing newline).

### Safeguards

1. **Backup always**: CLAUDE.md → CLAUDE.md.bak (or .bak.YYYYMMDD-HHMMSS on collision) **before** any disk write.
2. **Atomic writes**: write to `CLAUDE.md.new` and `CLAUDE-swift-toolkit.md.new`, then atomic rename.
3. **Idempotency**: if both the toolkit file exists AND CLAUDE.md has the @import line, state-detection routes to C, not D.
4. **Rollback hint** in report: `mv {backup_path} CLAUDE.md && rm CLAUDE-swift-toolkit.md`.
5. **Line endings**: normalize to LF on write.

## Stack Questions (q1–q7)

Same as before. Labels from locale keys (`auq_q1_ui_label` … `auq_q7_mode_label`):

- q1 — UI: SwiftUI / UIKit / AppKit
- q2 — Async: async/await / Combine / RxSwift
- q3 — DI: Swinject / Factory / manual
- q4 — Architecture: MVVM+Coordinator / VIPER / Clean Architecture / MVC
  - if user says "I don't know" / "advise me" → run `architecture-choice`, bring its result back as q4 + one-line justification.
- q5 — Platform: iOS 17+ / iOS 16+ / macOS 14+ / macOS 13+ / iOS+macOS
- q6 — Tests: XCTest / Quick+Nimble
- q7 — Mode: manual (default) / auto

## Placeholder Replacements

In `templates/claude-toolkit-md/en.md` (the toolkit file is EN-only):

| Placeholder | Source | Substituted with |
|---|---|---|
| `<SwiftUI \| UIKit \| AppKit>` | q1 | chosen UI framework |
| `<async/await \| Combine \| RxSwift>` | q2 | chosen async approach |
| `<Swinject \| Factory \| manual>` | q3 | chosen DI |
| `<MVVM+Coordinator \| VIPER \| Clean Architecture \| MVC>` | q4 | chosen architecture |
| `<iOS 16+ \| macOS 13+ \| iOS+macOS>` | q5 | chosen platform |
| `<XCTest \| Quick+Nimble>` | q6 | chosen test framework |
| `manual` in `## Mode` | q7 | `manual` or `auto` |
| `en` value in `## Language` | q0 | `en` or `ru` |
| `<Communication Language>` in `## Persona` | q0 | `English` or `Russian` (the human-readable language name; drives Claude's communication language with the user) |

In `templates/claude-md-stub/<lang>.md`:

| Placeholder | Source |
|---|---|
| `{project_name}` | basename of project directory |

## Output report

States A / B / C use `report_success_template`. State D uses `report_migration_success`. See `locales/<lang>.md` for exact wording.

## Edge cases

- **Not a Swift project** → `error_not_swift_project`. Stop. No disk changes.
- **Plugin templates not found** → `error_template_not_found`. Stop.
- **AUQ unavailable** → text fallback with numbered options.
- **User cancels** (Cancel on AUQ in state C or D) → exit, no disk changes.
- **Tasks/ already exists** → no overwrite; report `tasks_status_already_existed`.

## What this skill does NOT do

- Does NOT create an Xcode project, `Package.swift`, sources, `.swiftlint.yml`, or `README.md` — that is `@swift-toolkit:swift-init`.
- Does NOT modify Swift code or existing project configs (Info.plist, Build Settings).
- Does NOT start workflows or call `orchestrator`.
- Does NOT init git or make commits.
- Does NOT install dependencies (SPM, CocoaPods, Carthage).
- Does NOT create the first task — use `/task-new`.
- Does NOT modify user content in `CLAUDE.md` beyond inserting/preserving the `@import` line and (in state D) splitting toolkit sections out.
