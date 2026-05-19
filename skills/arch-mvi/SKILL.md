---
name: arch-mvi
description: "Use when implementing MVI (Model-View-Intent) architecture pattern in iOS apps. Covers Pure MVI (Intent/State/Reducer) and MVVM+Single State (MVI-like) variants, side-effect handling, Combine + @Observable patterns, and testing. Framework-agnostic — TCA is a specific implementation, see arch-tca."
---

# MVI (Model-View-Intent) Architecture

Unidirectional state management for iOS. A single `State` value type holds everything the screen renders; `Intent`s describe what happened; a pure reduction step produces the next `State`; side effects run outside the reducer. Roots: Cycle.js → Elm → Redux → Android MVI (Orbit, MVIKotlin). On iOS, **TCA is one DSL-flavored implementation of MVI** — this skill covers the framework-agnostic pattern.

> **Related skills:**
> - `architecture-choice` — when to pick MVI vs MVVM vs TCA
> - `arch-tca` — TCA = MVI + Point-Free DSL (`@Reducer`, `@Dependency`, `TestStore`); pick TCA when you want exhaustive testing and reducer composition built-in
> - `arch-mvvm` — Input/Output Pattern (RxSwift) is MVI-shaped; this skill covers `@Observable` / Combine flavors
> - `reactive-combine` — operator-level details for the Combine examples here
> - `concurrency-architecture` — where `@MainActor` lives, Task ownership, cancellation propagation
> - `error-architecture` — modelling errors inside `State` vs presenting them

## When Appropriate

| Project shape | MVI fits? |
|---|---|
| SwiftUI screen with non-trivial state machine (loading / loaded / error / refreshing / paginating) | ✅ Single `State` enum/struct removes "impossible state" bugs |
| Multiple developers want predictable mutation rules | ✅ `send(intent)` is the only entry point |
| Need time-travel / state snapshot debugging | ✅ Pure reducer makes replay trivial |
| Tests must assert "intent X from state Y produces state Z" | ✅ Reducer is a pure function |
| Mixed UIKit + Combine codebase, want unidirectional ViewModels | ✅ Pure MVI works without SwiftUI |
| Trivial CRUD form (3 fields, submit button) | ❌ MVVM with `@Published` properties is shorter |
| Team has zero reducer experience and a 2-week deadline | ❌ Default to MVVM, migrate later |
| You actually want exhaustive testing, dependency overrides, navigation as state | ❌ Use `arch-tca` — TCA gives all of that for free |
| UIKit-only, heavy table/collection or live text-input UI | ⚠️ Manual `render()` *is* the reconciler — cost is real; prefer MVVM (`arch-mvvm`). See "UIKit + MVI" below |
| UIKit-only, genuine complex async state machine, UI mostly labels/buttons | ✅ Pure MVI Store + small `render()` is fine — see "UIKit + MVI" below |

## When Not to Use

- **One-screen utility apps.** Reducer ceremony costs more than it saves.
- **Reducer composition + dependency overrides + exhaustive tests are hard requirements.** That is `arch-tca`'s job — don't reimplement TCA by hand.
- **Existing MVC/MVVM codebase, no migration appetite.** Keep what works; introduce MVI feature-by-feature only if the state-machine cost is real.

## UIKit + MVI

SwiftUI/Elm/React make `View = f(State)` cheap because the framework owns a **reconciler** that diffs the view tree and applies the minimum change. **UIKit has no reconciler.** On UIKit you hand-write `render(_ state:)` and *become* the reconciler — MVI's imperative mutation doesn't disappear, it moves from business logic into `render`.

Concrete costs on UIKit:

- **`render` re-applies everything** on any State change (even a `Bool`). Fine for labels; not for the rest.
- **Tables/collections:** naive `render` → `reloadData()` loses scroll position, cancels in-flight cell image loads, kills animation. Avoiding it = `UI*DiffableDataSource` + manual snapshot diff — an extra layer on top of MVI.
- **Text input:** every keystroke → Intent → State → `render` → reassigning `.text` breaks the cursor / IME composition. Needs a per-field `if new != old` guard.
- **UI-only state** (firstResponder, selection, scroll offset, in-flight animation) lives in UIKit, not in `State`. Either mirror it all into `State` (sync hell) or break the single-source-of-truth invariant.
- **No field-level diffing.** Either repaint all, or hand-write an `if newState.x != old.x` ladder per field — the bug-prone imperative code MVI was meant to remove, reintroduced in `render`.

### Decision

| UIKit screen shape | Choice |
|---|---|
| Heavy table/collection, or live text input | MVVM + `@Published` (`arch-mvvm`) — better cost/benefit |
| Genuine complex async state machine (wizard, payment, live socket) **and** UI is mostly labels/buttons | Pure MVI Store + a small `render()` is fine |
| In between | Per-field Combine binding: `store.$state.map(\.field).removeDuplicates().sink { … }` — pseudo field-level, mechanical but manual |

Apple's own `UI*DiffableDataSource` (iOS 13) exists precisely because manual state→`reloadData()` is bad — treat it as the signal that the manual UIKit path has known costs, not as a blanket ban on MVI.

## Two Flavors

This skill covers two pragmatic flavors. Pick one **per project** (or per module if a feature genuinely needs the heavier flavor).

### Flavor A — Pure MVI

Explicit `Reducer`, explicit `Effect`, explicit `Store`. Closest to Elm/Redux.

```
View ── send(intent) ──▶ Store ──▶ reduce(state, intent) ──▶ State'
                          │                                    │
                          └──▶ Effect ──▶ (async work) ─── Intent ─┐
                                                                    │
                          ◀────────────────── feedback intent ──────┘
```

- `State` — value type (struct or enum), `Equatable`.
- `Intent` — enum; cases name **events** (`viewAppeared`, `retryTapped`, `itemsLoaded([Item])`), not commands.
- Pure `func reduce(_ state: inout State, _ intent: Intent) -> Effect?`.
- `Effect` — async work that eventually feeds an `Intent` back into the store.
- `Store` — owns current `State`, drives the reduce/effect loop, exposes state to the View as `@Published` or `@Observable`.

### Flavor B — MVVM + Single State (MVI-like)

A ViewModel with **one** `State` property and **one** `send(_:)` entry point. No separate `Reducer`/`Effect` types. The ViewModel itself plays all three roles. Keeps MVI invariants (single source of truth, unidirectional flow) without the boilerplate.

- `@Observable` ViewModel.
- `private(set) var state: State`.
- `func send(_ intent: Intent)` — the **only** mutation entry point.
- Async branches spawn `Task { … }` inside `send` and feed completion back through another `send(.itemsLoaded(...))`.

### Choosing between A and B

| Need | Flavor |
|------|--------|
| Multiple developers, strict mutation discipline, dedicated reducer reviews | A |
| Time-travel debugging, action recording, replay tests | A |
| Single-screen feature, 1–2 devs, want unidirectional but not ceremony | B |
| Migrating an existing MVVM screen one step at a time | B |
| Considering TCA later | A (smaller jump) |

## Components

### State

- Value type. Holds **everything** the View needs to render.
- Use enums for mutually-exclusive phases (`enum ViewState { case loading; case loaded(Items); case error(Message) }`) instead of `isLoading: Bool` + `items: [Item]?` + `error: Error?` (avoids "impossible state" combinations).
- Mark `Equatable` — required for snapshot tests and SwiftUI diffing.
- Keep it `Sendable` if the Store crosses actor boundaries.

### Intent

- Enum. Names describe **events that happened** (`viewAppeared`, `retryTapped`, `itemReceived(Item)`), not imperative commands (`loadItems`, `setLoading`).
- Both user-driven events (`*Tapped`, `*Changed`) and reducer-internal results (`*Loaded`, `*Failed`) live in the same enum.

### Reducer (Flavor A only)

- Pure function: `func reduce(_ state: inout State, _ intent: Intent) -> Effect?`.
- **Synchronous.** No `await`, no `Task`, no captures of `self.client`. All async work returns as an `Effect`.
- Does not hold dependencies — the `Store` injects them into `Effect` execution.

### Effect (Flavor A only)

- Encapsulates async work + cancellation token.
- Returns one or more `Intent`s back to the store.
- Implementation: `AsyncStream<Intent>`, `Combine.Publisher<Intent, Never>`, or a closure `(Dependencies) async -> Intent`.

### Store / ViewModel

- Owns current `State` (`private(set)`).
- Owns the loop: `send(intent) → reduce → run effect → feed intents back`.
- Exposes `state` to the View via `@Observable` (iOS 17+) or `@Published` (Combine).
- `@MainActor` — see `concurrency-architecture`.

### View

- **Stateless renderer.** Reads `store.state`, calls `store.send(.something)`. No business logic.
- No `@State` / `@StateObject` for screen-level data — it lives in `State`.

## File Layout

```
Feature/
├── FeatureView.swift            # SwiftUI / UIViewController
├── FeatureState.swift           # struct/enum State : Equatable
├── FeatureIntent.swift          # enum Intent
├── FeatureReducer.swift         # Flavor A only — pure reduce(_:_:)
├── FeatureEffects.swift         # Flavor A only — Effect builders
└── FeatureStore.swift           # Store (Flavor A) or ViewModel (Flavor B)
```

For Flavor B, collapse to:

```
Feature/
├── FeatureView.swift
├── FeatureState.swift
├── FeatureIntent.swift
└── FeatureViewModel.swift       # state + send(_:) inside one type
```

## Code Sample — Flavor A (Pure MVI, Combine + `@Observable`)

A list screen that loads items, supports retry on failure, and refresh-on-pull.

### Domain type

```swift
import Foundation

struct Item: Equatable, Identifiable, Sendable {
    let id: Int
    let title: String
}
```

### State

```swift
struct ItemListState: Equatable, Sendable {
    enum Phase: Equatable { case idle, loading, loaded([Item]), failed(String) }
    var phase: Phase = .idle
    var isRefreshing: Bool = false
}
```

### Intent

```swift
enum ItemListIntent: Equatable, Sendable {
    // user events
    case viewAppeared
    case retryTapped
    case pullToRefresh
    // internal results
    case itemsLoaded([Item])
    case loadFailed(String)
    case refreshFinished
}
```

### Reducer + Effect

```swift
struct ItemListEffect {
    let run: () async -> ItemListIntent
}

func reduceItemList(
    _ state: inout ItemListState,
    _ intent: ItemListIntent,
    _ load: @Sendable @escaping () async throws -> [Item]
) -> ItemListEffect? {
    switch intent {
    case .viewAppeared, .retryTapped:
        state.phase = .loading
        return ItemListEffect {
            do { return .itemsLoaded(try await load()) }
            catch { return .loadFailed(error.localizedDescription) }
        }

    case .pullToRefresh:
        state.isRefreshing = true
        return ItemListEffect {
            do {
                let items = try await load()
                return .itemsLoaded(items)
            } catch {
                return .loadFailed(error.localizedDescription)
            }
        }

    case .itemsLoaded(let items):
        state.phase = .loaded(items)
        state.isRefreshing = false
        return nil

    case .loadFailed(let message):
        state.phase = .failed(message)
        state.isRefreshing = false
        return nil

    case .refreshFinished:
        state.isRefreshing = false
        return nil
    }
}
```

### Store

```swift
import Observation

@MainActor
@Observable
final class ItemListStore {
    private(set) var state = ItemListState()
    private let load: @Sendable () async throws -> [Item]
    private var inFlight: Task<Void, Never>?

    init(load: @Sendable @escaping () async throws -> [Item]) {
        self.load = load
    }

    func send(_ intent: ItemListIntent) {
        let effect = reduceItemList(&state, intent, load)
        guard let effect else { return }
        inFlight?.cancel()
        inFlight = Task { [weak self] in
            let next = await effect.run()
            guard !Task.isCancelled else { return }
            self?.send(next)
        }
    }

    deinit { inFlight?.cancel() }
}
```

### View

```swift
import SwiftUI

struct ItemListView: View {
    @State var store: ItemListStore

    var body: some View {
        Group {
            switch store.state.phase {
            case .idle, .loading:
                ProgressView()
            case .loaded(let items):
                List(items) { Text($0.title) }
                    .refreshable { store.send(.pullToRefresh) }
            case .failed(let message):
                VStack {
                    Text(message)
                    Button("Retry") { store.send(.retryTapped) }
                }
            }
        }
        .onAppear { store.send(.viewAppeared) }
    }
}
```

## Code Sample — Flavor B (MVVM + Single State, `@Observable`)

Same screen, lighter version. No separate `Reducer`/`Effect` types.

### State + Intent

Reuse `ItemListState` and `ItemListIntent` from Flavor A — they are framework-agnostic.

### ViewModel

```swift
import Observation

@MainActor
@Observable
final class ItemListViewModel {
    private(set) var state = ItemListState()
    private let load: @Sendable () async throws -> [Item]
    private var inFlight: Task<Void, Never>?

    init(load: @Sendable @escaping () async throws -> [Item]) {
        self.load = load
    }

    func send(_ intent: ItemListIntent) {
        switch intent {
        case .viewAppeared, .retryTapped:
            state.phase = .loading
            startLoad()

        case .pullToRefresh:
            state.isRefreshing = true
            startLoad()

        case .itemsLoaded(let items):
            state.phase = .loaded(items)
            state.isRefreshing = false

        case .loadFailed(let message):
            state.phase = .failed(message)
            state.isRefreshing = false

        case .refreshFinished:
            state.isRefreshing = false
        }
    }

    private func startLoad() {
        inFlight?.cancel()
        inFlight = Task { [weak self] in
            guard let self else { return }
            do {
                let items = try await self.load()
                guard !Task.isCancelled else { return }
                self.send(.itemsLoaded(items))
            } catch {
                guard !Task.isCancelled else { return }
                self.send(.loadFailed(error.localizedDescription))
            }
        }
    }

    deinit { inFlight?.cancel() }
}
```

### Async-`send` variant (when callers prefer to await)

If callers want to await the completion of an intent (e.g. in tests), expose an async overload:

```swift
extension ItemListViewModel {
    func send(_ intent: ItemListIntent) async {
        send(intent)
        await inFlight?.value
    }
}
```

Pick **one** style per project; do not mix sync `send` and `async send` for the same ViewModel in production code (only the test extension above is OK).

### View

Identical to Flavor A's `ItemListView`, replace `ItemListStore` with `ItemListViewModel`.

## Side Effects & Async

### Where side effects live

| Side effect | Flavor A | Flavor B |
|-------------|----------|----------|
| Network / DB / FS read | `Effect.run` | `Task` inside `send` |
| Timer / debounce | `Effect` returning `Intent.tick` | `Task.sleep` inside `send`, then re-send |
| Analytics fire-and-forget | `Effect` returning a `.noop` intent (or skip and call directly from View — analytics are usually outside the loop) | Same |
| Long-running stream (WebSocket, location) | `AsyncStream` wrapped as repeated `send(.streamItem(_))` | `for await … in stream { send(.streamItem(_)) }` inside a long-lived `Task` |

**Never call services directly from the reducer (Flavor A) or inside non-`Task` branches of `send` (Flavor B).** Side effects must always go through the loop so the next `State` is reachable from `Intent`s only.

### Cancellation

- Per-screen scope: store the `Task` in `private var inFlight: Task<Void, Never>?` and cancel it in `deinit` and at the start of any new request that supersedes the previous one (see `startLoad()` in Flavor B).
- Per-intent scope: keep a dictionary `[IntentKey: Task<…>]` and cancel on `Intent.cancelX`.
- Combine variant: store `AnyCancellable` in a set; same lifetime rules.

See `concurrency-architecture` for who owns Tasks across screens (Coordinator → ViewModel → UseCase) and how cancellation propagates.

### The reduce loop engine: manual vs Combine pipeline (Flavor A)

The reducer is the *logic*; the *engine* that pumps `Intent → reduce → State` is a separate choice. Two engines, both still MVI (single source of truth, unidirectional):

- **Manual (default).** `send(_:)` calls `reduce` synchronously, runs the returned `Effect`, feeds the result back via `send`. This is the `ItemListStore` above. Imperative, one breakpoint in `reduce`, easy for any team.
- **Combine pipeline.** `Intent`s go through a `PassthroughSubject`; `scan` accumulates `State` through the reducer; effects return new `Intent` publishers merged back in.

```swift
intentSubject
    .flatMap { intent -> AnyPublisher<Intent, Never> in
        switch intent {
        case .viewAppeared, .retryTapped:
            return load()                              // side effect
                .map(Intent.itemsLoaded)
                .catch { Just(Intent.loadFailed($0.localizedDescription)) }
                .eraseToAnyPublisher()
        default:
            return Just(intent).eraseToAnyPublisher()  // pure intent passes through
        }
    }
    .scan(ItemListState()) { state, intent in           // scan = functional reducer
        var s = state; reduceItemList(&s, intent, …); return s
    }
    .assign(to: &$state)
```

**Default to the manual engine** — it covers ~90% of screens, reads top-to-bottom, debugs with a breakpoint. Reach for the Combine pipeline **only** when effects are genuinely long chains needing `debounce` (search field), `retry`, `timeout`, or request-merging — wrap that reactive piece so it still emits a plain `Intent`. The Combine pipeline is a niche power tool, not the baseline.

### Errors

Model errors as part of `State` (e.g. `.failed(message)`), not as a separate `@Published var error: Error?`. Two sources of truth = MVI invariant violation.

For mapping low-level errors (`URLError`, decoding) to user-facing `String` / typed enum, see `error-architecture` ("Mapping between layers").

## Performance

### Whole-`State` copy is cheap (COW)

The common objection — "rebuilding the entire `State` struct on every `Intent` is wasteful" — is wrong in practice. `Array`/`String`/`Dictionary` are Copy-on-Write: the struct owns a pointer + refcount, not the buffer.

- `var next = state` copies value fields + bumps refcounts on collection buffers. ~free.
- A reducer that flips `state.phase = .loading` touches a stack value; the `[Item]` buffer is **not** copied — still shared with the previous `State`.
- A buffer is deep-copied **only** on first mutation while `refcount > 1` (e.g. `state.items.append(x)`), and **only** that buffer — untouched collections stay shared.

So you pay only for fields that actually change, at first mutation. Passing the whole snapshot down the loop is effectively free for unchanged parts. Do **not** hand-mutate UI/state to "avoid copying `State`" — that defeats COW and breaks the invariant.

**Threading caveat:** COW's refcount check is not atomic across threads. Two threads doing `var x = state` concurrently is a data race COW won't save. Keep the Store serial — `@MainActor` (as in the samples) or a dedicated serial executor. This is *why* serious MVI stores process intents serially.

### Avoiding over-render

A fresh `State` per intent must not mean repainting the whole screen. Diff at the **data** level, never the UI level (comparing `[Item]` is cheap; comparing view frames is not).

| Renderer | Granularity strategy |
|---|---|
| SwiftUI `@Observable` (iOS 17+) | Automatic — only sub-views reading a changed property re-evaluate. Nothing to do. `State : Equatable` still required for `List` diffing. |
| SwiftUI pre-17 / Combine | Subscribe per field: `store.$state.map(\.field).removeDuplicates().sink { … }`. `removeDuplicates` is the key — unchanged field = no sink call. |
| UIKit lists | `UI*DiffableDataSource` + snapshot — UIKit diffs and animates only changed cells; never `reloadData()` from `render`. |
| UIKit, plain controls | Per-field guard in `render`: `if new.x != old.x { apply }`. Cache previous `State`; mind `defer { old = new }` ordering. |

`State : Equatable` is the enabler for every row above — keep it.

## Testing

### Flavor A — pure reducer test (no `XCTestExpectation`, no async)

```swift
import XCTest
@testable import Feature

final class ItemListReducerTests: XCTestCase {
    func test_viewAppeared_setsLoading_andReturnsLoadEffect() async {
        var state = ItemListState()
        let load: @Sendable () async throws -> [Item] = { [Item(id: 1, title: "A")] }

        let effect = reduceItemList(&state, .viewAppeared, load)

        XCTAssertEqual(state.phase, .loading)
        XCTAssertNotNil(effect)
        let next = await effect!.run()
        XCTAssertEqual(next, .itemsLoaded([Item(id: 1, title: "A")]))
    }

    func test_loadFailed_movesToFailedPhase() {
        var state = ItemListState(phase: .loading, isRefreshing: false)
        _ = reduceItemList(&state, .loadFailed("boom"), { [] })
        XCTAssertEqual(state.phase, .failed("boom"))
        XCTAssertFalse(state.isRefreshing)
    }
}
```

The reducer is a pure function — tests are synchronous, deterministic, and exhaustive over the `Intent` enum.

### Flavor B — ViewModel test via async `send`

```swift
@MainActor
final class ItemListViewModelTests: XCTestCase {
    func test_viewAppeared_loadsItems() async {
        let vm = ItemListViewModel(load: { [Item(id: 1, title: "A")] })
        await vm.send(.viewAppeared)
        XCTAssertEqual(vm.state.phase, .loaded([Item(id: 1, title: "A")]))
    }
}
```

### Snapshot-based UI tests

Because `State : Equatable`, View snapshot tests can pin a state and render the View — no need to drive intents through the loop.

### Mocking dependencies

Inject closures (`@Sendable () async throws -> [Item]`) rather than protocol-conforming objects. Closures are lightweight, value-typed, and require no test-double class hierarchy. For non-trivial dependency surfaces, prefer a protocol — see `arch-mvvm` "Testing".

## Anti-Patterns

1. **Mutating `state` from the View.** The View calls `send(intent)` and reads `store.state`; that's all. A `state.items.append(...)` from a SwiftUI view breaks the invariant. Mark the property `private(set)`.

2. **Multiple sources of truth.** Keeping `state: State` **and** a sibling `@Published var items: [Item]`. Pick one container; everything the View needs goes inside `State`.

3. **`isLoading: Bool` + `items: [Item]?` + `error: Error?` instead of an enum.** Lets the type system represent impossible combinations (`isLoading == true && error != nil`). Use `enum Phase { case idle, loading, loaded(...), failed(...) }`.

4. **Side effects inside the reducer (Flavor A).** `URLSession.shared.data(...)` directly inside `reduce` makes the function impure, untestable, and non-deterministic. Side effects return as `Effect`s; `Effect.run` is where async work lives.

5. **Imperative intent names.** `case loadItems` (command) vs `case viewAppeared` / `case retryTapped` (event). Intents describe what *happened*; the reducer decides what to do.

6. **God-State struct.** A 40-property `State` that holds every screen's data. Split per feature; if two features share state, that's a higher-level container (App-level Store), not a kitchen sink.

7. **Forgetting `private(set)` on `state`.** Without it, callers outside the Store can mutate state and bypass the loop.

8. **Sync reducer that schedules async work via `DispatchQueue` instead of returning an `Effect`.** Looks like it works; breaks tests, breaks cancellation, breaks reasoning.

9. **Two `send` styles in production.** Sync `send(_:)` and async `send(_:) async` for the same ViewModel — callers don't know which to use. Keep async overloads in test targets only.

10. **MVI on a 3-field form.** State is `(name: String, email: String, isSubmitting: Bool)`; reducer is 5 lines of boilerplate. Use plain MVVM with `@Published` properties; revisit MVI if the screen actually grows a state machine.

11. **Reducer reaching out to `self.something`.** Reducers are top-level pure functions or static methods. Capturing `self` inside a reducer makes it impossible to unit-test without instantiating the store.

12. **Flavor A reducer that returns an `Effect` *and* mutates `state` based on the effect's not-yet-known result.** Reducers can only react to intents that have already been received. The result of an effect comes back as a new intent; the reducer handles it then.

13. **Bypassing the loop with manual UI/state mutation "to avoid copying `State`".** The perceived cost is imaginary — COW makes whole-`State` copy ~free (see "Performance"). Hand-patching a label or a sibling var to dodge a reducer pass trades a non-cost for a broken single-source-of-truth invariant.

## When to Escalate to TCA

Migrate from hand-rolled MVI to TCA (`arch-tca`) when **two or more** of these hold:

- **Reducer composition is a daily activity.** Multiple feature reducers need to be composed into a parent reducer with shared state slices. TCA's `@Reducer` + `Scope` solves this; hand-rolled solutions accrete bugs.
- **Exhaustive testing matters.** Every state mutation and every effect must be asserted. TCA's `TestStore` enforces it; hand-rolling exhaustive tests is possible but tedious.
- **Navigation as state.** `@Presents`, `StackState`, deep links via state mutation. Reimplementing this on top of plain MVI is reinventing TCA badly.
- **Dependency overrides per test / per preview.** TCA's `@Dependency` + `withDependencies { … }` is a complete system; closure-based DI starts to hurt at 10+ dependencies per feature.

If only **one** holds, stay on hand-rolled MVI — TCA's learning curve and binary size cost are real.

The migration is mechanical:
- `State` → `@ObservableState`-annotated struct.
- `Intent` → `Action` enum.
- `reduce(_:_:)` → `Reducer.body`.
- Closure dependencies → `@Dependency`.
- `Store` → TCA `Store` / `StoreOf<Feature>`.

See `arch-tca` "Migration paths" for the full procedure.
