---
name: di-factory
description: "Use when working with the Factory DI library by hmlongco (FactoryKit) in iOS/macOS apps — registration, property-wrapper injection, scopes, modular containers, contexts, and testing. For Composition Root see di-composition-root; for Coordinator wiring see di-module-assembly."
---

# Factory DI Patterns (hmlongco)

This skill provides Factory-specific guidelines: `Container`/`SharedContainer` model, registration via computed properties, property-wrapper injection, scopes, parameterized factories, modular containers, contexts, and testing.

> **Versions assumed:** Factory 2.5+ (`FactoryKit` is the canonical module name; older code may still import `Factory`). Swift 5.10+, iOS 13+. The Swift Testing trait API requires Factory 2.5+.

> **Related skills:**
> - `di-composition-root` — where the Container lives, how bootstrap starts, sync vs async, scopes as a strategy (Factory only covers the container itself; the CR is where it's created and operated)
> - `di-module-assembly` — how Coordinators get dependencies via `CoordinatorFactory` / `ModuleFactory`. **Canonical wiring is identical to the Swinject variant: only `AppDependencyContainer` imports `FactoryKit` and resolves via `Container.shared.foo()`; ModuleFactory and feature `*Factory`/`*Assembly` types receive a narrow `*FeatureDependencies` protocol through init and never see `Container` / `Container.shared`.** "ModuleFactory calls `Container.shared.foo()` directly" is the Service Locator shortcut and is explicitly rejected — see the "Coordinator and Module Assembly" section below
> - `di-swinject` — alternative DI framework. Comparison table at the end of this skill
> - `pkg-spm-design` — Factory, just like Swinject, **must not be imported into the main target of an SPM package**. Modular `extension Container` per feature lives in the **app target**, see "Modular Containers" section below
> - `arch-tca` — TCA uses its own `@Dependency` system; don't mix it with Factory inside TCA features

## When to Use

**Factory is the right choice when:**
- You want compile-time safety on registrations (factory missing → code won't compile)
- You want a property-wrapper style (`@Injected`) instead of manual resolve
- A modern SwiftUI app, with active use of `@Observable` / Observation
- You need contexts (preview/test/debug overrides) out of the box
- The graph is medium-sized (10–100 services) — Factory scales better than manual without Swinject's runtime overhead

**Consider alternatives:**
- < 10 services, monolith → Manual DI on `lazy var` (see `di-composition-root`, "Manual DI" section)
- Legacy on Swinject, rewriting is more expensive → Stick with Swinject (see `di-swinject`)
- A whole TCA feature → use `@Dependency` by Point-Free, not Factory
- Need runtime-registered factories with arbitrary arguments and name-based lookup → Swinject (`name:` parameter and autoregister)

## Installation

Swift Package Manager:

```swift
// Package.swift
.package(url: "https://github.com/hmlongco/Factory.git", from: "2.5.0")

// Targets
.product(name: "FactoryKit", package: "Factory"),               // app target
.product(name: "FactoryTesting", package: "Factory"),           // ONLY test target
```

```swift
import FactoryKit            // in production code (NOT `import Factory` — that's the deprecated name)
import FactoryTesting        // in test targets (provides the `.container` Suite trait for Swift Testing)
```

## Core Concepts

### Container

Registrations live as **computed properties in extension Container**. Each such property returns a `Factory<T>` that knows how to resolve an instance. The `Container` itself is a final class with `static let shared`, but you can (and should) **subclass / have your own** for modularity — see "Modular Containers" below.

```swift
import FactoryKit

extension Container {
    var userService: Factory<UserServiceProtocol> {
        self { UserService(networkClient: self.networkClient(), storage: self.keychainStorage()) }
    }

    var networkClient: Factory<HTTPClient> {
        self { URLSessionHTTPClient() }.singleton
    }

    var keychainStorage: Factory<KeychainStorage> {
        self { KeychainStorage(service: "com.example.app") }.singleton
    }
}
```

**What matters:**
- `self { … }` is syntactic sugar over `Factory(self) { … }`. Use the short form.
- The property name **becomes the registration key** (`StaticString = #function`). Don't rename it in production without a migration — old `register` overrides will be lost.
- The graph is wired **through the same `self`** inside the closure: `self.networkClient()`. NOT through `Container.shared.networkClient()` — otherwise isolation breaks when a separate `Container()` is created for tests or modules.

### Factory<T>

`Factory<T>` is a value type, not the instance itself. It's resolved via `callAsFunction`:

```swift
let service = Container.shared.userService()    // equivalent to .resolve()
```

Creating a `Factory` is cheap; the actual instance only appears on call.

### Composition Root

Factory **does not replace the Composition Root** — it implements it via a `Container`. CR logic (where the `Container` is created, what's registered in it, when bootstrap runs) lives in the `di-composition-root` skill.

```swift
// SceneDelegate / @main App
@main
struct MyApp: App {
    init() {
        Container.shared.bootstrap()    // see AutoRegistering below
    }
    var body: some Scene { … }
}
```

**Never reach for `Container.shared` from domain layers** — only via `@Injected` or an explicit constructor. Otherwise you get a Service Locator (see Common Mistakes).

## Resolution: Property Wrappers

### `@Injected` — eager, sync

Resolved **at the moment the owner is created**. Use for required dependencies.

```swift
final class ProfileViewModel: ObservableObject {
    @Injected(\.userService) private var userService
    @Injected(\.analyticsService) private var analytics

    func load() async {
        let user = try await userService.fetchCurrent()
        analytics.track(.profileLoaded)
    }
}
```

`\.userService` is a KeyPath to the `Container.userService` property.

### `@LazyInjected` — lazy, sync

Resolved on first access. Use when the dependency isn't always needed or the owner is created frequently.

```swift
final class AuthService {
    @LazyInjected(\.biometricAuthenticator) private var biometric
    // BiometricAuthenticator is created only if biometrics is actually invoked
}
```

### `@WeakLazyInjected` — weak reference

Use to **break cycles** or for optionally-cached resources.

```swift
final class CoordinatorRoot {
    @WeakLazyInjected(\.imageCache) private var imageCache: ImageCache?
    // imageCache lives while someone else retains it
}
```

### `@InjectedObservable` — for @Observable view models (Factory 2.4+)

```swift
@Observable
final class ContentViewModel {
    @ObservationIgnored @Injected(\.repository) private var repository
}

struct ContentView: View {
    @InjectedObservable(\.contentViewModel) var viewModel
    var body: some View { … }
}
```

`@ObservationIgnored` is mandatory on `@Injected` inside an `@Observable` class — otherwise the property becomes part of the change graph and every resolve triggers a UI update.

### Direct resolution (no property wrappers)

When `@Injected` doesn't fit (`ParameterFactory`, non-object, manual assembly):

```swift
let service = Container.shared.userService()
let detail = Container.shared.detailViewModel(itemId)   // see ParameterFactory
```

## Scopes

Scope is controlled by a modifier after `self { … }`. Default is `.unique` (a new instance on every resolve).

| Scope | Behavior | When to use |
|---|---|---|
| `.unique` (default) | New instance every time | ViewModels, Coordinators, stateful |
| `.singleton` | One global instance **per process** (not bound to the Container) | A single external resource (Keychain wrapper) |
| `.cached` | One instance **per this Container**, until `reset()` | Services (NetworkClient, Database) |
| `.shared` | Weak: alive while someone holds a strong reference; otherwise recreated | Optional shared caches |
| `.graph` | One instance **within a single top-level resolve** | Shared state inside a single feature's graph |

```swift
extension Container {
    var networkClient: Factory<HTTPClient> {
        self { URLSessionHTTPClient() }.cached         // singleton-within-this-Container
    }
    var keychainStorage: Factory<KeychainStorage> {
        self { KeychainStorage(service: "...") }.singleton  // process-global
    }
    var imageCache: Factory<ImageCache> {
        self { ImageCache() }.shared                   // weak
    }
    var profileViewModel: Factory<ProfileViewModel> {
        self { ProfileViewModel() }                    // .unique by default
    }
}
```

**`.cached` vs `.singleton`:**
- `.cached` — the instance lives in `Container.shared` (or another `Container`), cleared via `reset()`. **This is what you usually want** for testability.
- `.singleton` — the instance **survives** `Container.reset()`. Use only for system resources whose destruction is dangerous (Keychain handle, OSLog subsystem).

**Time-to-live:** `self { … }.singleton.timeToLive(60 * 5)` — recreates the instance after N seconds. Useful for tokens / short-lived caches.

## Parameterized Factories

When the instance requires a runtime parameter (screen id, flow config):

```swift
extension Container {
    var detailViewModel: ParameterFactory<String, DetailViewModel> {
        self { itemId in
            DetailViewModel(itemId: itemId, service: self.itemService())
        }
    }
}

// Resolve
let vm = Container.shared.detailViewModel("item-123")
```

**Multiple parameters** — via tuple:

```swift
extension Container {
    var chatViewModel: ParameterFactory<(String, String), ChatViewModel> {
        self { (roomId, userId) in
            ChatViewModel(roomId: roomId, userId: userId, chat: self.chatService())
        }
    }
}

let vm = Container.shared.chatViewModel(("room-1", "user-42"))
```

**Limitations:**
- `@Injected` does NOT work with `ParameterFactory` — there's no way to pass parameters before the wrapper is initialized. Use `Container.shared.foo(arg)` directly or pass the dependency explicitly through init.
- Caching (`.cached`/`.singleton`) by default **ignores parameters** — the same instance is returned for different ids. For key-by-parameters use `scopeOnParameters` (Factory 2.5+).

### ParameterFactory vs factory function

`ParameterFactory` is the canonical path the author recommends. Use it **by default**: you get scopes (`.cached.scopeOnParameters`), contexts (`.onTest`/`.onPreview`), `register` overrides in tests, and a uniform style with the rest of your `var foo: Factory<...>`.

A plain factory function — only when **none of the above is needed** and you want named arguments:

```swift
// Acceptable ONLY when: no need for .cached/.shared, no .onTest override, no register-based mocks
extension Container {
    func chatViewModel(roomId: String, userId: String) -> ChatViewModel {
        ChatViewModel(roomId: roomId, userId: userId, chat: self.chatService())
    }
}
```

| Criterion | `ParameterFactory` | Factory function |
|---|---|---|
| Scopes (`.cached`, `.singleton`) | ✅ via `scopeOnParameters` | ❌ always a new instance |
| Contexts (`.onTest`, `.onPreview`) | ✅ | ❌ |
| `register` override in tests | ✅ | ❌ — only by swapping the implementation |
| Named arguments | ❌ — tuple for 2+ | ✅ |
| Suited for | ViewModels with runtime ids, any prod case | One-liner factories with no lifecycle |

**Rule:** if there's at least one parameter and you need cache/context/mocks — `ParameterFactory`. Otherwise — choose by API aesthetics.

## AutoRegistering — Bootstrap Hook

If you need to run code **once before the first resolution** (register defaults, read config, hook up contexts):

```swift
extension Container: AutoRegistering {
    public func autoRegister() {
        // Conditional defaults
        #if DEBUG
        analyticsService.register { NoOpAnalytics() }
        #endif

        // Context-bound overrides
        networkClient.onPreview { MockHTTPClient(scenario: .happy) }
        userService.onTest { InMemoryUserService() }
    }
}
```

`autoRegister()` is called lazily on the first resolve and only once per `Container` instance.

**Use it for:**
- Default overrides in DEBUG/Test/Preview
- Registering factory methods from sub-modules (see below)
- Configuration that depends on bundle / env

**Do NOT use it for:**
- Heavy initialization (DB, network) — that belongs in CR `bootstrap()`
- Business logic

## Modular Containers (organization in the app target)

> **Rule first:** `import FactoryKit` **inside an SPM package is forbidden** — by the same rigid rule that applies to Swinject. This is required by `pkg-spm-design` (universal rule 1). A package always accepts its dependencies through `init(dependencies:)`. What's described below is **organization in the app target**, not in SPM packages.

The main modular pattern with Factory: one `Container.shared`, registrations split into files in the app target — one file per feature/layer:

```
App/
├── Composition/
│   ├── Container+Networking.swift      // apiClient, httpMiddleware
│   ├── Container+Persistence.swift     // database, repositories
│   ├── Container+Profile.swift         // profileService, profileViewModel
│   ├── Container+Settings.swift        // settingsService, settingsViewModel
│   └── Container+Bootstrap.swift       // AutoRegistering, context overrides
├── App.swift
└── ...
```

Each file is an `extension Container` with its own properties:

```swift
// App/Composition/Container+Profile.swift
import FactoryKit
import ProfileFeature       // SPM package — no Factory inside

extension Container {
    var profileService: Factory<ProfileServiceProtocol> {
        self { ProfileService(api: self.apiClient()) }.cached
    }
    var profileModule: Factory<ProfileModule> {
        self { ProfileModule(dependencies: .init(
            api: self.apiClient(),
            logger: self.logger()
        )) }
    }
}
```

```swift
// App/Composition/Container+Networking.swift
import FactoryKit

extension Container {
    var apiClient: Factory<APIClient> {
        self { URLSessionAPIClient(config: .production) }.cached
    }
}
```

`Container.shared.profileModule()` works in the host app, in previews, and in tests. The `ProfileFeature` SPM package contains zero lines about Factory — it accepts its dependencies via `init(dependencies: ProfileFeatureDependencies)`.

**Downside:** all extensions share one `Container` namespace. A name collision is undefined behavior (one property silently overrides another, because the key is the property name). Solution: feature prefixes (`profileService`, `profileViewModel`) or your own `SharedContainer` (see below).

### Custom `SharedContainer` (for very large apps)

When the monorepo grows to dozens of features and the name-collision risk is real:

```swift
// App/Composition/ProfileContainer.swift
public final class ProfileContainer: SharedContainer {
    public static let shared = ProfileContainer()
    public let manager = ContainerManager()
    public init() {}
}

extension ProfileContainer {
    var service: Factory<ProfileServiceProtocol> {
        self { ProfileService() }.cached
    }
}
```

```swift
// Usage
let svc = ProfileContainer.shared.service()
// or with a property wrapper:
@Injected(\ProfileContainer.service) var service
```

`@Injected(\KeyPath)` supports any `SharedContainer`, not just the base `Container`. This file also lives **in the app target**, not in a package.

### When to pick which

| Situation | Pick |
|---|---|
| One team, < 30 features | `extension Container` with prefixes in a single namespace |
| Multiple teams / 30+ features / real risk of name collisions | A custom `SharedContainer` per feature group |
| SPM package (any archetype) | Never Factory inside. `init(dependencies:)` + registration in the app target |

See also `pkg-spm-design`'s **library/feature archetypes** section — it describes the general contract for how a package accepts dependencies through `init`, which works with any DI framework (Swinject / Factory / manual).

## Contexts (preview / test / debug overrides)

Factory can override registrations **based on the launch context** without modifying production code:

```swift
extension Container: AutoRegistering {
    public func autoRegister() {
        analyticsService
            .onTest { NoOpAnalytics() }
            .onPreview { LoggingAnalytics() }
            .onDebug { VerboseAnalytics() }
            .onSimulator { SimulatorOnlyAnalytics() }

        // Launch arguments: -mockMode 1
        networkClient.onArg("mockMode") { MockHTTPClient() }
    }
}
```

| Modifier | When it triggers |
|---|---|
| `.onTest { … }` | XCTest / Swift Testing process |
| `.onPreview { … }` | SwiftUI Preview (`XCODE_RUNNING_FOR_PREVIEWS == 1`) |
| `.onDebug { … }` | DEBUG build |
| `.onSimulator { … }` | iOS Simulator |
| `.onDevice { … }` | Real device |
| `.onArg("name") { … }` | Launch argument `-name 1` |

Contexts are **additive** — several can be chained. The production closure (the one inside `self { … }`) is the fallback if no context is active.

## Coordinator and Module Assembly

The architectural pattern (`AppDependencies` → `*FeatureDependencies` → `CoordinatorFactory` → `ModuleFactory` → `Assembly`) **doesn't change** — only the `AppDependencyContainer` implementation does. See `di-module-assembly` for the full example. The difference vs Swinject:

```swift
// Swinject
final class AppDependencyContainer: AppDependencies {
    private let container: Container
    var userService: UserServiceProtocol { container.resolve(UserServiceProtocol.self)! }
}

// Factory
@MainActor
final class AppDependencyContainer: AppDependencies {
    var userService: UserServiceProtocol { Container.shared.userService() }
    var analyticsService: AnalyticsServiceProtocol { Container.shared.analyticsService() }
    // …
}
```

`import FactoryKit` lives **only** in `AppDependencyContainer` (and the `extension Container` files that register services). `ModuleFactoryImp`, `CoordinatorFactoryImp`, feature `*Factory`/`*Assembly`, Coordinators, ViewModels and Views must not import `FactoryKit` and must not touch `Container` / `Container.shared`. They receive `AppDependencies` / `*FeatureDependencies` and feature factory protocols through init.

```swift
// ✅ Correct — ModuleFactoryImp receives AppDependencies, NOT Container
@MainActor
final class ModuleFactoryImp: ProfileModuleFactory {
    private let dependencies: AppDependencies
    init(dependencies: AppDependencies) { self.dependencies = dependencies }

    func makeProfileModule() -> ModuleComponents<ProfileViewController, ProfileViewModel> {
        ProfileAssembly.assemble(dependencies: dependencies)    // protocol upcast: AppDependencies → ProfileFeatureDependencies
    }
}
```

```swift
// ❌ Wrong — ModuleFactoryImp imports FactoryKit and reaches into Container.shared
import FactoryKit                                              // ← never here

@MainActor
final class ModuleFactoryImp: ProfileModuleFactory {
    func makeProfileModule() -> ModuleComponents<ProfileViewController, ProfileViewModel> {
        ProfileAssembly.assemble(
            dependencies: Container.shared                     // ← Service Locator
        )
    }
}
```

```swift
// ❌ Wrong — Coordinator accepts the container instead of the factory
final class AppCoordinator {
    init(window: UIWindow, container: Container) { … }         // ← never accept Container/Resolver
}
```

> **Shortcut inside ModuleFactory.** It can be tempting to let `ModuleFactory` call `Container.shared.foo()` directly and drop the `AppDependencyContainer` facade. Don't do this: it disguises a Service Locator, breaks Coordinator tests (no init injection — no mock), and zeroes out compile-time visibility of the dependency surface. The pattern is the same on 1, 5, and 50 screens — the cost of the facade pays for itself the first time you have a regression.

> **`@Injected` exception.** `@Injected` is acceptable inside ViewModels/Coordinators **only** when the project has explicitly opted into property-wrapper injection at the architecture level and there is no ModuleFactory layer for that feature. In a project that uses the Module Assembly chain (the default scaffold), `@Injected` on a ViewModel bypasses the chain — the ViewModel goes through constructor injection from `*Assembly`, not via `@Injected`. Mixing both styles in the same feature produces hidden dependencies that don't show up in `ProfileAssembly.assemble(dependencies:)` signatures.

## Testing

### Unit Tests — Direct Injection (preferred)

As with Swinject — for ViewModels, a direct `init(...)` with mocks is best:

```swift
final class ProfileViewModelTests: XCTestCase {
    func test_load_success() async throws {
        let mock = MockUserService(result: .success(.fixture))
        let sut = ProfileViewModel(userService: mock)

        await sut.load()

        XCTAssertEqual(sut.state, .loaded(.fixture))
    }
}
```

This only works if the ViewModel accepts dependencies via init. For the `@Injected` case — see below.

### Override via `register` — for @Injected

```swift
final class ProfileViewModelTests: XCTestCase {
    override func setUp() {
        super.setUp()
        Container.shared.reset()        // CRITICAL: otherwise an override from a previous test leaks in
    }

    override func tearDown() {
        Container.shared.reset()
        super.tearDown()
    }

    func test_load_success() async {
        Container.shared.userService.register {
            MockUserService(result: .success(.fixture))
        }

        let sut = ProfileViewModel()    // @Injected picks up the mock

        await sut.load()
        XCTAssertEqual(sut.state, .loaded(.fixture))
    }
}
```

### Swift Testing — `.container` trait (Factory 2.5+)

`FactoryTesting` provides a Suite trait that automatically scopes a Container per test. No manual `reset()` calls are needed:

```swift
import Testing
import FactoryTesting
@testable import App

@Suite(.container)
struct ProfileViewModelTests {

    @Test func loadSuccess() async {
        Container.shared.userService.register {
            MockUserService(result: .success(.fixture))
        }
        let sut = ProfileViewModel()
        await sut.load()
        #expect(sut.state == .loaded(.fixture))
    }

    @Test func loadFailure() async {
        Container.shared.userService.register {
            MockUserService(result: .failure(TestError.network))
        }
        let sut = ProfileViewModel()
        await sut.load()
        #expect(sut.state == .error)
    }
}
```

Each `@Test` gets a fresh `Container.shared` (via `@TaskLocal`). Tests can run **in parallel** without interference — that's the main argument for moving Factory projects to Swift Testing.

### Reset gotchas

| Scenario | Behavior |
|---|---|
| `.unique` | No caches — `reset()` doesn't affect anything |
| `.cached` | Cleared via `Container.shared.reset()` |
| `.singleton` | NOT cleared by a plain `reset()`. Use `reset(options: .all)` |
| Override via `register` | Cleared by a plain `reset()` |

**Rule:** in `setUp` always call `Container.shared.reset(options: .all)`, in `tearDown` — the same. Otherwise test leaks are guaranteed.

### Preview overrides

**Preferred — centralized** via `.onPreview` inside `autoRegister()`. One source of truth for all `#Preview`s, doesn't pollute the View files themselves:

```swift
extension Container: AutoRegistering {
    public func autoRegister() {
        userService.onPreview { MockUserService(result: .success(.fixture)) }
        analytics.onPreview { NoOpAnalytics() }
    }
}

#Preview {
    ProfileView()    // mock is picked up automatically
}
```

**Local override** (a one-off variation in a specific `#Preview`) — via the `.preview` modifier (Factory 2.4+) or `register`:

```swift
#Preview("Loading state") {
    Container.shared.userService.register { MockUserService(result: .pending) }
    return ProfileView()
}
```

`return` is required because there's now a statement before the View in the `#Preview` body.

## Concurrency (Swift 6 / Strict Concurrency)

`Container` is `Sendable`. Registration and resolve are thread-safe (internal lock). But **the instance you return** must be Sendable / properly isolated — Factory does not perform magic.

### `@MainActor` view models

Isolate the **ViewModel class itself**, not the property in `Container`. The factory closure is annotated `@MainActor in` so initialization runs on the main queue:

```swift
@MainActor
@Observable
final class ContentViewModel { /* ... */ }

extension Container {
    var contentViewModel: Factory<ContentViewModel> {
        self { @MainActor in ContentViewModel() }
    }
}
```

**Why NOT `@MainActor` on the `var` itself:** if you mark the property `@MainActor`, accessing it (including `Container.shared.contentViewModel`) requires a MainActor context — that breaks resolution from background tasks, migrations, `URLSession.delegate`. Isolation should live **on the type that requires it** (the ViewModel), not on the registration.

If Swift 6 complains about resolving from nonisolated code — that means you're resolving a MainActor-bound type in the wrong place. Move the resolve into a MainActor zone (e.g. `View.task`/`onAppear`) instead of annotating the registration.

### `@Injected` in `@Observable` classes

```swift
@MainActor
@Observable
final class FeatureViewModel {
    @ObservationIgnored @Injected(\.repository) private var repository
    @ObservationIgnored @Injected(\.analytics) private var analytics

    var state: State = .idle
}
```

`@ObservationIgnored` is mandatory. Without it every `@Injected` property becomes observable, and SwiftUI will redraw the view unnecessarily.

### `nonisolated` Factory from a global-actor context

If the registration is pure (no UI), keep it nonisolated — otherwise the whole feature ends up on MainActor:

```swift
extension Container {
    var repository: Factory<RepositoryProtocol> {
        self { Repository(client: self.apiClient()) }.cached     // nonisolated → OK
    }
}
```

## Common Mistakes

### 1. `Container.shared` from the domain layer — Service Locator

```swift
// ❌ Anti-pattern
final class ProfileService {
    func load() {
        let analytics = Container.shared.analytics()     // hidden dependency
    }
}

// ✅ Correct: explicit init OR @Injected at the top level (ViewModel/Coordinator)
final class ProfileService {
    private let analytics: AnalyticsProtocol
    init(analytics: AnalyticsProtocol) { self.analytics = analytics }
}
```

`@Injected` is acceptable in the **presentation/ViewModel/Coordinator layer**, which owns the feature's graph. Services and repositories must accept dependencies explicitly via init.

### 2. Resolving via `Container.shared` inside a Factory closure

```swift
// ❌ Breaks modular containers and tests
extension Container {
    var profileService: Factory<ProfileService> {
        self { ProfileService(api: Container.shared.apiClient()) }
    }
}

// ✅ Use self
extension Container {
    var profileService: Factory<ProfileService> {
        self { ProfileService(api: self.apiClient()) }
    }
}
```

If someone creates a separate `Container()` for tests, in the first variant `apiClient` will come from `.shared` — test isolation is broken.

### 3. `.singleton` for a ViewModel — shared state across screens

```swift
// ❌ All screens see the same state
extension Container {
    var profileViewModel: Factory<ProfileViewModel> {
        self { ProfileViewModel() }.singleton
    }
}

// ✅ ViewModel = .unique (default)
extension Container {
    var profileViewModel: Factory<ProfileViewModel> {
        self { ProfileViewModel() }
    }
}
```

### 4. Forgot `reset()` in setUp

```swift
// ❌ Tests influence each other
final class Tests: XCTestCase {
    func test_a() {
        Container.shared.foo.register { MockA() }
        // …
    }
    func test_b() {
        // MockA from test_a is still active → test_b is unpredictable
    }
}

// ✅ ALWAYS reset
final class Tests: XCTestCase {
    override func setUp() {
        super.setUp()
        Container.shared.reset(options: .all)
    }
}
```

Better — Swift Testing with `@Suite(.container)`, then no reset is needed.

### 5. `@Injected` in `@Observable` without `@ObservationIgnored`

```swift
// ❌ Every resolve triggers a UI update
@Observable
final class ViewModel {
    @Injected(\.service) var service
}

// ✅
@Observable
final class ViewModel {
    @ObservationIgnored @Injected(\.service) var service
}
```

### 6. ParameterFactory + `.cached` without `scopeOnParameters`

```swift
// ❌ Same instance for different itemIds
extension Container {
    var detailViewModel: ParameterFactory<String, DetailViewModel> {
        self { DetailViewModel(itemId: $0) }.cached
    }
}

let vm1 = Container.shared.detailViewModel("a")
let vm2 = Container.shared.detailViewModel("b")
// vm1 === vm2, both look at itemId "a"

// ✅ Either .unique, or scopeOnParameters
self { DetailViewModel(itemId: $0) }.cached.scopeOnParameters
```

### 7. Importing `Factory` instead of `FactoryKit`

```swift
// ❌ Old name, deprecation warnings
import Factory

// ✅
import FactoryKit
```

### 8. `register` in production code outside `autoRegister()` or tests

```swift
// ❌ Somewhere in SceneDelegate
Container.shared.networkClient.register { CustomClient() }

// Was called ONCE — but any subsequent reset() returns the original
```

Overrides should live either in `autoRegister()` (via context modifiers) or in tests. Otherwise you're fighting the reset lifecycle.

### 9. Name collisions in a multi-package setup

Two packages declare `extension Container { var apiClient: Factory<…> }` with different implementations → one silently overrides the other. Grep for `var .*: Factory<` across all packages or use Option B (your own `Container` per package).

### 10. `@Injected` services in a SwiftUI `View`

```swift
// ❌ Service directly in the View — hidden dependency, the View can't be previewed with a mock without an AutoRegistering hack
struct ProfileView: View {
    @Injected(\.userService) var userService
    @Injected(\.analytics) var analytics
    var body: some View { … }
}

// ✅ DI lands on the ViewModel; the View receives it via @InjectedObservable or @State
struct ProfileView: View {
    @InjectedObservable(\.profileViewModel) var viewModel
    var body: some View { … }
}

// ✅ Composable components — via init, no DI:
struct ProfileHeaderView: View {
    let user: User
    let onEdit: () -> Void
    var body: some View { … }
}
```

**Rule:**
- Services (`UserService`, `Analytics`, `Repository`) — **never** in a `View`. Only in the ViewModel via `@Injected` + `@ObservationIgnored`.
- `@InjectedObservable` for the screen's root ViewModel — acceptable.
- Composable subviews — `let`/`@Binding` via init. DI = a headache for previews and snapshot tests.

## Swinject vs Factory: feature comparison

| Aspect | Swinject | Factory |
|---|---|---|
| Registration | `container.register(Foo.self) { _ in Foo() }` — runtime, in an Assembly | `extension Container { var foo: Factory<Foo> { self { Foo() } } }` — compile-time property |
| Type-safety | Runtime: missing registration → `resolve(...)!` crash | Compile-time: factory missing → code doesn't compile |
| Binding | By type + optional `name: String` | By KeyPath to a `Container` property |
| Resolve in code | `container.resolve(Foo.self)!` or hand-written wrappers | `Container.shared.foo()` or `@Injected(\.foo)` |
| Property wrappers | None built-in (you'd write your own) | First-class: `@Injected`, `@LazyInjected`, `@WeakLazyInjected`, `@InjectedObservable` |
| SwiftUI / Observation | Manual integration (`StateObject`, EnvironmentObject) | `@InjectedObservable` + `@ObservationIgnored` out of the box |
| Scopes | `.transient`, `.container`, `.weak`, `.graph`, custom | `.unique`, `.cached`, `.singleton`, `.shared`, `.graph`, `.timeToLive`, `.scopeOnParameters` |
| Parameters in factory | `register { (_, arg: String) in … }`, up to 9 args | `ParameterFactory<P, T>`, for 2+ — tuple |
| Contexts (test/preview/debug) | None — assemble your own via `#if DEBUG` + flags | `.onTest` / `.onPreview` / `.onDebug` / `.onSimulator` / `.onArg` |
| Bootstrap hook | Configure Assembly + assembler in the CR | `AutoRegistering.autoRegister()` lazily on first resolve |
| Modular setup | `Assembly` per module + `assembler.apply([...])` | `extension Container` per file, optionally a custom `SharedContainer` |
| SPM package | DI framework **forbidden** in main target → `init(dependencies:)` | Same restriction → `init(dependencies:)` |
| Test isolation | Fresh `Container()` per test OR manual Assembly reset | `Container.shared.reset(options: .all)` OR `@Suite(.container)` (FactoryTesting) for parallel Swift Testing |
| Mock overrides | `container.register(Foo.self) { _ in Mock() }` (on top) | `Container.shared.foo.register { Mock() }` |
| Performance | Runtime dictionary lookup + reflection | Static dispatch via property + closure |
| Async / Sendable | Not Sendable out of the box, manual synchronization | Container is Sendable, register/resolve thread-safe |
| Maturity | Older, more boilerplate, native to the UIKit era | Newer, tailored for SwiftUI/Observation/Swift 6 |

**When to pick which:**

- **Greenfield SwiftUI** + iOS 16+ + `@Observable` → **Factory**
- **Existing Swinject** in production → don't migrate for the sake of migration; see Migration below only if there's specific pain (tests, Swift 6, SwiftUI integration)
- Need **named registrations of the same type** (`name: "primary" / "fallback"`) or autoregister plugins → Swinject
- Need contexts (preview/test/debug overrides) **without your own scaffolding** → Factory
- Team coming from Spring/Dagger → Swinject is mentally closer (Assembly = Module)

## Migration: Swinject → Factory

| Swinject | Factory |
|---|---|
| `container.register(Foo.self) { _ in Foo() }` | `extension Container { var foo: Factory<Foo> { self { Foo() } } }` |
| `.inObjectScope(.container)` | `.cached` |
| `.inObjectScope(.transient)` (default) | `.unique` (default) |
| `.inObjectScope(.weak)` | `.shared` |
| `.inObjectScope(.graph)` | `.graph` |
| `container.resolve(Foo.self)!` | `Container.shared.foo()` |
| `r.resolve(Foo.self, name: "x")` | A custom key via KeyPath or a separate `var fooX: Factory<Foo>` |
| `Assembly.assemble(container:)` | `extension Container` per feature + `AutoRegistering` |
| `register(Foo.self) { (_, arg: String) in … }` | `var foo: ParameterFactory<String, Foo>` |

**Migration strategy:**
1. Rewrite services and registrations feature by feature (Container extension next to the old Assembly).
2. Leave Coordinators alone — they work through `AppDependencyContainer` (see `di-module-assembly`); only the facade implementation changes.
3. Don't keep a mixed state (some Swinject + some Factory) longer than one sprint — two DI frameworks at once = double the test complexity.

## Debugging Tips

> **API version:** the examples below rely on the internal `ContainerManager` API from Factory 2.5+. Names/signatures may change between minor releases — check the repository README if something stops compiling.

```swift
// List of registered factory keys (debug only)
#if DEBUG
Container.shared.manager.registrations.keys.forEach { print($0) }
#endif

// Decorator — log every resolve
Container.shared.manager.decorator { resolved in
    print("Resolved: \(type(of: resolved))")
}
```

The decorator is invoked on EVERY resolve — turn it off in production.
