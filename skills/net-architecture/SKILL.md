---
name: net-architecture
description: "Use when designing the networking layer of an iOS app — HTTPClient protocol behind framework choice (URLSession/Alamofire/Moya/Get), endpoint design, auth interceptors with token refresh, retry policies (idempotency-aware), pagination patterns, cancellation propagation, multipart/background URLSession, WebSocket/SSE, HTTP-level vs Repository-level caching, framework comparison, mock/stub testing strategies."
---

# Networking Architecture

Design the app networking layer: boundaries, typed endpoints, auth, retry,
cancellation, pagination, caching, framework choice, and tests. This skill is
about architecture, not a URLSession or Alamofire tutorial.

Detailed examples live in `references/detailed-guide.md`. Load only the section
you need with `rg -n "^## " skills/net-architecture/references/detailed-guide.md`.

## When To Load The Reference

| Need | Reference sections |
|---|---|
| Define `HTTPClient`, `HTTPRequest`, `HTTPResponse` | `The HTTPClient Boundary` |
| Pick endpoint style | `Endpoint Design` |
| Add middleware, auth, token refresh, retries | `Interceptors / Middleware` |
| Handle cancellation | `Cancellation` |
| Design paging | `Pagination` |
| Upload/download/background sessions | `Multipart, Downloads, Background URLSession` |
| WebSocket or SSE | `WebSocket / SSE` |
| Cache responses or domain data | `Caching` |
| Pick URLSession / Alamofire / Moya / OpenAPI | `Framework Comparison` |
| Write network tests | `Testing` |

## Core Shape

```
View / ViewModel
      |
      v
Repository (Domain DTO <-> API DTO mapping, cache, error mapping)
      |
      v
APIClient (typed endpoint methods returning DTOs)
      |
      v
HTTPClient (untyped request/response boundary)
      |
      v
Transport (URLSession / Alamofire / Moya / generated client)
```

Rules:

- ViewModels and UseCases do not use HTTP types. They depend on repositories and
  Domain types.
- Repositories own API DTO -> Domain mapping, repository-level cache, and
  network error mapping.
- API clients expose typed methods (`fetchItems(page:)`) and decode DTOs.
- `HTTPClient` is the framework-agnostic test boundary.
- The transport is the only layer that imports URLSession-specific wrappers,
  Alamofire, Moya, Apollo, or generated OpenAPI client types.

## HTTPClient Boundary

Use a small, portable request/response protocol:

```swift
public protocol HTTPClient {
    func send(_ request: HTTPRequest) async throws -> HTTPResponse
}

public struct HTTPRequest {
    public var url: URL
    public var method: HTTPMethod
    public var queryItems: [URLQueryItem]
    public var headers: [String: String]
    public var body: Data?
    public var timeout: TimeInterval?
    public var cachePolicy: URLRequest.CachePolicy?
    public var idempotencyKey: String?
}

public struct HTTPResponse {
    public let status: Int
    public let headers: [String: String]
    public let body: Data
}
```

Decoding belongs to the APIClient, not the transport. `idempotencyKey` is part of
the model because retry policy must know whether a `POST` or `PATCH` is safe to
retry.

## Endpoint Design

Pick one style per project:

- Typed protocol methods per API surface: best for small/medium APIs and
  direct mocking.
- Endpoint enum/value: best for large APIs that need a central endpoint catalog
  and uniform encoding.
- Generated OpenAPI client: best when a stable spec exists; wrap generated
  client types behind an app-owned API protocol. Use `net-openapi`.

Avoid exposing generated or framework-specific endpoint types outside the
networking layer.

## Middleware

Cross-cutting concerns belong in middleware/interceptors, not in every endpoint.

Standard order:

1. Logging: method/path/status/duration. Redact bodies and auth headers.
2. Auth: inject bearer token; on 401 refresh and retry once.
3. Retry: bounded exponential backoff with jitter and idempotency rules.
4. Headers/telemetry: request ID, user agent, trace headers.
5. Transport.

Auth token refresh should be single-flight, usually an actor that stores the
current refresh task. Multiple parallel 401s must wait for the same refresh
instead of starting multiple refresh requests.

## Retry And Cancellation

- Retry only idempotent methods by default: GET, HEAD, OPTIONS, PUT, DELETE.
- Retry POST/PATCH only when an idempotency key is present and the backend
  supports it.
- Retry 408, 429, 500, 502, 503, 504 by default; honor `Retry-After`.
- Keep attempts bounded, usually 3.
- Check cancellation before retrying. `URLSession.data(for:)` already propagates
  task cancellation; custom bridges must cancel the underlying task.
- `CancellationError` is not user-facing and should not be logged as an error.

## Pagination

Use what the backend supports, but do not mix patterns casually:

- Cursor pagination for feeds and changing lists.
- Page/offset pagination for stable archives.
- `AsyncSequence` when the View layer benefits from streaming page loads and
  natural cancellation.

Keep pagination state in a paginator/repository object, not in every ViewModel.

## Uploads, Downloads, Realtime

Keep specialized flows in dedicated clients:

```swift
public protocol UploadClient {
    func upload(_ data: Data, to url: URL, mimeType: String, filename: String) async throws -> URL
}

public protocol DownloadClient {
    func download(_ url: URL) async throws -> URL
}
```

Background URLSession requires a separate background configuration, delegate
bridge, stored completion handler, and relaunch recovery. Do not bolt those
concerns onto the generic `HTTPClient`.

For WebSocket/SSE, expose a channel that returns `AsyncThrowingStream` and owns
reconnect, heartbeat, and multiplexing. ViewModels consume events; they do not
own socket lifecycle.

## Caching

There are two independent cache layers:

- HTTP-level cache: `URLCache`, `URLRequest.cachePolicy`, server
  `Cache-Control`. Best for opaque responses and server-controlled freshness.
- Repository-level cache: in-memory, `NSCache`, or persistence. Best for
  domain freshness rules, offline-first, and derived data.

Never cache authorized responses in a shared `URLCache` unless server headers
explicitly make it safe. Repository-level cache should be scoped by user.

For local storage and cache schema evolution, use `persistence-architecture` and
`persistence-migrations`.

## Framework Choice

- New REST app with no spec: URLSession + this `HTTPClient` pattern.
- Stable OpenAPI spec: `swift-openapi-generator` wrapped in your own protocol.
- Existing Alamofire codebase: keep Alamofire, adapt it behind `HTTPClient`.
- Existing Moya codebase: keep Moya endpoint catalog, but keep an app-owned
  API protocol above it.
- GraphQL: Apollo and generated GraphQL models; keep it as a separate transport
  paradigm.

Do not use `URLSession.shared` directly in production code that needs auth,
custom delegates, test stubs, or environment switching. Bootstrap a configured
session in the Composition Root.

## Testing

- Unit tests: fake `HTTPClient` and assert requests, DTO decoding, and error
  mapping.
- Transport/integration tests: `URLProtocol` stub with an ephemeral
  `URLSessionConfiguration`.
- Endpoint contract tests: verify path, query, method, headers, and body
  encoding for at least one happy path per endpoint.
- Middleware tests: verify auth header injection, single-flight refresh,
  bounded retries, and cancellation.

Mock at the `HTTPClient` boundary unless the behavior under test is transport
integration itself.

## Common Mistakes

- Calling `URLSession.shared` from ViewModels or Repositories.
- Hardcoding base URLs with `#if DEBUG` instead of injecting environment.
- Decoding JSON in the ViewModel.
- Creating ad-hoc `JSONDecoder()` instances instead of central API decoder
  configuration.
- Showing `URLError.localizedDescription` to users.
- Retrying POST/PATCH without idempotency support.
- Letting every 401 request refresh tokens independently.
- Logging bodies or `Authorization` in production.
- Treating cancellation as an error.
- Caching authorized GETs in a shared URL cache.
- Putting WebSocket reconnect logic in ViewModels.
- Subclassing `URLSession` for tests instead of using `URLProtocol` or a fake
  `HTTPClient`.
