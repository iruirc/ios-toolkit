---
name: arch-tca
description: "Use when implementing The Composable Architecture (TCA, swift-composable-architecture by Point-Free) in SwiftUI apps. Covers Reducer/State/Action, Effects, dependencies (@Dependency), the modern @Reducer + @ObservableState observation API, store scoping, navigation (@Presents, StackState/StackAction), bindings, side effects/cancellation, exhaustive vs non-exhaustive TestStore, when TCA is appropriate, and TCA-specific anti-patterns."
---

# The Composable Architecture (TCA)

Unidirectional, reducer-based state management for SwiftUI. State is a value type, actions describe events, a pure `Reducer` returns the next state plus `Effect`s, and the `Store` glues everything together. Heavily inspired by Elm/Redux but built around Swift value types, async/await, and the SwiftUI observation system.

> **Related skills:**
> - `arch-mvi` — TCA is a specific DSL implementation of MVI; if you don't need reducer composition, exhaustive testing, or `@Dependency`, plain MVI is lighter
> - `architecture-choice` — TCA is the non-default track for SwiftUI-only teams already fluent with reducers; choose it consciously, not by default
> - `arch-mvvm` — MVVM is the default SwiftUI architecture; pick TCA only when the trade-offs below pay off
> - `arch-swiftui-navigation` — TCA replaces NavigationPath/Router with `@Presents` + `StackState`; this skill covers the TCA-specific mechanics, the navigation skill covers the underlying SwiftUI primitives
> - `di-composition-root` — `@Dependency` covers TCA reducers only; CR still applies for app-level Store construction, UIKit screens, and any non-TCA modules
> - `error-architecture`, `net-architecture`, `persistence-architecture` — cross-cutting; TCA only changes how you call into them (via `Effect.run` from a Reducer)
> - `reactive-combine` — Effect previously bridged Combine publishers; modern TCA uses async/await first
> - `concurrency-architecture` — TCA owns Task lifecycle via `Effect.run` + `cancellable(id:)`; for non-TCA modules in the same app (UIKit screens, app-scoped services) the placement rules in `concurrency-architecture` still apply

## When Appropriate

| Scenario | Use TCA |
|---|---|
| Pure SwiftUI app, iOS 16+ (ideally 17+ for new observation API) | ✅ |
| Team already fluent with TCA / Elm / Redux | ✅ |
| Heavy state machines, complex multi-step flows, undo/redo | ✅ |
| Need exhaustive, deterministic tests of every state transition | ✅ |
| Multiple developers want strict ownership boundaries via reducer composition | ✅ |
| Throwaway prototype, 1–2 screens | ❌ Use MVVM or MVC |
| UIKit-first app | ❌ TCA's UIKit story is awkward; prefer MVVM+Coordinator |
| Team has no reducer experience and tight deadline | ❌ Learning curve is real; don't pick under pressure |
| You just want "less boilerplate than MVVM" | ❌ TCA has *more* boilerplate; the payoff is testability and composition, not brevity |

**Rule of thumb:** TCA is worth its weight when the project lives for years, has a rich domain, and the team values exhaustive tests over implementation speed. For everything else, default to MVVM (`arch-mvvm`) or Clean (`arch-clean`).

**Versions assumed:** TCA 1.7+ baseline (macro-based `@Reducer` + `@ObservableState`). `@Shared` examples require 1.10+. The library supports iOS 16+; the new observation API works natively on iOS 17+, with a backport for iOS 16.

| OS | Observation property wrapper |
|---|---|
| iOS 17+ / macOS 14+ | `@Bindable var store: StoreOf<Feature>` (system Observation) |
| iOS 16 / macOS 13 | `@Perception.Bindable var store: StoreOf<Feature>` + wrap body in `WithPerceptionTracking { … }` (TCA backport) |

Use the system `@Bindable` if your minimum is iOS 17+, otherwise use the backport everywhere — don't mix.

## Structure

```
Feature/
├── FeatureFeature.swift        # @Reducer: State, Action, body
├── FeatureView.swift           # SwiftUI view bound to Store<State, Action>
└── Models/
    └── FeatureModel.swift      # Domain entities (no TCA imports)
```

For larger features:

```
Feature/
├── FeatureFeature.swift
├── FeatureView.swift
├── Subfeatures/
│   ├── ItemDetailFeature.swift
│   └── ItemDetailView.swift
└── Models/
    └── FeatureModel.swift
```

The `*Feature.swift` file is *the* state machine — Domain code (entities, services) stays out of it.

## Core Concepts

### State

Value type. Holds everything the feature needs to render and decide its next move. Conform to `Equatable` (TestStore needs it) and mark with `@ObservableState`.

```swift
@Reducer
struct FeatureFeature {
    @ObservableState
    struct State: Equatable {
        var items: [Item] = []
        var isLoading = false
        var errorMessage: String?
        var query: String = ""
    }
}
```

### Action

Enum describing every event the feature reacts to. One enum, with cases grouped by intent. Conform to `Equatable` for tests.

```swift
extension FeatureFeature {
    enum Action: Equatable {
        // User actions
        case onAppear
        case queryChanged(String)
        case itemTapped(Item.ID)
        case retryButtonTapped

        // System / async results — keep distinct from user actions
        case itemsLoaded(Result<[Item], EquatableError>)

        // Bindings (see "Bindings" below)
        case binding(BindingAction<State>)
    }
}
```

**Naming convention:** user-driven actions read like UI events (`*Tapped`, `*Changed`); reducer-internal results read like facts (`*Loaded`, `*Failed`). Avoid imperative names (`loadItems`, `setLoading`) — actions are events, not commands.

`Error` is not `Equatable` and `TestStore` requires `Equatable` actions for diffing. Two options:

**Option A — split success/failure into two action cases:**
```swift
case itemsLoaded([Item])
case itemsLoadingFailed(message: String)  // pre-mapped to a stable string
```

**Option B — wrap with a tiny `EquatableError` shim:**
```swift
struct EquatableError: Error, Equatable {
    let underlying: Error
    init(_ error: Error) { self.underlying = error }
    static func == (lhs: Self, rhs: Self) -> Bool {
        type(of: lhs.underlying) == type(of: rhs.underlying)
            && lhs.underlying.localizedDescription == rhs.underlying.localizedDescription
    }
}
```

Option A is simpler and aligns with `error-architecture` (map to a `UserMessage` early). Option B is acceptable when the action is consumed only by the same feature.

Historical note: TCA <1.5 shipped a built-in `TaskResult<Success>` for exactly this. It still appears in older codebases — treat as legacy, prefer the two options above for new code.

### Reducer

Pure function `(inout State, Action) -> Effect<Action>`. Macro-generated boilerplate via `@Reducer`. The body uses the `Reduce` builder.

```swift
extension FeatureFeature {
    @Dependency(\.itemsClient) var itemsClient

    var body: some ReducerOf<Self> {
        BindingReducer()  // for binding(...) actions

        Reduce { state, action in
            switch action {
            case .onAppear:
                guard state.items.isEmpty else { return .none }
                state.isLoading = true
                return .run { send in
                    do {
                        let items = try await itemsClient.fetchAll()
                        await send(.itemsLoaded(.success(items)))
                    } catch {
                        await send(.itemsLoaded(.failure(EquatableError(error))))
                    }
                }

            case let .queryChanged(query):
                state.query = query
                return .none

            case let .itemTapped(id):
                // Navigation action — see Navigation section
                return .none

            case .retryButtonTapped:
                state.errorMessage = nil
                return .send(.onAppear)

            case let .itemsLoaded(.success(items)):
                state.isLoading = false
                state.items = items
                return .none

            case let .itemsLoaded(.failure(error)):
                state.isLoading = false
                state.errorMessage = error.localizedDescription
                return .none

            case .binding:
                return .none
            }
        }
    }
}
```

Rules:
- The reducer is **synchronous**. All async work happens in `Effect.run`.
- `state` is `inout` — mutate it directly; do not return a new state.
- Return `.none` for "no effect", `.run { send in … }` for async work, `.send(.someAction)` to dispatch another action.
- Never call services directly inside the reducer's switch — only through dependencies (`@Dependency`), and only inside `Effect`s.

### Store

The runtime container. App owns one root `Store<RootFeature.State, RootFeature.Action>`; views receive scoped child stores.

```swift
@main
struct MyApp: App {
    static let store = Store(initialState: RootFeature.State()) {
        RootFeature()
    }

    var body: some Scene {
        WindowGroup {
            RootView(store: Self.store)
        }
    }
}
```

For tests and previews, build a fresh store with overridden dependencies — see Testing.

## SwiftUI Integration (Modern Observation API)

With `@ObservableState` and TCA 1.7+, views read state directly from `Store` and don't need `WithViewStore`.

```swift
struct FeatureView: View {
    @Bindable var store: StoreOf<FeatureFeature>

    var body: some View {
        List {
            if store.isLoading {
                ProgressView()
            }
            ForEach(store.items) { item in
                Button(item.title) {
                    store.send(.itemTapped(item.id))
                }
            }
        }
        .searchable(text: $store.query.sending(\.queryChanged))
        .task { store.send(.onAppear) }
    }
}
```

Errors should not be modeled as a free-standing `String?` bound directly to `.alert`. Use `@Presents var alert: AlertState<Action.Alert>?` (see Navigation → Alerts below) — it integrates with the reducer, is testable, and dismisses correctly.

Key points:
- `@Bindable var store` (iOS 17+) or `@Perception.Bindable` (iOS 16 backport, requires wrapping body in `WithPerceptionTracking { … }`).
- `store.send(action)` to dispatch.
- `$store.someField.sending(\.actionCase)` to bridge a SwiftUI `Binding` to a custom action case without `BindingReducer` — useful for one-off bindings (the case must take the field's type as its single payload).
- Read scalar state as `store.foo` (the macro routes through observation).

Avoid `WithViewStore` and `viewStore.binding(...)` in new code — those are the pre-1.7 idioms and add boilerplate.

## Composition: Scope, ifLet, forEach

The reason TCA exists. You compose features by embedding their state and actions into a parent.

### Embedding a child feature

```swift
@Reducer
struct AppFeature {
    @ObservableState
    struct State: Equatable {
        var feed = FeedFeature.State()
        var settings = SettingsFeature.State()
    }

    enum Action {
        case feed(FeedFeature.Action)
        case settings(SettingsFeature.Action)
    }

    var body: some ReducerOf<Self> {
        Scope(state: \.feed, action: \.feed) {
            FeedFeature()
        }
        Scope(state: \.settings, action: \.settings) {
            SettingsFeature()
        }
        Reduce { state, action in
            // App-level coordination (cross-feature reactions)
            switch action {
            case .settings(.signOutButtonTapped):
                state.feed = FeedFeature.State()  // reset
                return .none
            default:
                return .none
            }
        }
    }
}
```

In the view, scope the child store down:

```swift
struct AppView: View {
    @Bindable var store: StoreOf<AppFeature>

    var body: some View {
        TabView {
            FeedView(store: store.scope(state: \.feed, action: \.feed))
            SettingsView(store: store.scope(state: \.settings, action: \.settings))
        }
    }
}
```

### Optional child (presentation)

For a child feature that may or may not be active (sheet, alert, drill-down):

```swift
@Reducer
struct AppFeature {
    @ObservableState
    struct State: Equatable {
        @Presents var editor: EditorFeature.State?
    }

    enum Action {
        case editor(PresentationAction<EditorFeature.Action>)
        case addButtonTapped
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .addButtonTapped:
                state.editor = EditorFeature.State()
                return .none
            case .editor(.presented(.saveButtonTapped)):
                state.editor = nil
                return .none
            case .editor:
                return .none
            }
        }
        .ifLet(\.$editor, action: \.editor) {
            EditorFeature()
        }
    }
}
```

`@Presents` + `PresentationAction` + `.ifLet(\.$child, ...)` is the canonical pattern. Use it for sheets, full-screen covers, alerts, confirmation dialogs, and single-step drill-down.

### Collections

```swift
struct State: Equatable {
    var items: IdentifiedArrayOf<ItemFeature.State> = []
}

enum Action {
    case items(IdentifiedActionOf<ItemFeature>)
}

var body: some ReducerOf<Self> {
    Reduce { state, action in /* parent logic */ }
        .forEach(\.items, action: \.items) {
            ItemFeature()
        }
}
```

In the view:

```swift
ForEach(store.scope(state: \.items, action: \.items)) { itemStore in
    ItemRow(store: itemStore)
}
```

`IdentifiedArray` (from `swift-identified-collections`) is required — it gives O(1) lookups by ID and is what `forEach` needs.

## Shared State (TCA 1.10+)

`@Shared` is a property wrapper that lets a single piece of state live in multiple features at once and stay synchronized — without piping it through every `Scope`. It can also be persisted (UserDefaults, file, in-memory) so the same value survives app launches.

```swift
@Reducer
struct ProfileFeature {
    @ObservableState
    struct State: Equatable {
        @Shared(.appStorage("currentUser")) var user: User?
        var isEditing = false
    }
    // ...
}

@Reducer
struct FeedFeature {
    @ObservableState
    struct State: Equatable {
        @Shared(.appStorage("currentUser")) var user: User?  // same key → same value
        var posts: [Post] = []
    }
}
```

Built-in persistence strategies:

| Strategy | Backing store | When to use |
|---|---|---|
| `.inMemory("key")` | Process memory, cleared on relaunch | Cross-feature transient state |
| `.appStorage("key")` | `UserDefaults` | Small primitives (flags, IDs, names) — never tokens or PII |
| `.fileStorage(URL)` | JSON file in app sandbox | Larger codable structures |

Custom strategies (Keychain, SQLite, server-synced) are written by conforming to `SharedReaderKey` / `SharedKey`.

**When to use `@Shared` vs `Scope`:**
- `Scope` — child *owns* its state, parent passes it down explicitly. Default for parent/child relationships.
- `@Shared` — multiple unrelated features need to read/write the *same* value (current user, theme, feature flags, cart). Removes boilerplate of threading state through every intermediate Scope.

**When to use `@Shared` vs `@Dependency`:**
- `@Dependency` — *behavior* (functions/services). Stateless from the reducer's perspective.
- `@Shared` — *state* that mutates and is observed across features.

**Caveats:**
- `@Shared` participates in `TestStore` exhaustivity — every mutation must be asserted.
- Never put auth tokens or PII in `@Shared(.appStorage(...))` — `UserDefaults` is plaintext, world-readable on jailbroken devices, and synced via iCloud Backup. Use a custom Keychain-backed `SharedKey` instead. See `swift-security`.
- For read-only consumers, prefer `@SharedReader` to make intent explicit.

## Navigation

### Single-step (sheet, cover, alert)

Modeled with `@Presents` (see "Optional child" above). The view binds to it:

```swift
struct AppView: View {
    @Bindable var store: StoreOf<AppFeature>

    var body: some View {
        NavigationStack {
            ContentView(store: store)
                .toolbar {
                    Button("Add") { store.send(.addButtonTapped) }
                }
        }
        .sheet(item: $store.scope(state: \.editor, action: \.editor)) { editorStore in
            EditorView(store: editorStore)
        }
    }
}
```

For alerts, TCA ships an `AlertState`/`ConfirmationDialogState` value type:

```swift
@Reducer
struct Feature {
    @ObservableState
    struct State: Equatable {
        @Presents var alert: AlertState<Action.Alert>?
    }

    enum Action {
        case deleteTapped
        case alert(PresentationAction<Alert>)

        enum Alert: Equatable {
            case confirmDelete
        }
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .deleteTapped:
                state.alert = AlertState {
                    TextState("Delete item?")
                } actions: {
                    ButtonState(role: .destructive, action: .confirmDelete) {
                        TextState("Delete")
                    }
                    ButtonState(role: .cancel) {
                        TextState("Cancel")
                    }
                }
                return .none

            case .alert(.presented(.confirmDelete)):
                // perform deletion
                return .none

            case .alert:
                return .none
            }
        }
        .ifLet(\.$alert, action: \.alert)
    }
}
```

In the view:

```swift
.alert($store.scope(state: \.alert, action: \.alert))
```

### Multi-step navigation (NavigationStack)

For drill-downs of arbitrary depth, use `StackState` + `StackAction`:

```swift
@Reducer
struct AppFeature {
    @ObservableState
    struct State: Equatable {
        var path = StackState<Path.State>()
        // root state…
    }

    enum Action {
        case path(StackAction<Path.State, Path.Action>)
        case itemTapped(Item.ID)
    }

    @Reducer
    enum Path {
        case detail(ItemDetailFeature)
        case edit(ItemEditFeature)
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .itemTapped(id):
                state.path.append(.detail(ItemDetailFeature.State(id: id)))
                return .none

            case let .path(.element(id: _, action: .detail(.editTapped))):
                if case let .detail(detailState) = state.path.last {
                    state.path.append(.edit(ItemEditFeature.State(item: detailState.item)))
                }
                return .none

            case .path:
                return .none
            }
        }
        .forEach(\.path, action: \.path)
    }
}
```

In the view:

```swift
NavigationStack(path: $store.scope(state: \.path, action: \.path)) {
    RootContent(store: store)
} destination: { store in
    switch store.case {
    case let .detail(store):
        ItemDetailView(store: store)
    case let .edit(store):
        ItemEditView(store: store)
    }
}
```

**What `@Reducer enum Path` generates:** the macro on an enum with reducer-typed cases synthesizes `Path.State` and `Path.Action` (each as their own enum mirroring the cases), the inter-case routing reducer, `@CasePathable` conformance, and the `store.case` accessor used in the view's `destination:` closure (which yields a typed `StoreOf<ChildFeature>` per case). You do not write `Path.State`/`Path.Action` by hand.

For type-erased deep links, mutate `state.path` directly from a reducer that handles the URL action.

When to choose `@Presents` vs `StackState`: `@Presents` for single optional child (one sheet, one alert), `StackState` for arbitrary-depth push stacks. Don't model a stack as nested `@Presents` — it falls apart at deep links and reset operations. See `arch-swiftui-navigation` for the underlying SwiftUI mechanics this maps onto.

## Bindings

For straightforward two-way bindings between view fields and state, use `@BindingState` (legacy) or the modern `BindableAction`/`BindingReducer` plus the `binding(...)` action case:

```swift
@Reducer
struct FormFeature {
    @ObservableState
    struct State: Equatable {
        var name: String = ""
        var notificationsEnabled: Bool = false
    }

    enum Action: BindableAction {
        case binding(BindingAction<State>)
        case submitTapped
    }

    var body: some ReducerOf<Self> {
        BindingReducer()
        Reduce { state, action in
            switch action {
            case .binding(\.notificationsEnabled):
                // Side effect on a specific binding change
                return .run { _ in /* persist */ }
            case .binding, .submitTapped:
                return .none
            }
        }
    }
}
```

In the view (iOS 17+ with `@Bindable`):

```swift
TextField("Name", text: $store.name)
Toggle("Notifications", isOn: $store.notificationsEnabled)
```

`BindingReducer` handles every `binding(...)` action by writing through the keypath into state. Trap specific keypaths in your own `Reduce` to react to them.

**Notes on `case .binding(\.someField)`:**
- Works for top-level `State` fields. For nested fields use the full keypath (`\.someNested.field`).
- The matched field must be `Equatable` (otherwise the keypath won't conform to the `Equatable`-keyed `BindingAction` pattern).
- Don't perform expensive work directly in this branch — it fires on every keystroke/toggle. Debounce via `cancellable(id:, cancelInFlight: true)` for things like search or autosave.

## Effects and Side Work

`Effect<Action>` is how you run async work. The most common form is `Effect.run`:

```swift
return .run { send in
    let items = try await itemsClient.fetchAll()
    await send(.itemsLoaded(.success(items)))
} catch: { error, send in
    await send(.itemsLoaded(.failure(EquatableError(error))))
}
```

### Cancellation

Tag effects with a cancellation ID, then cancel by the same ID:

```swift
enum CancelID { case search }

case let .queryChanged(query):
    state.query = query
    return .run { [query] send in
        try await Task.sleep(for: .milliseconds(300))  // debounce
        let results = try await searchClient.search(query)
        await send(.searchCompleted(results))
    }
    .cancellable(id: CancelID.search, cancelInFlight: true)
```

`cancelInFlight: true` cancels any prior effect with the same ID before starting the new one — built-in debounce.

To cancel from another action:

```swift
case .stopButtonTapped:
    return .cancel(id: CancelID.search)
```

### Combining effects

```swift
return .merge(
    .run { send in await send(.userLoaded(try await api.fetchUser())) },
    .run { send in await send(.feedLoaded(try await api.fetchFeed())) }
)
```

`.merge` runs concurrently; `.concatenate` runs serially.

### When NOT to use Effect

- **Pure state changes** — just mutate `state` and return `.none`.
- **Synchronous computation** — do it inline in the reducer.
- **One-off `Task { }` from the view** — TCA has no opinion if it's truly view-local (analytics fire-and-forget); but most async work belongs in a reducer effect for testability.

## Debugging

`_printChanges()` is the built-in reducer modifier that logs every action and the resulting state diff to the console.

```swift
var body: some ReducerOf<Self> {
    Reduce { state, action in /* ... */ }
        ._printChanges()
}
```

Use sparingly:
- **Local debugging only.** Wrap in `#if DEBUG` and remove before merge — never commit a reducer with `_printChanges()` in `body` long-term.
- **Never on reducers handling auth, payments, or PII.** Tokens, passwords, profile data all end up in the console log and can leak via attached debugger, system logs, or shared screen recordings. Same risk for any logging middleware. See `swift-security` (M6 — Inadequate Privacy Controls) and the TCA-specific note there about action payloads showing up in `TestStore` failure diffs.

For ongoing observability in shipped builds, build a dedicated logging reducer that explicitly redacts sensitive cases instead of using `_printChanges()`.

## Dependencies

`@Dependency` is the dependency-injection mechanism for TCA reducers. Each external service is registered as a `DependencyKey` and read via `@Dependency(\.foo)` inside a reducer or effect. It does **not** replace your app-level Composition Root — that still constructs the root `Store`, builds non-TCA modules (UIKit screens, app-wide singletons), and overrides the live `DependencyValues` for the live runtime via `withDependencies { … }`.

### Defining a client

```swift
struct ItemsClient: Sendable {
    var fetchAll: @Sendable () async throws -> [Item]
    var save: @Sendable (Item) async throws -> Void
}

extension ItemsClient: DependencyKey {
    static let liveValue = Self(
        fetchAll: { try await APIClient.shared.fetchItems() },
        save: { try await APIClient.shared.save($0) }
    )

    static let testValue = Self(
        fetchAll: { unimplemented("ItemsClient.fetchAll") },
        save: { _ in unimplemented("ItemsClient.save") }
    )

    static let previewValue = Self(
        fetchAll: { Item.mockList },
        save: { _ in }
    )
}

extension DependencyValues {
    var itemsClient: ItemsClient {
        get { self[ItemsClient.self] }
        set { self[ItemsClient.self] = newValue }
    }
}
```

Each client is a **struct of closures**, not a protocol. This is intentional — closure-based clients can be partially overridden in tests (`itemsClient.fetchAll = { … }`) without writing a full mock.

### Built-in dependencies

TCA ships clients for common runtime values:

| Dependency | Replaces |
|---|---|
| `\.uuid` | `UUID()` |
| `\.date` | `Date()` |
| `\.continuousClock`, `\.suspendingClock` | `Task.sleep`, timers |
| `\.mainQueue`, `\.mainRunLoop` | DispatchQueue scheduling |
| `\.locale`, `\.calendar`, `\.timeZone` | system locale/calendar |
| `\.openURL` | `UIApplication.shared.open` |

**Never call `UUID()`, `Date()`, `Task.sleep`, or `DispatchQueue.main.async` directly inside a reducer or effect.** Always go through `@Dependency`. Otherwise the test is non-deterministic.

### Composition Root integration

For the live app, dependencies resolve to their `liveValue` by default — no wiring needed. The Composition Root (`SceneDelegate` / `@main App`) only constructs the root `Store`. If a non-trivial dependency needs runtime config (auth state, user ID), inject that into the live client at construction time, not into the reducer:

```swift
extension ItemsClient {
    static func live(authStore: AuthStore) -> Self {
        Self(
            fetchAll: { try await APIClient(token: authStore.token).fetchItems() },
            ...
        )
    }
}

// In Composition Root:
let store = withDependencies {
    $0.itemsClient = .live(authStore: authStore)
} operation: {
    Store(initialState: AppFeature.State()) { AppFeature() }
}
```

See `di-composition-root` for what else belongs in CR. TCA dependencies are **task-local** — `withDependencies { … }` overrides apply for the duration of that operation, including any effects spawned from the resulting store.

## Testing

`TestStore` lets you drive the reducer in tests and assert *every* state mutation and *every* effect.

### Exhaustive test

```swift
final class FeatureFeatureTests: XCTestCase {
    func test_onAppear_loadsItems() async {
        let store = TestStore(initialState: FeatureFeature.State()) {
            FeatureFeature()
        } withDependencies: {
            $0.itemsClient.fetchAll = { [Item.fixture] }
        }

        await store.send(.onAppear) {
            $0.isLoading = true
        }

        await store.receive(\.itemsLoaded.success) {
            $0.isLoading = false
            $0.items = [.fixture]
        }
    }
}
```

Rules:
- Every `send` must list every state mutation in the trailing closure. Anything not asserted = test failure.
- Every effect must be received and asserted with `receive(\.someCase)`.
- Unfinished effects at end of test = test failure (forces explicit cancellation).

This **exhaustivity** is the headline TCA testing feature. It catches every accidental state mutation and every leaked effect.

### Non-exhaustive (focused) test

For larger features where you only care about one transition:

```swift
let store = TestStore(initialState: AppFeature.State()) {
    AppFeature()
} withDependencies: {
    $0.itemsClient.fetchAll = { [Item.fixture] }
}
store.exhaustivity = .off

await store.send(.onAppear)
await store.receive(\.feed.itemsLoaded) {
    $0.feed.items = [.fixture]
}
```

Use sparingly. The default exhaustive mode is what makes TCA tests trustworthy.

### Testing dependencies

`unimplemented(...)` in `testValue` makes the test fail loudly if you forget to override a dependency. Rely on it — don't ship a `testValue` that returns plausible defaults.

```swift
static let testValue = Self(
    fetchAll: unimplemented("ItemsClient.fetchAll"),
    save: unimplemented("ItemsClient.save")
)
```

### Testing time

```swift
let clock = TestClock()
let store = TestStore(initialState: SearchFeature.State()) {
    SearchFeature()
} withDependencies: {
    $0.continuousClock = clock
    $0.searchClient.search = { _ in [.mock] }
}

await store.send(.queryChanged("foo")) { $0.query = "foo" }
await clock.advance(by: .milliseconds(300))
await store.receive(\.searchCompleted) { $0.results = [.mock] }
```

`TestClock` lets you control debounce/timer effects deterministically. Never use real `Task.sleep` in tests — it makes them slow and flaky.

## When NOT to Reach for TCA

| Symptom | What to do instead |
|---|---|
| "Just one screen with a form" | MVVM with `@Observable` — TCA's overhead isn't worth it |
| "We just want unidirectional flow" | Use `arch-mvi` — covers Pure MVI and MVVM+Single State variants without TCA's DSL overhead |
| "Need DI" | TCA's `@Dependency` is for TCA reducers only; for app-wide DI use `di-composition-root` |
| "We have UIKit screens" | TCA's UIKit story is awkward; bridge via `UIHostingController` for SwiftUI islands or stick with MVVM |
| "Team is new to TCA" | Don't pick TCA on a deadline. The learning curve is steep and the cost of misuse is real |

## Common Mistakes

1. **Calling services directly from the view** — `APIClient.shared.fetch()` in `.task { }` bypasses the reducer and breaks testability. All side effects go through actions and `Effect.run`.

2. **Calling `UUID()`, `Date()`, `Task.sleep` inside a reducer or effect** — non-deterministic, untestable. Use `@Dependency(\.uuid)`, `\.date`, `\.continuousClock` instead.

3. **Imperative action names** — `case loadItems` (command) vs `case onAppear` / `case retryButtonTapped` (event). Actions describe what *happened*, not what to *do*. The reducer decides what to do.

4. **Mutating state inside `Effect.run`** — you can't (state is `inout` in the reducer, not in effects). Send a follow-up action with the result and mutate state in the reducer.

5. **Forgetting `cancellable(id:)` on long effects** — leaked subscriptions, stale results overwriting fresh ones. Tag every effect that competes for the same conceptual slot (search debounce, polling, in-flight API call) with a cancel ID.

6. **`Equatable` on `Action` includes non-Equatable payloads** — wrap errors with `EquatableError`, or split success/failure. TestStore's diff machinery requires `Equatable`.

7. **`forEach` with a plain `Array`** — must be `IdentifiedArrayOf<...>`. Otherwise compile error or O(n) lookups.

8. **Modeling a navigation stack as nested `@Presents`** — falls apart at depth 3+, breaks deep links. Use `StackState` for stacks of arbitrary depth.

9. **Dependency leak in `liveValue`** — calling `URLSession.shared` or a singleton inside `liveValue` couples your live runtime to global state. Inject runtime config via a factory (`ItemsClient.live(authStore:)`) and override in CR with `withDependencies { … }`.

10. **Skipping `unimplemented(...)` in `testValue`** — silent fallback values hide missing dependency overrides in tests. Use `unimplemented(...)` everywhere; the failure is the feature.

11. **Asserting effects with non-exhaustive `exhaustivity = .off` by default** — defeats the whole point of TCA testing. Use `.off` only for narrow integration tests; default to exhaustive.

12. **Reaching for TCA because "MVVM doesn't scale"** — MVVM scales fine with discipline (small ViewModels, Coordinator, separation of side effects). TCA scales by making boilerplate uniform across a team. They're different trade-offs, not different rungs.

13. **Mixing TCA with another architecture per feature** — pick one. A half-TCA app where some features use plain `@Observable` ViewModels and others use Reducers is harder to maintain than either pure choice.

14. **Custom `Equatable` on State that ignores fields** — common motivation: a transient cache, a closure, or a non-Equatable third-party value lives on State and you write a manual `==` that skips it to make compilation pass. TestStore diff then silently misses mutations to *every* skipped field, and exhaustivity becomes a lie. Either move the offending field out of State (into a `@Dependency` client or computed property), or accept that nothing involving that field can ever be asserted in a test.

15. **Long-lived effects bound to a screen's lifetime** — TCA effects tied to a transient `@Presents` child are auto-cancelled when the child is dismissed. Long-running app-level work belongs in a long-lived reducer (the root), not in a child that may be torn down.

## Migration Paths

### From MVVM → TCA

1. Pick **one** feature first, not the whole app. TCA is invasive — converting the whole app at once is a yak shave.
2. Keep the existing service layer (Repository, APIClient). Wrap each used service in a TCA `Client` struct of closures with `liveValue` calling the existing service.
3. Convert `@Observable` ViewModel state into a `@Reducer` State + Action enum. ViewModel methods become action cases; their bodies become reducer branches.
4. Replace `Task { ... }` calls inside ViewModel with `Effect.run` returning actions.
5. Replace `Coordinator.show(...)` calls with `state.path.append(...)` (or `state.editor = ...` for sheet) and bind from the View via `@Presents` / `StackState`.
6. Write the TestStore tests **first** for the converted feature — that's where the payoff lands.

### From plain SwiftUI → TCA

Most plain-SwiftUI apps that consider TCA actually want MVVM with `@Observable` first. Try that. If it still feels chaotic after a real attempt — then TCA. See `architecture-choice` for the formal decision flow.
