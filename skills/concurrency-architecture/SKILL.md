---
name: concurrency-architecture
description: "Use when deciding where Swift Concurrency primitives live in a layered iOS app — which layer is @MainActor (View/ViewModel/Presenter/Coordinator/Service/Repository), when to introduce a custom actor, who owns Tasks and where they get cancelled, how cancellation propagates across Coordinator → ViewModel → UseCase → Repository → APIClient, where to place async let / TaskGroup (UseCase vs ViewModel), Sendable boundaries between layers, and background-work-outlives-screen patterns. Architectural placement only — defer language-level questions (actor reentrancy, isolation rules, Sendable conformance, Swift 6 migration) to swift-concurrency:swift-concurrency."
---

# Concurrency Architecture

Decisions about **where Swift Concurrency primitives live across the layers of an iOS app** — which layer is `@MainActor`, where custom actors belong, who owns `Task`s and who cancels them, how cancellation propagates through layers, where to put `async let` / `TaskGroup`. Not about language semantics — for `Sendable` conformance rules, actor reentrancy, isolation diagnostics, and Swift 6 migration use **`swift-concurrency:swift-concurrency`** (AvdLee skill).

> **Related skills:**
> - `swift-concurrency:swift-concurrency` (AvdLee) — language-level reference: async/await, actors, Sendable, Swift 6 migration. **This skill defers all language-level questions to it.**
> - `arch-mvvm`, `arch-clean`, `arch-viper`, `arch-tca`, `arch-mvc` — per-architecture layer definitions; this skill harmonises concurrency placement across them
> - `arch-coordinator`, `arch-swiftui-navigation` — navigation layer is the root of the Task tree (screen lifetime → Task lifetime)
> - `error-architecture` — `CancellationError` is not an error; cancellation policy here, error mapping there
> - `net-architecture` — APIClient must propagate cancellation; HTTP retry/cancellation interplay
> - `persistence-architecture` — context confinement (`viewContext`, `@ModelActor`, `DatabasePool`) is its own actor decision; this skill covers when it crosses layer boundaries
> - `di-composition-root` — singletons that own state are usually actors; bootstrap order matters when an actor depends on another

## Why This Skill Exists

Each `arch-*` skill answers concurrency questions for its own pattern in isolation. Without a cross-cutting view, real codebases drift into one of these failure modes:

- **`@MainActor` everywhere** — sprinkled on Repository, APIClient, even Logger because "it removed the warning". UI thread becomes the bottleneck for network and disk.
- **`@MainActor` nowhere** — every ViewModel call ends with `await MainActor.run { ... }` to update `@Published`. Boilerplate, easy to forget.
- **Tasks owned by no one** — `Task { ... }` fired from `viewDidAppear`, never stored, never cancelled. Screen dies, work continues, callback writes to deinit-ed `self?` (silent no-op) or to a new instance of the screen (state corruption).
- **Cancellation that stops at a layer boundary** — Coordinator pops the screen, ViewModel cancels its task, but the in-flight `URLSessionDataTask` keeps downloading 10 MB and the parsed response is thrown away.
- **Custom actor for nothing** — wrapping a stateless `URLSessionFetcher` in an `actor` because "it sounded thread-safe", paying serialization cost for zero benefit.

The fix: **one isolation domain per architectural role, decided once; Tasks owned at the layer that owns the screen; cancellation flows down through `await`, never re-implemented per layer.**

## Per-Layer Isolation: One Table, All Five Architectures

| Architectural role | Isolation | Why | Where it appears |
|---|---|---|---|
| **View / ViewController** | `@MainActor` (`UIViewController` implicit since iOS 16; SwiftUI `View` since iOS 17 / Swift 5.9) | UIKit/SwiftUI APIs are main-actor-isolated. Don't fight it. | All architectures |
| **ViewModel** | `@MainActor` | Owns `@Published` / `@Observable` state read by the View. Avoids `await MainActor.run` on every state update. | MVVM, Clean (Presentation), TCA (`@Reducer` itself is not actor-isolated, but the Store and Views are `@MainActor`) |
| **Presenter** | `@MainActor` | Same reason as ViewModel — formats data for View, owns presentation state. | VIPER, MVC (when split out) |
| **Coordinator / Router** | `@MainActor` | Pushes/presents view controllers — UIKit APIs require it. SwiftUI Router (`@Observable`) is also `@MainActor` in practice. | All architectures |
| **UseCase / Interactor (business logic)** | **nonisolated** | Pure orchestration. Inherits caller's actor (Presenter/ViewModel = `@MainActor`). Hops off main only when an `await` calls something explicitly off-main. | Clean (UseCase), VIPER (Interactor) |
| **Service (cross-feature, stateless)** | **nonisolated** | Stateless transformations don't need isolation. | All architectures |
| **Service (cross-feature, with mutable state)** | **`actor`** (custom) | E.g. token refresher, dedupe cache, in-memory state with concurrent readers. | All architectures — see "When to introduce a custom actor" |
| **Repository** | **nonisolated** (façade) — but its `DataSource` may be actor-confined | Repository itself is a thin façade. Backing store has its own threading model (Core Data context, `@ModelActor`, GRDB pool, Realm thread-confinement). | All architectures |
| **APIClient / HTTPClient** | **nonisolated** | URLSession is thread-safe. `data(for:)` is `nonisolated` and runs on URLSession's queue. | All architectures (see `net-architecture`) |
| **Logger** | **nonisolated** (or `actor` if buffering) | `OSLog` is thread-safe. Custom file logger with buffer = `actor`. | All architectures |

### Decision: where exactly is `@MainActor`?

```
@MainActor: View, ViewModel/Presenter, Coordinator/Router
nonisolated: UseCase/Interactor, Service (stateless), Repository façade, APIClient
actor (custom): Service with mutable state shared across callers
```

**Three rules that resolve 90% of placement questions:**

1. **`@MainActor` follows the View boundary.** Anything the View directly reads, observes, or calls is `@MainActor`. Stop at the boundary — UseCase/Repository/APIClient are not "called by the View", they are called by `@MainActor` code that `await`s them.
2. **Don't put `@MainActor` on a class just to silence a Swift 6 warning.** If the class doesn't touch UIKit/SwiftUI/`@Published` — it doesn't need `@MainActor`. The right fix is usually `Sendable`, not isolation. (Defer to `swift-concurrency:swift-concurrency` for the conformance details.)
3. **`UseCase`/`Interactor` is never `@MainActor`.** It's caller-isolated by default. If the Presenter is `@MainActor` and `await`s the UseCase, the await suspension is your hop-off point — the UseCase body runs on the cooperative pool. If you mark the UseCase `@MainActor`, you've just moved business logic onto the main thread and lost the hop.

## When to Introduce a Custom `actor`

`actor` is not free — every call is a hop, return values must be `Sendable`, and re-entrancy is a real footgun (see AvdLee skill for the mechanics). Use the decision matrix:

| Situation | Right answer |
|---|---|
| Stateless transformation (parser, mapper, formatter) | **plain struct/class**, nonisolated |
| Read-only configuration loaded once at boot | `let` on a `Sendable` value type, no actor needed |
| Mutable state, single owner, accessed from one isolation domain | Plain class/struct with that domain's isolation (often `@MainActor`) |
| Mutable state, **multiple concurrent callers**, cross-feature | **`actor`** |
| Mutable state, but readers can tolerate being one tick stale | **`actor` with cached snapshot** + nonisolated read of last snapshot |
| Need re-entrant access (callback re-enters the actor mid-await) | Reconsider design — actor re-entrancy is a known footgun. See AvdLee `references/actors.md`. |

**Concrete examples of legitimate actors:**

```swift
// ✅ Token refresher — single-flight refresh across N concurrent 401s
actor TokenRefresher {
    private var refreshTask: Task<AccessToken, Error>?

    func currentToken() async throws -> AccessToken {
        if let task = refreshTask { return try await task.value }
        let task = Task { try await self.performRefresh() }
        refreshTask = task
        defer { refreshTask = nil }
        return try await task.value
    }
}

// ✅ Image cache — many readers, occasional writers
actor ImageCache {
    private var entries: [URL: UIImage] = [:]
    func image(for url: URL) -> UIImage? { entries[url] }
    func store(_ image: UIImage, for url: URL) { entries[url] = image }
}

// ❌ Wrapping a stateless service "for safety"
actor URLSessionFetcher {  // No state. Just costs hops. Use a struct.
    func fetch(_ url: URL) async throws -> Data {
        try await URLSession.shared.data(from: url).0
    }
}
```

**Anti-pattern: `actor` as Singleton.** If you find yourself writing `static let shared` on an actor that holds the app-wide state, you've reinvented Service Locator. Wire actors through DI like any other dependency (see `di-composition-root`).

## Task Ownership: Who Owns Tasks, Who Cancels Them

The screen owns the Task tree for that screen. Period.

| Architecture | Task lives in | Cancelled in |
|---|---|---|
| MVVM (UIKit) | ViewModel (`var fetchTask: Task<Void, Never>?`) | `deinit` of ViewModel **and** `viewWillDisappear` of the View if work is screen-bound |
| MVVM (SwiftUI) | `.task { ... }` modifier | Auto-cancelled when the view disappears — that's the entire point of `.task` |
| Clean (UIKit) | ViewModel (Presentation layer) | Same as MVVM UIKit |
| VIPER | Presenter (`var fetchTask: Task<Void, Never>?`) | Presenter `deinit` + `viewWillDisappear` — see `arch-viper` |
| TCA | TCA owns it via `Effect.run` + `cancellable(id:)` | `.cancel(id:)` from a reducer; auto-cancelled when feature is removed via `@Presents`/`StackState` |
| MVC | ViewController | `deinit` + `viewWillDisappear` |

### The four ownership patterns

```swift
// Pattern A: SwiftUI View — use .task
struct ItemsScreen: View {
    @State var viewModel: ItemsViewModel   // ItemsViewModel is @Observable (iOS 17+)
    var body: some View {
        List(viewModel.items) { ... }
            .task { await viewModel.load() }   // auto-cancelled on disappear
    }
}

// Pattern B: UIKit ViewModel — store and cancel
@MainActor
final class ItemsViewModel: ObservableObject {
    @Published private(set) var items: [Item] = []
    private var fetchTask: Task<Void, Never>?
    private let fetchItems: FetchItemsUseCase

    func load() {
        fetchTask?.cancel()
        fetchTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await self.fetchItems.execute()
                try Task.checkCancellation()
                self.items = result
            } catch is CancellationError { return }
            catch { /* map to UserMessage — see error-architecture */ }
        }
    }

    deinit { fetchTask?.cancel() }
}

// Pattern C: User action that should NOT cancel on screen change
// (e.g. uploading a photo that should finish even if user leaves the screen)
// Move it OUT of the screen-owned ViewModel into a long-lived service.
// The screen kicks off the upload via a Service, the Service owns the Task.
@MainActor
final class ComposeViewModel {
    private let uploader: PhotoUploader   // app-scoped, not screen-scoped
    func tapSend() {
        uploader.enqueue(photo: ...)       // Service.Task survives screen
    }
}

// Pattern D: TCA — let the framework own it
@Reducer struct Items {
    enum CancelID { case fetch }
    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                return .run { send in
                    let items = try await fetchItems()
                    await send(.loaded(items))
                }
                .cancellable(id: CancelID.fetch, cancelInFlight: true)
            case .onDisappear:
                return .cancel(id: CancelID.fetch)
            }
        }
    }
}
```

**The rule that prevents 80% of "work outlives screen" bugs:** *If the work is bound to the screen's UI state, it lives on the screen-owned object and is cancelled when the screen dies. If the work must outlive the screen, it lives on a longer-lived service injected via DI.*

## Cancellation Propagation Across Layers

Cancellation flows **down through `await`**, automatically. You don't re-implement it per layer — you just don't break the chain.

```
Coordinator/Router cancels screen
        ↓
ViewModel.fetchTask.cancel()           ← explicit cancel here
        ↓
await useCase.execute()                ← Task.isCancelled propagates via await
        ↓
await repository.fetch()               ← propagates
        ↓
await apiClient.send(request)          ← propagates
        ↓
URLSession.data(for:)                  ← URLSession honours Task cancellation
                                         and aborts the actual HTTP request
```

### Three rules to keep the chain intact

**1. Don't catch `CancellationError` and turn it into a domain error.**

```swift
// ❌ Breaks the chain
do {
    try await repository.fetch()
} catch {
    throw DomainError.fetchFailed(error)   // hides CancellationError
}

// ✅ Re-throw cancellation
do {
    try await repository.fetch()
} catch is CancellationError {
    throw CancellationError()              // or just `throw`
} catch {
    throw DomainError.fetchFailed(error)
}
```

See `error-architecture` for the full pattern — `CancellationError` is **not an error to show the user**, it's a control-flow signal.

**2. Don't `Task.detached` inside a layer to "isolate" work.**

`Task.detached` creates a new Task tree with no parent — cancellation from above will not reach it. This is almost never what you want. The legitimate uses are: fire-and-forget logging, background analytics, or work that intentionally outlives the caller (and even then, prefer a long-lived service that owns its own Tasks).

```swift
// ❌ Cancellation lost
func execute() async throws -> [Item] {
    return try await Task.detached { try await self.repository.fetch() }.value
}

// ✅ Inherits cancellation
func execute() async throws -> [Item] {
    try await repository.fetch()
}
```

**3. Check `Task.isCancelled` before expensive work that doesn't await.**

`await` is a cancellation checkpoint. CPU-bound work between awaits is not — add explicit checks.

```swift
func process(items: [RawItem]) async throws -> [Item] {
    try items.map { raw in
        try Task.checkCancellation()       // explicit checkpoint
        return expensiveSyncTransform(raw)
    }
}
```

### Where to set timeouts

Timeouts are a form of cancellation. Two layers, two purposes:

| Layer | What | Why |
|---|---|---|
| `URLRequest.timeoutInterval` | Per-request transport timeout | Catches stuck TCP, slow servers |
| `withTimeout(seconds:) { ... }` (helper) at UseCase boundary | Per-business-operation timeout | E.g. "the search must respond in 5s, otherwise show empty state" — independent of how many HTTP calls happen inside |

Don't add timeouts in Repository or APIClient — they don't know the business intent. Either set transport timeout once in `URLSessionConfiguration` (defaulted in `net-architecture`), or wrap the UseCase call.

> `withTimeout` is not in the standard library. Typical implementation: race the work against `Task.sleep` via `withThrowingTaskGroup` and cancel the loser. See `swift-async-algorithms` and AvdLee `references/cancellation.md` for reference implementations.

## Parallel Loading: Where `async let` / `TaskGroup` Lives

The placement question is "**which layer fans out into N parallel calls?**"

| Scenario | Right layer | Construct |
|---|---|---|
| One screen needs profile + posts + followers (3 independent calls, fixed) | **UseCase / Interactor** | `async let` |
| Bulk import N items, all independent, count known at runtime | **UseCase** | `withThrowingTaskGroup` |
| Aggregate stream from multiple sources into one `AsyncSequence` | **Repository** | `merge` from `swift-async-algorithms` |
| Pure UI fan-out (load 3 thumbnails in parallel, no business meaning) | **ViewModel** (or even View `.task`) | `async let` is fine |
| Background prefetch when app foregrounds | **App-scoped Service** | `TaskGroup` — survives screens |

**Rule:** if the parallelism is part of the business operation ("loading the profile screen means fetching 3 things"), it lives in the UseCase. If it's pure presentation choreography ("show 3 thumbnails as soon as each is ready"), it lives in the ViewModel.

```swift
// ✅ UseCase fan-out — business operation
struct LoadProfileScreen: UseCase {
    func execute(userID: User.ID) async throws -> ProfileScreenData {
        async let profile = profileRepo.fetch(userID)
        async let posts   = postsRepo.recent(by: userID)
        async let followers = socialRepo.followers(of: userID)
        return try await ProfileScreenData(
            profile: profile,
            posts: posts,
            followers: followers
        )
    }
}

// ✅ ViewModel fan-out — UI choreography
@MainActor
final class GalleryViewModel {
    @Published var thumbnails: [URL: UIImage] = [:]
    func loadThumbnails(_ urls: [URL]) async {
        await withTaskGroup(of: (URL, UIImage?).self) { group in
            for url in urls {
                group.addTask { (url, await self.imageLoader.load(url)) }
            }
            for await (url, image) in group {
                thumbnails[url] = image    // safe — @MainActor
            }
        }
    }
}

// ❌ Repository fan-out for a business operation — wrong layer
final class ProfileRepository {
    func fetchScreenData(userID: User.ID) async throws -> ProfileScreenData {
        // Don't do this here. ProfileScreenData is a Presentation concept.
        // Repository should expose 3 separate methods. UseCase composes.
    }
}
```

## `Sendable` Boundaries Between Layers

Every value crossing an isolation boundary must be `Sendable`. The architectural placement of `Sendable` conformance:

| What crosses | `Sendable`? | Notes |
|---|---|---|
| Domain models (UseCase return values) | **Yes** — declare `: Sendable` | Always `struct` of `Sendable` fields. Easy. |
| DTOs (network/parsing layer) | **Yes** | `Codable` `struct` — implicitly `Sendable` if all stored properties are. |
| `NSManagedObject`, `@Model`, Realm `Object` | **Never `Sendable`** | Pass `NSManagedObjectID` / `PersistentIdentifier` / freeze-and-pass — see `persistence-architecture` |
| Closures crossing actors | Annotate `@Sendable` | Most async APIs require it |
| Reference types | Avoid; if needed, use `@unchecked Sendable` only with documented invariant | Defer to AvdLee `references/sendable.md` |
| Errors | `Error` is not `Sendable` automatically — make your error enums explicitly `Sendable` | Easy: `enum FooError: Error, Sendable { ... }` |

**One architectural rule:** the Repository → Domain boundary is where you guarantee `Sendable`. If your Repository returns `[Item]` and `Item` is `Sendable`, the rest of the layered code stays simple. If `Item` is a `class` with mutable state, you've poisoned every upper layer.

For the language-level rules of `@unchecked Sendable`, region isolation, and `@preconcurrency` — defer to AvdLee `swift-concurrency:swift-concurrency`.

## Background Work That Outlives the Screen

Some operations should not be cancelled when the screen disappears: file uploads, idempotent POSTs the user expects to "send and forget", crash report uploads. The architectural answer is **not** "use `Task.detached`" — it's **"move the work to a longer-lived owner."**

| Work | Owner | Lifetime |
|---|---|---|
| Photo upload from compose screen | `UploadCoordinator` (app-scoped Service) | App lifetime; survives screen pop |
| Background sync triggered by `BGTaskScheduler` | `SyncService` registered in App start | App lifetime |
| Analytics event flush | `AnalyticsService` | App lifetime |
| URLSession background config (system-managed re-launch) | `URLSession` with `.background(withIdentifier:)` | OS-managed, survives app termination |

**Pattern:**

```swift
// Composition Root
container.register(PhotoUploader.self, scope: .singleton) { _ in
    PhotoUploader(api: ..., persistence: ...)
}

// Service owns its own Tasks
final class PhotoUploader {
    private var inflight: [UUID: Task<Void, Error>] = [:]

    func enqueue(_ photo: Photo) {
        let id = photo.id
        inflight[id] = Task { [weak self] in
            try await self?.upload(photo)
            self?.inflight.removeValue(forKey: id)
        }
    }
}

// Screen just kicks it off and forgets
@MainActor
final class ComposeViewModel {
    let uploader: PhotoUploader   // injected
    func tapSend(_ photo: Photo) {
        uploader.enqueue(photo)
        coordinator.dismiss()      // safe — uploader owns the Task
    }
}
```

If `PhotoUploader` itself accumulates state (`inflight`), promote it to `actor`. If it's a thin adapter delegating to URLSession background config, keep it as a class (URLSession does the survival).

## DI and Concurrency Bootstrap

A few `arch-*`-spanning rules about wiring concurrency dependencies in Composition Root (see `di-composition-root` for the full bootstrap discussion):

1. **Singletons holding mutable shared state are actors.** Register them in the container with `.singleton` scope. Resolution is `await`-free (the container itself doesn't need to be an actor) but every method call on the resolved instance is `await`.
2. **`@MainActor`-isolated singletons** (e.g. a `RootRouter`, an `AppState` `@Observable`) must be created on the main actor. In SceneDelegate this is automatic; in `@main App` use `@MainActor` on the bootstrap function.
3. **Async bootstrap order** — if `TokenRefresher` needs `Keychain`, both are singletons, and Keychain access is `async`, the container's resolution must be ordered. Two options: (a) make all bootstrap explicit and serial in `application(_:didFinishLaunchingWithOptions:)`, (b) use a lazy async-init pattern. Pick one per project; document in CLAUDE-swift-toolkit.md.
4. **Don't make the container itself `@MainActor`.** Background work resolves dependencies too. Keep the container nonisolated; isolate only specific registrations.

## Common Mistakes

1. **`@MainActor` on Repository / APIClient / Logger.** Pushes I/O onto the main thread. The fix: remove the annotation. If you got a Swift 6 warning, the right answer is `Sendable` on the Repository's input/output types, not `@MainActor` on the Repository.

2. **`Task.detached` to "escape" `@MainActor`.** Loses cancellation, loses caller context, and almost always wrong. Use plain `Task { }` (inherits caller) and let the `await` boundary do the hop.

3. **`actor` for stateless services.** No state ⇒ no need for serialization. Use a plain `Sendable` `struct` or `final class`.

4. **`Task { ... }` inside `viewDidAppear` without storing the handle.** Work continues after the screen dies, results write to a stale `self`. Always store the `Task` and cancel it in `deinit` / `viewWillDisappear`. (Exception: SwiftUI `.task { }` modifier — handles this for you.)

5. **`await MainActor.run { ... }` everywhere.** If the calling class is `@MainActor`, you don't need `MainActor.run`. The boilerplate is a sign you forgot to mark the class. Mark the class.

6. **Catching `CancellationError` and re-throwing as a domain error.** Hides the cancellation upstream, the View shows an error alert for "user cancelled". Always re-throw `CancellationError` separately. See `error-architecture`.

7. **`Task` chain across module boundaries with no cancellation discipline.** ViewModel cancels, but UseCase wrapped its call in `Task.detached`, so the in-flight HTTP request continues. Audit every layer for `Task.detached` and unstructured `Task { }` that don't propagate the parent's cancellation.

8. **Parallel fan-out in the wrong layer.** Repository spawning `async let` for what is a UseCase composition. The Repository becomes a god-method, the UseCase becomes a passthrough. Fan-out belongs at the layer that knows the business meaning of the parallel calls.

9. **Long-running work bound to `viewDidAppear` Task.** Upload, background sync, analytics flush — these belong on app-scoped services, not on the screen. When the user pops the screen, the upload is killed mid-bytes. Move the work, not the cancellation.

10. **`actor` as Singleton with `static let shared`.** Service Locator with extra steps. Wire actors through DI (see `di-composition-root`).

11. **Mixing `nonisolated(unsafe)` and `@unchecked Sendable` because Swift 6 complains.** These are escape hatches with documented invariants. If you don't have an invariant to document, the right answer is to fix the data flow. Defer to `swift-concurrency:swift-concurrency` for when these are legitimate.

12. **`@MainActor` on a UseCase to "make the warning go away".** UseCase is now serialized through main thread. The right answer is almost always: make the UseCase nonisolated, make its inputs/outputs `Sendable`, and let the `@MainActor` ViewModel `await` it.

13. **`Task.sleep` for production debounce/throttle/retry-backoff without a clock abstraction.** `Task.sleep` itself is correct and respects cancellation — the real problem is wall-clock coupling that makes tests slow and flaky. In production use `swift-async-algorithms` `.debounce` for streams; for raw delays, inject a `Clock` (`ContinuousClock` / `SuspendingClock`) and substitute `TestClock` (swift-clocks) in tests.

14. **Cancellation "by deadline" via `Task { try await Task.sleep(...); task.cancel() }`.** Reinventing timeouts poorly. Wrap with a real `withTimeout` helper at the UseCase boundary; configure transport timeout in `URLSessionConfiguration`.

15. **Treating `@Observable` ViewModel as nonisolated because compiler doesn't force `@MainActor`.** `@Observable` doesn't imply `@MainActor`. If the View reads it on main and a background `Task` writes to it, you've created a data race that may not even warn. Mark the ViewModel `@MainActor` explicitly.

## Quick Reference

```
WHERE IS @MainActor?
  YES: View, ViewController, ViewModel, Presenter, Coordinator, Router, App-scoped UI state
  NO:  UseCase, Interactor, Service (stateless), Repository façade, APIClient, Logger
  CASE-BY-CASE: Service-with-state → custom `actor` instead

WHO OWNS THE TASK?
  SwiftUI:        .task { } modifier — auto-cancelled
  UIKit ViewModel: stored Task<Void, Never>?, cancelled in deinit + viewWillDisappear
  TCA:            Effect.run + .cancellable(id:)
  Outlives screen: app-scoped Service via DI (singleton)

WHERE DOES async let / TaskGroup LIVE?
  Business fan-out (3 calls = "load this screen"):  UseCase
  UI choreography (3 thumbnails in parallel):       ViewModel
  Bulk import / batch ops (N at runtime):           UseCase + TaskGroup
  Stream merge from multiple sources:               Repository + async-algorithms

WHEN A NEW `actor`?
  Stateless: NO — plain struct
  Single-owner mutable: NO — class with caller's isolation
  Multi-caller mutable: YES — actor
  Re-entrant call patterns: RECONSIDER — see AvdLee actors.md

CANCELLATION PROPAGATION
  Down through `await` automatically. Three things to NOT do:
   - catch CancellationError as domain error
   - Task.detached anywhere in the layered chain
   - skip `try Task.checkCancellation()` in CPU-bound loops between awaits

LANGUAGE-LEVEL QUESTIONS (Sendable, isolation rules, Swift 6 migration, actor reentrancy)
  → swift-concurrency:swift-concurrency  (AvdLee)
```
