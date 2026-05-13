---
name: feature-estimation
description: "Use when estimating mobile / app feature work — after `feature-landscape` produced work-items. Converts ideal-day baseline into a calibrated day range using static multipliers for unknowns, secondary requirements, unfamiliar tech, parallel API, binary-distribution risk, OS fragmentation, and App/Play Store review. Output is a range with explicit assumptions, never a point estimate."
---

# Feature Estimation

Estimates fail because they ignore the cost of what nobody wrote down: error states, the App Store review window, the engineer's unfamiliarity with the module, the API contract changing mid-sprint. This skill applies a static set of mobile-specific multipliers on top of a baseline and produces a calibrated *range* with explicit assumptions — never a single number.

> **Related skills:**
> - `feature-landscape` — produces the work-items list this skill consumes
> - `feature-requirements` — Secondary list and Known Unknowns directly drive the multipliers
> - `mobile-ops-checklist` — Applicable ops items add concrete days (feature flag wiring, analytics dashboards, on-call runbook)

## When to use

- Plan stage of any workflow (`workflow-feature`, `workflow-bug`, `workflow-refactor`) after the landscape is drawn
- Sprint planning — single-feature commitment to a sprint
- Trade-off discussion with stakeholders ("can this ship by Q3?")
- Direct invocation when the user asks "how long will this take?"

## Inputs

- `Research.md ## Landscape ### Work items` — decomposed list with each item ≤ 2 days
- `Research.md ## Requirements` — Secondary table + Known Unknowns
- Project stack from `CLAUDE-swift-toolkit.md` — for stack-specific multipliers (e.g. Android fragmentation only applies if cross-platform)
- API readiness state — built / in-parallel / not started
- Engineer familiarity with the module — first time / occasional / fluent
- Hard deadline presence (yes / no)

## Steps

### Step 1 — Baseline

For each work item from `feature-landscape`, estimate **ideal developer-days**: a single engineer, no interruptions, full knowledge of the codebase, no waiting on anyone. Sum per-item baselines.

Items are already ≤ 2 days (enforced by `feature-landscape` Step 4). If any item is larger, return to the landscape and decompose further — don't estimate at the wrong granularity.

### Step 2 — Apply multipliers

The baseline is multiplied by each applicable factor below. Multipliers compound; record each one used in the output with its justification.

| Factor | Multiplier | When applies |
|---|---|---|
| Unknown unknowns buffer | **×1.3–1.5** | Always. Pick 1.3 for well-known territory, 1.5 for greenfield. |
| Secondary requirements not yet scoped | **×1.4–1.7** | When `feature-requirements ### Secondary` still has Pending rows |
| New tech / unfamiliar module | **×1.5–2.0** | First time touching this area; new SDK; new framework |
| API in parallel | **×1.3–1.4** | API being built same sprint — contract may shift |
| Binary distribution risk | **×1.2** | Always for iOS/macOS apps (no instant rollback) |
| OS / device fragmentation | **×1.2–1.3** | Android only — Custom UI, Camera, Media. iOS-only project: skip. |
| App / Play Store review | **+2–7 days** (additive) | Any hard deadline that requires a store-submitted build |
| Cross-platform parallel | **×1.0 per platform** | Each platform is its own estimate, not half of one |

**Rules:**
- Multipliers **compound** (multiplicative), then App Store buffer is **added** at the end.
- Don't double-count: if Secondary is fully scoped (no Pending rows), don't apply the Secondary multiplier — the Secondary days are already in the baseline.
- Don't apply Unknown Unknowns above 1.5 — beyond that, you're guessing rather than buffering. Decompose the landscape further instead.
- Cross-platform parallel = two estimates, not one × 0.5. Each platform is its own baseline + multipliers.

### Step 3 — Known unknowns gate

List every Known Unknown from `feature-requirements ### Known unknowns`. For each:

- If unresolved at estimation time → the estimate is **conditional** ("9–12 days *assuming* the API contract is finalized this week")
- If a Known Unknown could swing the estimate >30% → return to `feature-requirements`, the unknown is too load-bearing to leave open

### Step 4 — Communicate as range with assumptions

Output is **always** a range, never a point. Anchor each end of the range to an assumption.

Example:

> "**5–7 days** if the API contract is finalized this week and the existing `CartRepository` can be reused.
> **8–10 days** if we build against a mock and discover deltas at integration.
> +3 days for accessibility and analytics if Secondary is left for last.
> +2–7 days App Store review buffer when a hard deadline applies."

State every assumption that backs each anchor. If an assumption breaks, the estimate changes — and that's expected.

## Output artifact

Write into the active task's `Plan.md` under heading `## Estimation`. Structure:

```markdown
## Estimation

### Baseline (per work item)
| Item | Layer | Ideal days |
|---|---|---|
| Define CartItem / Order / PaymentStatus | Domain | 0.5 |
| `CartRepository` add/remove/clear | Repository | 1.0 |
| Local cache (Core Data) | Repository | 1.5 |
| `CartViewModel` state transitions | State | 1.0 |
| ... | ... | ... |
| **Baseline total** | | **8.0 days** |

### Multipliers applied
| Factor | Value | Justification |
|---|---|---|
| Unknown unknowns | ×1.4 | Mid-familiarity territory, two unresolved known unknowns |
| Secondary not scoped | ×1.5 | Designer hasn't delivered error/empty mockups |
| API in parallel | ×1.3 | Backend committing this sprint, contract under discussion |
| Binary distribution | ×1.2 | iOS app — no hotfix path |
| App Store review | +3 days | Hard deadline at end of next sprint |

### Range
**Low (best case): 8.0 × 1.4 × 1.5 × 1.3 × 1.2 + 3 = 24 days**
**High (worst case): 8.0 × 1.5 × 1.7 × 1.4 × 1.2 + 7 = 35 days**

### Assumptions
1. Designer delivers error / loading / empty mockups within 2 working days.
2. Backend API contract frozen by end of week 1.
3. No new platform support (iOS-only).
4. Existing `ProductRepository` is reused as-is.

### Known unknowns blocking final estimate
- [u1] Designer behavior for offline checkout — owner: designer — resolution required before lockdown
- [u2] Payment-gateway error taxonomy — owner: backend
```

**Idempotency:** if `## Estimation` already exists in `Plan.md`, prompt the user before overwriting. Re-estimation is normal mid-feature — keep the previous version under `### Estimation history` with a date.

## Anti-patterns to avoid

- **Happy-path only estimate.** Ignoring Secondary turns a 10-day feature into a 20-day surprise.
- **"It's just a UI change."** UI almost always touches state, tests, analytics, and edge cases. The Secondary multiplier exists for exactly this.
- **Shared estimate across platforms.** iOS and Android are not "the same work × 2 people." Each is its own decomposition.
- **Point estimate without decomposition.** "Probably 2 weeks" with no work-item list is fiction. Always decompose first via `feature-landscape`.
- **Velocity-based without breakdown.** Story points are a team-private calibration on top of decomposition — not a replacement for it.
- **Multiplier-stacking without justification.** Each multiplier must be tied to a concrete observation. "Felt risky" is not a justification.
- **Communicating a single number to stakeholders.** Always give a range with assumptions. If forced into a single number, give the high end.
- **Hiding the App Store buffer.** Review windows are not engineering time, but they are *calendar* time. Always surface them.

## Calibration over time

Static multipliers are a starting point, not a prescription. After each shipped feature, compare *estimated range* to *actual days*. Patterns that emerge:

- Multipliers consistently too low → the team is under-decomposing the landscape; push for finer work items.
- Multipliers consistently too high → the team has built up tooling/library that reduces the Secondary cost; lower the Secondary multiplier for this codebase.

These calibrations live in the team's retro notes, not in this skill — the skill stays stable, the team's project-specific overrides go into the team's own playbook. (Future: an optional `## EstimationMultipliers` section in `CLAUDE-swift-toolkit.md` can override the defaults — not yet supported.)

## Platform-specific notes

- **SPM library / CLI** — Skip App Store buffer; skip OS fragmentation; binary-distribution multiplier still applies if the library is shipped as a binary artifact (e.g. xcframework).
- **macOS app distributed via Mac App Store** — App Store buffer applies; via Developer ID / direct distribution → skip the buffer but add notarization time (~1 hour, not days).
- **iOS app** — All multipliers in scope.

## What this skill does NOT do

- Does NOT produce a single number — only ranges.
- Does NOT promise calendar dates — output is *working days*, not weeks-with-holidays.
- Does NOT decide priority or scope — that's the product / planning conversation.
- Does NOT estimate features without a landscape — return to `feature-landscape` first if no work-items list exists.
