# RESEARCH vs EPIC `pure_research` — when to use which

> Companion note to `skills/workflow-research/` and `skills/workflow-epic/`.

Both profiles can finish without writing application code. They are NOT redundant — they encode different *up-front* intent.

## RESEARCH (first-class profile)

**Use when:** the task is known up-front to be investigation-only. No code will be written *because of this task* (follow-up tasks created from `## Follow-up` may write code; those are separate tasks of their own types).

**Examples:**
- Audit: "find every callsite that compares file paths without `resolvingSymlinksInPath()`"
- Feasibility: "can we replace Combine with async streams without breaking back-pressure semantics?"
- Comparative analysis: "GRDB vs Realm for our offline cache"
- Domain investigation: "how does ABC.Bank's new OpenBanking API differ from the old one"
- Security audit: "OWASP audit of the new card-entry flow"

**Shape:** `Research → [Review] → Done`. Single deliverable: `Research.md`. Agent: `swift-architect` (default) / `swift-diagnostics` (audits) / `swift-security` (security audits).

**Status folder:** orthogonal — typically `ACTIVE/` while running, `DONE/` when finished. May live in `RESEARCH/` if the team uses that folder as a parking lot for long-running investigations.

## EPIC `pure_research` branch (downgrade path)

**Use when:** the task started as an EPIC (expected decomposition into N steps and implementation), the Research stage uncovered that no decomposition / implementation is needed after all. The `## Decomposition decision` heading inside `Research.md` records `branch: pure_research`, the Plan stage writes a "research roadmap" instead of a step decomposition, and Execute is skipped.

**Examples:**
- "Investigate a large area" started as EPIC, Research concluded "the area is already fine, no work needed".
- A spike started as EPIC for prototype + integration, the prototype answered the question without needing integration.

**Shape:** `Research → Plan (roadmap) → Done`. The decomposition machinery (`.step/` subfolders, recursive workflows) is not engaged.

## Quick decision

- Will I write any application code *as a direct result of this task*?
  - **No** → RESEARCH
  - **Probably no, but maybe** → EPIC (with `pure_research` as the contingency)
  - **Yes, decomposed into multiple chunks** → EPIC
  - **Yes, a single focused change** → FEATURE / BUG / REFACTOR (no Research profile needed)
