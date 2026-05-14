---
name: di-swinject
description: "Use when working with Swinject dependency injection in iOS apps. Covers Swinject-specific patterns: object scopes, registrations (basic, autoregister, named, with arguments), Assembly pattern, testing configuration. For Composition Root design see di-composition-root skill; for connecting DI to Coordinators see di-module-assembly skill."
---

# Swinject Dependency Injection Patterns

This skill provides Swinject-specific guidelines: scopes, registration techniques, autoregistration, testing.

> **Related skills:**
> - `di-composition-root` — where the Swinject `Container` is created, its lifetime, sync/async bootstrap, scope strategies
> - `di-module-assembly` — how Coordinators get services from Swinject via the Factory pattern without Service Locator
> - `pkg-spm-design` — why Swinject **must not** be imported inside SPM packages
> - `di-factory` — an alternative DI framework (Factory by hmlongco): compile-time safety, property-wrapper injection, SPM-friendly. Comparison table at the end of this skill

## When to Use

**Swinject is the right choice when**:
- Need runtime dependency injection
- Want constructor injection with automatic resolution
- Building modular apps with swappable implementations
- Need different configurations for production/testing
- Complex dependency graphs

**Consider alternatives**:
- Simple apps → Manual DI (pass dependencies in init, see `di-composition-root` section "Manual AppDependencyContainer")
- SwiftUI apps without runtime binding needs → **Factory** (see `di-factory`) — property-wrapper injection, preview/test contexts out of the box, compile-time safety
- Compile-time safety priority → `di-factory` (a missing factory closure means the code won't compile) or manual DI
- A whole TCA feature → `@Dependency` by Point-Free (see `arch-tca`), not Swinject

## Core Concepts

### Container Setup

The Swinject `Container` is created in the Composition Root and wrapped in an `AppDependencyContainer` facade — never used as a global `static let shared`. **Details on CR — in the `di-composition-root` skill.**

Minimum for context:

```swift
import Swinject
import SwinjectAutoregistration

@MainActor
final class AppDependencyContainer {
    private let container = Container()

    func bootstrap() {
        registerServices()
        registerViewModels()
    }
}
```

> **`static let shared` is forbidden** — it turns the container into a Service Locator (hidden dependencies, no testability). See the `di-composition-root` skill for the correct location and lifetime of the container.

### Basic Registration

```swift
// Register with explicit factory
container.register(UserServiceProtocol.self) { _ in
    UserService()
}

// Register with dependencies
container.register(ProfileViewModelProtocol.self) { r in
    ProfileViewModel(
        userService: r.resolve(UserServiceProtocol.self)!,
        analyticsService: r.resolve(AnalyticsServiceProtocol.self)!
    )
}
```

### Auto-registration

Using `SwinjectAutoregistration` for cleaner syntax:

```swift
// Auto-resolve dependencies
container.autoregister(ProfileViewModel.self, initializer: ProfileViewModel.init)

// With protocol
container.autoregister(
    ProfileViewModelProtocol.self,
    initializer: ProfileViewModel.init
)
```

## Object Scopes

### `.transient` (Default)

New instance every time. Use for stateful objects.

```swift
container.register(FeatureViewModel.self) { r in
    FeatureViewModel(service: r.resolve(ServiceProtocol.self)!)
}
// Each resolve() creates new instance
```

**Use for**:
- ViewModels (each screen needs fresh state)
- Coordinators (each flow is independent)
- Stateful helpers

### `.container` (Singleton)

Single instance for container lifetime. Use for stateless services.

```swift
container.register(NetworkServiceProtocol.self) { _ in
    NetworkService()
}.inObjectScope(.container)
// Same instance returned every time
```

**Use for**:
- Network clients
- Database managers
- Analytics services
- App settings
- Caches

### `.weak`

Shared while retained, recreated when released.

```swift
container.register(CacheProtocol.self) { _ in
    ImageCache()
}.inObjectScope(.weak)
// Shared if someone holds reference, otherwise recreated
```

**Use for**:
- Optional shared caches
- Resources that can be recreated
- Memory-sensitive singletons

### `.graph` (Default for auto-registration)

Same instance within single resolution graph, new for each top-level resolve.

```swift
container.autoregister(SharedState.self, initializer: SharedState.init)
    .inObjectScope(.graph)

// If A and B both depend on SharedState:
// resolve(A.self) and resolve(B.self) → different SharedState
// But A and B resolved together share same SharedState
```

**Use for**:
- Shared state within a feature but not globally
- Request-scoped objects

## Registration Patterns

### Protocol-Based Registration

Always register protocols, not concrete types:

```swift
// Correct
container.register(UserServiceProtocol.self) { _ in
    UserService()
}

// Avoid
container.register(UserService.self) { _ in
    UserService()
}
```

### Named Registrations

When multiple implementations of same protocol exist:

```swift
container.register(APIClientProtocol.self, name: "production") { _ in
    ProductionAPIClient()
}

container.register(APIClientProtocol.self, name: "staging") { _ in
    StagingAPIClient()
}

// Resolve by name
let client = container.resolve(APIClientProtocol.self, name: "production")!
```

### Registrations with Arguments

When instance needs runtime parameters:

```swift
container.register(DetailViewModel.self) { (r, itemId: String) in
    DetailViewModel(
        itemId: itemId,
        service: r.resolve(ItemServiceProtocol.self)!
    )
}

// Resolve with argument
let viewModel = container.resolve(DetailViewModel.self, argument: "item-123")!
```

### Multiple Arguments

```swift
container.register(ChatViewModel.self) { (r, roomId: String, userId: String) in
    ChatViewModel(
        roomId: roomId,
        userId: userId,
        chatService: r.resolve(ChatServiceProtocol.self)!
    )
}

// Resolve
let viewModel = container.resolve(
    ChatViewModel.self,
    arguments: "room-1", "user-42"
)!
```

## Assembly Pattern

Organize registrations by feature using Assemblies:

```swift
class ServicesAssembly: Assembly {
    func assemble(container: Container) {
        container.register(NetworkServiceProtocol.self) { _ in
            NetworkService()
        }.inObjectScope(.container)

        container.register(DatabaseServiceProtocol.self) { _ in
            DatabaseService()
        }.inObjectScope(.container)
    }
}

class ProfileAssembly: Assembly {
    func assemble(container: Container) {
        container.autoregister(
            ProfileViewModelProtocol.self,
            initializer: ProfileViewModel.init
        )

        container.register(ProfileCoordinator.self) { (r, router: Router) in
            ProfileCoordinator(router: router, container: r)
        }
    }
}

// In DIContainer
let assembler = Assembler([
    ServicesAssembly(),
    ProfileAssembly(),
    SettingsAssembly(),
    // ... more assemblies
])
let container = assembler.resolver
```

## `@MainActor` UI types + Swinject

Swinject's `Container.register(_:factory:)` takes a **nonisolated** `(Resolver) -> Service` closure. Calling a `@MainActor`-isolated initializer (any `UIViewController`/`NSViewController` subclass on iOS 13+/macOS, or any `@MainActor` ViewModel) from inside that closure is a Swift 6 error:

```
error: call to main actor-isolated initializer 'init(...)' in a synchronous nonisolated context
```

### ❌ Wrong — direct registration of `@MainActor` types

```swift
final class RootAssembly: Assembly {
    func assemble(container: Container) {
        // FAILS under Swift 6 — RootViewModel is @MainActor, closure is nonisolated.
        container.register(RootViewModel.self) { resolver in
            RootViewModel(appInfo: resolver.resolve(AppInfoService.self)!)
        }
        // FAILS — UIViewController.init is @MainActor-isolated by SDK annotation.
        container.register(RootViewController.self) { resolver in
            RootViewController(viewModel: resolver.resolve(RootViewModel.self)!)
        }
    }
}
```

### ❌ Also wrong — `MainActor.assumeIsolated`

```swift
container.register(RootViewModel.self) { resolver in
    MainActor.assumeIsolated {              // ← masks the design issue
        RootViewModel(appInfo: resolver.resolve(AppInfoService.self)!)
    }
}
```

`assumeIsolated` traps at runtime if the closure ever runs off the main actor — and the design intent ("UI is built on main") is hidden from the type system. Keep `assumeIsolated` for true legacy/sync-callback bridges, not for DI wiring you control.

### ✅ Correct — register a `nonisolated` Factory, build UI on main

Register a **plain struct factory** (nonisolated) that holds the `Resolver`; put `@MainActor` on its `make…` method, which constructs the ViewModel and View on the main actor:

```swift
// Modules/Root/RootFactory.swift
struct RootFactory {
    private let resolver: Resolver
    init(resolver: Resolver) { self.resolver = resolver }

    @MainActor
    func makeViewController() -> RootViewController {
        let viewModel = RootViewModel(appInfo: resolver.resolve(AppInfoService.self)!)
        return RootViewController(viewModel: viewModel)
    }
}

// DI/RootAssembly.swift
final class RootAssembly: Assembly {
    func assemble(container: Container) {
        container.register(RootFactory.self) { resolver in
            RootFactory(resolver: resolver)
        }
    }
}

// Coordinator / AppDelegate (already @MainActor)
let factory = resolver.resolve(RootFactory.self)!
let viewController = factory.makeViewController()
```

**Rules:**

- `*Factory` is a `nonisolated` struct (no `@MainActor` on the type, no `@MainActor` on `init`) — Swinject's closure can build it freely.
- The `make…` method is `@MainActor` — it's the boundary that crosses into UI isolation, called from `@MainActor` Coordinator / `AppDelegate` / `SceneDelegate`.
- Register `*Factory` types in Swinject, **not** ViewModels/ViewControllers. Services stay registered directly (they're `nonisolated`).
- For runtime parameters (`itemId`, `userId`, …) add them as method parameters on `make…`, not as Swinject `arguments:` — keeps the isolation boundary explicit.

This matches the Factory pattern in `di-module-assembly` (`ModuleFactory` + `ModuleComponents`) — that skill explains the full Coordinator wiring; the rule above is just the Swinject-specific contract that lets the two layers compose under Swift 6 concurrency.

## Coordinator and Module Assembly

Coordinators should **not** receive the Swinject container directly — this creates a Service Locator anti-pattern. Instead, use the Factory pattern described in the `di-module-assembly` skill:

- `AppDependencyContainer` wraps Swinject and conforms to feature dependency protocols
- `ModuleFactory` assembles View + ViewModel using dependency protocols
- `CoordinatorFactory` creates Coordinators with their ModuleFactory
- Coordinators never import Swinject

See `di-module-assembly` skill for complete examples.

## Testing Configuration

### Unit Tests — Direct Injection (Preferred)

For ViewModels and services, inject mock dependencies directly — no container needed:

```swift
class ProfileViewModelTests: XCTestCase {
    func test_loadProfile_success() {
        let mockService = MockUserService(result: .success(testUser))
        let viewModel = ProfileViewModel(userService: mockService)

        viewModel.loadProfile()

        XCTAssertEqual(viewModel.state, .loaded(testUser))
    }

    func test_loadProfile_failure() {
        let mockService = MockUserService(result: .failure(TestError.network))
        let viewModel = ProfileViewModel(userService: mockService)

        viewModel.loadProfile()

        XCTAssertEqual(viewModel.state, .error("Network error"))
    }
}
```

### Integration Tests — Test Container

When testing the DI graph itself or integration between components:

```swift
class TestDIContainer {
    static func makeContainer() -> Container {
        let container = Container()

        container.register(NetworkServiceProtocol.self) { _ in
            MockNetworkService()
        }

        container.register(DatabaseServiceProtocol.self) { _ in
            InMemoryDatabase()
        }

        return container
    }
}
```

### Override Specific Dependencies

```swift
func testWithCustomMock() {
    let container = TestDIContainer.makeContainer()

    container.register(NetworkServiceProtocol.self) { _ in
        MockNetworkService(shouldFail: true)
    }

    let viewModel = container.resolve(ProfileViewModel.self)!
    // Test error handling path
}
```

## Common Mistakes

### 1. Force Unwrapping Without Registration

```swift
// Crashes if not registered
let service = container.resolve(ServiceProtocol.self)!

// Defensive approach
guard let service = container.resolve(ServiceProtocol.self) else {
    fatalError("ServiceProtocol not registered")
}
```

### 2. Wrong Scope Selection

```swift
// ViewModel as singleton - shares state between screens!
container.register(FeatureViewModel.self) { ... }
    .inObjectScope(.container)

// ViewModel as transient - fresh state each time
container.register(FeatureViewModel.self) { ... }
    .inObjectScope(.transient)  // or omit (default)
```

### 3. Circular Dependencies

```swift
// A needs B, B needs A → crash
container.register(A.self) { r in A(b: r.resolve(B.self)!) }
container.register(B.self) { r in B(a: r.resolve(A.self)!) }

// Break cycle with property injection
container.register(A.self) { r in
    let a = A()
    a.b = r.resolve(B.self)!
    return a
}
container.register(B.self) { r in B(a: r.resolve(A.self)!) }
```

### 4. Resolving in Initializers

```swift
// Accessing container during init — hidden dependency
class BadService {
    let dependency = appContainer.resolve(Dep.self)!
}

// Inject through initializer — explicit, testable
class GoodService {
    let dependency: DepProtocol
    init(dependency: DepProtocol) {
        self.dependency = dependency
    }
}
```

### 5. Container as Service Locator

```swift
// Anti-pattern: passing container to Coordinator/ViewModel
class FeatureCoordinator {
    private let container: Resolver
    func start() {
        let vm = container.resolve(FeatureViewModel.self)!  // Hidden dependency
    }
}

// Correct: use Factory pattern (see di-module-assembly skill)
class FeatureCoordinator {
    init(router: Router,
         coordinatorFactory: CoordinatorFactory,
         factory: FeatureModuleFactory) {
        let module = factory.makeFeatureModule()  // Explicit, testable
    }
}
```

## Debugging Tips

### Check Registration

```swift
#if DEBUG
func validateRegistrations() {
    let requiredTypes: [Any.Type] = [
        NetworkServiceProtocol.self,
        DatabaseServiceProtocol.self,
        ProfileViewModelProtocol.self,
    ]

    for type in requiredTypes {
        if container.resolve(type) == nil {
            print("Missing registration: \(type)")
        }
    }
}
#endif
```

### Log Resolutions

```swift
extension Container {
    func resolveWithLogging<T>(_ type: T.Type) -> T? {
        let result = resolve(type)
        #if DEBUG
        if result == nil {
            print("Failed to resolve: \(type)")
        } else {
            print("Resolved: \(type)")
        }
        #endif
        return result
    }
}
```

## Swinject vs Factory: when to pick which

Swinject and Factory (see `di-factory`) solve the same problem in different ways. The choice:

| Criterion | Swinject | Factory |
|---|---|---|
| Compile-time safety | ❌ Resolve crash at runtime | ✅ Won't compile without a factory |
| Injection style | Constructor via `r.resolve(...)` | Property wrapper `@Injected` or `Container.shared.foo()` |
| Registrations | `register` / `autoregister` inside an Assembly | Computed property `var foo: Factory<Foo> { self { Foo() } }` |
| Runtime parameters | `register { (r, arg) in ... }` + `name:` | `ParameterFactory` (one parameter type per key) |
| Multiple impls of one type | `name:` parameter | Separate computed properties or modular containers |
| Autoregister (auto-resolve init args) | ✅ Via `SwinjectAutoregistration` | ❌ No (deps must be wired explicitly in the closure) |
| Inside an SPM package | ❌ Forbidden | ❌ Forbidden in the main target. Modular `extension Container` per feature — in the app target |
| Preview/Test context overrides | Manual (separate test Assembly) | ✅ `.onPreview` / `.onTest` modifier out of the box |
| Parallel tests | Manual reset between tests | ✅ Swift Testing `@Suite(.container)` via `@TaskLocal` |
| Maturity | 10+ years in production, de facto standard | Modern library (2.x since 2023), actively developed |
| SwiftUI specifics | Neutral | Tailored for SwiftUI/Observation |
| Size | ~3000 LOC + SwinjectAutoregistration | <1000 LOC, single dependency |

**When Swinject is better:**
- Multi-module legacy is already on it — rewriting is more expensive
- Need autoregister (`r.autoregister(...)` without spelling out the constructor)
- Need **multiple** bindings keyed by `name:` with different arguments
- UIKit-first project, SwiftUI is used rarely

**When Factory is better:**
- New SwiftUI-first project
- 10–100 services in the graph, monorepo or SPM modules
- Want to see the entire dependency surface at compile time
- Team prefers the property-wrapper style
- Critical: tests must run in parallel without reset headaches

**When neither fits:**
- < 10 services → manual DI on `lazy var` (see `di-composition-root`)
- A whole TCA feature → `@Dependency` by Point-Free
