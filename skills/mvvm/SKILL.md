---
name: mvvm
description: "Use when implementing MVVM (Model-View-ViewModel) architecture pattern in iOS apps. Covers ViewModel design, UI binding with multiple approaches (Closures, Combine, async/await, @Observable, RxSwift), Input/Output pattern, and testing."
---

# MVVM (Model-View-ViewModel) Architecture

Separates business logic into a testable ViewModel, keeping ViewController as a thin UI binding layer.

## Structure

```
Feature/
├── FeatureViewController.swift  # UI binding only
├── FeatureViewModel.swift       # Business logic + state
└── Models/
    └── FeatureModel.swift
```

## Component Responsibilities

### Model
- Data structures and business entities
- Persistence and network DTOs
- Pure data — no UIKit, no reactive types

### ViewModel

**Purpose**: Holds business logic, processes user actions, exposes state for View binding.

**Rules**:
- No UIKit imports (except value types like `CGFloat` if unavoidable)
- No reference to ViewController
- All dependencies injected via init
- Define a protocol for testability

### ViewController

**Purpose**: Thin UI layer. Binds ViewModel outputs to UI, forwards user actions to ViewModel inputs.

## Choosing a Binding Approach

Pick ONE approach per project. Do not mix binding styles.

**IMPORTANT**: If the user did NOT explicitly specify which binding approach to use, you MUST ask before writing any code. Do not choose silently.

Use the decision guide below to suggest an approach. Always explain WHY you suggest it based on the project context.

### How to Ask

Analyze the project (check existing imports, Podfile/Package.swift, min iOS target, SwiftUI vs UIKit usage) and propose a recommendation:

> I see the project targets iOS 15+, uses UIKit, and has no reactive dependencies.
> I'd recommend **async/await + @Published** because:
> - No extra dependencies needed
> - Clean linear async code fits the project style
> - iOS 15+ requirement is already met
>
> Other options: **Closures** (simpler but less scalable), **Combine** (if you need stream operators like debounce/combineLatest).
>
> Which approach would you like?

If the project already uses RxSwift or Combine, mention that as the primary factor.

### Decision Guide

Use this to form your recommendation:

```
Is the project SwiftUI-first and targets iOS 17+?
  → Suggest @Observable (native, minimal boilerplate, fine-grained updates)

Does the project already use RxSwift?
  → Suggest RxSwift (consistency with existing code; see rxswift skill)

Does the project already use Combine?
  → Suggest Combine (consistency with existing code; see combine skill)

Does the project need complex stream composition
(merge, combineLatest, debounce, throttle)?
  → Suggest Combine (powerful operators, no third-party dependency)

Is the project targeting iOS 15+?
  → Suggest async/await + @Published (modern, no dependencies, readable)

Otherwise:
  → Suggest Closures (zero dependencies, works on any iOS version)
```

### Comparison Table

| Approach | Min iOS | Dependencies | Best For |
|----------|---------|-------------|----------|
| **Closures** | Any | None | Simple apps, small teams, beginners |
| **Combine** | 13+ | None (Apple) | UIKit apps, stream composition needed |
| **async/await + @Published** | 15+ | None | Modern UIKit apps, linear async flows |
| **@Observable** | 17+ | None | SwiftUI-first or SwiftUI+UIKit apps |
| **RxSwift** | 11+ | RxSwift | Complex reactive chains, existing Rx codebases |

---

## Approach 1: Closures (No Dependencies)

The simplest approach. ViewModel exposes closure properties that the View sets.

### ViewModel

```swift
protocol FeatureViewModelProtocol {
    var onItemsUpdated: (([ItemCellModel]) -> Void)? { get set }
    var onLoadingChanged: ((Bool) -> Void)? { get set }
    var onError: ((String) -> Void)? { get set }
    var onItemSelected: ((Item) -> Void)? { get set }

    func viewDidLoad()
    func didSelectItem(at index: Int)
    func didTapRetry()
}

class FeatureViewModel: FeatureViewModelProtocol {
    private let service: FeatureServiceProtocol
    private var items: [Item] = []

    // Outputs
    var onItemsUpdated: (([ItemCellModel]) -> Void)?
    var onLoadingChanged: ((Bool) -> Void)?
    var onError: ((String) -> Void)?

    // Navigation
    var onItemSelected: ((Item) -> Void)?

    init(service: FeatureServiceProtocol) {
        self.service = service
    }

    func viewDidLoad() {
        loadData()
    }

    func didSelectItem(at index: Int) {
        guard index < items.count else { return }
        onItemSelected?(items[index])
    }

    func didTapRetry() {
        loadData()
    }

    private func loadData() {
        onLoadingChanged?(true)
        service.fetchItems { [weak self] result in
            DispatchQueue.main.async {
                self?.onLoadingChanged?(false)
                switch result {
                case .success(let items):
                    self?.items = items
                    self?.onItemsUpdated?(items.map(ItemCellModel.init))
                case .failure(let error):
                    self?.onError?(error.localizedDescription)
                }
            }
        }
    }
}
```

### ViewController

```swift
class FeatureViewController: UIViewController {
    private var viewModel: FeatureViewModelProtocol
    private let tableView = UITableView()
    private let loadingIndicator = UIActivityIndicatorView()
    private var cellModels: [ItemCellModel] = []

    init(viewModel: FeatureViewModelProtocol) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        bindViewModel()
        viewModel.viewDidLoad()
    }

    private func bindViewModel() {
        viewModel.onItemsUpdated = { [weak self] items in
            self?.cellModels = items
            self?.tableView.reloadData()
        }

        viewModel.onLoadingChanged = { [weak self] isLoading in
            if isLoading {
                self?.loadingIndicator.startAnimating()
            } else {
                self?.loadingIndicator.stopAnimating()
            }
        }

        viewModel.onError = { [weak self] message in
            self?.showErrorAlert(message)
        }
    }
}
```

### Testing (Closures)

```swift
class FeatureViewModelTests: XCTestCase {
    var sut: FeatureViewModel!
    var mockService: MockFeatureService!

    override func setUp() {
        mockService = MockFeatureService()
        sut = FeatureViewModel(service: mockService)
    }

    func testViewDidLoad_fetchesItems() {
        let expectation = expectation(description: "items updated")
        mockService.stubbedResult = .success([Item(id: "1")])

        sut.onItemsUpdated = { items in
            XCTAssertEqual(items.count, 1)
            expectation.fulfill()
        }

        sut.viewDidLoad()
        waitForExpectations(timeout: 1)
    }

    func testViewDidLoad_showsAndHidesLoading() {
        var states: [Bool] = []

        sut.onLoadingChanged = { states.append($0) }
        mockService.stubbedResult = .success([])

        sut.viewDidLoad()

        XCTAssertEqual(states, [true, false])
    }

    func testDidSelectItem_signalsNavigation() {
        var selectedItem: Item?
        sut.onItemSelected = { selectedItem = $0 }
        mockService.stubbedResult = .success([Item(id: "42")])

        sut.viewDidLoad()
        sut.didSelectItem(at: 0)

        XCTAssertEqual(selectedItem?.id, "42")
    }
}
```

---

## Approach 2: Combine + @Published

Uses Apple's Combine framework. See `combine` skill for framework details.

### ViewModel

```swift
import Combine

protocol FeatureViewModelProtocol: AnyObject {
    var itemsPublisher: AnyPublisher<[ItemCellModel], Never> { get }
    var isLoadingPublisher: AnyPublisher<Bool, Never> { get }
    var errorPublisher: AnyPublisher<String, Never> { get }
    var onItemSelected: ((Item) -> Void)? { get set }

    func viewDidLoad()
    func didSelectItem(at index: Int)
    func didTapRetry()
}

class FeatureViewModel: FeatureViewModelProtocol {
    private let service: FeatureServiceProtocol
    private var cancellables = Set<AnyCancellable>()

    @Published private var items: [Item] = []
    @Published private var isLoading = false
    private let errorSubject = PassthroughSubject<String, Never>()

    var itemsPublisher: AnyPublisher<[ItemCellModel], Never> {
        $items.map { $0.map(ItemCellModel.init) }.eraseToAnyPublisher()
    }
    var isLoadingPublisher: AnyPublisher<Bool, Never> {
        $isLoading.eraseToAnyPublisher()
    }
    var errorPublisher: AnyPublisher<String, Never> {
        errorSubject.eraseToAnyPublisher()
    }

    var onItemSelected: ((Item) -> Void)?

    init(service: FeatureServiceProtocol) {
        self.service = service
    }

    func viewDidLoad() {
        loadData()
    }

    func didSelectItem(at index: Int) {
        guard index < items.count else { return }
        onItemSelected?(items[index])
    }

    func didTapRetry() {
        loadData()
    }

    private func loadData() {
        isLoading = true
        service.fetchItems()
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    self?.isLoading = false
                    if case .failure(let error) = completion {
                        self?.errorSubject.send(error.localizedDescription)
                    }
                },
                receiveValue: { [weak self] items in
                    self?.items = items
                }
            )
            .store(in: &cancellables)
    }
}
```

### ViewController

```swift
class FeatureViewController: UIViewController {
    private let viewModel: FeatureViewModelProtocol
    private var cancellables = Set<AnyCancellable>()
    private let tableView = UITableView()
    private let loadingIndicator = UIActivityIndicatorView()
    private var cellModels: [ItemCellModel] = []

    init(viewModel: FeatureViewModelProtocol) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        bindViewModel()
        viewModel.viewDidLoad()
    }

    private func bindViewModel() {
        viewModel.itemsPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] items in
                self?.cellModels = items
                self?.tableView.reloadData()
            }
            .store(in: &cancellables)

        viewModel.isLoadingPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isLoading in
                if isLoading {
                    self?.loadingIndicator.startAnimating()
                } else {
                    self?.loadingIndicator.stopAnimating()
                }
            }
            .store(in: &cancellables)

        viewModel.errorPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] message in
                self?.showErrorAlert(message)
            }
            .store(in: &cancellables)
    }
}
```

### Testing (Combine)

```swift
class FeatureViewModelTests: XCTestCase {
    var sut: FeatureViewModel!
    var mockService: MockFeatureService!
    var cancellables: Set<AnyCancellable>!

    override func setUp() {
        mockService = MockFeatureService()
        sut = FeatureViewModel(service: mockService)
        cancellables = []
    }

    func testViewDidLoad_fetchesItems() {
        let expectation = expectation(description: "items received")
        mockService.stubbedResult = Just([Item(id: "1")])
            .setFailureType(to: Error.self)
            .eraseToAnyPublisher()

        sut.itemsPublisher
            .dropFirst() // skip initial empty
            .sink { items in
                XCTAssertEqual(items.count, 1)
                expectation.fulfill()
            }
            .store(in: &cancellables)

        sut.viewDidLoad()
        waitForExpectations(timeout: 1)
    }

    func testViewDidLoad_showsAndHidesLoading() {
        let expectation = expectation(description: "loading states")
        var states: [Bool] = []
        mockService.stubbedResult = Just([Item]())
            .setFailureType(to: Error.self)
            .eraseToAnyPublisher()

        sut.isLoadingPublisher
            .sink { isLoading in
                states.append(isLoading)
                if states.count == 3 { // initial false, true, false
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        sut.viewDidLoad()
        waitForExpectations(timeout: 1)
        XCTAssertEqual(states, [false, true, false])
    }

    func testDidSelectItem_signalsNavigation() {
        let expectation = expectation(description: "items loaded")
        var selectedItem: Item?
        sut.onItemSelected = { selectedItem = $0 }
        mockService.stubbedResult = Just([Item(id: "42")])
            .setFailureType(to: Error.self)
            .eraseToAnyPublisher()

        sut.itemsPublisher
            .dropFirst()
            .sink { _ in expectation.fulfill() }
            .store(in: &cancellables)

        sut.viewDidLoad()
        waitForExpectations(timeout: 1)

        sut.didSelectItem(at: 0)
        XCTAssertEqual(selectedItem?.id, "42")
    }
}
```

---

## Approach 3: async/await + @MainActor

Modern Swift concurrency. No dependencies, clean linear code.

### ViewModel

```swift
@MainActor
protocol FeatureViewModelProtocol: AnyObject {
    var items: [ItemCellModel] { get }
    var isLoading: Bool { get }
    var onStateChanged: (() -> Void)? { get set }
    var onError: ((String) -> Void)? { get set }
    var onItemSelected: ((Item) -> Void)? { get set }

    func viewDidLoad()
    func didSelectItem(at index: Int)
    func didTapRetry()
}

@MainActor
class FeatureViewModel: FeatureViewModelProtocol {
    private let service: FeatureServiceProtocol
    private var rawItems: [Item] = []
    private var loadTask: Task<Void, Never>?

    private(set) var items: [ItemCellModel] = [] {
        didSet { onStateChanged?() }
    }
    private(set) var isLoading: Bool = false {
        didSet { onStateChanged?() }
    }

    var onStateChanged: (() -> Void)?
    var onError: ((String) -> Void)?
    var onItemSelected: ((Item) -> Void)?

    init(service: FeatureServiceProtocol) {
        self.service = service
    }

    func viewDidLoad() {
        loadData()
    }

    func didSelectItem(at index: Int) {
        guard index < rawItems.count else { return }
        onItemSelected?(rawItems[index])
    }

    func didTapRetry() {
        loadData()
    }

    private func loadData() {
        loadTask?.cancel()
        loadTask = Task {
            isLoading = true
            do {
                let fetched = try await service.fetchItems()
                rawItems = fetched
                items = fetched.map(ItemCellModel.init)
            } catch {
                onError?(error.localizedDescription)
            }
            isLoading = false
        }
    }
}
```

### ViewController

```swift
class FeatureViewController: UIViewController {
    private let viewModel: FeatureViewModelProtocol
    private let tableView = UITableView()
    private let loadingIndicator = UIActivityIndicatorView()

    init(viewModel: FeatureViewModelProtocol) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        bindViewModel()
        viewModel.viewDidLoad()
    }

    private func bindViewModel() {
        viewModel.onStateChanged = { [weak self] in
            guard let self else { return }
            self.tableView.reloadData()
            if self.viewModel.isLoading {
                self.loadingIndicator.startAnimating()
            } else {
                self.loadingIndicator.stopAnimating()
            }
        }

        viewModel.onError = { [weak self] message in
            self?.showErrorAlert(message)
        }
    }
}

// UITableViewDataSource reads viewModel.items directly
```

### Testing (async/await)

```swift
class FeatureViewModelTests: XCTestCase {
    var mockService: MockFeatureService!

    override func setUp() {
        mockService = MockFeatureService()
    }

    @MainActor
    func testViewDidLoad_fetchesItems() async {
        mockService.stubbedItems = [Item(id: "1")]
        let sut = FeatureViewModel(service: mockService)

        sut.viewDidLoad()
        await sut.loadTask?.value // wait for Task to complete

        XCTAssertEqual(sut.items.count, 1)
    }

    @MainActor
    func testViewDidLoad_showsAndHidesLoading() async {
        mockService.stubbedItems = []
        let sut = FeatureViewModel(service: mockService)

        sut.viewDidLoad()
        // isLoading is true immediately after viewDidLoad
        XCTAssertTrue(sut.isLoading)

        await sut.loadTask?.value
        XCTAssertFalse(sut.isLoading)
    }

    @MainActor
    func testViewDidLoad_setsErrorOnFailure() async {
        mockService.shouldFail = true
        let sut = FeatureViewModel(service: mockService)
        var receivedError: String?
        sut.onError = { receivedError = $0 }

        sut.viewDidLoad()
        await sut.loadTask?.value

        XCTAssertNotNil(receivedError)
    }

    @MainActor
    func testDidSelectItem_signalsNavigation() async {
        mockService.stubbedItems = [Item(id: "42")]
        let sut = FeatureViewModel(service: mockService)
        var selectedItem: Item?
        sut.onItemSelected = { selectedItem = $0 }

        sut.viewDidLoad()
        await sut.loadTask?.value

        sut.didSelectItem(at: 0)
        XCTAssertEqual(selectedItem?.id, "42")
    }
}
```

---

## Approach 4: @Observable (iOS 17+)

Apple's Observation framework. Minimal boilerplate, fine-grained updates. Best with SwiftUI, usable in UIKit.

### ViewModel (SwiftUI)

```swift
import Observation

@Observable
class FeatureViewModel {
    private let service: FeatureServiceProtocol

    private(set) var items: [ItemCellModel] = []
    private(set) var isLoading = false
    var errorMessage: String?

    // Navigation
    var onItemSelected: ((Item) -> Void)?

    private var rawItems: [Item] = []

    init(service: FeatureServiceProtocol) {
        self.service = service
    }

    func loadData() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let fetched = try await service.fetchItems()
            rawItems = fetched
            items = fetched.map(ItemCellModel.init)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func selectItem(at index: Int) {
        guard index < rawItems.count else { return }
        onItemSelected?(rawItems[index])
    }
}
```

### SwiftUI View

```swift
struct FeatureView: View {
    @State var viewModel: FeatureViewModel

    var body: some View {
        List(viewModel.items) { item in
            Text(item.title)
        }
        .overlay {
            if viewModel.isLoading {
                ProgressView()
            }
        }
        .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .task {
            await viewModel.loadData()
        }
    }
}
```

### UIKit Integration with @Observable

```swift
// UIKit requires manual observation tracking
class FeatureViewController: UIViewController {
    private let viewModel: FeatureViewModel
    private let tableView = UITableView()

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        startObserving()
        Task { await viewModel.loadData() }
    }

    private func startObserving() {
        // withObservationTracking is one-shot — must re-register
        func observe() {
            withObservationTracking {
                _ = viewModel.items
                _ = viewModel.isLoading
                _ = viewModel.errorMessage
            } onChange: { [weak self] in
                Task { @MainActor [weak self] in
                    self?.updateUI()
                    observe() // re-register
                }
            }
        }
        observe()
    }

    private func updateUI() {
        tableView.reloadData()
        // ... update loading indicator, show errors
    }
}
```

> **Note**: `withObservationTracking` in UIKit is awkward (one-shot, must re-register). If targeting iOS 17+ with UIKit, prefer Combine or async/await approach instead. Use `@Observable` primarily with SwiftUI.

### Testing (@Observable)

```swift
class FeatureViewModelTests: XCTestCase {
    var mockService: MockFeatureService!

    override func setUp() {
        mockService = MockFeatureService()
    }

    func testLoadData_populatesItems() async {
        mockService.stubbedItems = [Item(id: "1")]
        let sut = FeatureViewModel(service: mockService)

        await sut.loadData()

        XCTAssertEqual(sut.items.count, 1)
        XCTAssertFalse(sut.isLoading)
    }

    func testLoadData_setsErrorOnFailure() async {
        mockService.shouldFail = true
        let sut = FeatureViewModel(service: mockService)

        await sut.loadData()

        XCTAssertNotNil(sut.errorMessage)
        XCTAssertTrue(sut.items.isEmpty)
    }

    func testSelectItem_signalsNavigation() async {
        mockService.stubbedItems = [Item(id: "42")]
        let sut = FeatureViewModel(service: mockService)
        var selectedItem: Item?
        sut.onItemSelected = { selectedItem = $0 }

        await sut.loadData()
        sut.selectItem(at: 0)

        XCTAssertEqual(selectedItem?.id, "42")
    }
}
```

---

## Approach 5: RxSwift

See `rxswift` skill for framework details.

### ViewModel

```swift
import RxSwift
import RxCocoa

protocol FeatureViewModelProtocol {
    func viewDidLoad()
    func didSelectItem(at index: Int)
    func didTapRetry()

    var items: Driver<[ItemCellModel]> { get }
    var isLoading: Driver<Bool> { get }
    var error: Signal<String> { get }
    var onItemSelected: ((Item) -> Void)? { get set }
}

class FeatureViewModel: FeatureViewModelProtocol {
    private let service: FeatureServiceProtocol
    private let disposeBag = DisposeBag()

    private let itemsRelay = BehaviorRelay<[Item]>(value: [])
    private let loadingRelay = BehaviorRelay<Bool>(value: false)
    private let errorRelay = PublishRelay<String>()

    var items: Driver<[ItemCellModel]> {
        itemsRelay.map { $0.map(ItemCellModel.init) }.asDriver(onErrorJustReturn: [])
    }
    var isLoading: Driver<Bool> { loadingRelay.asDriver() }
    var error: Signal<String> { errorRelay.asSignal() }
    var onItemSelected: ((Item) -> Void)?

    init(service: FeatureServiceProtocol) {
        self.service = service
    }

    func viewDidLoad() { loadData() }

    func didSelectItem(at index: Int) {
        let item = itemsRelay.value[index]
        onItemSelected?(item)
    }

    func didTapRetry() { loadData() }

    private func loadData() {
        loadingRelay.accept(true)
        service.fetchItems()
            .subscribe(
                onSuccess: { [weak self] items in
                    self?.loadingRelay.accept(false)
                    self?.itemsRelay.accept(items)
                },
                onFailure: { [weak self] error in
                    self?.loadingRelay.accept(false)
                    self?.errorRelay.accept(error.localizedDescription)
                }
            )
            .disposed(by: disposeBag)
    }
}
```

### Input/Output Pattern (RxSwift)

For ViewModels where all bindings are set up at init:

```swift
class FeatureViewModel {
    struct Input {
        let viewDidLoad: Observable<Void>
        let itemSelected: Observable<IndexPath>
        let refresh: Observable<Void>
    }

    struct Output {
        let items: Driver<[ItemCellModel]>
        let isLoading: Driver<Bool>
        let error: Signal<String>
    }

    func transform(input: Input) -> Output {
        let loading = BehaviorRelay<Bool>(value: false)
        let errorRelay = PublishRelay<String>()

        let items = Observable.merge(input.viewDidLoad, input.refresh)
            .do(onNext: { loading.accept(true) })
            .flatMapLatest { [service] _ in
                service.fetchItems()
                    .catch { error in
                        errorRelay.accept(error.localizedDescription)
                        return .just([])
                    }
            }
            .do(onNext: { _ in loading.accept(false) })
            .map { $0.map(ItemCellModel.init) }
            .asDriver(onErrorJustReturn: [])

        return Output(
            items: items,
            isLoading: loading.asDriver(),
            error: errorRelay.asSignal()
        )
    }
}
```

### Testing (RxSwift)

```swift
import RxTest
import RxBlocking

class FeatureViewModelTests: XCTestCase {
    var sut: FeatureViewModel!
    var mockService: MockFeatureService!
    var disposeBag: DisposeBag!

    override func setUp() {
        mockService = MockFeatureService()
        sut = FeatureViewModel(service: mockService)
        disposeBag = DisposeBag()
    }

    func testViewDidLoad_fetchesItems() throws {
        mockService.stubbedItems = [Item(id: "1")]

        sut.viewDidLoad()

        let items = try sut.items.toBlocking().first()
        XCTAssertEqual(items?.count, 1)
    }

    func testViewDidLoad_showsLoading() {
        var states: [Bool] = []
        sut.isLoading
            .drive(onNext: { states.append($0) })
            .disposed(by: disposeBag)

        mockService.stubbedItems = []
        sut.viewDidLoad()

        XCTAssertEqual(states, [false, true, false])
    }

    func testDidSelectItem_signalsNavigation() {
        var selectedItem: Item?
        sut.onItemSelected = { selectedItem = $0 }
        mockService.stubbedItems = [Item(id: "42")]

        sut.viewDidLoad()
        sut.didSelectItem(at: 0)

        XCTAssertEqual(selectedItem?.id, "42")
    }
}
```

---

## ViewModel Rules Summary

| Do | Don't |
|----|-------|
| Define protocol | Import UIKit |
| Inject all dependencies | Reference ViewController |
| Keep state private | Expose mutable state directly |
| Transform data for display | Return raw models to View |
| Use one binding style | Mix Combine + RxSwift + closures |

## Testing ViewModel

All binding approaches share the same testing principle: trigger ViewModel actions (e.g. `viewDidLoad()`, `didSelectItem(at:)`) and verify the resulting state or emitted values. Each approach above includes a full Testing section.

Key points:
- Mock service dependencies via protocols
- Test state transitions (loading → loaded, loading → error)
- Test navigation signals via closures
- **Closures**: assert directly in closure callbacks with `XCTestExpectation`
- **Combine**: subscribe with `sink`, use `XCTestExpectation` (see `combine` skill)
- **async/await**: use `@MainActor async` test methods, await Task completion
- **@Observable**: use `async` test methods, call async ViewModel methods directly
- **RxSwift**: use `RxTest`/`RxBlocking` (see `rxswift` skill)

## When Appropriate

- Apps with testable business logic requirements
- Screens with multiple data sources or complex state
- Teams of 2+ developers

## When to Add Coordinator

If navigation becomes complex (conditional flows, deep links, reusable screens), add the `coordinator` pattern on top. See `coordinator` skill.
