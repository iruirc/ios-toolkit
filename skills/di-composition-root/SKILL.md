---
name: di-composition-root
description: "Use when designing where and how an app's object graph is wired — SceneDelegate / AppDelegate / @main App. Covers what belongs in Composition Root (CR), what doesn't, sync vs async bootstrap, scope strategies (app/scene/flow), and testing. DI-framework agnostic."
---

# Composition Root

The Composition Root (CR) is the single place in the application where **concrete types are created and wired together**. The rest of the app works through protocols and is unaware of the implementations.

> **Related skills:**
> - `di-swinject` — concrete registration techniques when Swinject is the chosen DI framework
> - `di-factory` — Factory (hmlongco) as an alternative DI framework: compile-time-safe registrations, property-wrapper injection, SPM-friendly modular containers
> - `di-module-assembly` — how UI features get their dependencies from the CR via the Factory pattern
> - `pkg-spm-design` — how SPM packages plug into the CR via `Dependencies` structs
> - `persistence-architecture` — where `ModelContainer` / `NSPersistentContainer` / `DatabasePool` are created (singleton scope in CR), how to switch `.disk` / `.inMemory` for tests
> - `persistence-migrations` — `try await stack.warmUp()` step in CR bootstrap where migration runs; why async warm-up belongs in the CR rather than lazy-on-first-call inside a Repository
> - `concurrency-architecture` — singletons with mutable state are registered as `actor`s; `@MainActor`-isolated singletons (RootRouter, AppState `@Observable`) are created on main; the container itself is `nonisolated`

## Why a Composition Root

Without a CR, concrete types are created scattered throughout the codebase — inside ViewModels, Coordinators, Services. That gives you:

- Hidden dependencies (not visible from the public API)
- Tight coupling between layers (a ViewModel knows about a concrete service, not a protocol)
- Inability to swap implementations (for tests or different environments)
- Cyclic module imports

The CR solves this: **only the CR** imports all concrete types and wires them into a graph. The rest of the code only sees protocols/abstractions.

## Where the Composition Root lives

| Entry point | When |
|---|---|
| `SceneDelegate.scene(_:willConnectTo:options:)` | UIKit, multi-scene apps (standard since iOS 13+) |
| `AppDelegate.application(_:didFinishLaunchingWithOptions:)` | UIKit, single-scene or legacy |
| `@main struct App: App { init() { ... } }` | SwiftUI lifecycle |
| `main.swift` / `@main` actor/struct | macOS CLI / sandboxed scripts |

For multi-scene UIKit: **AppDelegate** = bootstrap of shared app-scope resources (DB, caches, analytics); **SceneDelegate** = creation of the per-scene graph (UI, navigation). Don't mix the two.

## What the CR must do

1. **Creates the DI container** or the manual dependency graph
2. **Registers/initializes all services** (or invokes their Assembly)
3. **Creates Factory objects** (`CoordinatorFactory`, `ModuleFactory` — see `di-module-assembly`)
4. **Creates the app's root object** (RootCoordinator / RootView / TabBarController)
5. **Connects the root to the window** and starts the UI

## What the CR **must not** do

| Anti-pattern | Why it's bad | Where it belongs instead |
|---|---|---|
| Business logic, data mapping | The CR shouldn't grow with features | In the corresponding service |
| Network requests, data loading | Blocks startup, hides errors | In a service called from the root view |
| Navigation (push/present) | That's the Coordinator's job | RootCoordinator.start() |
| Conditional branches on feature flags | Pollutes the CR — turns it into a god class | Factory with branching + protocol substitution |
| Registration after app start | The CR must finish before the first frame | Lazy property + on-demand creation |

## DI: container vs manual graph

The CR can be implemented in three ways — through a runtime DI framework (Swinject), a compile-time DI framework (Factory), or manually (`lazy let` fields). The external contract (`AppDependencies`, per-feature `*FeatureDependencies`, `CoordinatorFactory`, `ModuleFactory`, `Assembly`) is **identical across all variants** — only the internal implementation of `AppDependencyContainer` changes.

| Aspect | Swinject (runtime) | Factory (compile-time) | Manual DI (`lazy let`) |
|---|---|---|---|
| Graph < 10 services | Overkill | Workable, but overkill | ✅ Best choice |
| Graph 10–30 services | Overkill | ✅ Good fit | ✅ Good fit |
| Graph 30–100 services | ✅ Pays off | ✅ Pays off | Workable, but bulky |
| Graph > 100 services | ✅ Standard | ✅ Standard | Hard to maintain |
| Compile-time safety of registrations | No (resolve crash at runtime) | ✅ Won't compile without a factory | ✅ The compiler points to the missing piece immediately |
| Circular dependencies | Property injection out of the box | `@WeakLazyInjected` or property injection | Manually (see below) |
| Multi-binding / conditional bind | Branching inside `register` | Contexts (`onTest`/`onPreview`/`onDebug`) + `register` override | `if`/`switch` in the getter |
| Runtime parameters in registrations | `Container` API with `name:` | `ParameterFactory` (one parameter type per key) | Computed getter with arguments |
| Property-wrapper injection | Via third-party libraries | ✅ `@Injected` out of the box | None (only via init) |
| Use inside an SPM package | ❌ Forbidden (see `pkg-spm-design`) | ❌ Forbidden in the main target (same rule). Modular extensions per feature live in the app target | ✅ Allowed |
| SwiftUI Preview / Test contexts | Manually via override Assembly | ✅ `.onPreview` / `.onTest` modifier out of the box | Manual |
| Parallel tests without interference | Manual reset, easy to forget | ✅ Swift Testing `@Suite(.container)` via `@TaskLocal` | N/A (one container per test) |
| Learning curve | Need to learn the container API | Need KeyPath + property wrappers | 0 — plain Swift |

**Start with manual by default.** Move to Factory when: the `lazy var` chain starts feeling like boilerplate, you need preview/test overrides without amending the CR, or you have SPM packages with their own graphs. Move to Swinject when you need runtime-registered factories, name-based lookup, autoresolve, or legacy is already on it. For framework-specific details — see `di-swinject` or `di-factory`.

### Manual AppDependencyContainer — full example

Keep `AppDependencyContainer` itself **nonisolated**. Background services and
repositories may resolve dependencies too; put `@MainActor` on UI factories,
coordinators, routers, and app-scoped UI state instead.

```swift
final class AppDependencyContainer: AppDependencies {

    // App-scope: lazy var — created on first access, lives until the app is killed
    lazy var userService: UserServiceProtocol = UserService(
        networkClient: networkClient,
        storage: keychainStorage,
        logger: logger
    )
    lazy var analyticsService: AnalyticsServiceProtocol = AnalyticsService(
        config: config,
        logger: logger
    )
    lazy var imageLoader: ImageLoaderProtocol = ImageLoader(
        networkClient: networkClient,
        cache: imageCache
    )

    // Internal infra — not part of AppDependencies, but needed to build the services above
    private lazy var config: AppConfig = .fromBundle()
    private lazy var logger: Logger = OSLogger(subsystem: "com.example.app")
    private lazy var networkClient: HTTPClient = URLSessionHTTPClient(
        config: config,
        logger: logger
    )
    private lazy var keychainStorage: KeychainStorage = KeychainStorage(
        service: config.bundleId
    )
    private lazy var imageCache: ImageCache = ImageCache(maxBytes: 50 * 1024 * 1024)

    func bootstrap() {
        // Eagerly init critical services — fail at startup, not on the first screen
        _ = config
        _ = logger
        _ = networkClient
        _ = userService
    }
}
```

From the outside, `AppDependencyContainer` behaves like the Swinject variant: it conforms to `AppDependencies` and is passed to `CoordinatorFactoryImp(dependencies: container)` (see `di-module-assembly`).

### Scopes in manual DI

| Scope | Implementation | Example |
|---|---|---|
| **app / scene** (single instance) | `lazy var` field | `lazy var userService = UserService(...)` |
| **transient** (new every time) | computed `var` getter | `var requestId: UUID { UUID() }` |
| **flow** (lives while the flow is active) | `let` field on the flow's parent Coordinator | `OnboardingCoordinator { let state = OnboardingState() }` |
| **weak / optional shared** | `weak var` + manual management | Rarely needed |

`lazy var` corresponds to `.container` scope in Swinject. To initialize eagerly rather than lazily — `_ = service` in `bootstrap()`.

### Circular dependencies in manual DI

If A needs B and B needs A — using `lazy` directly won't work (init requires the other side to be ready). Options:

1. **Property injection** — make one of the fields an optional `weak var` and set it after both are initialized
2. **Introduce a third type C** that A and B communicate through (usually the right move — a cycle is an architectural defect)
3. **Closure injection** — A receives `() -> B` instead of `B`, the actual B is created on first call

```swift
// Property injection: each service holds a weak reference to the other
final class AppDependencyContainer: AppDependencies {
    lazy var userService: UserService = {
        let service = UserService(network: networkClient)
        service.analytics = analyticsService  // weak var inside UserService
        return service
    }()
    lazy var analyticsService: AnalyticsService = {
        let service = AnalyticsService()
        service.userService = userService     // weak var inside AnalyticsService
        return service
    }()
}
```

The mechanics are identical to the Swinject variant, just without autoresolve. More detail — `di-swinject` skill, "Circular Dependencies" section.

### When manual definitely doesn't fit

- Multi-module apps with > 100 services and active developer onboarding — a DI framework modularizes registrations better (Assembly classes in Swinject, `extension Container` per feature/package in Factory)
- You need runtime-registered factories with automatic parameter resolution (autoregister, name-based binding) — Swinject
- You want a property-wrapper style (`@Injected`) and preview/test overrides out of the box — Factory (see `di-factory`)
- Legacy is already on Swinject — rewriting is more expensive than maintaining it

## Bootstrap: sync vs async

### Sync bootstrap (typical case)

```swift
final class AppDependencyContainer {
    private let container = Container()

    func bootstrap() {
        registerServices()      // registration only — no async operations
        registerViewModels()
        registerFactories()
    }
}

// SceneDelegate
let appContainer = AppDependencyContainer()
appContainer.bootstrap()
// 100% ready to use immediately
```

**Use when:** all dependencies are created instantly, with no I/O.

### Async bootstrap (DB with migration, cache warm-up, license validation)

Two approaches:

**A) Wait on the splash screen**

```swift
final class AppDependencyContainer {
    func bootstrapAsync() async throws {
        registerServices()
        try await migrationService.runPendingMigrations()
        try await cacheWarmer.preload()
    }
}

// SceneDelegate shows splash, awaits, then creates the root
window.rootViewController = SplashViewController()
window.makeKeyAndVisible()

Task { @MainActor in
    do {
        try await appContainer.bootstrapAsync()
        startMainFlow()
    } catch {
        showFatalError(error)
    }
}
```

**B) Show the root immediately, the service publishes a Ready signal**

```swift
final class DatabaseService {
    @Published private(set) var state: ReadyState = .initializing

    func bootstrap() {
        Task {
            await runMigrations()
            state = .ready
        }
    }
}

// ViewModel waits for the signal
viewModel.$databaseState
    .filter { $0 == .ready }
    .sink { _ in self.loadData() }
```

Use approach A for cases where nothing works without the service (auth token, config). Use approach B for optional services (analytics, image cache).

## Scopes: app / scene / flow / request

Different objects live for different durations — the CR must distinguish them explicitly.

| Scope | Lifetime | Examples | Where registered |
|---|---|---|---|
| **app** | from start to app kill | NetworkClient, DatabaseService, AnalyticsService, FeatureFlags | AppDelegate / @main App |
| **scene** | while the scene is active (iPad multi-window) | NavigationCoordinator, scene-specific cache | SceneDelegate |
| **flow** | while a single user flow is active (onboarding, checkout) | OnboardingState, CheckoutSession | The flow's parent Coordinator |
| **request** | one network request / screen | RequestParameters, ScreenLogger | Created inline, not registered |

**In Swinject:** `.container` ≈ app/scene scope (depending on whose container it is); `.transient` ≈ request scope; `.weak` ≈ optional shared. See `di-swinject` skill, "Object Scopes" section.

**In manual DI:** scope = lifetime of the reference. Hold strong → alive; weak/optional → may be deallocated.

## Bootstrap order: who depends on whom

The CR must register services in dependency order. Cycles are forbidden.

Typical order (top to bottom):

```
1. Logger / Crash reporter            ← no dependencies
2. Configuration / FeatureFlags       ← Logger
3. Persistence (DB, Keychain, Cache)  ← Logger, Config
4. Network (HTTPClient, Auth)         ← Persistence (for tokens), Config
5. Domain services (User, Catalog)    ← Network, Persistence
6. UI services (ImageLoader, Theme)   ← Network
7. Factories (Coordinator, Module)    ← everything above
8. RootCoordinator                    ← Factories
```

If a cycle appears (A needs B, B needs A) — that's an **architectural defect**, not an excuse to use lazy injection as a workaround. Introduce a third type C, or use property injection (see `di-swinject` skill, "Circular Dependencies").

## Multiple Composition Roots

Sometimes you need **more than one CR**:

| Scenario | Solution |
|---|---|
| iPad multi-scene | App-scope CR in AppDelegate + per-scene CR in SceneDelegate; the scene gets references to app-scope services |
| App + extensions (widget, share, intents) | Each extension has its own CR; shared code is extracted into an SPM package (see `pkg-spm-design`) |
| App + UITests host app | A test CR substitutes services with mocks via an environment variable |
| App with multiple product modes (full/lite) | One CR, but FeatureFlags swap implementations inside registerServices() |

## Testing the Composition Root

CRs are rarely covered with unit tests (they are testing infrastructure themselves), but **a smoke test on registrations is useful**:

```swift
final class CompositionRootSmokeTests: XCTestCase {
    func test_allCriticalServicesResolve() {
        let container = AppDependencyContainer()
        container.bootstrap()

        // Verify that critical services resolve
        XCTAssertNotNil(container.userService)
        XCTAssertNotNil(container.networkClient)
        XCTAssertNotNil(container.appSettingsManager)
    }

    func test_bootstrapDoesNotCrash() {
        let container = AppDependencyContainer()
        XCTAssertNoThrow(container.bootstrap())
    }
}
```

For async bootstrap — verify the graph builds in a reasonable time:

```swift
func test_asyncBootstrapCompletesInReasonableTime() async throws {
    let container = AppDependencyContainer()
    let start = Date()
    try await container.bootstrapAsync()
    let elapsed = Date().timeIntervalSince(start)
    XCTAssertLessThan(elapsed, 2.0)  // must not take >2s
}
```

## Common Mistakes

1. **CR as a singleton** — `static let shared = AppContainer()`. That's a Service Locator and throws away the value of DI.
2. **CR imports UIKit views directly** — should go through Factory/Assembly so the UI layer can be swapped out.
3. **CR methods called from arbitrary code** — `AppDependencyContainer.shared.userService` anywhere = anti-pattern. The CR is accessible only to root objects (Coordinator, RootView).
4. **Bootstrap performs network requests synchronously** — blocks the main thread, the app looks frozen. Use async bootstrap (variant A or B above).
5. **Registration in multiple places** — part in AppDelegate, part in SceneDelegate, part in some Manager. There must be one (or explicitly several with clear scopes) CR.

## File Structure (typical)

```
App/
├── SceneDelegate.swift                  # CR (UIKit) — runs bootstrap, creates the root
├── AppDelegate.swift                    # app-scope bootstrap (optional)
└── DependencyInjection/
    ├── AppDependencyContainer.swift     # CR facade, owns DI container
    ├── AppDependencies.swift            # composite protocol for feature deps
    └── Registrations/
        ├── ServicesRegistration.swift   # services grouped together
        ├── ViewModelsRegistration.swift
        └── FactoriesRegistration.swift
```

For SwiftUI apps:

```
App/
├── MyApp.swift                          # @main + init() — CR
└── DependencyInjection/
    └── AppDependencyContainer.swift
```

## When you don't need a CR

- A 1-screen prototype — manual DI right inside `@main App.init()` is enough
- A script/CLI without an object graph — a plain main() function
- When all your functionality is stateless static utilities

In all other cases an explicit CR pays for itself the first time you change the architecture.
