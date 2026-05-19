---
name: nav-deeplinks
description: "Use when wiring deep links / universal links into an iOS or macOS app — choosing custom URL scheme vs Universal Links vs App Links, Associated Domains entitlement and apple-app-site-association, the architecture-agnostic URL → typed Route parser, every entry point (onOpenURL / application(_:open:) / NSUserActivity / push payload / UNNotificationResponse / Quick Actions / widgets / Spotlight), deferred deep links, cold-start buffering behind auth/onboarding gates, and testing. This skill owns the URL→Route mechanics; it hands the Route to the navigation layer (see arch-coordinator / arch-swiftui-navigation for how a Route reaches a screen)."
---

# Deep Links & Universal Links

Turn an inbound URL / activity / notification into a **typed `Route`**, then hand
that `Route` to the navigation layer. This skill is about the *entry side*: link
types, entitlements, the parser, every OS entry point, cold-start timing, and
tests. It is **not** a navigation tutorial — how a `Route` reaches a screen is
owned by `arch-coordinator` (Coordinator) or `arch-swiftui-navigation` (SwiftUI
Router) or `arch-tca` (state mutation).

Detailed code lives in `references/detailed-guide.md`. Load only the section you
need with `rg -n "^## " skills/nav-deeplinks/references/detailed-guide.md`.

> **Related skills:**
> - `arch-coordinator` — how a parsed `Route`/`DeepLink` drives UIKit Coordinator navigation
> - `arch-swiftui-navigation` — how a parsed `Route` mutates `NavigationPath` / tab selection
> - `arch-tca` — deep link as a state-mutating action (`StackState`/`@Presents`)
> - `feature-requirements` — design-time: is a deep-link entry needed, reset-vs-preserve policy
> - `mobile-ops-checklist` — validation-time: entitlements/AASA/link registration verified
> - `di-composition-root` — where `DeepLinkRouter` is wired and given the "graph ready" signal

## When To Load The Reference

| Need | Reference section |
|---|---|
| Pick scheme vs Universal vs App Links | `Link Type Decision` |
| Configure AASA + entitlement | `Universal Links Setup` |
| Write the URL → Route parser | `The DeepLink Parser` |
| Handle every OS entry point | `Entry Points` |
| Buffer links during cold start / auth gate | `Cold Start & Pending Route` |
| Deferred deep links (post-install attribution) | `Deferred Deep Links` |
| Test parsing and routing | `Testing` |

## Core Shape

```
OS entry point                          (many sources, one funnel)
  onOpenURL / application(_:open:)
  NSUserActivity (Universal Link)
  push userInfo / UNNotificationResponse
  UIApplicationShortcutItem / widget / Spotlight
        |
        v
DeepLinkRouter.handle(URL | NSUserActivity | userInfo)   <- this skill
        |
        v
DeepLinkParser.parse(...) -> Route?                       <- this skill (pure)
        |
        v
  app graph ready?  --no--> PendingRoute (buffer)         <- this skill
        |
       yes
        v
NavigationLayer.route(Route)        <- arch-coordinator / arch-swiftui-navigation
```

## Rules

- **One funnel.** Every entry point converts its payload to a `URL` (or directly
  to intent) and calls a single `DeepLinkRouter`. No parsing scattered across
  `AppDelegate`, `SceneDelegate`, and views.
- **Parser is pure and Sendable.** `DeepLinkParser.parse` takes a `URL`, returns
  `Route?`, touches no UI, no singletons, no navigation. This is the only unit
  that needs heavy unit tests.
- **`Route` is a typed enum**, exhaustive, owned by the navigation layer's
  contract — not stringly-typed `[String: Any]`. Unknown URL → `nil` → defined
  fallback (open app at root, not crash).
- **The router does not navigate.** It produces a `Route` and forwards it to the
  navigation abstraction. Crossing that line duplicates `arch-coordinator` /
  `arch-swiftui-navigation`.
- **Cold start is the hard case.** A link can arrive before the object graph,
  auth state, or onboarding is ready. Buffer one `PendingRoute`; replay it when
  the graph signals ready and the gate (auth/onboarding) is satisfied or
  re-evaluated.
- **Validate, don't trust.** A URL is untrusted input. Validate host/path,
  bounds-check IDs, never `try!`-decode, never perform a destructive or
  authenticated action purely from a link without an in-app confirmation step.
- **macOS:** Universal Links via `NSUserActivity` apply; custom scheme via
  `application(_:open:)` / `NSAppleEventManager`. App Links is Android-only.

## Link Type Decision

| | Custom scheme `myapp://` | Universal Links (iOS) / App Links (Android) |
|---|---|---|
| Setup | `CFBundleURLTypes` only | AASA file on HTTPS domain + Associated Domains entitlement |
| Opens web fallback if app missing | No (link dead) | Yes (same `https://` URL works in browser) |
| Hijackable by other apps | Yes (any app can claim scheme) | No (domain-bound) |
| Use for | internal app-to-app, dev/QA, OAuth callback | all user-facing / shared / marketing links |

**Default: Universal Links for anything a user can receive or share.** Keep a
custom scheme only for internal/OAuth/testing. Ship both; the parser maps both
URL shapes to the same `Route`.

## Entry Points — all funnel to one router

- Custom scheme, app foreground/background: `onOpenURL` (SwiftUI) /
  `scene(_:openURLContexts:)` / `application(_:open:options:)`.
- Universal Link: `onContinueUserActivity(NSUserActivityTypeBrowsingWeb)` /
  `scene(_:continue:)` / `application(_:continue:restorationHandler:)` —
  extract `userActivity.webpageURL`.
- Push (silent or tap): parse a `deeplink`/`url` key from `userInfo` →
  same parser. Tap handled in `userNotificationCenter(_:didReceive:)`.
- Quick Action: `UIApplicationShortcutItem.type` → `Route`.
- Widget: `Link`/`widgetURL` → custom scheme → same funnel.
- Spotlight / Handoff: `NSUserActivity` with your activity type → `Route`.

All of these reduce to: build/extract a `URL` (or a direct intent enum) and call
`DeepLinkRouter.handle`. See `references/detailed-guide.md` → `Entry Points`.

## Cold Start & Pending Route

The single most common deep-link bug: link works when app is warm, drops or
crashes from cold start because navigation graph / auth isn't ready.

- Router holds `private var pending: Route?`.
- On `handle`: parse → if app not ready **or** route requires auth and user
  logged out **or** onboarding incomplete → store `pending`, return.
- When graph signals ready and gate resolves (login finishes, onboarding
  completes) → replay `pending` once, then clear it.
- Decide per route: **reset vs preserve** existing nav stack on arrival
  (mid-flow deep link). This is a product decision — capture it in
  `feature-requirements`.

## Testing

- Parser: pure unit tests. Table of `URL` → expected `Route?`, including
  malformed, unknown host, missing/oversized params, both scheme and
  `https://` shapes, locale/trailing-slash variants.
- Router: cold-start test — `handle` before "ready" then signal ready →
  asserts the route replays exactly once.
- Auth gate: deep link while logged out → buffered → replays after login.
- Manual: `xcrun simctl openurl booted "myapp://item/42"` and
  `xcrun simctl openurl booted "https://example.com/item/42"`.
- Universal Links: validate AASA with
  `https://app-site-association.cdn-apple.com/a/v1/example.com` and the
  device "Diagnostics" (long-press the link in Notes).

## Common Mistakes

- Parsing URLs inside views or `AppDelegate` instead of one funnel.
- Stringly-typed payload (`[String: Any]`) passed around instead of a `Route`
  enum.
- Router that navigates directly — duplicates the navigation layer.
- No cold-start buffer → link from a killed app silently lands on root.
- Ignoring the auth/onboarding gate → deep link drops the user into a screen
  behind the login wall, or crashes.
- Treating an unknown/old link as fatal instead of falling back to root.
- `try!` / force-unwrapping IDs from an untrusted URL.
- Performing an authenticated/destructive action straight from a link with no
  in-app confirmation.
- Custom scheme only, no Universal Links → links are dead when app not
  installed and are hijackable.
- AASA served with wrong `Content-Type`, behind a redirect, or with `appID`
  not matching `TeamID.BundleID`.
- One giant `if url.path == ...` ladder instead of a tested parser.
- No tests for malformed input — the exact thing attackers and old clients
  send.
