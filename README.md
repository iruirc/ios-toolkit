# swift-toolkit

A set of skills, agents, and slash commands for Claude Code that turn the assistant into a disciplined iOS/macOS developer. Covers architectural choice, pattern-driven implementation, DI, cross-cutting layers (errors / network / persistence), modularization via SPM, and task orchestration (FEATURE / BUG / REFACTOR / TEST / REVIEW / EPIC).

## Setup

- **New project from scratch** — `/swift-init` (creates an iOS/macOS app or an SPM package, lays down the `Tasks/` structure, writes both `CLAUDE.md` and `CLAUDE-swift-toolkit.md` — see *File layout* below).
- **Existing project** — `/swift-setup` (creates `CLAUDE-swift-toolkit.md` from the template, inserts the `@./CLAUDE-swift-toolkit.md` import into your `CLAUDE.md`, creates `Tasks/`).
- From there — manage tasks via slash commands (`/task-new`, `/task-run`, `/task-continue`, `/task-redo`, `/task-restart`, `/task-move`, `/task-status`) or NL phrases ("create task: …", "run 001", "continue 001", "status 001").

### File layout

`/swift-setup` and `/swift-init` produce two files in your project root:

- **`CLAUDE-swift-toolkit.md`** — toolkit-owned configuration (`## Language`, `## Persona`, `## Stack`, `## Mode`, `## Modules`, `## Paths`, `## Orchestration`). Updated by `/swift-setup` and `/swift-lang`. Don't edit by hand — re-running `/swift-setup` may overwrite it (with a backup).
- **`CLAUDE.md`** — your project-level Claude instructions. Contains a single `@./CLAUDE-swift-toolkit.md` line that imports toolkit configuration into Claude's context. Add your own sections, conventions, and project-specific instructions here. Toolkit never overwrites this file beyond inserting the import line.

Existing projects on the legacy single-file format (everything in `CLAUDE.md`) are migrated automatically on the next `/swift-setup` invocation: toolkit sections move to `CLAUDE-swift-toolkit.md`, your sections stay in `CLAUDE.md`, and the original is backed up to `CLAUDE.md.bak`.

---

## Skills as a system

The skills live flat under `skills/`, but logically split into **seven groups**. The links between groups are not arbitrary: some decisions are independent of each other (parallel decisions), others are sequential (architecture choice → concrete patterns).

### 0. Meta — entry point

| Skill | Purpose |
|---|---|
| [`architecture-choice`](skills/architecture-choice/SKILL.md) | A compass: 5 axes (team / lifetime / domain complexity / UI framework / tests) → one of 9 rows in the Decision Matrix. Points to a specific `arch-*`; does not replace it. Run once per project. |

**Run first** during bootstrap or a major refactor, if `CLAUDE-swift-toolkit.md → ## Stack` is empty.

### 1. Architectural patterns (pick **one** per project)

| Skill | When |
|---|---|
| [`arch-mvc`](skills/arch-mvc/SKILL.md) | Prototypes, small CRUD utilities, small teams. Includes triggers for migration to MVVM/VIPER. |
| [`arch-mvvm`](skills/arch-mvvm/SKILL.md) | Default for most teams. 5 binding flavors (Closures / Combine / async-await / `@Observable` / RxSwift). |
| [`arch-viper`](skills/arch-viper/SKILL.md) | Very large teams, strict role contracts. Default Interactor — async/await. |
| [`arch-clean`](skills/arch-clean/SKILL.md) | Complex domain, long lifetime, explicit Use Cases, layer-by-layer testability. |
| [`arch-tca`](skills/arch-tca/SKILL.md) | SwiftUI-only, fluent team, state machines, exhaustive testing. Replaces both architecture and navigation. |

### 2. Navigation (pick by UI framework, **independent** of architecture)

| Skill | When |
|---|---|
| [`arch-coordinator`](skills/arch-coordinator/SKILL.md) | UIKit-first projects. Child coordinators, Router, deep links, hybrid with SwiftUI via `UIHostingController`. |
| [`arch-swiftui-navigation`](skills/arch-swiftui-navigation/SKILL.md) | SwiftUI-first projects. `NavigationStack` + `NavigationPath`, `@Observable Router`, `@Environment`-driven navigation, hybrid with UIKit. |

> TCA covers its own navigation (`@Presents`, `StackState`/`StackAction`) — `arch-coordinator` / `arch-swiftui-navigation` are not needed.

### 3. DI (parallel decision: container vs manual + a specific library)

| Skill | Purpose |
|---|---|
| [`di-composition-root`](skills/di-composition-root/SKILL.md) | **Where** the graph is assembled (SceneDelegate / AppDelegate / `@main App`). Container vs manual comparison, sync/async bootstrap, scope strategies. DI-framework agnostic. |
| [`di-module-assembly`](skills/di-module-assembly/SKILL.md) | Factory pattern (CoordinatorFactory / ModuleFactory) — links DI to coordinators without a Service Locator. |
| [`di-swinject`](skills/di-swinject/SKILL.md) | Swinject specifics: scopes, registrations, Assembly. |
| [`di-factory`](skills/di-factory/SKILL.md) | FactoryKit (hmlongco): property-wrapper injection, scopes, modular containers, contexts. |
| [`pkg-spm-design`](skills/pkg-spm-design/SKILL.md) | SPM package boundaries (Feature / Library / API-Contract / Engine-SDK). When to extract and what to make public. |

### 4. Cross-cutting layers (needed almost always, **independent** of architecture)

| Skill | Purpose |
|---|---|
| [`error-architecture`](skills/error-architecture/SKILL.md) | Per-layer error types, mapping between layers, presentation strategy, PII-safe logging, retry/cancellation. |
| [`net-architecture`](skills/net-architecture/SKILL.md) | `HTTPClient` protocol as the boundary, framework comparison (URLSession/Alamofire/Moya/Get), interceptors, retry, pagination, WebSocket, caching. |
| [`net-openapi`](skills/net-openapi/SKILL.md) | `swift-openapi-generator`: SPM plugin, wrapping the generated `Client` in your own `APIClient`, custom transport, mocking. |
| [`persistence-architecture`](skills/persistence-architecture/SKILL.md) | Repository as the boundary, choosing the storage (Core Data / SwiftData / GRDB / Realm / UserDefaults / files / Keychain), threading, reactive queries, CloudKit, encryption. |
| [`persistence-migrations`](skills/persistence-migrations/SKILL.md) | Schema migrations (CD lightweight/heavyweight, SwiftData VersionedSchema, GRDB DatabaseMigrator, Realm migrationBlock), Codable evolution, backup, telemetry. |
| [`concurrency-architecture`](skills/concurrency-architecture/SKILL.md) | Placement of Swift Concurrency across layers: where `@MainActor` lives, when to use a custom `actor`, who owns a `Task`, how cancellation propagates between layers, where `async let` / `TaskGroup` belong. An architectural concern; language-level questions (Sendable, Swift 6 migration) belong to the external `swift-concurrency:swift-concurrency` skill (AvdLee). |

### 5. Binding tools — **not architectures**, just tools used inside them

| Skill | Purpose |
|---|---|
| [`reactive-combine`](skills/reactive-combine/SKILL.md) | Combine as an event-stream / UI-binding tool. The architecture is chosen separately (`arch-mvvm` / `arch-clean` / `arch-tca`). |
| [`reactive-rxswift`](skills/reactive-rxswift/SKILL.md) | RxSwift as an event-stream / UI-binding tool. The architecture is chosen separately (`arch-mvvm` / `arch-clean` / `arch-viper`). |

### 6. Task orchestration (the toolkit's internal "kitchen")

| Skill | Purpose |
|---|---|
| [`orchestrator`](skills/orchestrator/SKILL.md) | Routes a request to the right profile workflow, resolves the start point, manages stages. |
| `workflow-feature` / `workflow-bug` / `workflow-refactor` / `workflow-test` / `workflow-review` / `workflow-epic` | Profile procedures (Research → Plan → Execute → Validation → Review → Done). Activated by the `orchestrator`; not invoked directly. |
| `task-new` / `task-move` / `task-status` | Tending `Tasks/` (creation, status moves, progress). |
| `swift-setup` | Sets up the toolkit in an existing project. |
| `swift-lang` | Switches the project's prompt language (en / ru). |

---

## How the groups connect

```
                  architecture-choice (meta, once per project)
                            │
                            ▼
              ┌─────────────┴─────────────┐
              │                           │
        arch-* (one)               parallel decisions:
              │                    ─────────────────────
              │                     • DI (di-*)
              │                     • Navigation (arch-coordinator | arch-swiftui-navigation)
              │                     • Modularization (pkg-spm-design)
              │                     • Cross-cutting (error- / net- / persistence-)
              ▼                     • Binding (reactive-*)
        Feature implementation
              │
              ▼
        orchestrator + workflow-* + task-*
```

**Key rules:**

- `architecture-choice` is meta-level. Run once. After that, the concrete `arch-*` skills take over.
- `arch-coordinator` ↔ `arch-swiftui-navigation` — picked by UI framework, **not** by architecture. Navigation can be swapped without touching `arch-mvvm`.
- DI is a separate decision from architecture. Any `arch-*` is compatible with any `di-*` (or with a manual graph).
- `reactive-combine` / `reactive-rxswift` are **tools**, not architectures. Don't confuse them with `arch-*`.
- Cross-cutting (`error-architecture`, `net-architecture`, `persistence-architecture`, `concurrency-architecture`) are needed regardless of the chosen `arch-*`.
- `concurrency-architecture` covers the **placement** of primitives across layers; for the **language** layer (Sendable, isolation rules, Swift 6 migration, actor reentrancy) plug in the external `swift-concurrency:swift-concurrency` skill (see [AvdLee/Swift-Concurrency-Agent-Skill](https://github.com/AvdLee/Swift-Concurrency-Agent-Skill) — installed separately as an Agent Skill / plugin).
- TCA is the exception: it replaces both architecture and navigation (its own `@Presents` / `StackState`).

---

## Agents

Live under `agents/`. Each is a specialized role with its own set of relevant skills in the Skills Reference:

| Agent | Role |
|---|---|
| `swift-init` | Bootstrap a new project |
| `swift-architect` | Architecture design and review |
| `swift-developer` | Feature implementation and bug fixes |
| `swift-refactorer` | Refactoring without behavior change |
| `swift-reviewer` | Code review |
| `swift-tester` | Unit / integration test generation |
| `swift-diagnostics` | Bug hunting, reproduction, instrumentation |
| `swift-security` | OWASP Mobile Top-10 audit |

---

## Internationalization

swift-toolkit ships with English source-of-truth and per-language locale files for user-facing prompts. Currently supported: `en`, `ru`.

- The active language is stored in your project's `CLAUDE-swift-toolkit.md` under `## Language` (set during `/swift-setup`).
- Switch any time with `/swift-lang en` or `/swift-lang ru`.
- Skill triggers are bilingual — phrase your request in Russian or English regardless of the active language; only the response language changes.

Adding a new language: see [`conventions/i18n.md`](conventions/i18n.md).

---

## Roadmap

Current state and gaps — in [`docs/skills-roadmap.md`](docs/skills-roadmap.md).
