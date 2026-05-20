---
name: workflow-research
description: |
  RESEARCH profile workflow: Research → [Review] → Done. Pure-investigation profile for audits, feasibility studies, comparative analyses, and domain investigations. NO code changes. Activated by swift-toolkit:orchestrator; not invoked by the user directly.
  Use when (en): orchestrator dispatches a task with [TASK_TYPE]=RESEARCH
  Use when (ru): оркестратор диспетчеризует задачу с [TASK_TYPE]=RESEARCH
stack_axes_envelope: { may: [], never: all }
---

# Workflow Research

The profile workflow for tasks with `[TASK_TYPE] = RESEARCH`. Pure investigation: produces `Research.md` (the final artifact), optionally goes through `Review`, then `Done`. NO implementation, NO tests, NO Plan stage — the research IS the deliverable. The skill receives an already-resolved contract from the orchestrator and does not try to re-resolve any parameter on its own.

**When to use vs EPIC pure_research:** RESEARCH is for tasks known up-front to be investigation-only. EPIC `pure_research` is a *downgrade path*: a task starts as an EPIC, the Research stage discovers that no decomposition / implementation is needed, and the workflow finishes at the Plan stage. See `conventions/research-vs-epic.md`.

## Language Resolution

Before producing any user-facing string:

1. Read `CLAUDE-swift-toolkit.md` from the project root.
2. Find the `## Language` section.
3. Take the first non-empty line in that section, lowercase and trim it. That is `<lang>`.
4. If `<lang>` is `en` or `ru`, use it. Otherwise default to `en`.
5. Read this skill's `locales/<lang>.md`. Look up keys by H2 header.
6. If a key is missing, fall back to the same key in `locales/en.md`. If still missing, that's a bug — fail loudly with key name.

Caching: resolve `<lang>` once per skill invocation; do not re-read CLAUDE-swift-toolkit.md per string.

## 1. Input Contract

The skill is invoked by `swift-toolkit:orchestrator` via the `Skill` tool with structured `args` in `key=value` form, separated only by newlines.

The field structure is documented in `swift-toolkit:orchestrator` (section **Outbound Contract**). Workflow-research accepts every field already filled — invariant.

If a required field arrives empty — workflow-research does not try to recover. It returns `{status: error, reason: status_error_empty_required_field}` (the `reason` value is taken from a locale key) back to the orchestrator.

RESEARCH-profile specifics:
- `start_stage` — `Research`, `Review`, or `Done`. Any other value is a contract error.
- `end_stage` — `Research`, `Review`, `Done`, or `null`.
- `stage_scope` — `single` / `forward` / `all` (same semantics as other workflows).
- `start_phase` — not used (Research has no phases in this profile).
- `need_test` — ignored: research profile produces no code → no tests applicable. Workflow-research treats it as `false` regardless of the contract value.
- `need_review` — gates the inclusion of `swift-toolkit:swift-reviewer` over `Research.md`. Default `true` (set by the orchestrator from `[NEED_REVIEW]` in `Task.md`).
- `mode` — `manual` / `auto` (see sections 3 and 4).
- `stack` — see envelope (`never: all`) below.
- `lang` — project language for `Research.md` / `Review.md` / `Done.md` prose + the final report; artifact structure stays EN. See `conventions/i18n.md` → "Artifact authoring rule".
- `archive_paths` — paths to backups already created by the orchestrator.
- `research_agent` — **RESEARCH-specific optional field** (added in the orchestrator's Outbound Contract for this profile only). Values are BARE agent names: `swift-architect` (default) | `swift-diagnostics` | `swift-security`. Workflow-research resolves the bare name to the prefixed form `swift-toolkit:<name>` at dispatch time, mirroring how `[TASK_TYPE]` carries `FEATURE` rather than `swift-toolkit:workflow-feature`. If unset or empty → fall back to `swift-architect`. If set to any other value → return `{status: error, reason: invalid_research_agent}` before dispatching a subagent.

**Stack envelope.** `stack_axes_envelope: { may: [], never: all }` — same as REVIEW and EPIC. The project `## Stack` from `CLAUDE-swift-toolkit.md` is read raw as ambient context; no per-axis chain, no AUQ.

**Execution range.** Stages run in the order Research → Review → Done, starting at `start_stage` and continuing through `end_stage` inclusive. If `end_stage=null` — through the end of the profile. If `end_stage` precedes `start_stage` in order, that is a contract error: return `{status: error, reason: "end_stage before start_stage"}`. If `need_review=false` and the natural flow reaches Review — skip it and go straight to Done.

**Scope.** `stage_scope` controls execution width:
- `single` — only `start_stage` runs.
- `forward` — `start_stage` plus every subsequent stage up to `end_stage` (or to the end of the profile).
- `all` — equivalent to `forward` with `start_stage = Research`. Used for `action=restart-full`.

## 2. Stages

- **Research** — agent selected per `research_agent` (default `swift-toolkit:swift-architect`; alternatives `swift-toolkit:swift-diagnostics` for code-audit / inventory tasks; `swift-toolkit:swift-security` for security-audit tasks). Artifact: `Research.md` in the task folder. Goal: investigation, inventory, classification, comparative analysis, or feasibility verdict — depending on the Task.md description.

  **Output shape (mandatory headings):**
  - `## Goal` — what the research must answer (one paragraph).
  - `## Method` — how it was conducted (grep / file walk / external research / cross-reference).
  - `## Findings` — the bulk of the artifact (free-form: tables, inventories, classifications, trade-off matrices — whatever the kind requires).
  - `## Follow-up` — list of concrete follow-up tasks (each as a one-liner the user can paste into `task-new`). For an audit-style RESEARCH this section often produces N BUG / REFACTOR tasks. **CRITICAL — DO NOT TRANSLATE THE HEADING.** The heading is the byte-for-byte literal `## Follow-up`. The bullet items below it follow the user's natural language.

  Research-only invariant: the agent MUST NOT modify any source code or write any non-artifact files. If `swift-architect`/`swift-diagnostics`/`swift-security` is tempted to propose a fix inline, it should instead enumerate the proposed fix as a follow-up task under `## Follow-up`.

- **Review** — `swift-toolkit:swift-reviewer` (only if `need_review=true`). Artifact: `Review.md`, **mandatory first line** `[REVIEW_STATUS] = APPROVED | CHANGES_REQUESTED | DISCUSSION` (shared contract). The reviewer evaluates `Research.md` for: coverage of the stated goal, soundness of method, internal consistency of the findings, actionability of the follow-up list. **Critically — the reviewer does NOT validate the technical accuracy of the findings against the codebase**; that is the Research agent's domain. The reviewer judges only research quality.

- **Done** — final report `Done.md`: what was investigated, the verdict / key finding (one paragraph), pointer to `Research.md`, count and brief list of follow-up tasks (with `task-new` invocation hints).

## 3. Manual mode

After each completed stage the orchestrator asks the user via the structured question mechanism using the `stage_done_prompt` key from `locales/<lang>.md`, with placeholder `{stage}`.

Workflow-research **does NOT ask the user itself** — it returns control to the orchestrator after a stage completes (see section 5, Output Contract) with `next_recommended_action`.

## 4. Auto mode

No pauses between stages. Workflow-research runs the stages sequentially within `stage_scope` and returns the final result to the orchestrator.

Workflow-research has no per-phase commits (no phases). It may commit `Research.md`, `Review.md`, and `Done.md` autonomously without a user prompt (docs-only changes). Any flow-level wrap commit the orchestrator initiates is confirmed with the user regardless of mode.

## 5. Output Contract

After each stage (in `manual` mode) or after a full pass (in `auto` mode), workflow-research returns:

```
{
  status: ok | error | cancelled | interrupted,
  last_completed_stage: Research | Review | Done,
  artifact_path: <path to the last artifact written>,
  next_recommended_action: continue | stop | ask_user,
  notes: <free-form text, optional>
}
```

Field semantics:
- `status=ok` — the stage finished correctly.
- `status=error` — an error occurred (including reasons such as the locale key `status_error_empty_required_field`, an invalid contract, or a fatal subagent failure).
- `status=cancelled` — the user explicitly declined to continue (the orchestrator forwarded a `No` from its AUQ; rendered to the user via locale key `status_cancelled_user_no`). A normal outcome, not an error.
- `status=interrupted` — execution was interrupted by a technical fault or external signal (not by user decision): subagent disconnect, timeout, tool unavailable. Requires diagnostics on the orchestrator side.
- `last_completed_stage` — the last stage that actually finished (not the one execution stopped on with an error). For pure-investigation tasks the maximum is `Done`; if `need_review=false` and the workflow finishes without Review, the value is `Done` (Review is treated as skipped, not failed).
- `artifact_path` — path to the key artifact of the last stage (`Research.md`, `Review.md`, or `Done.md`).
- `next_recommended_action=continue` — the next stage may start immediately; `stop` — natural finish (Done) or a fatal error; `ask_user` — confirmation is needed before continuing (e.g. after a Review with `[REVIEW_STATUS] = CHANGES_REQUESTED`, the user must edit `Research.md` and re-run Review).
- `notes` — short free-form description (e.g. rendered from locale key `notes_research_only_no_code` when the workflow wants to remind the user that no code was produced).

## 6. What workflow-research does NOT do

- Does NOT route — profile selection happens in the orchestrator before the call.
- Does NOT modify source code — pure-investigation invariant.
- Does NOT run tests, build the project, or invoke XcodeBuildMCP — no executable artifact produced.
- Does NOT trigger `task-new` for the follow-up items — that is the user's choice (the `## Follow-up` list provides paste-ready descriptions).
- Does NOT call `mobile-ops-checklist` — there is nothing implemented to validate.
- Does NOT decide between Research / Review / Done order — the orchestrator passes `start_stage`, `end_stage`, `stage_scope`.
- Does NOT create backups in `_archive/` — the orchestrator did so before handing off control; the paths arrive in `archive_paths`.
- Does NOT ask the user — the orchestrator does that between stages in `manual` mode.
