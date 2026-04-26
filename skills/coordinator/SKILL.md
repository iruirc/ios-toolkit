---
name: coordinator
description: "Use when implementing Coordinator navigation pattern in iOS apps. Covers child coordinator lifecycle, Router abstraction, deep linking, tab bar coordination, and communication patterns. Uses Factory pattern for module assembly — see module-assembly skill for full Factory details."
---

# Coordinator Pattern

Navigation pattern that extracts routing logic from ViewControllers into dedicated Coordinator objects. Orthogonal to architectural pattern — works with MVC, MVVM, VIPER, etc.

**Scope:** this skill covers the **UIKit** Coordinator pattern (imperative `push`/`present` via `UINavigationController`). For SwiftUI-first apps use `swiftui-navigation` instead — the SwiftUI equivalent is a state-driven `@Observable` Router holding a `NavigationPath`. For hybrid apps (UIKit Coordinators + embedded SwiftUI screens via `UIHostingController`), see the «Hybrid: SwiftUI ↔ UIKit Interop» section in `swiftui-navigation`.

> **Related skills:**
> - `swiftui-navigation` — SwiftUI-native navigation (NavigationStack/Path, Router class, deep links, hybrid interop)
> - `module-assembly` — covers CoordinatorFactory, ModuleFactory, Assembly in detail
> - `composition-root` — where Coordinators get bootstrapped (SceneDelegate / @main App / AppDelegate)
> - `swinject` — DI-framework-specific patterns if Swinject is the chosen container

## Structure

```
Feature/
├── FeatureCoordinator.swift     # Navigation + flow control
├── FeatureViewController.swift  # UI (no navigation logic)
├── FeatureViewModel.swift       # Business logic (if MVVM)
└── Models/
```

## Core Protocol

```swift
protocol Coordinator: AnyObject {
    var childCoordinators: [Coordinator] { get set }
    func start()
}

extension Coordinator {
    func addChild(_ coordinator: Coordinator) {
        childCoordinators.append(coordinator)
    }

    func removeChild(_ coordinator: Coordinator) {
        childCoordinators.removeAll { $0 === coordinator }
    }
}
```

## Base Coordinator

```swift
class BaseCoordinator: Coordinator {
    var childCoordinators: [Coordinator] = []

    func start() {
        fatalError("Subclass must implement start()")
    }
}
```

## Router Abstraction

Wrap UINavigationController to make Coordinators testable:

```swift
protocol Router: AnyObject {
    func push(_ viewController: UIViewController, animated: Bool)
    func pop(animated: Bool)
    func present(_ viewController: UIViewController, animated: Bool)
    func dismiss(animated: Bool)
    func setRoot(_ viewController: UIViewController, animated: Bool)
}

class AppRouter: Router {
    private let navigationController: UINavigationController

    init(navigationController: UINavigationController) {
        self.navigationController = navigationController
    }

    func push(_ viewController: UIViewController, animated: Bool = true) {
        navigationController.pushViewController(viewController, animated: animated)
    }

    func pop(animated: Bool = true) {
        navigationController.popViewController(animated: animated)
    }

    func present(_ viewController: UIViewController, animated: Bool = true) {
        navigationController.present(viewController, animated: animated)
    }

    func dismiss(animated: Bool = true) {
        navigationController.dismiss(animated: animated)
    }

    func setRoot(_ viewController: UIViewController, animated: Bool = false) {
        navigationController.setViewControllers([viewController], animated: animated)
    }
}
```

## Feature Coordinator

Coordinator receives factories — never the DI container. See `module-assembly` skill for Factory details.

```swift
class FeatureCoordinator: BaseCoordinator {
    private let router: Router
    private let coordinatorFactory: CoordinatorFactory
    private let view: FeatureViewController
    private let viewModel: FeatureViewModel

    // Completion signal to parent
    var onFinish: ((FeatureResult) -> Void)?

    init(router: Router,
         coordinatorFactory: CoordinatorFactory,
         factory: FeatureModuleFactory) {
        self.router = router
        self.coordinatorFactory = coordinatorFactory

        let module = factory.makeFeatureModule()
        self.view = module.view
        self.viewModel = module.viewModel
    }

    override func start() {
        // ViewModel signals navigation intent, Coordinator decides
        viewModel.onItemSelected = { [weak self] item in
            self?.showDetail(for: item)
        }

        viewModel.onComplete = { [weak self] result in
            self?.onFinish?(result)
        }

        router.push(view)
    }

    private func showDetail(for item: Item) {
        let detailCoordinator = coordinatorFactory.makeDetailCoordinator(
            router: router,
            item: item
        )

        detailCoordinator.onFinish = { [weak self, weak detailCoordinator] in
            guard let detailCoordinator else { return }
            self?.removeChild(detailCoordinator)
        }

        addChild(detailCoordinator)
        detailCoordinator.start()
    }
}
```

## App Coordinator (Root)

```swift
class AppCoordinator: BaseCoordinator {
    private let router: Router
    private let coordinatorFactory: CoordinatorFactory

    init(router: Router, coordinatorFactory: CoordinatorFactory) {
        self.router = router
        self.coordinatorFactory = coordinatorFactory
    }

    override func start() {
        if userIsLoggedIn {
            showMainFlow()
        } else {
            showAuthFlow()
        }
    }

    private func showAuthFlow() {
        let authCoordinator = coordinatorFactory.makeAuthCoordinator(router: router)
        authCoordinator.onFinish = { [weak self, weak authCoordinator] in
            guard let authCoordinator else { return }
            self?.removeChild(authCoordinator)
            self?.showMainFlow()
        }
        addChild(authCoordinator)
        authCoordinator.start()
    }

    private func showMainFlow() {
        let mainCoordinator = coordinatorFactory.makeTabBarCoordinator(router: router)
        addChild(mainCoordinator)
        mainCoordinator.start()
    }
}
```

Window setup belongs in SceneDelegate (Composition Root) — see `composition-root` skill.

## Communication Patterns

### ViewModel → Coordinator (closures)

Simple and explicit. Preferred for most cases.

```swift
// In ViewModel
var onItemSelected: ((Item) -> Void)?
var onComplete: (() -> Void)?

// In Coordinator
viewModel.onItemSelected = { [weak self] item in
    self?.showDetail(for: item)
}
```

### ViewModel → Coordinator (delegate)

For complex flows with many navigation signals:

```swift
protocol FeatureNavigationDelegate: AnyObject {
    func didSelectItem(_ item: Item)
    func didTapSettings()
    func didRequestLogout()
    func didFinish(with result: FeatureResult)
}

class FeatureViewModel {
    weak var navigationDelegate: FeatureNavigationDelegate?
}

class FeatureCoordinator: BaseCoordinator, FeatureNavigationDelegate {
    func didSelectItem(_ item: Item) { showDetail(for: item) }
    func didTapSettings() { showSettings() }
    func didRequestLogout() { onFinish?(.logout) }
    func didFinish(with result: FeatureResult) { onFinish?(result) }
}
```

### Child → Parent Coordinator (closures)

```swift
let child = coordinatorFactory.makeChildCoordinator(router: router)
child.onFinish = { [weak self, weak child] result in
    guard let child = child else { return }
    self?.removeChild(child)
    self?.handleChildResult(result)
}
addChild(child)
child.start()
```

## Child Coordinator Lifecycle

**Critical**: always remove child coordinators when they finish, otherwise they leak.

```swift
// Correct — remove child on finish
child.onFinish = { [weak self, weak child] in
    guard let child = child else { return }
    self?.removeChild(child)
}

// Wrong — child never removed, memory leak
child.onFinish = { [weak self] in
    self?.router.pop()
    // forgot to removeChild!
}
```

## Tab Bar Coordinator

```swift
class MainTabCoordinator: BaseCoordinator {
    private let tabBarController = UITabBarController()
    private let router: Router
    private let coordinatorFactory: CoordinatorFactory

    init(router: Router, coordinatorFactory: CoordinatorFactory) {
        self.router = router
        self.coordinatorFactory = coordinatorFactory
    }

    override func start() {
        let homeNav = UINavigationController()
        let homeRouter = AppRouter(navigationController: homeNav)
        let homeCoordinator = coordinatorFactory.makeHomeCoordinator(router: homeRouter)

        let profileNav = UINavigationController()
        let profileRouter = AppRouter(navigationController: profileNav)
        let profileCoordinator = coordinatorFactory.makeProfileCoordinator(router: profileRouter)

        homeNav.tabBarItem = UITabBarItem(title: "Home", image: R.image.tabHome(), tag: 0)
        profileNav.tabBarItem = UITabBarItem(title: "Profile", image: R.image.tabProfile(), tag: 1)

        tabBarController.viewControllers = [homeNav, profileNav]

        addChild(homeCoordinator)
        addChild(profileCoordinator)

        homeCoordinator.start()
        profileCoordinator.start()

        router.setRoot(tabBarController)
    }
}
```

## Deep Link Handling

```swift
class AppCoordinator: BaseCoordinator {
    func handleDeepLink(_ deepLink: DeepLink) {
        switch deepLink {
        case .profile(let userId):
            navigateToProfile(userId: userId)
        case .item(let itemId):
            navigateToItem(itemId: itemId)
        }
    }

    private func navigateToItem(itemId: String) {
        // Reset to main flow if needed
        // Then navigate to specific item
        let detailCoordinator = coordinatorFactory.makeDetailCoordinator(
            router: router,
            itemId: itemId
        )
        detailCoordinator.onFinish = { [weak self, weak detailCoordinator] in
            guard let detailCoordinator else { return }
            self?.removeChild(detailCoordinator)
        }
        addChild(detailCoordinator)
        detailCoordinator.start()
    }
}
```

## DI Registration

Coordinators are created by `CoordinatorFactory`, not resolved from Swinject container directly. See `module-assembly` skill for the full pattern.

## Testing Coordinators

With Factory pattern, coordinators are testable without DI container:

```swift
class FeatureCoordinatorTests: XCTestCase {
    var sut: FeatureCoordinator!
    var mockRouter: MockRouter!
    var mockCoordinatorFactory: MockCoordinatorFactory!
    var mockModuleFactory: MockFeatureModuleFactory!

    @MainActor
    override func setUp() {
        mockRouter = MockRouter()
        mockCoordinatorFactory = MockCoordinatorFactory()
        mockModuleFactory = MockFeatureModuleFactory()
        sut = FeatureCoordinator(
            router: mockRouter,
            coordinatorFactory: mockCoordinatorFactory,
            factory: mockModuleFactory
        )
    }

    @MainActor
    func test_start_pushesFeatureViewController() {
        sut.start()
        XCTAssertTrue(mockRouter.pushedViewController is FeatureViewController)
    }

    @MainActor
    func test_itemSelected_createsChildCoordinator() {
        sut.start()
        sut.viewModel.onItemSelected?(Item(id: "1"))

        XCTAssertEqual(sut.childCoordinators.count, 1)
        XCTAssertTrue(mockCoordinatorFactory.lastCreatedCoordinator is DetailCoordinator)
    }
}

class MockRouter: Router {
    var pushedViewControllers: [UIViewController] = []
    var pushedViewController: UIViewController? { pushedViewControllers.last }

    func push(_ vc: UIViewController, animated: Bool) {
        pushedViewControllers.append(vc)
    }
    func pop(animated: Bool) { pushedViewControllers.removeLast() }
    func present(_ vc: UIViewController, animated: Bool) {}
    func dismiss(animated: Bool) {}
    func setRoot(_ vc: UIViewController, animated: Bool) {}
}
```

## Common Mistakes

1. **Navigation in ViewController** — VC should only signal intent, Coordinator decides destination
2. **Leaking child coordinators** — always `removeChild` when child finishes
3. **Fat coordinators** — split into child coordinators for sub-flows
4. **Strong reference cycles** — use `[weak self, weak child]` in completion closures
5. **Coordinator knowing about UI details** — Coordinator creates VC but doesn't configure UI
