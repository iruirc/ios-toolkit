---
name: arch-viper
description: "Use when implementing VIPER architecture pattern in iOS apps. Covers View, Interactor, Presenter, Entity, Router components, Assembly wiring, and testing."
---

# VIPER Architecture

Maximum separation of concerns. Each layer has a single responsibility with strict protocol boundaries.

> **Related skills:**
> - `di-composition-root` — where Assemblies are bootstrapped
> - `di-module-assembly` — Factory pattern for module wiring (VIPER's Assembly maps onto it)
> - `arch-mvvm`, `arch-clean` — alternative patterns; choose VIPER only when strict layering pays off
> - `reactive-combine`, `reactive-rxswift` — alternative async approaches inside Interactor (this skill defaults to async/await; Combine and callback variants are documented at the end of the Interactor section)

## Structure

```
Feature/
├── FeatureProtocols.swift       # All interfaces
├── FeatureView.swift            # UI (passive)
├── FeaturePresenter.swift       # Presentation logic
├── FeatureInteractor.swift      # Business logic
├── FeatureRouter.swift          # Navigation
├── FeatureEntity.swift          # Data models
└── FeatureAssembly.swift        # DI wiring
```

## Choosing an Async Approach

Classic VIPER literature shows callback-based Interactors with an `InteractorOutput` protocol (`didFetchItems` / `didFailFetchingItems`). Modern projects collapse that to `async/await` or Combine — once results can flow through `await` or a `Publisher`, the Output protocol becomes redundant boilerplate.

| Approach | Interactor signature | When |
|---|---|---|
| **async/await** | `func fetchItems() async throws -> [FeatureEntity]` | iOS 15+, no reactive deps. Default for new VIPER modules. |
| **Combine** | `func fetchItems() -> AnyPublisher<[FeatureEntity], Error>` | Existing Combine codebase, need stream operators (debounce, combineLatest) |
| **Callback + Output protocol** | `func fetchItems()` + `didFetchItems` / `didFailFetchingItems` | Legacy projects with strict classical-VIPER convention. No reason to introduce in greenfield code. |

The examples below use **async/await** as the default. Combine and callback variants are documented at the end of the Interactor section. The rest of VIPER (View / Presenter / Router / Entity / Assembly) is the same regardless of which async approach you pick.

## Component Responsibilities

### Protocols (define all contracts first)

```swift
// MARK: - View
protocol FeatureViewProtocol: AnyObject {
    var presenter: FeaturePresenterProtocol! { get set }

    func showItems(_ items: [FeatureItemViewModel])
    func showLoading()
    func hideLoading()
    func showError(_ message: String)
}

// MARK: - Presenter
protocol FeaturePresenterProtocol: AnyObject {
    var view: FeatureViewProtocol? { get set }
    var interactor: FeatureInteractorProtocol! { get set }
    var router: FeatureRouterProtocol! { get set }

    func viewDidLoad()
    func didSelectItem(at index: Int)
}

// MARK: - Interactor (async/await default — see "Choosing an Async Approach")
protocol FeatureInteractorProtocol {
    func fetchItems() async throws -> [FeatureEntity]
}

// MARK: - Router
protocol FeatureRouterProtocol: AnyObject {
    func navigateToDetail(for item: FeatureEntity)
    func dismiss()
}
```

### View (UIViewController — passive)

Only renders what Presenter tells it to. No business logic, no data transformation.

```swift
class FeatureViewController: UIViewController, FeatureViewProtocol {
    var presenter: FeaturePresenterProtocol!

    private let tableView = UITableView()
    private let loadingIndicator = UIActivityIndicatorView()
    private var items: [FeatureItemViewModel] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        presenter.viewDidLoad()
    }

    // MARK: - FeatureViewProtocol

    func showItems(_ items: [FeatureItemViewModel]) {
        self.items = items
        tableView.reloadData()
    }

    func showLoading() {
        loadingIndicator.startAnimating()
    }

    func hideLoading() {
        loadingIndicator.stopAnimating()
    }

    func showError(_ message: String) {
        let alert = UIAlertController(title: "Error", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

// MARK: - UITableViewDelegate
extension FeatureViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        presenter.didSelectItem(at: indexPath.row)
    }
}
```

### Presenter (mediator)

Receives user events from View, requests data from Interactor, formats results for View, delegates navigation to Router.

```swift
@MainActor
final class FeaturePresenter: FeaturePresenterProtocol {
    weak var view: FeatureViewProtocol?
    var interactor: FeatureInteractorProtocol!
    var router: FeatureRouterProtocol!

    private var items: [FeatureEntity] = []
    private(set) var fetchTask: Task<Void, Never>?

    func viewDidLoad() {
        view?.showLoading()
        fetchTask = Task { [weak self] in
            guard let self else { return }
            do {
                let items = try await interactor.fetchItems()
                self.items = items
                view?.hideLoading()
                view?.showItems(items.map(FeatureItemViewModel.init(entity:)))
            } catch is CancellationError {
                // Cancelled — no UI update
            } catch {
                view?.hideLoading()
                view?.showError(error.localizedDescription)
            }
        }
    }

    func didSelectItem(at index: Int) {
        guard index < items.count else { return }
        router.navigateToDetail(for: items[index])
    }

    deinit { fetchTask?.cancel() }
}
```

`@MainActor` keeps view updates on the main thread without `DispatchQueue.main.async`. The `Task` is stored so it can be cancelled in `deinit` (or on view disappearance) — long-running fetches must not outlive the screen. The Output-protocol extension that classic VIPER puts on the Presenter is gone — `await` returns the result directly.

### Interactor (business logic)

Pure business logic. Calls services/repositories, returns results to the Presenter.

```swift
final class FeatureInteractor: FeatureInteractorProtocol {
    private let service: FeatureServiceProtocol

    init(service: FeatureServiceProtocol) {
        self.service = service
    }

    func fetchItems() async throws -> [FeatureEntity] {
        try await service.fetchItems()
    }
}
```

The Interactor has no back-reference to the Presenter — results flow back through `await`. Threading is owned by the caller (`@MainActor` Presenter); the Interactor itself is unisolated unless it touches mutable state that needs protection (use an `actor` then).

#### Combine variant

```swift
protocol FeatureInteractorProtocol {
    func fetchItems() -> AnyPublisher<[FeatureEntity], Error>
}

final class FeatureInteractor: FeatureInteractorProtocol {
    private let service: FeatureServiceProtocol
    init(service: FeatureServiceProtocol) { self.service = service }

    func fetchItems() -> AnyPublisher<[FeatureEntity], Error> {
        service.fetchItems()
    }
}
```

The Presenter holds an `AnyCancellable` instead of a `Task`, subscribes via `sink`, and routes `.failure` to `view?.showError(...)`. See `reactive-combine` skill for binding patterns.

#### Callback + Output protocol (legacy)

The classical VIPER form keeps separate Input and Output protocols. **Use only when continuing an existing classical-VIPER codebase** — for greenfield modules pick async/await.

```swift
protocol FeatureInteractorInputProtocol: AnyObject {
    var presenter: FeatureInteractorOutputProtocol? { get set }
    func fetchItems()
}

protocol FeatureInteractorOutputProtocol: AnyObject {
    func didFetchItems(_ items: [FeatureEntity])
    func didFailFetchingItems(_ error: Error)
}

final class FeatureInteractor: FeatureInteractorInputProtocol {
    weak var presenter: FeatureInteractorOutputProtocol?
    private let service: FeatureServiceProtocol

    init(service: FeatureServiceProtocol) { self.service = service }

    func fetchItems() {
        service.fetchItems { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let items): self?.presenter?.didFetchItems(items)
                case .failure(let error): self?.presenter?.didFailFetchingItems(error)
                }
            }
        }
    }
}
```

In this variant the Presenter conforms to `FeatureInteractorOutputProtocol` and Assembly wires `interactor.presenter = presenter` (which is the only reason that line exists in classical-VIPER tutorials).

### Entity (data model)

Plain data structures. No logic, no dependencies.

```swift
struct FeatureEntity {
    let id: String
    let title: String
    let description: String
    let createdAt: Date
}

// View-layer representation
struct FeatureItemViewModel {
    let title: String
    let subtitle: String

    init(entity: FeatureEntity) {
        self.title = entity.title
        self.subtitle = DateFormatter.shortDate.string(from: entity.createdAt)
    }
}
```

### Router (navigation)

Handles all navigation. Creates and wires the next VIPER module.

```swift
class FeatureRouter: FeatureRouterProtocol {
    weak var viewController: UIViewController?
    private let container: Resolver

    init(container: Resolver) {
        self.container = container
    }

    func navigateToDetail(for item: FeatureEntity) {
        let detailVC = DetailAssembly.build(container: container, item: item)
        viewController?.navigationController?.pushViewController(detailVC, animated: true)
    }

    func dismiss() {
        viewController?.navigationController?.popViewController(animated: true)
    }
}
```

### Assembly (wiring)

Creates and connects all components:

```swift
enum FeatureAssembly {
    @MainActor
    static func build(container: Resolver) -> UIViewController {
        let view = FeatureViewController()
        let presenter = FeaturePresenter()
        let interactor = FeatureInteractor(
            service: container.resolve(FeatureServiceProtocol.self)!
        )
        let router = FeatureRouter(container: container)

        // Wire
        view.presenter = presenter
        presenter.view = view
        presenter.interactor = interactor
        presenter.router = router
        router.viewController = view

        return view
    }
}
```

> The async/await variant has no `interactor.presenter = presenter` line — there is no Output protocol to wire. Add that line back **only** when using the legacy callback Interactor.

## Data Flow

```
User taps → View → Presenter ─── await interactor.fetchItems() ──→ Service
                       │                                              │
                       └──────── result returned via await ───────────┘
                                     ↓
               View ← Presenter (formats data, updates UI on @MainActor)
```

In the legacy callback variant the inner edge is `Interactor → didFetchItems(...)` on the `InteractorOutput` protocol the Presenter conforms to. Async/await replaces that round-trip with a single `try await`.

Navigation:
```
User taps → View → Presenter → Router → Creates next module
```

## Testing

Each component is independently testable:

```swift
// Presenter test (async/await)
@MainActor
final class FeaturePresenterTests: XCTestCase {
    var sut: FeaturePresenter!
    var mockView: MockFeatureView!
    var mockInteractor: MockFeatureInteractor!
    var mockRouter: MockFeatureRouter!

    override func setUp() {
        super.setUp()
        sut = FeaturePresenter()
        mockView = MockFeatureView()
        mockInteractor = MockFeatureInteractor()
        mockRouter = MockFeatureRouter()

        sut.view = mockView
        sut.interactor = mockInteractor
        sut.router = mockRouter
    }

    func testViewDidLoad_fetchesAndShowsItems() async {
        mockInteractor.stubbedItems = [
            FeatureEntity(id: "1", title: "Test", description: "", createdAt: Date())
        ]

        sut.viewDidLoad()
        await sut.fetchTask?.value  // wait for the async fetch

        XCTAssertTrue(mockView.showLoadingCalled)
        XCTAssertTrue(mockView.hideLoadingCalled)
        XCTAssertEqual(mockView.shownItems?.count, 1)
    }

    func testViewDidLoad_failure_showsError() async {
        mockInteractor.stubbedError = NetworkError.timeout

        sut.viewDidLoad()
        await sut.fetchTask?.value

        XCTAssertTrue(mockView.hideLoadingCalled)
        XCTAssertNotNil(mockView.shownErrorMessage)
    }

    func testDidSelectItem_navigatesToDetail() async {
        mockInteractor.stubbedItems = [
            FeatureEntity(id: "1", title: "Test", description: "", createdAt: Date())
        ]
        sut.viewDidLoad()
        await sut.fetchTask?.value

        sut.didSelectItem(at: 0)

        XCTAssertEqual(mockRouter.navigatedItem?.id, "1")
    }
}

// Mock returns async throws to match the modern Interactor protocol
final class MockFeatureInteractor: FeatureInteractorProtocol {
    var stubbedItems: [FeatureEntity] = []
    var stubbedError: Error?

    func fetchItems() async throws -> [FeatureEntity] {
        if let stubbedError { throw stubbedError }
        return stubbedItems
    }
}

// Interactor test (async/await)
final class FeatureInteractorTests: XCTestCase {
    func testFetchItems_returnsServiceItems() async throws {
        let mockService = MockFeatureService()
        mockService.stubbedItems = [
            FeatureEntity(id: "1", title: "Test", description: "", createdAt: Date())
        ]
        let sut = FeatureInteractor(service: mockService)

        let items = try await sut.fetchItems()

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.id, "1")
    }

    func testFetchItems_propagatesServiceError() async {
        let mockService = MockFeatureService()
        mockService.stubbedError = NetworkError.timeout
        let sut = FeatureInteractor(service: mockService)

        do {
            _ = try await sut.fetchItems()
            XCTFail("Expected error")
        } catch {
            XCTAssertTrue(error is NetworkError)
        }
    }
}
```

For the legacy callback Interactor, tests use `MockInteractorOutput` injected via `sut.presenter = mockOutput`, then assert on `mockOutput.receivedItems` after calling `sut.fetchItems()`. With async/await the round-trip collapses into the single `try await sut.fetchItems()` shown above.

## When Appropriate

- Large enterprise apps with multiple teams
- Strict separation requirements
- Very high test coverage requirements
- Features with complex business logic independent of UI

## Common Mistakes

1. **Business logic in Presenter** — Presenter only formats and delegates. Logic goes in Interactor.
2. **View calling Interactor directly** — Always go through Presenter.
3. **Fat Assembly** — Keep Assembly as pure wiring, no logic.
4. **Retain cycles** — `View ↔ Presenter` (and `Interactor ↔ Presenter` in the legacy callback variant) connections must use `weak`. The async/await variant has no Interactor → Presenter back-reference, so this risk shrinks to one edge.
5. **Too much boilerplate for simple screens** — Use simpler pattern (MVC/MVVM) for basic screens.
6. **Output protocol on top of async/await** — When the Interactor is `async throws -> ...`, do **not** also introduce a parallel `InteractorOutput` protocol. Results flow through `await`; an Output protocol on top is dead boilerplate that fragments the call site. Output belongs only to the legacy callback variant.
7. **Long-running Interactor work without cancellation** — Store the Presenter's fetch `Task` and cancel it in `deinit` (or on `viewWillDisappear`) so background work doesn't outlive the screen and overwrite a fresh module's state.
8. **`DispatchQueue.main.async` inside `@MainActor` Presenter** — Once the Presenter is `@MainActor`, view updates after `await` are already on the main thread. Manual hopping is redundant and confuses concurrency expectations.
9. **Mixing async styles inside one module** — Don't expose `async throws` and a Combine `Publisher` from the same Interactor protocol. Pick one (per the table at the top) and keep the module consistent; cross-style adapters belong at module boundaries, not inside.
