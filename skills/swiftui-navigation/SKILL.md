---
name: swiftui-navigation
description: "Use when implementing navigation in a SwiftUI-first iOS app. Covers NavigationStack + NavigationPath, type-based vs enum-based routing, modal presentation (sheet/cover/popover/alert), TabView, Router class pattern as a SwiftUI alternative to Coordinator, @Environment-based navigation, deep links, and hybrid SwiftUI ↔ UIKit interop."
---

# SwiftUI Navigation

State-driven navigation for SwiftUI apps. Replaces the imperative push/present/pop model with a declarative `NavigationPath`-as-state model. iOS 16+ for `NavigationStack`; iOS 17+ for `@Observable` Router.

> **Related skills:**
> - `coordinator` — UIKit navigation pattern; comparable role (flow control, decoupling navigation from views), but different mechanics
> - `mvvm` — ViewModel emits navigation intent; the Router/Path here is what the View binds to in response
> - `composition-root` — where Routers and root NavigationStacks are wired
> - `module-assembly` — Factory pattern for assembling SwiftUI screens with their dependencies

## Navigation Primitives

| Primitive | When |
|---|---|
| `NavigationStack` | Hierarchical push navigation (replaces deprecated `NavigationView`) |
| `NavigationPath` | Type-erased stack state; programmatic deep links and mutation |
| `.navigationDestination(for:)` | Maps a value type to a destination view |
| `NavigationLink(value:)` | Push by appending value to path |
| `.sheet(isPresented:)` / `.sheet(item:)` | Modal half/full sheet |
| `.fullScreenCover(...)` | Modal that fully covers the screen |
| `.popover(...)` | Anchored popover (iPad-friendly) |
| `.alert(...)` / `.confirmationDialog(...)` | System dialogs |
| `TabView` | Top-level tab navigation; each tab usually owns a `NavigationStack` |

**Rule of thumb:** for new code use `NavigationStack`. `NavigationView` and `NavigationLink(destination:)` (eager destination) are deprecated patterns — see Common Mistakes.

## NavigationStack + navigationDestination

The modern way: declare destinations once at the stack root, push by value.

```swift
struct ItemListView: View {
    let items: [Item]

    var body: some View {
        NavigationStack {
            List(items) { item in
                NavigationLink(value: item) {
                    Text(item.title)
                }
            }
            .navigationDestination(for: Item.self) { item in
                ItemDetailView(item: item)
            }
        }
    }
}
```

`Item` must conform to `Hashable`. The destination view is **lazy** — created only when the user actually navigates.

## NavigationPath — programmatic state

For programmatic navigation, deep links, and reset operations — bind a `NavigationPath` (or typed array) to the stack.

### Typed array (compile-time safe, single destination type)

```swift
struct OnboardingFlow: View {
    @State private var path: [OnboardingStep] = []

    var body: some View {
        NavigationStack(path: $path) {
            WelcomeView(onContinue: { path.append(.profile) })
                .navigationDestination(for: OnboardingStep.self) { step in
                    switch step {
                    case .profile:  ProfileSetupView(onContinue: { path.append(.notifications) })
                    case .notifications: NotificationsSetupView(onFinish: { path = [] })
                    }
                }
        }
    }
}

enum OnboardingStep: Hashable { case profile, notifications }
```

Use typed array when **all** destinations share one enum/type.

### NavigationPath — type-erased

When destinations span multiple types (e.g. `Item` and `Profile`), use `NavigationPath`.

```swift
struct AppRootView: View {
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            HomeView()
                .navigationDestination(for: Item.self) { ItemDetailView(item: $0) }
                .navigationDestination(for: Profile.self) { ProfileView(profile: $0) }
        }
    }
}
```

Operations:

```swift
path.append(item)            // push
path.append(profile)         // push different type — works
path.removeLast()            // pop
path.removeLast(path.count)  // pop to root
```

`NavigationPath` is `Codable` if all values it holds are `Codable` — useful for state restoration.

## Routing: enum-based vs type-based

Two strategies for declaring destinations:

### Enum-based (one `navigationDestination`)

```swift
enum Route: Hashable {
    case itemDetail(Item)
    case profile(userId: UUID)
    case settings
}

NavigationStack(path: $path) {
    HomeView()
        .navigationDestination(for: Route.self) { route in
            switch route {
            case .itemDetail(let item): ItemDetailView(item: item)
            case .profile(let id): ProfileView(userId: id)
            case .settings: SettingsView()
            }
        }
}
```

**Pros:** single switch, all routes visible in one place; easier to handle deep links.
**Cons:** route enum grows large in big apps; one giant switch.

### Type-based (one `navigationDestination` per type)

```swift
NavigationStack {
    HomeView()
        .navigationDestination(for: Item.self) { ItemDetailView(item: $0) }
        .navigationDestination(for: Profile.self) { ProfileView(profile: $0) }
        .navigationDestination(for: SettingsRoute.self) { SettingsView(route: $0) }
}
```

**Pros:** scales naturally; each module owns its own destination; less coupling.
**Cons:** need to remember to register all types; harder to enumerate all routes.

**Recommendation:** type-based by default; enum-based when one screen needs to deep-link to many distinct destinations.

## Modal Presentation

### `.sheet(isPresented:)` — boolean trigger

```swift
struct HomeView: View {
    @State private var showSettings = false

    var body: some View {
        Button("Settings") { showSettings = true }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
    }
}
```

### `.sheet(item:)` — Identifiable-trigger (preferred for data-driven sheets)

```swift
struct ItemListView: View {
    @State private var editingItem: Item?

    var body: some View {
        List(items) { item in
            Button(item.title) { editingItem = item }
        }
        .sheet(item: $editingItem) { item in
            EditItemView(item: item)
        }
    }
}
```

`item: Item?` ensures the sheet always has the correct value — no race between setting bool and ID.

### Detents (iOS 16+)

```swift
.sheet(isPresented: $showFilter) {
    FilterView()
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
}
```

### `.fullScreenCover` vs `.sheet`

- Sheet — half-modal on iPhone, popover on iPad. Dismissable by drag.
- FullScreenCover — fully covers; dismiss only via explicit action. Use for onboarding, login walls, immersive flows.

### Programmatic dismiss

```swift
struct ChildView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Button("Close") { dismiss() }
    }
}
```

Works for sheet, fullScreenCover, and pushed views in a NavigationStack (pops one level).

## TabView + per-tab NavigationStack

Each tab owns its own `NavigationStack` so that switching tabs preserves push state per tab.

```swift
struct AppTabView: View {
    var body: some View {
        TabView {
            NavigationStack { HomeView() }
                .tabItem { Label("Home", systemImage: "house") }

            NavigationStack { SearchView() }
                .tabItem { Label("Search", systemImage: "magnifyingglass") }

            NavigationStack { ProfileView() }
                .tabItem { Label("Profile", systemImage: "person") }
        }
    }
}
```

For programmatic tab selection:

```swift
@State private var selection: Tab = .home

TabView(selection: $selection) { ... }
```

To reset a tab to root when re-tapped — use `.onChange(of: selection)` and clear that tab's path.

## Router Class Pattern (SwiftUI alternative to Coordinator)

When navigation logic outgrows view-local `@State`, extract it into an `@Observable` Router. This is the SwiftUI equivalent of Coordinator — but reactive, not imperative.

```swift
@Observable
final class AppRouter {
    var path = NavigationPath()
    var presentedSheet: SheetRoute?
    var presentedFullScreen: FullScreenRoute?

    func push<V: Hashable>(_ value: V) { path.append(value) }
    func pop() { path.removeLast() }
    func popToRoot() { path.removeLast(path.count) }
    func present(sheet: SheetRoute) { presentedSheet = sheet }
    func dismissSheet() { presentedSheet = nil }
}

enum SheetRoute: Identifiable {
    case settings, profileEdit(userId: UUID)
    var id: String {
        switch self {
        case .settings: "settings"
        case .profileEdit(let id): "profileEdit-\(id)"
        }
    }
}
```

Wire it once at the root and inject via `@Environment`:

```swift
@main
struct MyApp: App {
    @State private var router = AppRouter()

    var body: some Scene {
        WindowGroup {
            NavigationStack(path: $router.path) {
                HomeView()
                    .navigationDestination(for: Item.self) { ItemDetailView(item: $0) }
                    .navigationDestination(for: Profile.self) { ProfileView(profile: $0) }
            }
            .sheet(item: $router.presentedSheet) { route in
                switch route {
                case .settings: SettingsView()
                case .profileEdit(let id): EditProfileView(userId: id)
                }
            }
            .environment(router)
        }
    }
}
```

Children read it from environment and call methods:

```swift
struct ItemRowView: View {
    let item: Item
    @Environment(AppRouter.self) private var router

    var body: some View {
        Button(item.title) { router.push(item) }
    }
}
```

**One Router vs many:** one global Router for small/medium apps. Split by flow (`OnboardingRouter`, `CheckoutRouter`) when flows are long-lived and isolated — same rule as for Coordinators.

### Router vs Coordinator — quick comparison

| Aspect | Coordinator (UIKit) | Router (SwiftUI) |
|---|---|---|
| Style | Imperative (`push`, `present`) | Declarative (mutate `path` / `presented…`) |
| Owns | `UINavigationController` | `NavigationPath` + presentation state |
| ViewModel triggers nav via | Closure / delegate | Calls `router.push(...)` (also closure-friendly) |
| Tested by | Asserting calls on mock Router | Asserting state of router after action |
| Memory model | Tree of child Coordinators | Often flat; per-flow routers when needed |

## @Environment as lightweight alternative

For very small apps (1-3 flows), skip the Router class entirely. Inject **navigation actions** as environment values, and let children call them.

```swift
struct OpenItemAction: EnvironmentKey {
    static let defaultValue: (Item) -> Void = { _ in }
}

extension EnvironmentValues {
    var openItem: (Item) -> Void {
        get { self[OpenItemAction.self] }
        set { self[OpenItemAction.self] = newValue }
    }
}

// At root
@State private var path = NavigationPath()

NavigationStack(path: $path) {
    HomeView()
        .navigationDestination(for: Item.self) { ItemDetailView(item: $0) }
        .environment(\.openItem) { item in path.append(item) }
}

// Child
struct ItemRowView: View {
    let item: Item
    @Environment(\.openItem) private var openItem
    var body: some View { Button(item.title) { openItem(item) } }
}
```

Use this when state is genuinely local to one flow. Beyond ~5 actions, switch to a Router class.

## Deep Links

URL → Route enum → mutate `NavigationPath`. The Router (or App) owns the parsing.

```swift
extension AppRouter {
    func handle(_ url: URL) {
        guard let route = DeepLinkParser.parse(url) else { return }
        path.removeLast(path.count)  // reset
        switch route {
        case .item(let id):
            path.append(Item(id: id))
        case .profile(let userId):
            path.append(Profile(id: userId))
        case .settings:
            presentedSheet = .settings
        }
    }
}

// Wire to scene
.onOpenURL { url in router.handle(url) }
```

For cross-tab deep links (`myapp://profile` should switch to Profile tab + push), the Router holds tab selection too:

```swift
@Observable
final class AppRouter {
    var selectedTab: Tab = .home
    var homePath = NavigationPath()
    var profilePath = NavigationPath()

    func handle(_ url: URL) {
        switch DeepLinkParser.parse(url) {
        case .profile(let id):
            selectedTab = .profile
            profilePath.append(Profile(id: id))
        // ...
        }
    }
}
```

## Hybrid: SwiftUI ↔ UIKit Interop

Real apps mix paradigms — legacy modules in UIKit, new screens in SwiftUI, or vice versa.

### Embed SwiftUI in UIKit — `UIHostingController`

```swift
let hostingController = UIHostingController(rootView: ProfileView())
navigationController?.pushViewController(hostingController, animated: true)
```

Inject dependencies via init or environment:

```swift
let view = ProfileView().environment(router)
let hosting = UIHostingController(rootView: view)
```

Coordinator-based UIKit apps can use `UIHostingController` to add SwiftUI screens without rewriting navigation.

### Embed UIKit in SwiftUI — `UIViewControllerRepresentable`

```swift
struct LegacyMapView: UIViewControllerRepresentable {
    let region: MKCoordinateRegion

    func makeUIViewController(context: Context) -> MKMapViewController {
        MKMapViewController(region: region)
    }

    func updateUIViewController(_ vc: MKMapViewController, context: Context) {
        vc.update(region: region)
    }
}
```

Communicate UIKit → SwiftUI via `Coordinator` (the `Representable.Coordinator`, not the navigation pattern) and `@Binding` / closures.

### When hybrid makes sense

- **Migration:** rewriting incrementally, screen-by-screen
- **SwiftUI gaps:** features SwiftUI doesn't support natively yet (advanced text input, AVPlayerViewController integration, MapKit fine control)
- **Performance:** very large lists where `UICollectionView` still outperforms SwiftUI `List`

Don't mix paradigms inside a single screen unless necessary — debugging dual-state ownership is painful.

## Testing

### Test Router state, not SwiftUI internals

```swift
@MainActor
final class AppRouterTests: XCTestCase {
    func test_push_appendsToPath() {
        let router = AppRouter()
        router.push(Item(id: "42"))
        XCTAssertEqual(router.path.count, 1)
    }

    func test_handleDeepLink_resetsPathAndAppendsTarget() {
        let router = AppRouter()
        router.path.append(Item(id: "old"))
        router.handle(URL(string: "myapp://item/42")!)
        XCTAssertEqual(router.path.count, 1)
    }

    func test_presentSheet_setsPresentedSheet() {
        let router = AppRouter()
        router.present(sheet: .settings)
        XCTAssertEqual(router.presentedSheet, .settings)
    }
}
```

What to **not** test: `View` body, what NavigationStack actually renders, `@State` updates inside views. These are SwiftUI internals — covered by Apple's tests, not yours. For visual confirmation use snapshot tests.

## Common Mistakes

1. **Using `NavigationView` for new code** — deprecated since iOS 16. Always `NavigationStack`.
2. **`NavigationLink(destination: HeavyView())`** — eagerly creates `HeavyView` for every list row, even invisible ones. Use `NavigationLink(value:)` + `.navigationDestination(for:)` for lazy creation.
3. **Mutating `path` from a background thread** — must be on `@MainActor`. Use `await MainActor.run { ... }` if coming from async work.
4. **Stacking sheets on the same view** — only one `.sheet` per view at a time. To present a sheet from inside a sheet, attach the second `.sheet` to the inner view, not the outer.
5. **Sharing navigation `@State` across screens via globals** — use a Router (`@Observable` + `@Environment`), not `static var`.
6. **Mixing programmatic `path` with `NavigationLink(destination:)`** — second form bypasses `path`, leading to inconsistent state. Pick one mechanism per stack.
7. **Forgetting `Identifiable` for `.sheet(item:)`** — the API requires `Identifiable`; using `Optional<Hashable>` only works with `.sheet(isPresented:)` (which is racier).
8. **Per-tab `NavigationStack` shared between tabs** — each tab MUST own its own `NavigationStack`; one stack at the root with multiple tabs flattens push state across tabs.
9. **Overusing `@Environment(\.dismiss)` for deep dismissal** — it pops one level. To pop to root, mutate the Router's path instead.
10. **Forgetting `.navigationDestination` for a type pushed via `path.append(...)`** — runtime warning ("A NavigationLink is presenting a value of type X but there is no matching navigationDestination"). Each pushed type needs a destination registered above it in the view hierarchy.
