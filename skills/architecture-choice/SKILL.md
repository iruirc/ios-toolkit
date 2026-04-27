---
name: architecture-choice
description: "Use at project bootstrap or major refactor to pick the iOS/macOS architecture stack. Compass-style: 5 input axes (team size, lifetime, domain complexity, UI framework, testing rigor) → one of six reference stacks (MVC / MVVM+Coordinator / MVVM+Router SwiftUI / Hybrid UIKit+SwiftUI / Clean Architecture / VIPER). Points to detailed skills, doesn't replace them."
---

# Architecture Choice — Decision Compass

A **meta-skill** for picking a stack at day-one or at a major refactor. Doesn't teach any pattern — points to the skill that does. Use this once per project; for everything else use the skill of the chosen pattern.

> **Related skills:**
> - `arch-mvc`, `arch-mvvm`, `arch-clean`, `arch-viper`, `arch-tca` — the patterns this skill chooses between (`arch-mvc` "When Appropriate" gives the fuller MVC criteria; `arch-tca` "When Appropriate" gives the fuller TCA criteria; this matrix is a one-line summary)
> - `arch-coordinator`, `arch-swiftui-navigation` — orthogonal navigation skills, almost always added on top
> - `pkg-spm-design` — when "should we modularize at all" is also being decided
> - `di-composition-root`, `di-swinject`, `di-factory`, `di-module-assembly` — DI is a **parallel** decision, not derived from architecture
> - `reactive-combine`, `reactive-rxswift` — binding framework, orthogonal to architecture
> - `error-architecture`, `net-architecture`, `persistence-architecture` — cross-cutting; bring them in regardless of pattern

## When to Use

- New project (`swift-init`, `swift-setup`) and CLAUDE-swift-toolkit.md `## Stack` is empty
- Major refactor and a concrete trigger fired: signals from `arch-mvc` "Signals that MVC has run out of steam"; team grows past 3 devs; domain develops explicit Use Cases; compile time / merge conflicts hurt enough to consider modularization
- User asks "which architecture should I pick", "what should I use for a new iOS project", "MVVM or Clean"

If `CLAUDE-swift-toolkit.md → ## Stack` is already filled and the user is not refactoring — **don't run this skill**. Follow the chosen stack's skill instead.

## Fast Path (skip the questionnaire)

If one of these is clearly true from context, recommend directly without running the 5-axis flow:

| If user says | Recommend |
|---|---|
| "Throwaway prototype, 1–2 weeks" | MVC + manual DI; skip Coordinator |
| "Greenfield SwiftUI iOS 17+ app, 1–2 devs" | MVVM + Router with `@Observable`; manual DI |
| "Existing UIKit production app, stable target" | MVVM + Coordinator (preserves UIKit idioms) |
| "Existing UIKit app, new features in SwiftUI" | Hybrid: MVVM + Coordinator at top, SwiftUI islands with Router |
| "Multi-platform iOS + macOS with shared business logic" | Clean Architecture (shared Domain) + per-platform Presentation |

If none fits clearly — proceed to Five Input Axes.

## Five Input Axes

Get an answer to each before recommending a stack. Don't guess.

| Axis | Spectrum | Why it matters |
|---|---|---|
| **Team size** | solo → 2–3 → 4+ | More people → stronger boundaries to avoid stepping on each other |
| **Expected lifetime** | weeks → months → years | Longer life → invest in tests, layers, documentation conventions |
| **Domain complexity** | CRUD/forms → multiple flows → rich business rules | Rich domain → explicit Use Cases/Interactors to keep logic out of UI |
| **UI framework** | UIKit / SwiftUI / AppKit / hybrid | Drives navigation choice (Coordinator vs NavigationStack+Router) and binding tools |
| **Testing rigor** | smoke/manual → unit on logic → unit + integration + UI | Pivots toward Clean when combined with rich domain — Use Cases give pure-Swift testable units without UIKit |

**Domain complexity and screen count are independent.** A 30-screen catalog with simple CRUD stays MVVM+Coordinator; 4 screens with banking rules may need Clean.

**Don't ask team familiarity for default-track stacks (MVC/MVVM/Clean).** Do ask for non-default tracks (VIPER, TCA) — those require existing fluency, otherwise the choice is wrong regardless of other axes.

## Decision Matrix

Find the row that best matches reality. Thresholds are heuristics, not boundaries — at the edges, apply When-in-Doubt defaults.

| Scenario | Recommended stack | Navigation | Why |
|---|---|---|---|
| Solo, weeks–months, simple CRUD, ≤5 screens | **MVC** | VC `push` / `present` | One file per screen; tests target Models only — see `arch-mvc` "When Appropriate" |
| Solo/pair, months–years, modest logic, UIKit | **MVVM + Coordinator** | Coordinator | ViewModel testable in isolation; Coordinator removes `pushViewController` from VCs |
| Solo/pair, months–years, modest logic, SwiftUI iOS 16+ | **MVVM + Router** | NavigationStack + Path | `@Observable` ViewModel + state-driven navigation; no Coordinator boilerplate |
| Existing UIKit app + new SwiftUI features | **Hybrid: MVVM + Coordinator + Router** | Coordinator outer, Router per SwiftUI island | Old code stays UIKit; new code uses native SwiftUI navigation. See `arch-swiftui-navigation` "Hybrid" |
| 2–3 devs, years, rich domain, must unit-test business rules | **Clean Architecture** | Coordinator / Router | Use Cases are pure Swift — testable without UIKit; Repository hides data sources from Domain |
| 4+ devs, parallel feature work, strict module ownership | **Clean Architecture + SPM modules** | Coordinator / Router | Cross-team dependencies become compile errors, not merge conflicts. See `pkg-spm-design` |
| macOS utility / settings-style app | **MVC (AppKit) or MVVM (SwiftUI)** | Window / Sheet | AppKit MVC if heavy menu/window APIs; SwiftUI MVVM if mostly forms — pick the framework you'll write more in |
| Multi-platform iOS + macOS, shared business logic | **Clean Architecture** | Per-platform Presentation | Domain/Data shared via SPM Library package, Presentation per platform. See `pkg-spm-design` "Library" archetype |
| Legacy team trained on VIPER, large existing codebase | **VIPER** (modernized to async/await) | Router | Use only where the team is already fluent; otherwise pick MVVM |
| SwiftUI-only, team fluent with TCA / Elm / Redux, rich state machines, exhaustive testing required | **TCA** (Point-Free Composable Architecture) | `@Presents` / `StackState` | Reducer composition + `TestStore` exhaustive tests pay off on years-long projects with complex state; non-default track — pick consciously, not "to future-proof". See `arch-tca` |

**One row, not a pattern blend.** A "Clean-MVC" hybrid is almost always Massive ViewController in disguise. The Hybrid row above is the one **legitimate** mix — same patterns across two UI frameworks, not different patterns per feature.

## Stack Cookbook

Each stack is the set of skills you should now follow. Cross all of them off.

- **MVC** → `arch-mvc` (+ `arch-coordinator` once 4+ screens)
- **MVVM + Coordinator (UIKit)** → `arch-mvvm` + `arch-coordinator`
- **MVVM + Router (SwiftUI)** → `arch-mvvm` + `arch-swiftui-navigation`
- **Hybrid UIKit + SwiftUI** → `arch-mvvm` + `arch-coordinator` + `arch-swiftui-navigation` ("Hybrid" section)
- **Clean Architecture** → `arch-clean` + `arch-mvvm` (Presentation layer) + `arch-coordinator` / `arch-swiftui-navigation`; add `pkg-spm-design` if 4+ devs or multi-platform
- **VIPER** → `arch-viper` + `arch-coordinator`
- **TCA** → `arch-tca` (replaces both architecture and navigation: `@Presents` + `StackState` cover what `arch-swiftui-navigation` would otherwise cover); add `arch-mvvm` only if mixing TCA islands with plain SwiftUI screens elsewhere — but see `arch-tca` "Common Mistakes" #13 first

Cross-cutting (always, regardless of pattern):

- **DI** (parallel decision): `di-composition-root` is the entry point — covers manual graph (default for MVC/small), Swinject (runtime, autoregister, SwiftUI-agnostic — see `di-swinject`), and Factory (compile-time, property-wrapper injection, SwiftUI-friendly — see `di-factory`). `di-module-assembly` is the Coordinator/ModuleFactory pattern that sits on top of any of those choices
- **Errors:** `error-architecture` from day one — cheap to set up, expensive to retrofit
- **Networking:** `net-architecture` (and `net-openapi` if API has an OpenAPI spec)
- **Persistence:** `persistence-architecture` once you store more than UserDefaults; `persistence-migrations` on first commit if schema is non-trivial
- **Modularization:** `pkg-spm-design` when 2+ devs OR 3+ features share code OR compile time hurts

## When in Doubt

| Tension | Default to |
|---|---|
| MVC vs MVVM, can't decide | MVVM. Cost of a ViewModel is one file; cost of a Massive VC is six months |
| Clean vs MVVM, can't decide | MVVM. Migrate to Clean later by extracting Use Cases — additive change, no rewrite |
| Coordinator vs Router on hybrid UIKit+SwiftUI | Coordinator at the top; Router inside SwiftUI islands |
| "Should we modularize?" | Not yet. One package, multiple folders, until 2+ devs collide or compile time hurts |
| RxSwift vs Combine on a new project | Combine. RxSwift only if existing code already uses it |
| Manual DI vs Factory vs Swinject | Manual graph (`di-composition-root` "Manual DI" section) until 10+ services. Then **Factory** (`di-factory`) by default for SwiftUI-first projects — compile-time safety, property-wrapper injection, preview/test contexts out of the box. **Swinject** (`di-swinject`) only when you need runtime autoregister, name-based lookup, or are stuck with legacy |
| TCA? | Pick TCA only when SwiftUI-only **and** team already fluent **and** the project benefits from exhaustive reducer-level tests. Otherwise default to MVVM (`arch-mvvm`) — see `arch-tca` "When Appropriate" for the full criteria. TCA is a non-default track; don't pick it on a deadline or to "future-proof" |

## Anti-Patterns at Choice Time

1. **Picking the most ambitious stack "just in case"** — Clean+VIPER+SPM+Swinject for a 5-screen utility wastes weeks and obscures intent
2. **Mixing patterns by feature** — one feature MVC, another MVVM, third Clean — newcomers can't predict where logic lives. (Hybrid UIKit+SwiftUI is **not** this — same patterns, different UI frameworks)
3. **Choosing without writing it down** — record the choice in `CLAUDE-swift-toolkit.md` `## Stack` so every future task reads from one source of truth
4. **Refusing to migrate when signals appear** — see `arch-mvc` "Signals that MVC has run out of steam". Stacks fit a project's current size, not its lifetime
5. **Letting frameworks pick architecture** — "we use SwiftUI, therefore MVVM" is fine; "we use Combine, therefore MVVM-C" is not. Frameworks are tools, not patterns

## How to Use This Skill

1. **Read CLAUDE-swift-toolkit.md `## Stack`.** If filled and user isn't refactoring — this skill is done; follow the chosen stack's skill.
2. **Try Fast Path.** If a Fast Path scenario clearly applies — skip the questionnaire and recommend.
3. **Otherwise collect the Five Axes** from the user via `AskUserQuestion` (or text fallback). Don't infer from project name or vibes.
4. **Pick the matching row** from the Decision Matrix. If two rows fit — apply the When-in-Doubt defaults.
5. **Write the choice into `CLAUDE-swift-toolkit.md` `## Stack`** in the existing bullet format (`- Architecture: <stack>`, `- UI: <framework>`, etc. — don't invent your own fields). Record a short context line above the section as a comment: `<!-- Chosen YYYY-MM-DD: <axes summary> → <stack> -->`.
6. **If user disagrees with the recommendation** — record their choice as-is, then add `Objection: <reason from matrix or Fast Path>` either in `CLAUDE-swift-toolkit.md` directly under `## Stack`, or in `Done.md → ## Objections` of the active task. Per CLAUDE-swift-toolkit.md "Persona" — risks must be visible.
7. **Hand control** to `swift-init` (new project) or `swift-architect` (existing project) with the skill list from Stack Cookbook.

The output of this skill is one paragraph in CLAUDE-swift-toolkit.md and a list of skills to follow next — nothing more. Don't generate code here.
