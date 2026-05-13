---
name: feature-requirements
description: "Use when starting any new feature, bug fix, or refactor from a briefing or PRD — before designing the architecture or estimating effort. Extracts implicit secondary requirements (error/loading/empty/offline/a11y/deeplinks/push/i18n/analytics), compiles designer and backend questions, lists known unknowns. Output feeds `feature-landscape` and `feature-estimation`."
---

# Feature Requirements

A briefing describes the business goal. The engineering task is to discover what the briefing **didn't say** but the implementation still has to handle. This skill turns a raw briefing into a structured Requirements section: Primary vs Secondary, designer/backend questions, and known unknowns — all before any architecture decision is made.

> **Related skills:**
> - `feature-landscape` — consumes Primary + Secondary to build the entity graph and layer map
> - `feature-estimation` — multiplies baseline by Secondary count and known-unknowns count
> - `mobile-ops-checklist` — Secondary items overlap with cross-cutting ops concerns; this skill is the *design-time* checkpoint, `mobile-ops-checklist` is the *validation-time* one
> - `error-architecture` — when designing how Secondary error states surface to the UI
> - `arch-swiftui-navigation` / `arch-coordinator` — deep-link entry points
> - `concurrency-architecture` — offline/sync Secondary behaviors

## When to use

- New feature from a briefing or PRD (`workflow-feature` Research stage)
- Bug investigation — to enumerate which Secondary states the bug touches (`workflow-bug` Reproduce stage)
- Refactor of an unclear area — to capture current behavior contract before changing structure (`workflow-refactor` Analyze stage)
- Epic decomposition — to surface Secondary work items before splitting into `.step/` (`workflow-epic` Research stage)
- Direct invocation when the user explicitly asks "what are we missing in this brief?" / "what should I ask the designer?"

## Inputs

- The briefing / PRD / user-typed task description
- The project stack (from `CLAUDE-swift-toolkit.md`) — informs which Secondary items are applicable
- The target platform (iOS app / macOS app / SPM library / CLI) — affects N/A semantics

## Steps

### Step 1 — Extract Primary

Read the briefing. Write a single-sentence happy path. List explicit acceptance criteria as they appear in the briefing, verbatim. Do **not** invent criteria the briefing didn't state — those go to Step 2.

### Step 2 — Generate Secondary checklist

For each row below, ask: *what does this feature do in this scenario?* Mark **Applicable**, **N/A (reason)**, or **Pending (need clarification)**. Pending items become Designer or Backend questions in Steps 3/4.

| Category | Probe |
|---|---|
| Error — network failure | What does the UI show when the request fails? Retry button? |
| Error — server 5xx | Same as network or different? |
| Error — partial data | Some items load, some don't — render or fail whole? |
| Loading state | Skeleton, spinner, or instant? Threshold for showing? |
| Empty state | First launch, no results, cleared data — what does the screen say? |
| Offline mode | Hidden, read-only, optimistic + queue, full-block? |
| Accessibility | VoiceOver/TalkBack labels, Dynamic Type, contrast, touch targets ≥44pt |
| Deep link entry | Can a deep link land directly on this screen mid-flow? State reset or preserve? |
| Push notification | Does a push lead here? Foreground vs background behavior? |
| Analytics events | Which user actions need to be logged? Funnel events? |
| Localization | Strings extracted? Text expansion (RU/DE +30%)? RTL? |
| Concurrent updates | Two devices, same user — server-authoritative, LWW, or merge? |
| Lifecycle | App backgrounded mid-flow — preserve state, refresh, or reset? |
| Cancellation | User abandons screen mid-load — cancel network or finish silently? |

**Output of this step:** a table written into `Research.md ## Requirements ### Secondary` with three columns (Category / Status / Notes).

### Step 3 — Compile Designer questions

Generate a numbered list addressed to the designer. Cover at minimum:

1. Which parts of the design are *law* vs *guideline*? (pixel-perfect vs approximate)
2. Are there mockups for error / loading / empty states? If no — what's the intended visual?
3. Which components already exist in the design system? Reuse vs new?
4. Deep link entry points into this feature — defined?
5. Animation spec — finalized or open?
6. iPad / landscape / split-screen support required?
7. Dark mode mockups present?
8. Dynamic Type behavior — what scales, what is fixed?

Add feature-specific questions as needed; **do not drop the generic ones** unless explicitly N/A.

### Step 4 — Compile Backend questions

Generate a numbered list addressed to backend / API owner:

1. Is the API built / in-parallel / not started?
2. Contract format — REST, GraphQL, Protobuf/gRPC?
3. Can we consolidate into one call, or do we need multiple roundtrips?
4. Error codes — full list and intended client behavior per code?
5. Pagination — cursor or offset? Page size cap?
6. Session/token expiry — refresh-token flow on the client side?
7. Idempotency — is `Retry-After` supported, do POSTs accept idempotency keys?
8. Breaking changes planned during our window?
9. Offline-capable variant of any endpoint (or do we cache client-side)?
10. Real-time updates — polling, SSE, WebSocket, push?

Add feature-specific questions as needed.

### Step 5 — Compile Known Unknowns

Walk Steps 2–4. Every **Pending** Secondary item and every unanswered Designer/Backend question becomes a Known Unknown. Each entry:

```
- [unknown-id] <one-line description> — owner: <designer|backend|product|self> — blocks: <which next step>
```

Unknown unknowns are **not listed** — they're absorbed by the buffer applied in `feature-estimation`. This list is only for things you *know* you don't know.

## Output artifact

Write into the active task's `Research.md` under heading `## Requirements`. Structure:

```markdown
## Requirements

### Primary
<one-sentence happy path>

Acceptance criteria from briefing:
- <criterion 1>
- <criterion 2>

### Secondary
| Category | Status | Notes |
|---|---|---|
| Error — network failure | Applicable | Retry button; 3 attempts then give up |
| Loading state | Pending | Need designer mockup |
| Offline mode | N/A | Online-only feature per brief |
| ...

### Designer questions
1. <question 1>
2. <question 2>
...

### Backend questions
1. <question 1>
...

### Known unknowns
- [u1] <description> — owner: designer — blocks: feature-landscape Step 2
- [u2] ...
```

**Idempotency:** if `## Requirements` already exists in `Research.md`, do not silently overwrite. Read the existing section, present it to the user via `AskUserQuestion`, ask: overwrite / merge / skip.

## Anti-patterns

- **Skipping Secondary because brief didn't mention them.** The whole point of this skill is that the brief omitted them. Default each row to Applicable until you have a reason to mark N/A.
- **Treating Secondary as "polish for later".** Secondary items drive 40–70% of effort. Estimating without them produces fiction.
- **Asking the designer/backend in chat without writing the questions down.** Verbal answers evaporate. Capture every question and answer in `Research.md`.
- **Folding unknown unknowns into Known unknowns.** They're different: Known = list, Unknown = buffer. Mixing them undercounts both.
- **Generating questions that the briefing already answered.** Re-read first. Only ask what's truly open.

## Platform-specific N/A semantics

- **SPM library / CLI** — Deep links, push notifications, Dynamic Type, RTL layout are typically N/A; mark them with explicit reason ("CLI tool, no UI"). Error/loading/empty/concurrency/cancellation still apply.
- **macOS app** — Deep links → URL scheme handling still applies; touch targets are mouse targets; Dynamic Type → preferred-fonts equivalent.
- **iOS app** — All categories typically Applicable until proven otherwise.

## What this skill does NOT do

- Does NOT design components, modules, or architecture — that's `feature-landscape`.
- Does NOT produce time estimates — that's `feature-estimation`.
- Does NOT verify implementation against the checklist — that's `mobile-ops-checklist` (validation-time).
- Does NOT contact designers or backend itself — it produces a question list the human (or orchestrator) routes to the right people.
