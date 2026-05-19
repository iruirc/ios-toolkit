# nav-deeplinks — Detailed Guide

Load one section at a time:
`rg -n "^## " skills/nav-deeplinks/references/detailed-guide.md`

The navigation layer (`Route` → screen) is **out of scope** here. See
`arch-coordinator`, `arch-swiftui-navigation`, or `arch-tca`.

## Link Type Decision

Ship **both** a custom scheme and Universal Links; map both to one `Route`.

Custom scheme — `Info.plist`:

```xml
<key>CFBundleURLTypes</key>
<array>
  <dict>
    <key>CFBundleURLName</key><string>com.example.app</string>
    <key>CFBundleURLSchemes</key><array><string>myapp</string></array>
  </dict>
</array>
```

Custom scheme is unauthenticated and hijackable (any app may register the same
scheme). Never use it as a security boundary; OAuth callbacks should use a
unique scheme and still verify `state`.

Universal Links survive "app not installed" (browser opens the `https://` URL),
are domain-bound (not hijackable), and are the default for any user-facing or
shared link.

## Universal Links Setup

1. Associated Domains entitlement:

```
applinks:example.com
applinks:www.example.com
```

2. `apple-app-site-association` (AASA) — served at
`https://example.com/.well-known/apple-app-site-association`, `Content-Type:
application/json`, **no redirect**, reachable without auth:

```json
{
  "applinks": {
    "details": [
      {
        "appIDs": ["ABCDE12345.com.example.app"],
        "components": [
          { "/": "/item/*",    "comment": "item detail" },
          { "/": "/profile/*", "comment": "profile" },
          { "/": "/promo",     "?": { "code": "*" } }
        ]
      }
    ]
  }
}
```

3. Apple's CDN caches AASA — bump it on deploy; verify via
`https://app-site-association.cdn-apple.com/a/v1/example.com`.

Common AASA failures: wrong `Content-Type`, served behind a 301/302,
`appIDs` not `TeamID.BundleID`, file not at `.well-known`, JSON invalid.

## The DeepLink Parser

Pure, `Sendable`, no UI, no navigation, no singletons. The `Route` enum is
owned by the navigation layer's public contract; the parser only produces it.

```swift
enum Route: Equatable, Sendable {
    case item(id: String)
    case profile(userId: String)
    case promo(code: String)
}

enum DeepLinkParser {
    private static let universalLinkHosts: Set<String> = [
        "example.com",
        "www.example.com"
    ]

    static func parse(_ url: URL) -> Route? {
        guard let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return nil }

        // Normalize custom scheme and https:// to the same path shape.
        // myapp://item/42            -> host "item", path "/42"
        // https://example.com/item/42 -> path "/item/42"
        guard let scheme = comps.scheme?.lowercased() else { return nil }
        let segments: [String]
        switch scheme {
        case "myapp":
            segments = ([comps.host].compactMap { $0 })
                + comps.path.split(separator: "/").map(String.init)
        case "https":
            guard let host = comps.host?.lowercased(),
                  universalLinkHosts.contains(host)
            else { return nil }
            segments = comps.path.split(separator: "/").map(String.init)
        default:
            return nil
        }

        switch segments.first {
        case "item":
            guard let id = segments[safe: 1], !id.isEmpty, id.count <= 64
            else { return nil }
            return .item(id: id)
        case "profile":
            guard let uid = segments[safe: 1], !uid.isEmpty else { return nil }
            return .profile(userId: uid)
        case "promo":
            guard let code = comps.queryItems?
                .first(where: { $0.name == "code" })?.value, !code.isEmpty
            else { return nil }
            return .promo(code: code)
        default:
            return nil   // unknown / old link -> caller falls back to root
        }
    }
}

private extension Array {
    subscript(safe i: Int) -> Element? {
        indices.contains(i) ? self[i] : nil
    }
}
```

Validate every extracted value (non-empty, length/bounds). The URL is
untrusted input; `nil` is a normal, tested outcome.

## Entry Points

One router, every source funnels in. The router owns timing/auth; it forwards
the `Route` to the navigation layer via an injected closure/protocol so this
skill stays navigation-agnostic.

```swift
@MainActor
final class DeepLinkRouter {
    private var pending: Route?
    private var isReady = false
    private let isAuthed: () -> Bool
    private let requiresAuth: (Route) -> Bool
    private let navigate: (Route) -> Void   // -> arch-coordinator / SwiftUI Router

    init(isAuthed: @escaping () -> Bool,
         requiresAuth: @escaping (Route) -> Bool,
         navigate: @escaping (Route) -> Void) {
        self.isAuthed = isAuthed
        self.requiresAuth = requiresAuth
        self.navigate = navigate
    }

    // Custom scheme
    func handle(_ url: URL) {
        guard let route = DeepLinkParser.parse(url) else { return }  // app already at root
        dispatch(route)
    }

    // Universal Link
    func handle(_ activity: NSUserActivity) {
        guard activity.activityType == NSUserActivityTypeBrowsingWeb,
              let url = activity.webpageURL else { return }
        handle(url)
    }

    // Push / notification tap
    func handle(userInfo: [AnyHashable: Any]) {
        guard let s = userInfo["deeplink"] as? String,
              let url = URL(string: s) else { return }
        handle(url)
    }

    // Quick action / widget — already an intent
    func handle(shortcut type: String) {
        switch type {
        case "com.example.app.newItem": dispatch(.item(id: "new"))
        default: break
        }
    }

    func appBecameReady() {
        isReady = true
        if let p = pending { pending = nil; dispatch(p) }
    }

    func authDidChange() {
        if isAuthed(), let p = pending { pending = nil; dispatch(p) }
    }

    private func dispatch(_ route: Route) {
        guard isReady else { pending = route; return }
        if requiresAuth(route) && !isAuthed() { pending = route; return }
        navigate(route)
    }
}
```

SwiftUI wiring:

```swift
.onOpenURL { router.handle($0) }
.onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { router.handle($0) }
```

`AppDelegate` / `SceneDelegate`:

```swift
func application(_ app: UIApplication, open url: URL,
                 options: [UIApplication.OpenURLOptionsKey: Any]) -> Bool {
    router.handle(url); return true
}

func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
    router.handle(userActivity)
}
```

## Cold Start & Pending Route

Sequence for a link from a *killed* app:

1. OS launches app, delivers URL/activity before the object graph exists.
2. `router.handle` parses → `isReady == false` → store `pending`.
3. Composition Root finishes building graph + restores auth → calls
   `router.appBecameReady()` → `pending` replays once.
4. If the route needs auth and the user is logged out, it stays buffered;
   `router.authDidChange()` after a successful login replays it.

Reset-vs-preserve: per route decide whether arrival resets the nav stack
(e.g. promo → fresh) or pushes onto the current stack (e.g. item from a list).
Record the decision in `feature-requirements` and verify in
`mobile-ops-checklist`.

## Deferred Deep Links

User taps a marketing link, has no app, installs from the App Store, opens —
the original link is lost (App Store does not pass it through). Options:

- **Universal Link first** — if the app *is* installed there is no deferral
  problem; this only matters for the not-installed path.
- Attribution SDK (Branch, AppsFlyer, Adjust) stores the click server-side
  keyed by a fingerprint / paste of a clipboard token, then returns the
  intended `Route` on first launch via its callback → feed into the same
  `DeepLinkParser` / `Route`.
- Apple Ads Attribution / `AdServices` token for campaign attribution only —
  not a content router.

Keep the SDK at the edge: its callback yields a `URL` or `Route`, then the
normal funnel + cold-start buffer takes over. Do not let an attribution SDK
own navigation.

## Testing

Parser table test:

```swift
func test_parse() {
    let cases: [(String, Route?)] = [
        ("myapp://item/42",                       .item(id: "42")),
        ("https://example.com/item/42",           .item(id: "42")),
        ("https://evil.example/item/42",          nil),
        ("ftp://example.com/item/42",             nil),
        ("https://example.com/item/",             nil),
        ("https://example.com/unknown",           nil),
        ("https://example.com/promo?code=ABC",    .promo(code: "ABC")),
        ("myapp://item/" + String(repeating: "x", count: 999), nil),
    ]
    for (s, expected) in cases {
        XCTAssertEqual(DeepLinkParser.parse(URL(string: s)!), expected, s)
    }
}
```

Cold-start replay:

```swift
func test_coldStart_replaysOnce() {
    var routed: [Route] = []
    let r = DeepLinkRouter(isAuthed: { true },
                           requiresAuth: { _ in false },
                           navigate: { routed.append($0) })
    r.handle(URL(string: "myapp://item/7")!)   // not ready -> buffered
    XCTAssertTrue(routed.isEmpty)
    r.appBecameReady()
    XCTAssertEqual(routed, [.item(id: "7")])
    r.appBecameReady()                          // no duplicate
    XCTAssertEqual(routed, [.item(id: "7")])
}
```

Auth gate:

```swift
func test_authGate_buffersUntilLogin() {
    var routed: [Route] = []
    var loggedIn = false
    let r = DeepLinkRouter(isAuthed: { loggedIn },
                           requiresAuth: { _ in true },
                           navigate: { routed.append($0) })
    r.appBecameReady()
    r.handle(URL(string: "myapp://profile/me")!)   // logged out -> buffered
    XCTAssertTrue(routed.isEmpty)
    loggedIn = true
    r.authDidChange()
    XCTAssertEqual(routed, [.profile(userId: "me")])
}
```

Manual:

```
xcrun simctl openurl booted "myapp://item/42"
xcrun simctl openurl booted "https://example.com/item/42"
```

Universal Links on device: long-press the link in Notes → it must offer
"Open in <App>"; if it opens Safari, AASA/entitlement is wrong.
