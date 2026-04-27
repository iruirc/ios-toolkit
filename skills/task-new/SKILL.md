---
name: task-new
description: |
  Creates and fills a Task.md scaffold in Tasks/<STATUS>/NNN-slug/ (or nested as .step inside an epic). Formalizes the user's description and fills sections; does not implement anything or research the codebase.
  Use when (en): "create task", "new task", "ft", "create sub-task for N", "step for N", "named step for N"
  Use when (ru): "создай задачу", "новая задача", "ft", "создай под-задачу для N", "step для N", "шаг для N", "создай шаг <name> для N"
---

# Task New

Creates a numbered task folder + Task.md scaffold and fills it with the user's formalized description. Single action (no separate scaffold vs fill stages).

## Language Resolution

Before producing any user-facing string:

1. Read `CLAUDE-swift-toolkit.md` from the project root.
2. Find the `## Language` section.
3. Take the first non-empty line in that section, lowercase and trim it. That is `<lang>`.
4. If `<lang>` is `en` or `ru`, use it. Otherwise default to `en`.
5. Read this skill's `locales/<lang>.md`. Look up keys by H2 header.
6. If a key is missing, fall back to the same key in `locales/en.md`. If still missing, that's a bug — fail loudly with key name.

Caching: resolve `<lang>` once per skill invocation; do not re-read CLAUDE-swift-toolkit.md per string.

## Triggers

Bilingual triggers are listed in the frontmatter `description:`. Both EN and RU phrases activate the skill regardless of the project's active language; the body of the formalized Task.md follows the user's natural language.

Root task triggers cover variants like: "create task", "new task", "ft" + description, or with an explicit status ("create task in TODO", "in BACKLOG", "in RESEARCH").

Step-task triggers cover sub-tasks of an epic: "create sub-task for 137", "step for 137", "shag for epic 137" — including named steps ("create step composition-model for 137").

## Task.md Template

The Task.md template is **NOT inlined in this skill body**. It lives in two physical files inside the plugin's `templates/task-md/` folder:

- `templates/task-md/task-root.md` — for root tasks (no `[STATUS]` field).
- `templates/task-md/task-step.md` — for step tasks (includes `[STATUS]`).

The skill **MUST load the template via the Read tool and write it via the Write tool, byte-for-byte**, with only `{{...}}` placeholder substitution. Do NOT retype the template inline, do NOT paraphrase it, do NOT translate any of its literal characters.

Section headings (`## 1. [Files]` … `## 6. [StackTrace]`), the `**Date:**` label, and bracketed metadata (`[TASK_TYPE]`, `[NEED_TEST]`, `[NEED_REVIEW]`, `[WORKFLOW_MODE]`, `[STATUS]`) are stable machine identifiers parsed by `orchestrator`, `task-status`, `task-move`, and `workflow-*`. Translating any of them silently breaks parsing across the toolkit. The Read+Write copy step guarantees they reach disk unmodified.

Localize ONLY the **prose the user composes inside the sections** (their natural language). The section headings themselves stay exactly as the template provides them.

For reference, the templates contain these placeholders:

| Placeholder | Substituted value |
|---|---|
| `{{DATE}}` | Today's ISO date (`YYYY-MM-DD`). |
| `{{NNN_SLUG}}` | The folder name, e.g. `001-profile-screen`. |
| `{{TASK_TYPE}}` | `FEATURE` \| `BUG` \| `REFACTOR` \| `REVIEW` \| `TEST` \| `EPIC` (decided in step 6 below). |
| `{{NEED_TEST}}` | `true` \| `false` (decided in step 7 below). |
| `{{NEED_REVIEW}}` | `true` \| `false` (decided in step 7 below). |
| `{{STATUS}}` | (`task-step.md` only) `PENDING` \| `IN_PROGRESS` \| `DONE` \| `DEFERRED` \| `BLOCKED` \| `SKIPPED`. |

## Process — root task

1. **Choose the start status** by keywords (default `ACTIVE/`); the same intent in any language maps to the same status:
   - "plan it" / "in TODO" / "later" → `TODO/`
   - "to backlog" / "future idea" → `BACKLOG/`
   - "research epic" / "long research" → `RESEARCH/`
   - "in UNABLE_FIX" (rare; usually set later) → `UNABLE_FIX/`
   - Default → `ACTIVE/`
   - Explicit "create in <STATUS>" → that STATUS folder
2. **Get the next NNN**: scan every folder under `Tasks/**/` matching `^\d{3}-`, find the max, increment by 1.
3. **Make the folder**: `Tasks/<STATUS>/NNN-slug/`.
4. **Decide `{{TASK_TYPE}}`** by intent (matched across languages):
   - "bug" / "crash" / "doesn't work" / "regression" → `BUG`
   - "epic" / "roadmap" / "investigate a large area" → `EPIC`
   - "refactor" / "extract" / "split into modules" → `REFACTOR`
   - "review" / "look at the diff" → `REVIEW`
   - "write tests" / "cover with tests" / "unit tests" → `TEST`
   - Default → `FEATURE`
5. **Decide `{{NEED_TEST}}` / `{{NEED_REVIEW}}`** — default `true` / `true`. Flip to `false` when:
   - Visual/cosmetic ("change color", "move button", "update icon", "update localization string") → `NEED_TEST = false`.
   - `TASK_TYPE` is `REVIEW`, `TEST`, or `EPIC` → both flags become `false` (not applicable).
   - The user explicitly asked for the work without tests or without review.
6. **Locate the template** in the plugin (Read the first existing path):
   a. `~/.claude/plugins/cache/swift-toolkit/swift-toolkit/<version>/templates/task-md/task-root.md`
   b. `~/.claude/plugins/marketplaces/swift-toolkit/templates/task-md/task-root.md`
7. **Read the template, substitute placeholders, write the result** as a single mechanical pass:
   - Read the template via the Read tool. Do NOT retype it. Do NOT paraphrase it. Do NOT translate any character of it.
   - Substitute `{{DATE}}`, `{{NNN_SLUG}}`, `{{TASK_TYPE}}`, `{{NEED_TEST}}`, `{{NEED_REVIEW}}` with the values determined above. Touch ONLY the `{{...}}` tokens; every other character is preserved exactly.
   - Write the result via the Write tool to `<project>/Tasks/<STATUS>/<NNN-slug>/Task.md`.
8. **Fill section bodies** with the user's prose using the Edit tool (one Edit per section). Append text under each H2 heading without changing the heading itself:
   - File paths, screenshot paths → `## 1. [Files]`
   - Context / current behavior / problem → `## 2. [Description]`
   - What to do / questions / reproduction steps → `## 3. [Task]`
   - Logs → `## 5. [Logs]` (only if present in the request)
   - Stack traces / crashlogs → `## 6. [StackTrace]` (only if present)
   The prose follows the user's natural language. The headings themselves are not touched.
9. **`[WORKFLOW_MODE]`** — if the user explicitly asked for a mode different from the project's `## Mode`, append the line `[WORKFLOW_MODE] = [<mode>]` immediately after the `[NEED_REVIEW]` line via Edit. Otherwise leave the template as is (the optional commented-out line stays as documentation).
10. **Verify structural anchors are intact.** Read the just-written `Task.md`. Check that **every** one of the following literal strings is present (case-sensitive, byte-for-byte):
    - `**Date:**`
    - `[TASK_TYPE] = `
    - `[NEED_TEST] = `
    - `[NEED_REVIEW] = `
    - `## 1. [Files]`
    - `## 2. [Description]`
    - `## 3. [Task]`
    - `## 4. [Stack]`
    - `## 5. [Logs]`
    - `## 6. [StackTrace]`

    For step tasks also verify `[STATUS] = `.

    If ANY anchor is missing — that means the model translated / adapted / localized the template against instruction. Fix it via Edit:
    - Find whatever non-canonical variant is present in `Task.md` for the missing anchor.
    - Edit it back to the canonical English literal listed above (e.g. whatever stands in place of `**Date:**` becomes `**Date:**`; whatever stands in place of `## 1. [Files]` becomes `## 1. [Files]`; and so on for every missing anchor).
    - Re-verify after each Edit. Only proceed once all anchors are present in the canonical form.

    This is a defensive net for cases where the byte-for-byte copy step did not survive the model's attempt to "help" by localizing labels. The toolkit cannot run on a `Task.md` whose anchors have been translated, so this verification step is mandatory.
11. **Report** the created folder path to the user. Do not start the workflow.

## Process — step task (sub-task of an epic)

1. **Identify the parent** — by number ("for 137"), slug ("for cross-platform-roadmap"), or current conversation context. Ambiguous → ask the user via `AskUserQuestion` using key `ambiguous_parent_question` with placeholder `{candidates}` (the matching folder names).
2. **Find the parent folder**: `Tasks/**/137-*` (any STATUS).
3. **Choose the step name**:
   - Numeric: find the max existing `N.step` in the parent (including sibling steps in nested epics), increment by 1 → `<N+1>.step`.
   - Named: the user said "step composition-model" → `composition-model.step`.
4. **Decide `{{TASK_TYPE}}`, `{{NEED_TEST}}`, `{{NEED_REVIEW}}`** — same rules as the root-task process steps 4–5.
5. **Decide `{{STATUS}}`** — default `PENDING`. Any other starting status requires an explicit user statement.
6. **Locate the template** in the plugin (Read the first existing path):
   a. `~/.claude/plugins/cache/swift-toolkit/swift-toolkit/<version>/templates/task-md/task-step.md`
   b. `~/.claude/plugins/marketplaces/swift-toolkit/templates/task-md/task-step.md`
7. **Read the template, substitute placeholders, write the result** to `parent/<name>.step/Task.md` — exactly the same Read+substitute+Write pass as for root tasks, plus the `{{STATUS}}` placeholder. Touch ONLY `{{...}}` tokens.
8. **Fill section bodies** via Edit, like for root tasks. Step tasks do NOT have their own STATUS-subfolder — they inherit their parent's folder.
9. **Report** the created path.

## Rules

- Do NOT research the codebase (no file reads, no grep, no glob beyond folder discovery and the template Read).
- Do NOT add information that isn't in the user's request.
- Do NOT propose architecture or a plan — that is the job of later workflow stages.
- Sections Logs / StackTrace / Stack are created only if the user's request contains that data.
- For steps, `[STATUS] = [PENDING]` by default; any other starting status requires an explicit user statement.
- The language of the formalized prose follows the user's natural language (Russian in → Russian out; English in → English out). Structural anchors come from the template file and are NOT modified by this skill — Read+Write copy guarantees they reach disk byte-for-byte.
