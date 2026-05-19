---
name: mobile-ops-checklist
description: "Use during validation or review of any mobile / app feature to verify operational concerns are handled — feature flags, crash reporting, deep links, push, offline, accessibility, analytics, App Store constraints, performance, privacy, migrations, testing, third-party SDKs, CI/CD. Each item is marked Applicable / N/A (with reason) / Pending. Output is a separate `OpsChecklist.md` artifact in the task folder."
---

# Mobile Ops Checklist

A cross-cutting checklist distilled from production mobile engineering challenges (Orosz, Building Mobile Apps at Scale). It is *not* a design tool — design happens in `feature-landscape`. It is the late-stage verification that nothing operational was forgotten: feature flag, analytics, deep link, push, offline, privacy, App Store readiness.

> **Related skills:**
> - `feature-requirements` — Secondary list maps onto a subset of this checklist; this skill is the validation-time counterpart
> - `feature-landscape` — graph layers determine which items apply (no networking layer → most networking items become N/A)
> - `error-architecture` — error-handling items reference its taxonomy
> - `persistence-migrations` — schema-migration items expand here
> - `concurrency-architecture` — background work / cancellation items
> - `net-architecture` — retry / pagination / cache items
> - `swift-toolkit:swift-security` — privacy / Keychain / pinning items

## When to use

- Validation stage of `workflow-feature` / `workflow-bug` / `workflow-refactor`
- Review stage — cross-check that items marked Applicable in this artifact were actually implemented
- Pre-release readiness review
- Direct invocation when the user asks "is this ready to ship?" / "did we cover everything?"

## How to use

For each item, choose one of:

- **Applicable** — write the verification evidence: file path, commit ref, test name, screenshot reference, or `Reproduce.md` step
- **N/A (reason)** — write a short reason: "no UI layer", "CLI tool", "internal-only feature", "feature flag not introduced"
- **Pending** — work not yet done; surfaces as a blocker for the Review stage

Default an item to **Applicable** unless you have a concrete reason to mark it N/A. Conservative bias is intentional — the cost of false-Applicable is a small extra check; the cost of false-N/A is a production incident.

## Inputs

- The active task's `Research.md` + `Plan.md` + the profile's main artifact (`Execute.md` / `Fix.md` / `Refactor.md`)
- Project stack from `CLAUDE-swift-toolkit.md` — platform target, UI framework, etc.
- The product context (internal vs public-facing, B2B vs consumer)

## Checklist categories

### Release & rollout

- [ ] Feature flag wraps the new feature (kill switch ready)
- [ ] Gradual rollout plan documented (1% → 10% → 100% with monitoring gates)
- [ ] Minimum supported OS version covered
- [ ] App Store / Play Store review constraints reviewed (no rejection risk: no private API use, no IDFA misuse, no payment-flow violation)
- [ ] Forced-upgrade path considered if breaking
- [ ] Feature flag TTL set (prevent dead-flag accumulation)

### State & lifecycle

- [ ] App lifecycle handled — foreground, background, suspend, terminate
- [ ] Single source of truth for feature state (no mutation from multiple owners)
- [ ] All four UI states covered — loading, success, error, empty
- [ ] Background → foreground refresh policy decided

### Networking

- [ ] API endpoints versioned or contract stable
- [ ] Error codes mapped 1:1 to user-facing behavior
- [ ] Retry policy idempotency-aware
- [ ] Pagination strategy (cursor preferred for feeds; offset only for bounded lists)
- [ ] Cache strategy with explicit TTL and eviction
- [ ] Network failure UX defined (banner, inline retry, degraded mode)

### Offline & sync

- [ ] Local source of truth chosen (memory, disk, network-only)
- [ ] Conflict resolution defined (LWW / server-authoritative / merge / CRDT)
- [ ] Optimistic updates have a rollback path
- [ ] Background sync trigger defined (foreground, push, BGTask, none)

### Crash & stability

- [ ] Crash reporting wired (Crashlytics / Bugsnag / Sentry)
- [ ] Symbolication setup verified for new binaries
- [ ] OOM tracking strategy if memory-intensive
- [ ] Fatal vs recoverable errors distinguished per `error-architecture`

### Performance

- [ ] Cold-launch impact measured (< 2s target)
- [ ] 60fps on critical screens (Instruments / Time Profiler check)
- [ ] No retain cycles (Allocations / leaks)
- [ ] Battery: no background polling, no high-frequency timers without justification
- [ ] Network payloads compressed where applicable

### Push & background

- [ ] APNS / FCM token registration handled
- [ ] Token rotation handled
- [ ] Silent push for server-side state changes (if applicable)
- [ ] Opt-out flow gracefully degraded
- [ ] Background fetch / BGTask scheduled correctly

### Deep links & navigation

<!-- Design-time mechanics (parser, AASA, entry points, cold-start, auth gate): `nav-deeplinks`. This is verification-time only. -->

- [ ] Deep link path defined and registered
- [ ] Backward compatibility of pre-existing links preserved
- [ ] State reset vs preserve policy decided (deep link mid-flow)
- [ ] Universal Links (iOS) / App Links (Android) entitlements configured

### Accessibility

- [ ] VoiceOver / TalkBack labels and hints on interactive elements
- [ ] Dynamic Type / system-text-size scaling
- [ ] Touch targets ≥ 44pt (iOS) / 48dp (Android)
- [ ] Color contrast WCAG AA on critical text
- [ ] Tested with assistive tech, not just static audit

### Localization

- [ ] No hardcoded user-visible strings
- [ ] RTL layout (Arabic / Hebrew) verified if app ships those locales
- [ ] Pluralization rules use the platform's stringsdict / plural resources
- [ ] Date / time / number formatting locale-aware
- [ ] Text-expansion safe (DE / RU ~+30%)

### Analytics & monitoring

- [ ] Key user actions instrumented
- [ ] Funnel events defined and emitted
- [ ] Crash-free rate threshold agreed with on-call
- [ ] Dashboards / alerts configured for the feature
- [ ] No PII in event names, parameters, or screen names

### Privacy & security

- [ ] No PII in logs, analytics, or crash reports
- [ ] Secrets in Keychain (iOS) / Keystore (Android) — never UserDefaults / SharedPreferences
- [ ] Certificate pinning if handling sensitive data
- [ ] ATS (iOS) compliance verified
- [ ] GDPR / CCPA: consent flow + data-erasure path
- [ ] App Privacy report (iOS) / Data Safety form (Android) updated

### Migrations

- [ ] Schema migration from N-2 versions tested (or rationale to skip)
- [ ] Migration failure recovery path defined
- [ ] Atomic backup before destructive migration
- [ ] Long-migration UX (progress indicator if >2s)

### Testing

- [ ] Unit tests for domain / service / repository
- [ ] Snapshot tests for critical UI states (all four: loading / success / error / empty)
- [ ] Integration tests at layer boundaries
- [ ] UI tests for golden path only (expensive — don't over-invest)
- [ ] Manual test pass: accessibility + device matrix

### Third-party SDKs

- [ ] License compatible with the product license
- [ ] Binary-size impact measured (added bytes ≤ budget)
- [ ] Wrapped behind a project-owned protocol (vendor lock-out)
- [ ] Security audit / vulnerability scan
- [ ] Transitive dependency footprint reviewed

### CI/CD

- [ ] Lint passes (SwiftLint / Detekt / etc)
- [ ] Tests green in CI on the merge branch
- [ ] Build-time impact within budget
- [ ] Beta distribution path verified
- [ ] Code-signing / provisioning profile updated if entitlements changed

## Output artifact

Write a **separate file** `OpsChecklist.md` in the task folder (`Tasks/<STATUS>/<NNN-slug>/OpsChecklist.md`). Do **not** inline into `Validation.md` — the checklist evolves through Validation → Review and survives as a standalone audit artifact in the eventual `Done.md` reference.

Structure:

```markdown
# Ops Checklist — <task-id>

> Generated by `mobile-ops-checklist`. Mark each item Applicable / N/A (reason) / Pending.

## Release & rollout
- [x] Feature flag wraps the feature — `Features.cartV2` in `FeatureFlags.swift:42`
- [x] Gradual rollout plan — `docs/cart-v2-rollout.md`
- [ ] Pending: minimum-OS check
- N/A: Forced-upgrade — internal beta only, no public release

## State & lifecycle
- [x] All four UI states covered — `CartView` previews `CartView_Previews.swift`
- [x] Single source of truth — `CartViewModel.state`
- N/A: Background sync — feature is online-only

## ...
```

**Idempotency:** if `OpsChecklist.md` already exists, prompt the user — overwrite / merge / skip. Re-checking a list mid-feature is normal; preserve prior entries with timestamps if merging.

## Platform-specific N/A semantics

- **SPM library** — Most categories N/A: deep links, push, App Store, accessibility (no UI), analytics (library should not emit), localization (consumer's job). Applicable: error handling, performance, testing, third-party SDKs, CI/CD, security (if handling secrets).
- **CLI tool** — Push / deep links / accessibility / localization N/A. Crash reporting may be N/A (stderr is the report). Privacy still applies if reading user files.
- **macOS app (Developer ID distribution)** — App Store review N/A; notarization still applies.
- **iOS app** — All categories typically Applicable.

## Anti-patterns to avoid

- **Marking everything Applicable to be safe.** Forces noise. Each Applicable needs a verification step — if you can't write evidence, downgrade to Pending.
- **Marking N/A without reason.** Future reviewer can't tell if N/A is correct or a cop-out. Always write the reason.
- **Filing OpsChecklist.md and moving on.** The checklist is a Review-stage input — the reviewer agent reads it and cross-checks Applicable items against the actual diff.
- **Treating the checklist as a release-gate-only artifact.** Best practice: fill it during Plan (Pending everywhere), update during Execute as items resolve, finalize at Validation. Don't leave the whole list for the end.
- **Hiding pending items by deleting them.** Pending = blocker. Either resolve it, get explicit N/A approval, or push the release.

## What this skill does NOT do

- Does NOT design the feature — that's `feature-landscape`.
- Does NOT estimate effort of completing items — combine with `feature-estimation` if needed.
- Does NOT auto-fix Pending items — it surfaces them; humans / agents handle resolution.
- Does NOT replace `swift-toolkit:swift-security` — security audit is a deeper pass, this checklist's privacy/security section is the surface scan.
