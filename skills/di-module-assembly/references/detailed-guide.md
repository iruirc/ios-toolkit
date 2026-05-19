---
name: di-module-assembly
description: "Use when assembling UI modules (MVVM/MVVM+Coordinator), creating CoordinatorFactory/ModuleFactory, wiring View+ViewModel. Covers Factory pattern that connects DI container with Coordinators without Service Locator. Also covers non-UI factories and late/conditional initialization patterns."
---

# Module Assembly Pattern

Connects Dependency Injection with Coordinators through explicit Factory objects. Coordinators never touch the DI container directly — they receive pre-built modules from Factories.

> **Related skills:**
> - `di-composition-root` — where the CR lives, how it passes dependencies to Factories (extracted separately — this skill **no longer describes CR in detail**, just uses it)
> - `di-swinject` — Swinject specifics, if chosen as the DI framework
> - `di-factory` — Factory (hmlongco) specifics. The architectural pattern (`AppDependencies` → `CoordinatorFactory` → `ModuleFactory`) is identical; only the `AppDependencyContainer` facade implementation changes (instead of `container.resolve(...)` — `Container.shared.foo()`)
> - `pkg-spm-design` — how Module Assembly applies inside an SPM package (Feature archetype)

## Problem

Without Factories, coordinators become dependency dumps:

```swift
// Anti-pattern: Coordinator as Service Locator
class FeatureCoordinator: BaseCoordinator {
    private let container: Resolver  // knows about DI container

    func start() {
        // Hidden dependencies — impossible to know what's needed without reading body
        let viewModel = container.resolve(FeatureViewModelProtocol.self)!
        let viewController = FeatureViewController(viewModel: viewModel)
        router.push(viewController)
    }
}
```

Problems:
- Coordinator has hidden dependencies (only visible at runtime)
- Crash if registration is missing — no compile-time safety
- Hard to test — need full container setup
- Violates Dependency Inversion — high-level module depends on container

## Architecture Overview

```
SceneDelegate (Composition Root)
    └── AppDependencyContainer (DI facade)
            └── CoordinatorFactory (creates coordinators)
                    └── ModuleFactory (assembles View + ViewModel)
                            └── Assembly (actual wiring per module)
                                    └── ModuleComponents<View, ViewModel>
```

**Rules:**
- Only `AppDependencyContainer` knows about DI container internals
- `CoordinatorFactory` knows about `ModuleFactory` and dependency protocols
- `ModuleFactory` delegates to `Assembly` enums
- `Assembly` receives only the dependency protocol it needs
- Coordinators receive only `CoordinatorFactory` + typed `ModuleFactory` protocol

## ModuleComponents

Type-safe container for assembled module:

```swift
struct ModuleComponents<View, ViewModel> {
    let view: View
    let viewModel: ViewModel
}
```

## Feature Dependency Protocols

Each feature declares **only the dependencies it needs**:

```swift
// Feature declares what it needs — nothing more
protocol ProfileFeatureDependencies {
    var userService: UserServiceProtocol { get }
    var analyticsService: AnalyticsServiceProtocol { get }
    var imageLoader: ImageLoaderProtocol { get }
}

protocol SettingsFeatureDependencies {
    var appSettingsManager: AppSettingsManagerProtocol { get }
    var userService: UserServiceProtocol { get }
}

// App container conforms to all feature protocols
protocol AppDependencies: ProfileFeatureDependencies,
                          SettingsFeatureDependencies,
                          HomeFeatureDependencies {
    // Composite — no additional requirements
}
```

**Why feature protocols matter:**
- Assembly accepts only its protocol — compile-time guarantee of minimal dependencies
- Adding a dependency to a feature = changing its protocol = compiler shows all affected code
- Easy to create focused test doubles — mock only what the feature needs

## Assembly

Static factory that performs actual wiring. One per module. Receives only its feature dependency protocol:

```swift
enum ProfileAssembly {
    @MainActor
    static func assemble(dependencies: ProfileFeatureDependencies)
        -> ModuleComponents<ProfileViewController, ProfileViewModel> {

        let viewModel = ProfileViewModel(
            userService: dependencies.userService,
            analyticsService: dependencies.analyticsService
        )
        let view = ProfileViewController(viewModel: viewModel)
        return ModuleComponents(view: view, viewModel: viewModel)
    }
}
```

**Why `enum`:** No state, no instances — pure factory function. Prevents accidental instantiation.

For modules that need runtime parameters:

```swift
enum DetailAssembly {
    @MainActor
    static func assemble(
        dependencies: ProfileFeatureDependencies,
        itemId: String
    ) -> ModuleComponents<DetailViewController, DetailViewModel> {

        let viewModel = DetailViewModel(
            itemId: itemId,
            userService: dependencies.userService
        )
        let view = DetailViewController(viewModel: viewModel)
        return ModuleComponents(view: view, viewModel: viewModel)
    }
}
```

## ModuleFactory

Creates modules for Coordinators. Split into feature-specific protocols:

```swift
// Each feature has its own factory protocol
@MainActor
protocol ProfileModuleFactory {
    func makeProfileModule() -> ModuleComponents<ProfileViewController, ProfileViewModel>
    func makeDetailModule(itemId: String) -> ModuleComponents<DetailViewController, DetailViewModel>
    func makeEditProfileModule() -> ModuleComponents<EditProfileViewController, EditProfileViewModel>
}

@MainActor
protocol SettingsModuleFactory {
    func makeSettingsModule() -> ModuleComponents<SettingsViewController, SettingsViewModel>
}

@MainActor
protocol HomeModuleFactory {
    func makeHomeModule() -> ModuleComponents<HomeViewController, HomeViewModel>
}
```

Single implementation conforms to all protocols:

```swift
@MainActor
final class ModuleFactoryImp: ProfileModuleFactory,
                               SettingsModuleFactory,
                               HomeModuleFactory {

    private let dependencies: AppDependencies

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
    }

    // MARK: - ProfileModuleFactory

    func makeProfileModule() -> ModuleComponents<ProfileViewController, ProfileViewModel> {
        ProfileAssembly.assemble(dependencies: dependencies)
    }

    func makeDetailModule(itemId: String) -> ModuleComponents<DetailViewController, DetailViewModel> {
        DetailAssembly.assemble(dependencies: dependencies, itemId: itemId)
    }

    func makeEditProfileModule() -> ModuleComponents<EditProfileViewController, EditProfileViewModel> {
        EditProfileAssembly.assemble(dependencies: dependencies)
    }

    // MARK: - SettingsModuleFactory

    func makeSettingsModule() -> ModuleComponents<SettingsViewController, SettingsViewModel> {
        SettingsAssembly.assemble(dependencies: dependencies)
    }

    // MARK: - HomeModuleFactory

    func makeHomeModule() -> ModuleComponents<HomeViewController, HomeViewModel> {
        HomeAssembly.assemble(dependencies: dependencies)
    }
}
```

**Why feature-specific protocols:** Coordinator receives only `ProfileModuleFactory`, not the full `ModuleFactoryImp`. It can only create modules it's responsible for.

## CoordinatorFactory

Creates Coordinators with their ModuleFactory and Router:

```swift
@MainActor
protocol CoordinatorFactory {
    func makeProfileCoordinator(router: Router) -> ProfileCoordinator
    func makeSettingsCoordinator(router: Router) -> SettingsCoordinator
    func makeHomeCoordinator(router: Router) -> HomeCoordinator
    func makeTabBarCoordinator(router: Router) -> TabBarCoordinator
}

@MainActor
final class CoordinatorFactoryImp: CoordinatorFactory {
    private let dependencies: AppDependencies
    private let moduleFactory: ModuleFactoryImp

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
        self.moduleFactory = ModuleFactoryImp(dependencies: dependencies)
    }

    func makeProfileCoordinator(router: Router) -> ProfileCoordinator {
        ProfileCoordinator(
            router: router,
            coordinatorFactory: self,
            factory: moduleFactory  // passed as ProfileModuleFactory
        )
    }

    func makeSettingsCoordinator(router: Router) -> SettingsCoordinator {
        SettingsCoordinator(
            router: router,
            coordinatorFactory: self,
            factory: moduleFactory
        )
    }

    func makeHomeCoordinator(router: Router) -> HomeCoordinator {
        HomeCoordinator(
            router: router,
            coordinatorFactory: self,
            factory: moduleFactory
        )
    }

    func makeTabBarCoordinator(router: Router) -> TabBarCoordinator {
        TabBarCoordinator(
            router: router,
            coordinatorFactory: self,
            factory: moduleFactory
        )
    }
}
```

## Coordinator Usage

Coordinator receives typed factory protocols — no container, no resolve calls:

```swift
@MainActor
final class ProfileCoordinator: BaseCoordinator {
    private let router: Router
    private let coordinatorFactory: CoordinatorFactory
    private let view: ProfileViewController
    private let viewModel: ProfileViewModel

    // onFinish signal to parent
    var onFinish: (() -> Void)?

    init(router: Router,
         coordinatorFactory: CoordinatorFactory,
         factory: ProfileModuleFactory) {

        self.router = router
        self.coordinatorFactory = coordinatorFactory

        // Module assembled by factory — Coordinator doesn't know how
        let module = factory.makeProfileModule()
        self.view = module.view
        self.viewModel = module.viewModel
    }

    override func start() {
        viewModel.onEditProfile = { [weak self] in
            self?.showEditProfile()
        }
        viewModel.onOpenSettings = { [weak self] in
            self?.showSettings()
        }
        router.push(view)
    }

    private func showEditProfile() {
        // For child screens within same feature — use moduleFactory
        // (Coordinator keeps reference to its own factory)
    }

    private func showSettings() {
        // For different feature — use coordinatorFactory
        let coordinator = coordinatorFactory.makeSettingsCoordinator(router: router)
        coordinator.onFinish = { [weak self, weak coordinator] in
            guard let coordinator else { return }
            self?.removeChild(coordinator)
        }
        addChild(coordinator)
        coordinator.start()
    }
}
```

## Composition Root (its brief role in Module Assembly)

The CR creates `AppDependencyContainer`, passes it to `CoordinatorFactoryImp`, creates the root Coordinator and starts the UI. Full CR description — bootstrap patterns, scope strategies, testing, what does NOT belong there — see the **`di-composition-root` skill**.

Minimal example for context (UIKit, SceneDelegate):

```swift
let container = AppDependencyContainer()
container.bootstrap()
let coordinatorFactory = CoordinatorFactoryImp(dependencies: container)
let router = AppRouter(navigationController: UINavigationController())
let appCoordinator = ApplicationCoordinator(router: router, coordinatorFactory: coordinatorFactory)
appCoordinator.start()
```

## AppDependencyContainer

Facade over Swinject that conforms to all feature dependency protocols:

The facade itself stays **nonisolated**. UI construction remains `@MainActor`
on `Assembly`, `ModuleFactory`, `CoordinatorFactory`, and Coordinator methods;
the dependency container may also be used by background services.

```swift
final class AppDependencyContainer: AppDependencies {

    private let container = Container()

    func bootstrap() {
        registerServices()
    }

    // MARK: - AppDependencies conformance

    var userService: UserServiceProtocol {
        container.resolve(UserServiceProtocol.self)!
    }

    var analyticsService: AnalyticsServiceProtocol {
        container.resolve(AnalyticsServiceProtocol.self)!
    }

    var appSettingsManager: AppSettingsManagerProtocol {
        container.resolve(AppSettingsManagerProtocol.self)!
    }

    var imageLoader: ImageLoaderProtocol {
        container.resolve(ImageLoaderProtocol.self)!
    }

    // MARK: - Private

    private func registerServices() {
        container.register(UserServiceProtocol.self) { _ in
            UserService()
        }.inObjectScope(.container)

        container.register(AnalyticsServiceProtocol.self) { _ in
            AnalyticsService()
        }.inObjectScope(.container)

        // ... more registrations
    }
}
```

**Key insight:** Swinject `container.resolve()` calls happen **only inside AppDependencyContainer**. The rest of the app works with typed protocols — no container leaks out.

### Implementation without a DI framework

`AppDependencyContainer` can be implemented with `lazy var` fields instead of Swinject — the external contract (`AppDependencies` + per-feature `*FeatureDependencies`) is identical, the rest of the chain (`CoordinatorFactory`, `ModuleFactory`, `Assembly`) is unchanged.

```swift
final class AppDependencyContainer: AppDependencies {
    lazy var userService: UserServiceProtocol = UserService(networkClient: networkClient)
    lazy var analyticsService: AnalyticsServiceProtocol = AnalyticsService()
    private lazy var networkClient: HTTPClient = URLSessionHTTPClient()

    func bootstrap() { _ = networkClient; _ = userService }
}
```

Use for small apps (< 30 services) and **mandatory** for SPM packages (see `pkg-spm-design`). Full comparison, scope strategies, and handling of cycles — in `di-composition-root`, section "DI: container vs manual graph".

## File Structure

```
App/
├── SceneDelegate.swift                          # Composition Root
├── DependencyInjection/
│   ├── AppDependencyContainer.swift             # DI facade, conforms to AppDependencies
│   ├── ModuleComponents.swift                   # Generic <View, ViewModel> container
│   ├── Protocols/
│   │   ├── AppDependencies.swift                # Composite protocol
│   │   ├── ProfileFeatureDependencies.swift     # Per-feature dependency protocol
│   │   ├── SettingsFeatureDependencies.swift
│   │   └── HomeFeatureDependencies.swift
│   └── ModuleFactory/
│       ├── ProfileModuleFactory.swift           # Per-feature factory protocol
│       ├── SettingsModuleFactory.swift
│       ├── HomeModuleFactory.swift
│       └── ModuleFactoryImp.swift               # Single implementation
├── Coordinators/
│   ├── Factories/
│   │   ├── CoordinatorFactory.swift             # Protocol
│   │   └── CoordinatorFactoryImp.swift          # Implementation
│   ├── ApplicationCoordinator.swift
│   └── TabBarCoordinator.swift
└── Modules/
    ├── Profile/
    │   ├── ProfileAssembly.swift                # enum, static assemble()
    │   ├── ProfileCoordinator.swift
    │   ├── ProfileViewController.swift
    │   └── ProfileViewModel.swift
    └── Settings/
        ├── SettingsAssembly.swift
        ├── SettingsCoordinator.swift
        ├── SettingsViewController.swift
        └── SettingsViewModel.swift
```

## Testing

### Testing Coordinators (no container needed)

```swift
class ProfileCoordinatorTests: XCTestCase {
    var sut: ProfileCoordinator!
    var mockRouter: MockRouter!
    var mockCoordinatorFactory: MockCoordinatorFactory!
    var mockModuleFactory: MockProfileModuleFactory!

    @MainActor
    override func setUp() {
        mockRouter = MockRouter()
        mockCoordinatorFactory = MockCoordinatorFactory()
        mockModuleFactory = MockProfileModuleFactory()
        sut = ProfileCoordinator(
            router: mockRouter,
            coordinatorFactory: mockCoordinatorFactory,
            factory: mockModuleFactory
        )
    }

    @MainActor
    func test_start_pushesProfileView() {
        sut.start()
        XCTAssertTrue(mockRouter.pushedViewController is ProfileViewController)
    }
}

// Mock factory returns controlled modules
class MockProfileModuleFactory: ProfileModuleFactory {
    func makeProfileModule() -> ModuleComponents<ProfileViewController, ProfileViewModel> {
        let vm = ProfileViewModel(
            userService: MockUserService(),
            analyticsService: MockAnalyticsService()
        )
        let vc = ProfileViewController(viewModel: vm)
        return ModuleComponents(view: vc, viewModel: vm)
    }
}
```

### Testing Assemblies

```swift
class ProfileAssemblyTests: XCTestCase {
    @MainActor
    func test_assemble_createsConnectedModule() {
        let deps = MockProfileDependencies()
        let module = ProfileAssembly.assemble(dependencies: deps)

        XCTAssertNotNil(module.view)
        XCTAssertNotNil(module.viewModel)
    }
}

class MockProfileDependencies: ProfileFeatureDependencies {
    var userService: UserServiceProtocol = MockUserService()
    var analyticsService: AnalyticsServiceProtocol = MockAnalyticsService()
    var imageLoader: ImageLoaderProtocol = MockImageLoader()
}
```

## When to Use

**Use this pattern when:**
- App has 5+ screens with navigation between features
- Using Coordinator pattern for navigation
- Using Swinject or other DI container
- Want compile-time safety for dependency graph
- Need testable coordinators without DI container in tests

**Skip for:**
- Simple apps with 2-3 screens — manual DI in Coordinator is fine
- SwiftUI-only apps with NavigationStack — use Environment instead
- Prototypes — overhead not justified

## Scaling

**Growing number of modules:** Split `ModuleFactoryImp` into feature-grouped partial implementations using extensions, or separate factory classes per feature group.

**Shared sub-modules:** If two features share a sub-screen, create a shared factory protocol that both coordinators accept.

**Runtime parameters:** Assembly accepts parameters alongside dependencies:
```swift
static func assemble(dependencies: ProfileFeatureDependencies, userId: String)
    -> ModuleComponents<ProfileViewController, ProfileViewModel>
```

## Beyond UI Modules

The Factory pattern applies **not only to View+ViewModel pairs**. Real projects need a few more flavors of factories and late-initialization strategies.

### Non-UI factories

When you need to build complex non-UI objects with runtime parameters or context:

| Type | What it assembles | Example |
|---|---|---|
| **AlertFactory** | UIAlertController with typed actions | `ProjectStorageAlertFactory.makeOverwriteConfirmation(onConfirm:)` |
| **DataProviderFactory** | DataSource/Adapter for a specific screen or collection | `TimelineContainerDataProviderFactory.make(for: track)` |
| **Stub/Mock factories** | Test doubles for UI screenshots, demo mode | `StubServicesFactory.makeOfflineMode()` |
| **DTO factories** | Complex domain structures built from many fields | `RenderRequestFactory.makeFor(project:, settings:)` |

The rules are the same as for ModuleFactory:
- Dependencies via init (from a narrow `Dependencies` protocol)
- Pure `make(...)` function — no side effects
- `enum` for stateless / `final class` for those that hold a cache or dependencies
- Only internal API exposed — no `static let shared`

### Late & Conditional Initialization

The CR creates the **root** of the graph, but not all objects are created at startup. Several typical scenarios:

| Scenario | Solution | Example |
|---|---|---|
| **Runtime parameter** (`itemId`, `userId`) | Assembly takes `(deps, param)` | `DetailAssembly.assemble(dependencies:, itemId:)` — see section above "Modules that need runtime parameters" |
| **Heavy resource** | `lazy var` in AppDependencyContainer | `lazy var renderEngine: RenderEngine = makeRenderEngine()` |
| **Per-flow service** | Created by the Coordinator on `start()`, disposed on `finish` | `OnboardingState`, `CheckoutSession` |
| **Config from user input** | Service has `configure(with:)` or `bootstrap(token:)` | `APIClient.configure(token:)` after login |
| **Async init** | See `di-composition-root`, section "Async bootstrap" | DB with migrations, cache warm-up |
| **Conditional creation** (Pro-only feature) | Lazy + flag check in the getter; or a separate factory method that the Coordinator calls only under the right condition | Player with/without Metal rendering — branch in `createPlayerModule()` |
| **Circular dependencies** | See `di-swinject` skill, "Circular Dependencies" — property injection or introducing a third type | A↔B → A→C, B→C |

General rule: **CR is the root, not the only place where things get created.** If something can't be created at the CR — that's not a reason to drag the container into the call site (Service Locator). It's a reason to extract the creation logic into a factory or Assembly with explicit parameters.

### When to apply the Factory pattern outside UI

Not every object creation needs a factory. Use one when at least one of the following holds:
- The object is complex (≥3 dependencies)
- The object is built from context parameters known only at runtime
- Creation requires conditional logic (platform, feature flag, config)
- The same type is created in multiple places (DRY)
- Creation has side effects that need to be isolated (observer registration, starting a timer)

If none of these apply — a plain inline init is better. Premature factory introduction complicates the code without any benefit.

## Common Mistakes

1. **Coordinator resolving from container** — Coordinator should never import Swinject or call `resolve()`. It receives factories.
2. **Fat ModuleFactoryImp** — If it has 30+ methods, split by feature group using extensions or separate classes.
3. **Assembly with side effects** — Assembly should only wire objects. No analytics, no logging, no network calls.
4. **Skipping feature dependency protocols** — Passing `AppDependencies` everywhere defeats the purpose. Each Assembly should accept its minimal protocol.
5. **Creating ModuleFactory inside Coordinator** — Factory is created once in CoordinatorFactory and passed down. Coordinator doesn't create factories.
6. **Premature factory for trivial init** — `UserFactory.make() -> User { User() }` is pointless. Apply Factory only with real complexity (see the checklist "When to apply the Factory pattern outside UI").
