---
name: module-assembly
description: "Use when assembling UI modules (MVVM/MVVM+Coordinator), creating CoordinatorFactory/ModuleFactory, wiring View+ViewModel. Covers Factory pattern that connects DI container with Coordinators without Service Locator. Also covers non-UI factories and late/conditional initialization patterns."
---

# Module Assembly Pattern

Connects Dependency Injection with Coordinators through explicit Factory objects. Coordinators never touch the DI container directly — they receive pre-built modules from Factories.

> **Related skills:**
> - `composition-root` — где живёт CR, как он передаёт зависимости в Factory-и (вынесено отдельно — этот скилл больше **не описывает CR подробно**, только использует)
> - `swinject` — Swinject-специфика, если выбран как DI-framework
> - `spm-package-design` — как Module Assembly применяется внутри SPM-пакета (Feature-архетип)

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

## Composition Root (краткая роль в Module Assembly)

CR создаёт `AppDependencyContainer`, передаёт его в `CoordinatorFactoryImp`, создаёт root-Coordinator и стартует UI. Полное описание CR — паттерны bootstrap, scope-стратегии, тестирование, что в нём НЕ должно быть — см. **`composition-root` skill**.

Минимальный пример для контекста (UIKit, SceneDelegate):

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

```swift
@MainActor
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

Factory-паттерн применим **не только к парам View+ViewModel**. В реальных проектах нужны ещё несколько разновидностей фабрик и стратегий late initialization.

### Non-UI factories

Когда нужно создавать сложные не-UI объекты с runtime-параметрами или контекстом:

| Тип | Что собирает | Пример |
|---|---|---|
| **AlertFactory** | UIAlertController с типизированными actions | `ProjectStorageAlertFactory.makeOverwriteConfirmation(onConfirm:)` |
| **DataProviderFactory** | DataSource/Adapter под конкретный экран или коллекцию | `TimelineContainerDataProviderFactory.make(for: track)` |
| **Stub/Mock factories** | Тестовые двойники для UI-screenshots, demo-mode | `StubServicesFactory.makeOfflineMode()` |
| **DTO factories** | Сложные доменные структуры из множества полей | `RenderRequestFactory.makeFor(project:, settings:)` |

Правила те же, что для ModuleFactory:
- Зависимости через init (от своего узкого `Dependencies`-протокола)
- Чистая функция `make(...)` — без побочных эффектов
- `enum` для stateless / `final class` для тех, что хранят кэш или зависимости
- Только internal API наружу — никаких `static let shared`

### Late & Conditional Initialization

CR создаёт **корень** графа, но не все объекты создаются на старте. Несколько типичных сценариев:

| Сценарий | Решение | Пример |
|---|---|---|
| **Runtime-параметр** (`itemId`, `userId`) | Assembly принимает `(deps, param)` | `DetailAssembly.assemble(dependencies:, itemId:)` — см. секцию выше «Modules that need runtime parameters» |
| **Тяжёлый ресурс** | `lazy var` в AppDependencyContainer | `lazy var renderEngine: RenderEngine = makeRenderEngine()` |
| **Per-flow сервис** | Создаётся Coordinator-ом на `start()`, dispose на `finish` | `OnboardingState`, `CheckoutSession` |
| **Конфиг из user input** | Сервис имеет `configure(with:)` или `bootstrap(token:)` | `APIClient.configure(token:)` после логина |
| **Async init** | См. `composition-root`, секция «Async bootstrap» | БД с миграциями, прогрев кэша |
| **Условное создание** (Pro-only фича) | Lazy + проверка флага в getter; либо отдельный фабричный метод, который Coordinator вызывает только при нужном условии | Player с/без Metal-rendering — ветка в `createPlayerModule()` |
| **Циклические зависимости** | См. `swinject` skill, «Circular Dependencies» — property injection или ввод третьего типа | A↔B → A→C, B→C |

Общее правило: **CR — это корень, а не единственное место создания.** Если что-то нельзя создать в CR — это не повод тащить контейнер в место использования (Service Locator). Это повод вынести логику создания в фабрику или Assembly с явными параметрами.

### Когда применять Factory-паттерн вне UI

Не каждое создание объекта требует фабрики. Применяй её, когда выполнено хотя бы одно:
- Объект сложный (≥3 зависимости)
- Объект собирается из контекстных параметров, известных только в рантайме
- Создание требует условной логики (платформа, фича-флаг, конфиг)
- Один и тот же тип создаётся в нескольких местах (DRY)
- Создание имеет побочные эффекты, которые надо изолировать (регистрация observer-а, запуск таймера)

Если ничего из этого нет — обычный init на месте лучше. Преждевременное введение фабрики усложняет код без пользы.

## Common Mistakes

1. **Coordinator resolving from container** — Coordinator should never import Swinject or call `resolve()`. It receives factories.
2. **Fat ModuleFactoryImp** — If it has 30+ methods, split by feature group using extensions or separate classes.
3. **Assembly with side effects** — Assembly should only wire objects. No analytics, no logging, no network calls.
4. **Skipping feature dependency protocols** — Passing `AppDependencies` everywhere defeats the purpose. Each Assembly should accept its minimal protocol.
5. **Creating ModuleFactory inside Coordinator** — Factory is created once in CoordinatorFactory and passed down. Coordinator doesn't create factories.
6. **Premature factory for trivial init** — `UserFactory.make() -> User { User() }` бессмысленна. Применяй Factory только при реальной сложности (см. чек-лист «Когда применять Factory-паттерн вне UI»).
