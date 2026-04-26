---
name: net-architecture
description: "Use when designing the networking layer of an iOS app — HTTPClient protocol behind framework choice (URLSession/Alamofire/Moya/Get), endpoint design, auth interceptors with token refresh, retry policies (idempotency-aware), pagination patterns, cancellation propagation, multipart/background URLSession, WebSocket/SSE, HTTP-level vs Repository-level caching, framework comparison, mock/stub testing strategies."
---

# Networking Architecture

Decisions about **how the network layer is shaped** in an iOS app: layering, the `HTTPClient` boundary, interceptors, retry/cancellation, pagination, framework choice. Not a tutorial on URLSession or Alamofire — this skill tells you **how to wire any of them into a layered architecture** that stays testable as the app grows.

> **Related skills:**
> - `arch-clean`, `arch-mvvm`, `arch-viper` — which layers the network layer reports into
> - `error-architecture` — error mapping at the network boundary, retry/idempotency rules, PII-safe logging, cancellation policy
> - `di-composition-root` — where `URLSession`, `HTTPClient`, `APIClient`, interceptors are wired
> - `di-module-assembly` — registering networking services into feature modules
> - `reactive-combine`, `reactive-rxswift` — bridging async/await network calls into reactive pipelines
> - `net-openapi` — generating typed clients from OpenAPI specs (Apple's `swift-openapi-generator`)
> - `persistence-architecture` — pairing remote source with a local cache (offline-first, read-through, observe-with-refresh)
> - `persistence-migrations` — when a server contract change requires a local-store schema migration (DTO restructure → cached DTO/entity restructure)

## Why This Skill Exists

Without an architecture, network code drifts into:

- **API call inside ViewModel** — `URLSession.shared.dataTask(...)` lives in 30 ViewModels, each handling auth/retry/decoding differently.
- **Hardcoded base URL and headers** — staging/prod toggles via `#if DEBUG`, can't run UI tests against a stub.
- **Copy-pasted JSON decoding** — same DTO defined twice with different field cases; one screen breaks when API renames a field.
- **Auth token refresh races** — five parallel requests get 401, all five trigger `/refresh` simultaneously.
- **Retry that double-charges** — `POST /payments` retried on timeout because "the framework does it".
- **Mocking nightmare** — to test a ViewModel you need to swap `URLSession`, but it's a `let` inside a singleton.

Fix: **a typed boundary (`HTTPClient` / `APIClient` protocols) with all cross-cutting concerns implemented as composable interceptors, isolated from the rest of the app behind a Repository.**

## Layering

```
View / ViewModel              ← никогда не трогает HTTP напрямую
        │
        ▼
Repository (Domain DTO ↔ API DTO mapping, cache, error mapping)
        │
        ▼
APIClient (typed endpoints: func fetchItems() async throws -> [ItemDTO])
        │
        ▼
HTTPClient (untyped: takes Request, returns (Data, HTTPURLResponse))
        │
        ▼
Transport (URLSession / Alamofire / Moya / generated client)
```

**Rules:**

- **ViewModel/UseCase never imports Foundation.URL or HTTP types.** They depend on `Repository` (domain types only).
- **Repository owns mapping** API DTO → Domain model and `RepositoryError` ← network errors. See `error-architecture`.
- **APIClient is the typed surface** — one method per endpoint, returns DTO, throws `APIError` (or `Result<DTO, APIError>` for storage; see `error-architecture` decision table).
- **HTTPClient is the framework-agnostic boundary** — any of URLSession/Alamofire/Moya hides behind it. This is what tests stub.
- **Transport is where the framework actually lives.** If you swap Alamofire for raw URLSession, only `URLSessionHTTPClient` changes.

## The HTTPClient Boundary

```swift
public protocol HTTPClient {
    func send(_ request: HTTPRequest) async throws -> HTTPResponse
}

public struct HTTPRequest {
    public var url: URL
    public var method: HTTPMethod          // .get, .post, .put, .delete, .patch
    public var headers: [String: String]
    public var body: Data?
    public var timeout: TimeInterval?
    public var cachePolicy: URLRequest.CachePolicy?
    public var idempotencyKey: String?     // see retry section
}

public struct HTTPResponse {
    public let status: Int
    public let headers: [String: String]
    public let body: Data
}
```

**Why this shape:**

- Returns raw `Data` + status — decoding belongs to `APIClient`, not transport.
- `idempotencyKey` is a first-class field, not a magic header — retry policy uses it to decide what's safe to retry.
- No `URLRequest` in the public surface — keeps the protocol portable to non-Foundation transports (e.g. `AsyncHTTPClient` on Linux for KMP/server-shared code).

## Endpoint Design

Three patterns. Pick **one per project** and stick with it.

### Pattern 1 — Per-endpoint typed methods on APIClient

```swift
public protocol ItemsAPI {
    func fetchItems(page: Int) async throws -> ItemsPage
    func createItem(_ draft: ItemDraft) async throws -> ItemDTO
    func deleteItem(id: String) async throws
}

final class HTTPItemsAPI: ItemsAPI {
    let http: HTTPClient
    let baseURL: URL

    func fetchItems(page: Int) async throws -> ItemsPage {
        let req = HTTPRequest(
            url: baseURL.appending(path: "items"),
            method: .get,
            headers: [:],
            queryItems: [.init(name: "page", value: "\(page)")]
        )
        let res = try await http.send(req)
        try APIErrorMapper.check(res)
        return try JSONDecoder.api.decode(ItemsPage.self, from: res.body)
    }
}
```

**Best for:** small/medium APIs (≤50 endpoints), strong autocomplete, easy mocking via protocol.

### Pattern 2 — Endpoint as value (Moya-style enum or struct)

```swift
public enum ItemsEndpoint: APIEndpoint {
    case list(page: Int)
    case create(ItemDraft)
    case delete(id: String)

    var path: String {
        switch self {
        case .list: return "items"
        case .create: return "items"
        case .delete(let id): return "items/\(id)"
        }
    }
    var method: HTTPMethod { /* ... */ }
    var task: APITask { /* ... */ }
}

final class APIClient {
    func send<T: Decodable>(_ endpoint: APIEndpoint) async throws -> T { /* ... */ }
}
```

**Best for:** large APIs (100+ endpoints), strict cross-cutting transformation (uniform encoding/headers), Moya-style codebases. Trade-off: weaker autocomplete (return type erased to `T`).

### Pattern 3 — Generated client (OpenAPI)

See `net-openapi` skill. Generated `Client` exposes `try await client.listItems(.init(query: .init(page: page)))`. Wrap it in your `ItemsAPI` protocol so the rest of the app doesn't depend on generated types.

## Interceptors / Middleware

Cross-cutting concerns belong in composable middleware, not scattered through endpoints.

```swift
public protocol HTTPMiddleware {
    func intercept(
        _ request: HTTPRequest,
        next: (HTTPRequest) async throws -> HTTPResponse
    ) async throws -> HTTPResponse
}

final class MiddlewareHTTPClient: HTTPClient {
    let transport: HTTPClient
    let middlewares: [HTTPMiddleware]

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        var chain: (HTTPRequest) async throws -> HTTPResponse = transport.send
        for middleware in middlewares.reversed() {
            let next = chain
            chain = { try await middleware.intercept($0, next: next) }
        }
        return try await chain(request)
    }
}
```

**Standard middleware stack (order matters — top to bottom):**

1. **Logging** (outermost — sees everything including retries) — log method/path/status/duration; **never log body or auth headers without PII redaction** (see `error-architecture`).
2. **Auth** — inject `Authorization` header; on 401 try refresh + retry once.
3. **Retry** — exponential backoff with jitter; idempotency-aware (see below).
4. **Headers / Telemetry** — `User-Agent`, request ID, trace headers.
5. **Transport** (innermost) — actual `URLSession`/Alamofire/Moya.

### Auth interceptor with token refresh

Naïve refresh has a race: 5 parallel requests all see 401, all 5 fire `/refresh`. Solution: **a single in-flight refresh, queued waiters.**

```swift
actor TokenRefresher {
    private var refreshTask: Task<AccessToken, Error>?
    private let storage: TokenStorage
    private let api: AuthAPI

    func currentToken() async throws -> AccessToken {
        if let task = refreshTask { return try await task.value }
        if let token = storage.token, !token.isExpiringSoon { return token }
        return try await refresh()
    }

    func refresh() async throws -> AccessToken {
        if let task = refreshTask { return try await task.value }
        let task = Task<AccessToken, Error> { [api, storage] in
            defer { storage.token = nil }
            let new = try await api.refresh(refreshToken: storage.refreshToken!)
            storage.token = new
            return new
        }
        refreshTask = task
        defer { refreshTask = nil }
        return try await task.value
    }
}

struct AuthMiddleware: HTTPMiddleware {
    let refresher: TokenRefresher

    func intercept(
        _ request: HTTPRequest,
        next: (HTTPRequest) async throws -> HTTPResponse
    ) async throws -> HTTPResponse {
        var req = request
        let token = try await refresher.currentToken()
        req.headers["Authorization"] = "Bearer \(token.value)"

        let response = try await next(req)
        guard response.status == 401 else { return response }

        let newToken = try await refresher.refresh()
        req.headers["Authorization"] = "Bearer \(newToken.value)"
        return try await next(req)
    }
}
```

**Key invariants:**

- `actor TokenRefresher` — only one refresh at a time, automatically.
- 401 → refresh → retry **once.** If second attempt also returns 401, propagate — refresh token is dead, user must re-login.
- Refresh failure → clear tokens, route to login screen via a separate `AuthEvents` stream (do NOT throw a UI message from the middleware).

### Retry policy

```swift
struct RetryPolicy {
    var maxAttempts: Int = 3
    var baseDelay: TimeInterval = 0.3
    var maxDelay: TimeInterval = 4.0
    var retryableStatuses: Set<Int> = [408, 429, 500, 502, 503, 504]

    func shouldRetry(_ request: HTTPRequest, attempt: Int, response: HTTPResponse?) -> Bool {
        guard attempt < maxAttempts else { return false }
        guard isIdempotent(request) else { return false }
        if let res = response { return retryableStatuses.contains(res.status) }
        return true   // transport error (no response)
    }

    private func isIdempotent(_ request: HTTPRequest) -> Bool {
        switch request.method {
        case .get, .head, .options, .put, .delete: return true
        case .post, .patch: return request.idempotencyKey != nil
        }
    }

    func delay(for attempt: Int) -> TimeInterval {
        let exp = baseDelay * pow(2, Double(attempt))
        let jitter = Double.random(in: 0...(exp * 0.3))
        return min(maxDelay, exp + jitter)
    }
}
```

**Hard rules:**

- **Never auto-retry POST/PATCH without `Idempotency-Key`.** Double-charge bugs are real and ugly. See `error-architecture`.
- **Honor `Retry-After` header** for 429/503 — overrides backoff.
- **Bounded attempts** — 3 is a sane default; 10 turns transient outages into thundering herds.
- **Per-host circuit breaker** is the next step for production; out of scope for the skill.

## Cancellation

Cancellation must propagate from the View layer all the way down to `URLSession.dataTask`.

```swift
final class ItemListViewModel {
    private var loadTask: Task<Void, Never>?

    func onAppear() {
        loadTask = Task { @MainActor in
            do {
                items = try await repository.fetchItems()
            } catch is CancellationError {
                // silent — see error-architecture
            } catch {
                message = ErrorMapper.toUserMessage(error)
            }
        }
    }

    func onDisappear() {
        loadTask?.cancel()
    }
}
```

**Rules:**

- `URLSession` async methods (`data(for:)`) **already** propagate cancellation to the underlying task — no extra wiring needed.
- Custom `HTTPClient` implementations **must** check `Task.isCancelled` before retry attempts and call `URLSessionDataTask.cancel()` if you maintain your own bridge.
- **`CancellationError` is not a user error** — never show it; never log at error level. Filter at the boundary that knows the user's intent (typically the ViewModel).
- Combine: use `.handleEvents(receiveCancel:)` to stop side effects; do NOT call `cancel()` on a publisher inside `sink` — store the `AnyCancellable` and drop it.

## Pagination

Three patterns. Choose based on what the API supports; never roll multiple in one app.

### Cursor-based (preferred for infinite feeds)

```swift
public struct ItemsPage {
    public let items: [Item]
    public let nextCursor: String?     // nil = end
}

actor ItemsPaginator {
    let api: ItemsAPI
    private var cursor: String?
    private var isExhausted = false
    private(set) var items: [Item] = []

    func loadNext() async throws -> [Item] {
        guard !isExhausted else { return items }
        let page = try await api.fetchItems(cursor: cursor)
        items.append(contentsOf: page.items)
        cursor = page.nextCursor
        isExhausted = page.nextCursor == nil
        return items
    }

    func reset() { cursor = nil; isExhausted = false; items = [] }
}
```

### Offset / page-number (for stable, paginated lists)

```swift
let page = try await api.fetchItems(page: pageNumber, pageSize: 20)
```

Trade-off: **drift** — if items are added/deleted server-side between page loads, you see duplicates or skips. Use cursors for feeds, offsets only for stable archives.

### Streaming (`AsyncSequence`)

```swift
extension ItemsPaginator: AsyncSequence {
    typealias Element = [Item]
    /* AsyncIterator that yields each loaded page */
}

for try await page in paginator { /* update UI */ }
```

Cleanest API for the View layer; cancellation propagates naturally via `Task.cancel()`.

## Multipart, Downloads, Background URLSession

Keep these in dedicated specialized clients — don't pollute `HTTPClient` with multipart concerns.

```swift
public protocol UploadClient {
    func upload(_ data: Data, to url: URL, mimeType: String, filename: String) async throws -> URL
}

public protocol DownloadClient {
    func download(_ url: URL) async throws -> URL  // local file URL
}
```

**Background URLSession** (when uploads must survive app suspension):

- Separate `URLSessionConfiguration.background(withIdentifier:)` instance — one per session ID; never share.
- Delegate-based; bridge to async via `withCheckedThrowingContinuation` keyed by `taskIdentifier`.
- App must implement `application(_:handleEventsForBackgroundURLSession:completionHandler:)` and store the completion handler — without this iOS won't wake your app.
- Resume strategy on app relaunch: enumerate `session.tasks` and rebind continuations.

## WebSocket / SSE

Native iOS has `URLSessionWebSocketTask`. Wrap it in an `AsyncStream` for the consumer:

```swift
public protocol RealtimeChannel {
    func messages() -> AsyncThrowingStream<RealtimeEvent, Error>
    func send(_ event: RealtimeEvent) async throws
    func close()
}
```

**Architectural notes:**

- Reconnect logic belongs in the channel implementation (exponential backoff, jitter), not the consumer.
- Keep one connection per logical channel; multiplex on top if needed — never open one socket per ViewModel.
- Heartbeat (ping every N seconds) — ALWAYS. iOS aggressively kills idle TCP sockets in background.
- For SSE there's no native API; use `URLSession.bytes(for:)` and parse the `text/event-stream` format yourself, or use `LDSwiftEventSource`.

## Caching

Two layers — pick deliberately.

| Layer | Implementation | When to use |
|---|---|---|
| HTTP-level | `URLCache`, `URLRequest.cachePolicy`, `Cache-Control` from server | Server controls freshness, opaque blobs (images, large JSON) |
| Repository-level | In-memory dict / `NSCache` / SQLite | Domain-specific freshness rules, offline-first, derived data |

**Hard rules:**

- **Never cache responses with `Authorization` header** unless the server returns explicit `Cache-Control: private` and you trust it. `URLCache` is shared across users on the same device — leak risk.
- **Cache invalidation** belongs to the Repository, not the View — when a `POST /items` succeeds, the Repository invalidates `items list` cache before returning.
- **Do not** cache 4xx/5xx responses unless you're implementing offline-first explicitly (then cache them as "last known error" with TTL).

Persistent storage strategies (Core Data, SwiftData, SQLite) — see `persistence-architecture` skill; for cached-DTO/entity schema evolution see `persistence-migrations`.

## Framework Comparison

| Framework | Style | Async | Interceptors | Codegen | When to pick |
|---|---|---|---|---|---|
| `URLSession` | Native, low-level | async/await ✅, Combine ✅ | Manual (your middleware) | — | **Default for new projects.** No dependency, full control. |
| Alamofire | Imperative request builder | async/await ✅, Combine ✅, RxSwift via extension | Built-in `RequestInterceptor` | — | Existing Alamofire codebases; multipart edge cases; legacy iOS 13- support. |
| Moya | Declarative endpoint enum on top of Alamofire | async/await (Moya 15+), Combine ✅, RxSwift ✅ | Plugins | — | Large API surface (100+ endpoints), Rx-heavy team, want endpoint catalog. |
| Get (kean) | Modern minimal URLSession wrapper | async/await ✅ | Delegate-based | — | Greenfield projects that want less boilerplate than raw URLSession. |
| `swift-openapi-generator` | Generated client from OpenAPI spec | async/await ✅ | `ClientMiddleware` | ✅ from yaml | API has stable OpenAPI spec; want compile-time guarantees. See `net-openapi`. |
| Apollo iOS | GraphQL client (different paradigm) | async/await ✅ | Interceptors | ✅ from `.graphql` | GraphQL backend — out of scope for this skill. |

**Recommendation matrix:**

- **New project, REST, no spec yet** → URLSession + this skill's HTTPClient pattern.
- **New project, REST, OpenAPI spec exists** → `swift-openapi-generator` wrapped in your `APIClient` protocol.
- **Existing Alamofire codebase** → keep Alamofire, adapt to `HTTPClient` protocol via `AlamofireHTTPClient`.
- **Existing Moya codebase** → keep, but consider whether the enum endpoint catalog still pays for itself in async/await world (Moya's RxSwift sweet spot is fading).
- **GraphQL** → Apollo, separate skill territory.

### URLSession integration (mini-section)

```swift
final class URLSessionHTTPClient: HTTPClient {
    let session: URLSession
    let baseURL: URL

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        let urlRequest = try toURLRequest(request)
        let (data, response) = try await session.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse else {
            throw HTTPClientError.invalidResponse
        }
        return HTTPResponse(
            status: http.statusCode,
            headers: http.allHeaderFields as? [String: String] ?? [:],
            body: data
        )
    }
}
```

Bootstrap in CR: one `URLSession(configuration: .default)` per environment; **do not** use `URLSession.shared` if you have custom delegate or auth challenge logic.

### Alamofire integration (mini-section)

```swift
import Alamofire

final class AlamofireHTTPClient: HTTPClient {
    let session: Session

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        let af = try toAFRequest(request)
        let response = await session.request(af).serializingData().response
        guard let http = response.response, let data = response.data else {
            throw response.error ?? HTTPClientError.invalidResponse
        }
        return HTTPResponse(
            status: http.statusCode,
            headers: http.allHeaderFields as? [String: String] ?? [:],
            body: data
        )
    }
}
```

Use Alamofire's `RequestInterceptor` only if you actively use Alamofire-specific features (auth challenge, custom server trust). Otherwise put interceptor logic in your own `HTTPMiddleware` chain — keeps it portable.

### Moya integration (mini-section)

```swift
enum ItemsTarget: TargetType {
    case list(page: Int)
    case create(ItemDraft)
    /* baseURL, path, method, task, headers, sampleData */
}

let provider = MoyaProvider<ItemsTarget>(plugins: [LoggerPlugin(), AuthPlugin()])

final class MoyaItemsAPI: ItemsAPI {
    let provider: MoyaProvider<ItemsTarget>

    func fetchItems(page: Int) async throws -> ItemsPage {
        let response = try await provider.request(.list(page: page))
        try APIErrorMapper.check(response)
        return try JSONDecoder.api.decode(ItemsPage.self, from: response.data)
    }
}
```

`MoyaProvider` is itself the transport — for Moya projects you can skip `HTTPClient` middleware and use Moya `PluginType` instead. **But** keep the `ItemsAPI` protocol layer above Moya so the rest of the app doesn't import Moya types.

### swift-openapi-generator (cross-link)

Setup, integration, error mapping, mocking — see dedicated `net-openapi` skill.

## Testing

Mock at the **HTTPClient** boundary, not at `URLSession`. Two approaches:

### URLProtocol stub (transport-level, integration-style)

```swift
final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown)); return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
    override func stopLoading() {}
}

func makeStubbedSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [StubURLProtocol.self]
    return URLSession(configuration: config)
}
```

**Use for:** integration tests verifying retry/auth/middleware end-to-end, contract tests against a recorded server response.

### Fake HTTPClient (unit-style)

```swift
final class FakeHTTPClient: HTTPClient {
    var responses: [URL: Result<HTTPResponse, Error>] = [:]
    var sentRequests: [HTTPRequest] = []

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        sentRequests.append(request)
        guard let result = responses[request.url] else {
            throw HTTPClientError.invalidResponse
        }
        return try result.get()
    }
}
```

**Use for:** ViewModel/Repository unit tests where you don't care about transport — only "did the call happen with the right query/body, what does this DTO turn into?"

### Contract tests for endpoint encoding

```swift
func test_fetchItems_encodesPageAsQuery() async throws {
    let fake = FakeHTTPClient()
    let api = HTTPItemsAPI(http: fake, baseURL: URL(string: "https://x")!)

    _ = try? await api.fetchItems(page: 3)

    let req = fake.sentRequests.first!
    XCTAssertEqual(req.url.absoluteString, "https://x/items?page=3")
    XCTAssertEqual(req.method, .get)
}
```

**Always** verify URL composition for at least one happy-path test per endpoint — endpoint encoding bugs are silent until QA finds them in prod.

## Common Mistakes

1. **`URLSession.shared` everywhere** — can't swap for tests, no place to inject auth interceptor or custom delegate. Use a CR-bootstrapped `URLSession` instance.
2. **Hardcoded `https://api.example.com`** — staging/prod toggles via `#if DEBUG`. Inject `BaseURLProvider` or `Environment` value type from CR.
3. **JSON decoding in the ViewModel** — couples UI to API DTO shape. Decode in `APIClient`, map to Domain in Repository, hand the View a Domain type.
4. **Using `JSONDecoder()` ad-hoc** — forgot `keyDecodingStrategy`, dates parsed as ISO8601 in one place and Unix timestamp in another. Centralize one `JSONDecoder.api` extension.
5. **Showing `URLError.localizedDescription`** to the user (`The Internet connection appears to be offline. (Code -1009.)`). Map at the Repository boundary to `RepositoryError.networkUnavailable`, then to a `UserMessage` in the ViewModel. See `error-architecture`.
6. **Auto-retrying `POST` on timeout** — double-charge in payments, duplicate orders. `POST` retries require `Idempotency-Key` agreed with backend.
7. **Token refresh race** — 5 parallel 401s fire 5 refresh requests. Single in-flight refresh via `actor`.
8. **Logging request body / `Authorization` header in production** — leaks PII and credentials. Strip at the logger; OSLog `privacy:` markers. See `error-architecture`.
9. **Treating `CancellationError` as user-facing** — flash of "Cancelled" message every time the user navigates away. Filter at the ViewModel.
10. **Caching authorized GETs in `URLCache`** — `URLCache` is shared across users on the same device. Use Repository-level cache keyed by user.
11. **WebSocket reconnect logic in the ViewModel** — every screen reinvents it. Belongs in the channel implementation; ViewModel just consumes the `AsyncStream`.
12. **Mocking `URLSession` directly with subclassing** — fragile; methods are not all overridable. Stub via `URLProtocol` or hide behind `HTTPClient` protocol and fake that.
