---
name: di-swinject
description: "Use when working with Swinject dependency injection in iOS apps. Covers Swinject-specific patterns: object scopes, registrations (basic, autoregister, named, with arguments), Assembly pattern, testing configuration. For Composition Root design see di-composition-root skill; for connecting DI to Coordinators see di-module-assembly skill."
---

# Swinject Dependency Injection Patterns

Swinject-specific guidance: scopes, registration patterns, autoregistration,
Assemblies, `@MainActor` UI wiring, testing, and comparison with Factory.

Detailed examples live in `references/detailed-guide.md`. Load only the relevant
section with `rg -n "^## " skills/di-swinject/references/detailed-guide.md`.

## When To Load The Reference

| Need | Reference sections |
|---|---|
| Set up a container | `Core Concepts`, `Container Setup` |
| Register protocols, names, arguments | `Registration Patterns` |
| Pick Swinject scopes | `Object Scopes` |
| Use Assemblies | `Assembly Pattern` |
| Register/build `@MainActor` UI types | `@MainActor UI types + Swinject` |
| Wire Coordinators/modules | `Coordinator and Module Assembly` |
| Test the graph | `Testing Configuration` |
| Debug missing registrations | `Debugging Tips` |
| Compare with Factory | `Swinject vs Factory` |

## When To Use Swinject

Use Swinject when:

- The project already uses Swinject and migration has no concrete payoff.
- You need runtime registration or named registrations of the same protocol.
- You use `SwinjectAutoregistration` to reduce constructor boilerplate.
- The app is UIKit-first or has an established Assembly-based DI graph.
- You need swappable production/test configurations via containers/assemblies.

Prefer alternatives when:

- The graph is small: manual DI in `di-composition-root` is clearer.
- The app is SwiftUI/Observation-first and wants property-wrapper injection:
  consider `di-factory`.
- Compile-time registration safety is more important than runtime flexibility:
  consider Factory or manual DI.
- The feature is TCA-based: use Point-Free `@Dependency`.

## Core Rules

- Create the Swinject `Container` in the Composition Root. Do not expose a
  global `static let shared`.
- Wrap the container in `AppDependencyContainer`; that facade is the boundary
  between Swinject and app architecture.
- Keep `import Swinject` out of Domain, ViewModels, Coordinators, ModuleFactory,
  feature factories, and SPM packages.
- Feature packages accept explicit dependency protocols/structs through
  initializers.
- Resolve services in `AppDependencyContainer`; pass them through
  `*FeatureDependencies`, `ModuleFactory`, and feature assemblies.
- Never pass `Resolver` or `Container` into Coordinators or ViewModels.

## Registration

Register protocols, not concrete types:

```swift
container.register(UserServiceProtocol.self) { _ in
    UserService()
}.inObjectScope(.container)

container.register(ProfileViewModel.self) { r in
    ProfileViewModel(
        userService: r.resolve(UserServiceProtocol.self)!,
        analytics: r.resolve(AnalyticsServiceProtocol.self)!
    )
}
```

Use named registrations only when several implementations of the same protocol
are truly needed:

```swift
container.register(APIClientProtocol.self, name: "staging") { _ in
    StagingAPIClient()
}
```

Use argument registrations for runtime IDs:

```swift
container.register(DetailViewModel.self) { (r, itemId: String) in
    DetailViewModel(itemId: itemId, service: r.resolve(ItemServiceProtocol.self)!)
}
```

When using the module-assembly chain, prefer passing runtime IDs as factory
method parameters instead of Swinject `argument:` values. That keeps UI assembly
and actor boundaries explicit.

## Scopes

| Scope | Use |
|---|---|
| `.transient` | ViewModels, Coordinators, stateful per-screen objects |
| `.container` | Stateless app services, API clients, repositories, database managers |
| `.weak` | Optional caches/resources that can be recreated |
| `.graph` | Shared object within one top-level resolve only |

ViewModels should normally be transient. App services and repositories are
usually `.container`.

## Assemblies

Assemblies organize registrations, but they are not a license to leak Swinject
into feature code:

```swift
final class ServicesAssembly: Assembly {
    func assemble(container: Container) {
        container.register(NetworkServiceProtocol.self) { _ in
            NetworkService()
        }.inObjectScope(.container)
    }
}
```

Keep Assemblies in the app/composition layer. SPM packages expose dependency
protocols and get implementations from the host app.

## MainActor UI Wiring

Swinject registration closures are nonisolated. Directly registering
`@MainActor` ViewModels or UIKit/AppKit controllers can fail under Swift 6.

Do not fix that with `MainActor.assumeIsolated`, and do not create factories that
hold `Resolver`.

Use the canonical module-assembly chain:

```
AppDependencyContainer (imports Swinject)
-> FeatureDependencies
-> ModuleFactory
-> FeatureFactory/Assembly
-> @MainActor makeViewController()
```

The feature factory receives a narrow dependency protocol and has a
`@MainActor` make method that builds the ViewModel and View/Controller. It does
not import Swinject.

## Coordinator And Module Assembly

Coordinators receive factories, not containers:

- `AppDependencyContainer` wraps Swinject and conforms to feature dependency
  protocols.
- `ModuleFactory` assembles View + ViewModel using dependency protocols.
- `CoordinatorFactory` creates Coordinators with their ModuleFactory.
- Coordinators never import Swinject.

Use `di-module-assembly` as the source of truth for the full chain.

## Testing

- Unit-test ViewModels/services with direct initializer injection and mocks; no
  container required.
- Test the DI graph with a dedicated test container/assembler.
- Override specific registrations in the test container for edge cases.
- Avoid force-unwrapping `resolve` in test setup unless the failure should be a
  hard setup failure.
- Keep test containers fresh per test to avoid override leaks.

## Common Mistakes

- Force-unwrapping missing registrations without a clear setup failure message.
- Registering ViewModels as `.container` and sharing state across screens.
- Creating circular dependencies through constructor resolution.
- Resolving dependencies inside service initializers.
- Passing `Container` / `Resolver` to Coordinators or ViewModels.
- Importing Swinject inside feature packages.
- Using `MainActor.assumeIsolated` to hide DI design issues.
- Registering `@MainActor` UI types directly in nonisolated closures.

## Swinject vs Factory

Swinject is better when a legacy app already uses it, when named runtime
bindings matter, or when autoregistration is heavily used.

Factory is better for new SwiftUI-first apps that want compile-time registration
properties, built-in preview/test contexts, property-wrapper injection, and
parallel Swift Testing isolation.

Neither is needed for very small graphs; use manual DI.
