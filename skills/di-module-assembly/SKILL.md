---
name: di-module-assembly
description: "Use when assembling UI modules (MVVM/MVVM+Coordinator), creating CoordinatorFactory/ModuleFactory, wiring View+ViewModel. Covers Factory pattern that connects DI container with Coordinators without Service Locator. Also covers non-UI factories and late/conditional initialization patterns."
---

# Module Assembly Pattern

Connect DI to Coordinators through explicit factories. Coordinators never touch
the DI container directly; they receive typed factories that create modules.

Detailed examples live in `references/detailed-guide.md`. Load only the relevant
section with `rg -n "^## " skills/di-module-assembly/references/detailed-guide.md`.

## When To Load The Reference

| Need | Reference sections |
|---|---|
| Understand the full chain | `Architecture Overview` |
| Define feature dependency protocols | `Feature Dependency Protocols` |
| Build View + ViewModel | `Assembly`, `ModuleComponents` |
| Create feature module factories | `ModuleFactory` |
| Create coordinators | `CoordinatorFactory`, `Coordinator Usage` |
| See the Composition Root role | `Composition Root`, `AppDependencyContainer` |
| Choose files/folders | `File Structure` |
| Test coordinators or assemblies | `Testing` |
| Apply factories outside UI | `Beyond UI Modules` |

## Problem

The anti-pattern:

```swift
final class ProfileCoordinator {
    private let resolver: Resolver

    func start() {
        let viewModel = resolver.resolve(ProfileViewModel.self)!
        let view = ProfileViewController(viewModel: viewModel)
        router.push(view)
    }
}
```

This hides dependencies, couples navigation to a DI framework, crashes at
runtime for missing registrations, and makes coordinator tests require a full
container.

## Canonical Chain

```
Composition Root
  -> AppDependencyContainer (DI facade)
  -> CoordinatorFactory
  -> ModuleFactory
  -> Assembly
  -> ModuleComponents<View, ViewModel>
```

Rules:

- Only `AppDependencyContainer` knows DI internals.
- `CoordinatorFactory` creates Coordinators and passes typed ModuleFactory
  protocols.
- `ModuleFactory` delegates to stateless Assembly functions.
- Assemblies receive the narrow feature dependency protocol they need.
- Coordinators receive factories, routers, and child-coordinator factories. They
  do not receive `Container`, `Resolver`, or service locators.

## Feature Dependency Protocols

Each feature declares the minimum dependencies it needs:

```swift
protocol ProfileFeatureDependencies {
    var userService: UserServiceProtocol { get }
    var analyticsService: AnalyticsServiceProtocol { get }
}

protocol AppDependencies: ProfileFeatureDependencies,
                          SettingsFeatureDependencies {}
```

Benefits:

- Adding a dependency changes a protocol and lets the compiler show every
  affected assembly/test double.
- Tests mock only the feature's narrow surface.
- SPM feature packages can accept the same dependency protocol without importing
  the DI framework.

## Assembly

One stateless assembly per module:

```swift
enum ProfileAssembly {
    @MainActor
    static func assemble(
        dependencies: ProfileFeatureDependencies
    ) -> ModuleComponents<ProfileViewController, ProfileViewModel> {
        let viewModel = ProfileViewModel(
            userService: dependencies.userService,
            analyticsService: dependencies.analyticsService
        )
        let view = ProfileViewController(viewModel: viewModel)
        return ModuleComponents(view: view, viewModel: viewModel)
    }
}
```

Use `enum` for stateless assemblies. Add runtime parameters to the `assemble`
method, not to a hidden container resolve.

## ModuleFactory

Coordinators depend on feature-specific factory protocols:

```swift
@MainActor
protocol ProfileModuleFactory {
    func makeProfileModule() -> ModuleComponents<ProfileViewController, ProfileViewModel>
    func makeDetailModule(itemId: String) -> ModuleComponents<DetailViewController, DetailViewModel>
}
```

A single implementation may conform to several factory protocols, but each
Coordinator receives only the one it needs. This keeps the coordinator's module
creation surface narrow.

## CoordinatorFactory

`CoordinatorFactory` creates Coordinators with their router, child coordinator
factory access, and typed module factory:

```swift
@MainActor
protocol CoordinatorFactory {
    func makeProfileCoordinator(router: Router) -> ProfileCoordinator
}
```

Coordinator constructors should be explicit:

```swift
init(
    router: Router,
    coordinatorFactory: CoordinatorFactory,
    factory: ProfileModuleFactory
)
```

No `Resolver`, no `Container`, no global `shared`.

## AppDependencyContainer

`AppDependencyContainer` is the facade over the concrete DI mechanism:

- With Swinject, it is the only app-facing type that calls `container.resolve`.
- With FactoryKit, it is the only app-facing type that resolves from
  `Container.shared`.
- With manual DI, it exposes `lazy var` dependencies.

The external contract is the same: it conforms to `AppDependencies` and the rest
of the app sees only feature dependency protocols.

Keep the facade itself nonisolated unless it truly owns UI state. UI creation is
`@MainActor` on assemblies, module factories, coordinator factories, and
coordinator methods.

## Non-UI Factories

Use the same pattern for complex non-UI objects when creation has runtime
parameters, feature flags, side effects, or several dependencies:

- alert factories,
- data-provider/adapter factories,
- screenshot/demo stub factories,
- DTO/domain factory helpers,
- per-flow service/session factories.

Do not introduce factories for trivial initializers.

## Late And Conditional Initialization

The Composition Root creates the graph root, not every object eagerly.

Use:

- assembly/factory parameters for runtime IDs,
- `lazy var` for heavy resources,
- per-flow services created by the Coordinator on `start()`,
- explicit `configure`/`bootstrap` for post-login/user-driven config,
- async Composition Root bootstrap for migrations and cache warm-up,
- factories for feature-flagged or platform-conditional modules.

If something cannot be created in the Composition Root, that is not a reason to
pass the DI container down. Extract a factory with explicit parameters.

## Testing

- Coordinator tests pass mock router, mock coordinator factory, and mock module
  factory. No DI container is needed.
- Assembly tests pass a mock feature dependency protocol and assert connected
  View/ViewModel output.
- ModuleFactory tests verify parameter forwarding and correct assembly calls.
- AppDependencyContainer tests can exercise the actual container graph separately.

## When To Use

Use this pattern when an app has Coordinators, cross-feature navigation, or
enough screens that hidden dependencies are already hurting tests.

Skip for tiny prototypes and simple 2-3 screen apps. For SwiftUI-only
NavigationStack apps, environment-based composition may be enough.

## Common Mistakes

- Coordinator resolving from the container.
- Passing `AppDependencies` everywhere instead of narrow feature protocols.
- Creating ModuleFactory inside a Coordinator.
- Assemblies doing side effects beyond wiring.
- Fat `ModuleFactoryImp` with dozens of methods and no feature grouping.
- Premature factories for trivial `init` calls.
- Hiding runtime parameters in DI arguments instead of explicit factory methods.
