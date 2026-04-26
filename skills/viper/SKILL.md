---
name: viper
description: "Use when implementing VIPER architecture pattern in iOS apps. Covers View, Interactor, Presenter, Entity, Router components, Assembly wiring, and testing."
---

# VIPER Architecture

Maximum separation of concerns. Each layer has a single responsibility with strict protocol boundaries.

> **Related skills:**
> - `composition-root` — where Assemblies are bootstrapped
> - `module-assembly` — Factory pattern for module wiring (VIPER's Assembly maps onto it)
> - `mvvm`, `clean-architecture` — alternative patterns; choose VIPER only when strict layering pays off
> - `combine`, `rxswift` — async approach inside Interactor (legacy callback style is shown here, but modern projects use these)

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
    var interactor: FeatureInteractorInputProtocol! { get set }
    var router: FeatureRouterProtocol! { get set }

    func viewDidLoad()
    func didSelectItem(at index: Int)
}

// MARK: - Interactor
protocol FeatureInteractorInputProtocol: AnyObject {
    var presenter: FeatureInteractorOutputProtocol? { get set }

    func fetchItems()
}

protocol FeatureInteractorOutputProtocol: AnyObject {
    func didFetchItems(_ items: [FeatureEntity])
    func didFailFetchingItems(_ error: Error)
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
class FeaturePresenter: FeaturePresenterProtocol {
    weak var view: FeatureViewProtocol?
    var interactor: FeatureInteractorInputProtocol!
    var router: FeatureRouterProtocol!

    private var items: [FeatureEntity] = []

    func viewDidLoad() {
        view?.showLoading()
        interactor.fetchItems()
    }

    func didSelectItem(at index: Int) {
        guard index < items.count else { return }
        router.navigateToDetail(for: items[index])
    }
}

// MARK: - Interactor Output
extension FeaturePresenter: FeatureInteractorOutputProtocol {
    func didFetchItems(_ items: [FeatureEntity]) {
        self.items = items
        let viewModels = items.map { FeatureItemViewModel(entity: $0) }
        view?.hideLoading()
        view?.showItems(viewModels)
    }

    func didFailFetchingItems(_ error: Error) {
        view?.hideLoading()
        view?.showError(error.localizedDescription)
    }
}
```

### Interactor (business logic)

Pure business logic. Calls services/repositories, returns results to Presenter via output protocol.

```swift
class FeatureInteractor: FeatureInteractorInputProtocol {
    weak var presenter: FeatureInteractorOutputProtocol?

    private let service: FeatureServiceProtocol

    init(service: FeatureServiceProtocol) {
        self.service = service
    }

    func fetchItems() {
        service.fetchItems { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let items):
                    self?.presenter?.didFetchItems(items)
                case .failure(let error):
                    self?.presenter?.didFailFetchingItems(error)
                }
            }
        }
    }
}
```

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
class FeatureAssembly {
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
        interactor.presenter = presenter
        router.viewController = view

        return view
    }
}
```

## Data Flow

```
User taps → View → Presenter → Interactor → Service
                                     ↓
                              Interactor Output
                                     ↓
               View ← Presenter (formats data)
```

Navigation:
```
User taps → View → Presenter → Router → Creates next module
```

## Testing

Each component is independently testable:

```swift
// Presenter test
class FeaturePresenterTests: XCTestCase {
    var sut: FeaturePresenter!
    var mockView: MockFeatureView!
    var mockInteractor: MockFeatureInteractor!
    var mockRouter: MockFeatureRouter!

    override func setUp() {
        sut = FeaturePresenter()
        mockView = MockFeatureView()
        mockInteractor = MockFeatureInteractor()
        mockRouter = MockFeatureRouter()

        sut.view = mockView
        sut.interactor = mockInteractor
        sut.router = mockRouter
    }

    func testViewDidLoad_showsLoadingAndFetches() {
        sut.viewDidLoad()

        XCTAssertTrue(mockView.showLoadingCalled)
        XCTAssertTrue(mockInteractor.fetchItemsCalled)
    }

    func testDidFetchItems_updatesView() {
        let items = [FeatureEntity(id: "1", title: "Test", description: "", createdAt: Date())]

        sut.didFetchItems(items)

        XCTAssertTrue(mockView.hideLoadingCalled)
        XCTAssertEqual(mockView.shownItems?.count, 1)
    }

    func testDidSelectItem_navigatesToDetail() {
        let item = FeatureEntity(id: "1", title: "Test", description: "", createdAt: Date())
        sut.didFetchItems([item])

        sut.didSelectItem(at: 0)

        XCTAssertEqual(mockRouter.navigatedItem?.id, "1")
    }
}

// Interactor test
class FeatureInteractorTests: XCTestCase {
    func testFetchItems_callsPresenterOnSuccess() {
        let mockService = MockFeatureService()
        mockService.stubbedResult = .success([FeatureEntity(id: "1", ...)])
        let sut = FeatureInteractor(service: mockService)
        let mockPresenter = MockInteractorOutput()
        sut.presenter = mockPresenter

        sut.fetchItems()

        XCTAssertEqual(mockPresenter.receivedItems?.count, 1)
    }
}
```

## When Appropriate

- Large enterprise apps with multiple teams
- Strict separation requirements
- Very high test coverage requirements
- Features with complex business logic independent of UI

## Common Mistakes

1. **Business logic in Presenter** — Presenter only formats and delegates. Logic goes in Interactor.
2. **View calling Interactor directly** — Always go through Presenter.
3. **Fat Assembly** — Keep Assembly as pure wiring, no logic.
4. **Retain cycles** — View↔Presenter and Interactor↔Presenter connections must use `weak`.
5. **Too much boilerplate for simple screens** — Use simpler pattern (MVC/MVVM) for basic screens.
