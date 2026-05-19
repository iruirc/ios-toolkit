---
name: di-factory
description: "Use when working with the Factory DI library by hmlongco (FactoryKit) in iOS/macOS apps — registration, property-wrapper injection, scopes, modular containers, contexts, and testing. For Composition Root see di-composition-root; for Coordinator wiring see di-module-assembly."
---

# Factory DI Patterns

Factory-specific guidance for `FactoryKit` 2.5+: `Container` /
`SharedContainer`, computed-property registrations, property-wrapper injection,
scopes, parameterized factories, contexts, modular organization, and tests.

Detailed examples live in `references/detailed-guide.md`. Load only the relevant
section with `rg -n "^## " skills/di-factory/references/detailed-guide.md`.

## When To Load The Reference

| Need | Reference sections |
|---|---|
| Install/import Factory correctly | `Installation` |
| Register services and resolve them | `Core Concepts`, `Resolution: Property Wrappers` |
| Pick `.unique`, `.cached`, `.singleton`, `.graph` | `Scopes` |
| Build ViewModels with runtime IDs | `Parameterized Factories` |
| Add preview/test/debug overrides | `AutoRegistering`, `Contexts` |
| Split registrations by feature | `Modular Containers` |
| Wire Coordinators and ModuleFactory | `Coordinator and Module Assembly` |
| Test `@Injected` code | `Testing` |
| Fix Swift 6 / Observation issues | `Concurrency` |
| Compare or migrate from Swinject | `Swinject vs Factory`, `Migration: Swinject -> Factory` |

## When To Use Factory

Factory is a good fit when:

- You want compile-time checked registration properties.
- You prefer property-wrapper injection (`@Injected`) for presentation objects.
- The app is SwiftUI/Observation-heavy.
- You need built-in test/preview/debug contexts.
- The dependency graph is medium-sized and manual DI is getting noisy.

Prefer alternatives when:

- The graph has fewer than roughly 10 services: use manual DI in the Composition
  Root.
- The app is already stable on Swinject and there is no concrete migration pain.
- The feature is TCA-based: use Point-Free `@Dependency`, not Factory.
- You need name-based runtime lookup with many registrations of the same type:
  Swinject may fit better.

## Core Rules

- Import `FactoryKit` in production code. `import Factory` is the old module
  name.
- Add `FactoryTesting` only to test targets.
- Factory implements the DI container; it does not remove the need for a
  Composition Root. Bootstrap decisions still live in `di-composition-root`.
- Keep Factory out of Domain and SPM package targets. Packages accept explicit
  dependency structs/protocols through `init(dependencies:)`.
- Use `self.foo()` inside Factory closures, not `Container.shared.foo()`, so
  tests and custom containers stay isolated.
- `Container.shared` is allowed in the app composition layer. It is not allowed
  in services, repositories, Domain, or feature packages.

## Registration Shape

Registrations are computed properties on `Container`:

```swift
import FactoryKit

extension Container {
    var userService: Factory<UserServiceProtocol> {
        self { UserService(networkClient: self.networkClient()) }.cached
    }

    var networkClient: Factory<HTTPClient> {
        self { URLSessionHTTPClient() }.cached
    }
}
```

The property name is the registration key. Rename with care because test
overrides and context modifiers use that key.

## Resolution

Use constructor injection by default for services and repositories. Use Factory
property wrappers mainly at graph edges: ViewModels, Coordinators, SwiftUI root
views, or app composition objects.

- `@Injected`: eager required dependency.
- `@LazyInjected`: first-use dependency.
- `@WeakLazyInjected`: weak optional cache/cycle breaker.
- `@InjectedObservable`: SwiftUI root ViewModel integration.

Inside `@Observable` classes, mark injected properties:

```swift
@Observable
final class ContentViewModel {
    @ObservationIgnored @Injected(\.repository) private var repository
}
```

Without `@ObservationIgnored`, injection participates in Observation and can
cause unnecessary UI updates.

## Scopes

| Scope | Use |
|---|---|
| `.unique` | ViewModels, Coordinators, stateful per-screen objects |
| `.cached` | Per-container services, repositories, database clients |
| `.singleton` | Rare process-global resources that must survive reset |
| `.shared` | Weak shared caches |
| `.graph` | One instance within a single top-level resolve |

Default to `.cached` for app-wide stateless services and repositories. Avoid
`.singleton` unless destroying/recreating the instance is unsafe; plain
`reset()` does not clear singletons.

## Parameterized Factories

Use `ParameterFactory` when construction needs runtime input and you still want
Factory scopes, contexts, and test overrides:

```swift
extension Container {
    var detailViewModel: ParameterFactory<String, DetailViewModel> {
        self { itemId in
            DetailViewModel(itemId: itemId, service: self.itemService())
        }
    }
}

let viewModel = Container.shared.detailViewModel("item-123")
```

For `.cached` parameterized factories, use `scopeOnParameters` when different
arguments must produce different cached instances.

## Modular Organization

In the app target, split registrations into focused `extension Container` files:

```
App/Composition/
  Container+Networking.swift
  Container+Persistence.swift
  Container+Profile.swift
  Container+Bootstrap.swift
```

For very large apps, use a custom `SharedContainer` per feature group to avoid
property-name collisions.

In SPM feature packages, do not import FactoryKit. The package exposes a
dependency protocol/struct and the app target adapts Factory registrations into
that dependency surface.

## Coordinator And Module Assembly

The canonical chain stays:

```
AppDependencyContainer -> FeatureDependencies -> CoordinatorFactory
-> ModuleFactory -> Assembly
```

Only `AppDependencyContainer` and app-target `extension Container` files import
FactoryKit. `ModuleFactoryImp`, Coordinators, ViewModels, and feature assemblies
receive protocols through initializers and never resolve from `Container.shared`.

This keeps dependency surfaces visible and testable. Letting `ModuleFactory`
resolve directly from `Container.shared` is a Service Locator shortcut.

## Contexts

Use `AutoRegistering.autoRegister()` for context-bound overrides:

- `.onTest { ... }`
- `.onPreview { ... }`
- `.onDebug { ... }`
- `.onSimulator { ... }`
- `.onArg("name") { ... }`

Use contexts for mocks, preview scenarios, and debug defaults. Do not put heavy
startup work or business logic in `autoRegister()`; that belongs in the
Composition Root bootstrap.

## Testing

- Prefer direct initializer injection for ViewModel and service unit tests.
- For code that uses `@Injected`, register mocks before creating the SUT.
- Reset `Container.shared.reset(options: .all)` in XCTest `setUp` and
  `tearDown`.
- In Swift Testing with Factory 2.5+, prefer `@Suite(.container)` from
  `FactoryTesting` for task-local container isolation and parallel tests.
- Avoid `.singleton` in tests unless you explicitly reset with `.all`.

## Concurrency

Factory's container operations are thread-safe, but the resolved objects still
need correct isolation.

- Put `@MainActor` on ViewModel types, not on the `Container` property.
- Use `self { @MainActor in ContentViewModel() }` when constructing a
  main-actor ViewModel.
- Keep non-UI registrations nonisolated so background work can resolve them.
- Factory does not make non-Sendable services safe. The instance returned by the
  factory must still be Sendable or actor-isolated as appropriate.

## Common Mistakes

- Resolving from `Container.shared` inside Domain/services/repositories.
- Resolving from `Container.shared` inside a Factory closure instead of `self`.
- Registering ViewModels as `.singleton`.
- Forgetting `reset(options: .all)` in tests.
- Using `@Injected` inside `@Observable` without `@ObservationIgnored`.
- Using `.cached` on `ParameterFactory` without `scopeOnParameters` when args
  should produce distinct instances.
- Calling `register` in production code outside `autoRegister()`.
- Putting services directly into SwiftUI Views instead of ViewModels.
- Allowing registration-name collisions in large modular apps.
