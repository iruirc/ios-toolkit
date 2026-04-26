---
name: error-architecture
description: "Use when designing how errors flow through a layered iOS app — typed vs untyped errors (Swift 6 typed throws), per-layer error types, mapping between layers (Network → Domain → UI), presentation strategy (alert/inline/banner/empty-state/log), recoverable vs fatal classification, localization, PII-safe logging, retry/cancellation, and reactive-framework error handling."
---

# Error Architecture

Decisions about **where errors live, how they flow between layers, and how they reach the user** in an iOS app. Not about syntax of `try/catch` — about the architectural shape of error handling across DataSource → Repository → UseCase → ViewModel → View.

> **Related skills:**
> - `arch-clean`, `arch-mvvm`, `arch-viper` — layer boundaries that error mapping respects
> - `di-composition-root` — where `ErrorMapper`, `Logger`, crash-reporter are bootstrapped
> - `reactive-combine`, `reactive-rxswift` — reactive-framework error semantics (this skill covers cross-cutting decisions only)
> - `arch-mvc` — for small apps you can collapse mapping into one layer (Controller); rules below still apply
> - `net-architecture`, `persistence-architecture` — boundaries that produce errors mapped here (network errors, storage errors, migration failures)

## Why This Skill Exists

Without an error architecture, real codebases drift into one of two failure modes:

- **God-enum:** one `AppError` with 200 cases, every layer pollutes it, every `catch` becomes a 50-case switch.
- **Opaque pass-through:** every layer just `throws`/`Error`, the View ends up calling `error.localizedDescription` on a `URLError` and the user sees `The Internet connection appears to be offline. (Code -1009.)`.

The fix: **per-layer error types + explicit mapping at each boundary + a presentation policy decided once.**

## Error Type Hierarchy by Layer

Each layer owns its own error type. Lower layers do **not** leak their errors upward.

| Layer | Error type | Examples |
|---|---|---|
| Infrastructure (Network, DB, FS) | Native (`URLError`, `DecodingError`, `CocoaError`) — or thin wrapper | Transport failures, decode failures |
| Data (Repository) | `XxxRepositoryError` enum | `.notFound`, `.unauthorized`, `.networkUnavailable`, `.conflict`, `.unknown(Error)` |
| Domain (UseCase / Service) | `XxxDomainError` enum | `.itemAlreadyExists`, `.quotaExceeded`, `.notLoggedIn` |
| Presentation (ViewModel) | `UserMessage` value type | `{ title, body, severity, retryAction? }` — already localized, ready for UI |

**Rules:**
- Each layer accepts errors from below as `Error` and converts to its own type before propagating.
- `.unknown(Error)` (or `.underlying(Error)`) case stores the original — for logging only, never for `switch` decisions in callers.
- ViewModel does not throw — it converts errors to UI state (`@Published var errorMessage: UserMessage?` or equivalent).

### Typed throws (Swift 6) vs untyped `throws`

```swift
// Untyped — flexible, default for most code
func fetchItems() async throws -> [Item]

// Typed — Swift 6, opt-in
func fetchItems() async throws(ItemRepositoryError) -> [Item]
```

**When typed throws pay off:**
- Pure-Swift modules (no UIKit, no third-party reactive) where the full error set is closed
- Performance-sensitive paths (typed throws can be specialized; existential `any Error` cannot)
- API boundary of a reusable library — gives callers compile-time exhaustiveness

**When untyped is right:**
- Glue code that mixes errors from many sources (network + DB + parsing + business)
- Code calling third-party APIs that throw `any Error`
- Top-level layers (ViewModel, Coordinator) that don't switch on error specifics

**Default:** untyped `throws` for app code, typed throws for SPM packages with a closed error vocabulary (see `pkg-spm-design`).

### One enum vs split enums per layer

| Approach | When |
|---|---|
| **One enum per Repository / UseCase** | Standard. Keeps each enum 5-15 cases, easy to switch on. |
| **One shared `RepositoryError`** for all repos | OK if errors are truly identical (rare — auth differs, payload differs). |
| **God `AppError`** at app level | Anti-pattern. Use only as a final type at the very top boundary, not propagated down. |

## Layer-by-Layer Mapping

The boundary between layers is where the previous layer's error type dies and a new one is born. Make this conversion explicit — never let `URLError` reach a ViewModel.

### Infrastructure → Repository

```swift
enum ItemRepositoryError: Error {
    case notFound
    case unauthorized
    case networkUnavailable
    case server(statusCode: Int)
    case decoding
    case unknown(underlying: Error)
}

final class ItemRepository {
    func fetch(id: String) async throws(ItemRepositoryError) -> Item {
        do {
            let dto: ItemDTO = try await httpClient.get("/items/\(id)")
            return dto.toDomain()
        } catch let error as URLError where error.code == .notConnectedToInternet {
            throw .networkUnavailable
        } catch let error as HTTPError {
            switch error.statusCode {
            case 401: throw .unauthorized
            case 404: throw .notFound
            case 500...599: throw .server(statusCode: error.statusCode)
            default: throw .unknown(underlying: error)
            }
        } catch is DecodingError {
            throw .decoding
        } catch {
            throw .unknown(underlying: error)
        }
    }
}
```

### Repository → UseCase (Domain)

```swift
enum FetchItemDomainError: Error {
    case itemNotFound
    case notLoggedIn
    case temporary           // user can retry
    case permanent(message: String)
}

struct FetchItemUseCase {
    let repository: ItemRepository

    func execute(id: String) async throws(FetchItemDomainError) -> Item {
        do {
            return try await repository.fetch(id: id)
        } catch {
            throw Self.mapError(error)
        }
    }

    private static func mapError(_ error: ItemRepositoryError) -> FetchItemDomainError {
        switch error {
        case .notFound: return .itemNotFound
        case .unauthorized: return .notLoggedIn
        case .networkUnavailable, .server: return .temporary
        case .decoding, .unknown: return .permanent(message: "Unexpected response")
        }
    }
}
```

The Domain layer **drops infrastructural detail** that the user can't act on. The UI doesn't need to know whether it was a 503 or a timeout — both map to "temporary, try again."

### UseCase → ViewModel (Presentation)

ViewModel converts domain errors into a `UserMessage` value: localized, with a recommended UI affordance and a severity. **ViewModel never throws.**

```swift
struct UserMessage: Equatable {
    let title: String
    let body: String
    let severity: Severity
    let retryAction: (@MainActor () -> Void)?

    enum Severity { case info, warning, error }
}

@MainActor
@Observable
final class ItemDetailViewModel {
    private(set) var item: Item?
    private(set) var message: UserMessage?
    private let useCase: FetchItemUseCase

    func load(id: String) async {
        do {
            item = try await useCase.execute(id: id)
        } catch let error as FetchItemDomainError {
            message = Self.userMessage(from: error, retryId: id)
        } catch {
            message = .unexpected
        }
    }

    private static func userMessage(from error: FetchItemDomainError, retryId: String) -> UserMessage {
        switch error {
        case .itemNotFound:
            return UserMessage(
                title: L10n.Item.notFoundTitle,
                body: L10n.Item.notFoundBody,
                severity: .warning,
                retryAction: nil
            )
        case .notLoggedIn:
            return UserMessage(
                title: L10n.Auth.requiredTitle,
                body: L10n.Auth.requiredBody,
                severity: .warning,
                retryAction: nil
            )
        case .temporary:
            return UserMessage(
                title: L10n.Common.temporaryProblemTitle,
                body: L10n.Common.tryAgain,
                severity: .error,
                retryAction: { [weak self] in Task { await self?.load(id: retryId) } }
            )
        case .permanent(let msg):
            return UserMessage(title: L10n.Common.errorTitle, body: msg, severity: .error, retryAction: nil)
        }
    }
}

extension UserMessage {
    static let unexpected = UserMessage(
        title: L10n.Common.errorTitle,
        body: L10n.Common.unexpected,
        severity: .error,
        retryAction: nil
    )
}
```

### Avoiding mapping copy-paste

If you have many UseCases mapping the same low-level errors, extract a `protocol ErrorMapping` or a free function per layer pair (`RepositoryError → DomainError`). Keep mappers as pure functions — testable in isolation, no DI needed.

## Presentation Strategy

Decide **once per project** which UI affordance fits which severity. The matrix below is a starting point.

| Affordance | Use when | Don't use when |
|---|---|---|
| **Alert (modal)** | Action is irreversibly blocked; user must acknowledge | For background/transient errors — interrupts flow |
| **Inline (next to field)** | Form validation, per-field issue | For app-wide errors |
| **Banner / toast** | Transient, recoverable, user can keep working (offline mode, autosave failed, sync paused) | For errors that block the next user action |
| **Empty-state in view** (iOS 17+: `ContentUnavailableView`) | List/detail failed to load → replace content with retry CTA | When partial data is available |
| **Silent log only** | Fire-and-forget side-effects (analytics, prefetch, cache miss) | When the user is waiting for a result |
| **App-wide overlay / fatal screen** | Unrecoverable, cannot continue (data corruption, license invalid) | Anything the user can retry |

### Recoverable vs non-recoverable vs fatal

```swift
enum ErrorSeverity {
    case recoverable    // user retries → success likely
    case nonRecoverable // user must navigate away or change input
    case fatal          // app cannot continue
}
```

Map this in `UserMessage` (or in the ViewModel decision) — the View should not re-classify.

### Cancellation is not an error

`CancellationError` from Swift Concurrency must **not** reach the user as an error message. Treat it as "operation aborted by us."

```swift
do {
    item = try await useCase.execute(id: id)
} catch is CancellationError {
    return  // silent — user cancelled or screen closed
} catch let error as FetchItemDomainError {
    message = Self.userMessage(from: error, retryId: id)
}
```

## Localization

User-facing strings come from `L10n.*` (or `String(localized:)` / `NSLocalizedString`). Technical strings stay in code.

```swift
extension FetchItemDomainError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .itemNotFound: L10n.Item.notFoundBody
        case .notLoggedIn: L10n.Auth.requiredBody
        case .temporary: L10n.Common.tryAgain
        case .permanent(let m): m
        }
    }
}
```

But **prefer building `UserMessage` in the ViewModel over `LocalizedError`** — `LocalizedError` ties presentation to the error type and breaks if the same error needs different copy in different contexts (e.g. on Login screen vs Detail screen).

**Anti-pattern:** showing `error.localizedDescription` of `URLError` to the user. The OS-provided string is technical and inconsistent across locales.

## Logging, Analytics, and PII Redaction

Logging happens at the **Repository layer and above** — Infrastructure throws, layers above log when they catch.

```swift
do {
    return try await repository.fetch(id: id)
} catch {
    logger.error("Failed to fetch item \(id, privacy: .public): \(error.localizedDescription, privacy: .private)")
    throw Self.mapError(error)
}
```

### Log levels

| Level | When |
|---|---|
| `.debug` | Verbose dev-only diagnostics; never goes to release builds |
| `.info` | Notable events (login, logout, switched account) |
| `.notice` | Recovered errors (retry succeeded after one failure) |
| `.error` | Caught error that affected user-visible behaviour |
| `.fault` | Programmer error; should crash in debug, log loudly in release |

### Crash reporters (Crashlytics, Sentry)

Send to crash-reporter only:
- `.fault` events
- Caught-but-unexpected errors (the `.unknown(Error)` case in your enums)
- Breadcrumbs leading to a crash

Do **not** send every caught error — you'll drown in noise from offline-mode users.

### PII redaction

Never log: passwords, tokens, full emails, full names, file paths containing usernames, location coordinates with high precision, payment data.

```swift
// Bad
logger.error("Login failed for \(email)")

// Good — use OSLog privacy markers
logger.error("Login failed for \(email, privacy: .private(mask: .hash))")

// For non-OSLog loggers — explicit redaction
logger.error("Login failed for \(PII.mask(email))")
```

Define a `PII` namespace with `mask(_ email: String) -> String` (returns `"a***@example.com"`), `mask(_ token: String) -> String` (last 4 chars), etc. Centralize policy.

## Retry, Recovery, and Idempotency

Auto-retry rules of thumb:
- ✅ `GET` requests on 5xx, network unavailable, timeout → exponential backoff with jitter
- ✅ Rate limits (429) → respect `Retry-After` header
- ❌ `POST` / `PUT` / `DELETE` without an idempotency key → never auto-retry; user might pay twice
- ❌ 4xx (other than 429) → never auto-retry; client error won't fix itself
- ❌ Auth (401) → trigger refresh flow once, then surface to user

Networking-specific retry policy lives in the future `net-architecture` skill — this skill only enforces **where the decision is made**: in the Repository or HTTPClient layer, never in the ViewModel.

User-initiated retry: ViewModel exposes `retryAction: () -> Void` in `UserMessage`. The View renders a button; tapping calls the closure. Closure re-invokes the original UseCase.

## async/await and Cancellation

```swift
func load(id: String) async {
    do {
        try Task.checkCancellation()
        item = try await useCase.execute(id: id)
    } catch is CancellationError {
        return  // silent
    } catch {
        message = Self.userMessage(from: error, retryId: id)
    }
}
```

For long-running tasks, wrap in `Task { ... }` and store handle in ViewModel; cancel on `deinit` or when the screen disappears:

```swift
@MainActor
@Observable
final class FeedViewModel {
    private var loadTask: Task<Void, Never>?

    func onAppear() {
        loadTask?.cancel()
        loadTask = Task { await load() }
    }

    func onDisappear() {
        loadTask?.cancel()
    }
}
```

### `Result<T, E>` vs `throws`

| Use `throws` | Use `Result` |
|---|---|
| async/await call site | Storing past outcome (`var lastResult: Result<...>`) |
| Single happy/error path | Combine/RxSwift bridges (`.publisher(for: Result<...>)`) |
| Layer boundaries (UseCase, Repository) | Returning from completion-handler-style callbacks (legacy) |

Mixing both in the same module is fine — each at its right place. Do not unconditionally convert `throws → Result` "to be safe" — you lose call-site clarity.

## Combine and RxSwift Specifics

Reactive frameworks make one error fatal to a stream. Decide the boundary explicitly.

### Combine

```swift
useCasePublisher(id: id)
    .map { Result<Item, Error>.success($0) }
    .catch { error in Just(.failure(error)) }   // turn error into value
    .receive(on: DispatchQueue.main)
    .sink { [weak self] result in
        switch result {
        case .success(let item): self?.item = item
        case .failure(let error): self?.message = Self.userMessage(from: error, retryId: id)
        }
    }
    .store(in: &cancellables)
```

### RxSwift

```swift
useCase.fetch(id: id)
    .map { Result<Item, Error>.success($0) }
    .catch { .just(.failure($0)) }
    .observe(on: MainScheduler.instance)
    .subscribe(onNext: { [weak self] in self?.handle($0) })
    .disposed(by: disposeBag)
```

**Rule:** convert `Error → Value` (typically `Result`) at the latest reasonable layer (ViewModel) — let upper layers see a non-failing stream that always emits state.

See `reactive-combine` and `reactive-rxswift` skills for operator-level detail.

## Testing Error Paths

Three things to test:

1. **Mappers are pure functions** — golden-test `RepositoryError → DomainError` matrix:

```swift
final class FetchItemUseCaseMappingTests: XCTestCase {
    func test_mapError_notFound_mapsTo_itemNotFound() {
        XCTAssertEqual(FetchItemUseCase.mapError(.notFound), .itemNotFound)
    }
    func test_mapError_networkUnavailable_mapsTo_temporary() {
        XCTAssertEqual(FetchItemUseCase.mapError(.networkUnavailable), .temporary)
    }
    // ... one test per case
}
```

2. **ViewModel translates domain errors to UserMessage** — mock UseCase to throw, assert published `message`:

```swift
@MainActor
final class ItemDetailViewModelErrorTests: XCTestCase {
    func test_load_whenUseCaseThrowsItemNotFound_setsWarningMessage() async {
        let useCase = MockFetchItemUseCase(error: .itemNotFound)
        let sut = ItemDetailViewModel(useCase: useCase)

        await sut.load(id: "42")

        XCTAssertEqual(sut.message?.severity, .warning)
        XCTAssertNil(sut.item)
    }
}
```

3. **Cancellation is silent** — assert no message is shown when cancelled:

```swift
func test_load_whenCancelled_doesNotSetMessage() async {
    let useCase = MockFetchItemUseCase(error: CancellationError())
    let sut = ItemDetailViewModel(useCase: useCase)

    await sut.load(id: "42")

    XCTAssertNil(sut.message)
}
```

UI snapshot tests for error states (empty state, banner, alert layout) — but only after the logic above is covered.

## Common Mistakes

1. **Showing `error.localizedDescription` to the user** — OS strings are technical, inconsistent, and sometimes leak codes (`Error -1009`). Always go through your localized `UserMessage`.
2. **God `AppError` enum** — 200 cases, every layer mutates it. Split per layer; keep top-level enums small.
3. **`catch { }`** swallowing errors — at minimum log; if you intentionally ignore, write `catch { /* intentionally ignored: <reason> */ }`.
4. **`try? value!`** — silently turns failure into crash. Either handle the error or use `try value` and `throws`.
5. **`fatalError` for predictable cases** — disk full, decoding mismatch, missing token. These are runtime conditions, not programmer errors.
6. **Treating `CancellationError` as a user-facing error** — produces a flash of "Cancelled" message every time the user navigates away. Always filter it out.
7. **Logging the same error at every layer** — three layers each log `Failed to fetch item 42` ⇒ noise. Log at the boundary that handles the error, not at every catch.
8. **PII in logs** — emails, tokens, full names, paths. Always redact at the logging call site or via OSLog `privacy:` markers.
9. **Auto-retrying non-idempotent requests** — `POST /payments` on 500 with no idempotency key → double charge. Only retry GET / explicitly idempotent endpoints.
10. **`LocalizedError` everywhere** — couples error type to user-facing copy. OK for very simple apps; for anything else build `UserMessage` in the ViewModel where context is available.
11. **One mega-`switch` in the View** — ViewModel decides severity and copy; View only renders. If View has a `switch error { ... }`, you've leaked domain types upward.
12. **Returning `Optional` instead of `throws`** — `func fetch() -> Item?` hides the reason for failure. Caller can't distinguish "not found" from "network down". Use `throws` (or `Result`) when the failure reason matters.
