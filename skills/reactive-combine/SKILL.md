---
name: reactive-combine
description: "Use when working with Apple's Combine framework — a binding/event-stream tool, not an architecture. Covers publishers, subscribers, subjects, operators, UIKit/SwiftUI integration, ViewModel binding patterns, and testing. Architecture is chosen separately (see arch-mvvm / arch-clean / arch-tca)."
---

# Combine Framework Patterns & Best Practices

> **Category:** binding/event-stream framework, **not** an architectural pattern.
> Combine is the "wiring" between layers (View ↔ ViewModel, Service ↔ Repository), not a way to organize the layers themselves. Pick the architecture separately: `arch-mvvm` / `arch-clean` / `arch-tca` / `arch-viper` — Combine can be used with any of them.

This skill provides guidelines for using Apple's Combine framework effectively in iOS applications.

## When to Use Combine

**Good fit**:
- New projects targeting iOS 13+
- Want first-party Apple framework (no dependencies)
- SwiftUI projects (native integration)
- Simple to moderate async flows
- Team familiar with reactive concepts

**Consider alternatives**:
- Complex operators needed → RxSwift (more operators)
- iOS 12 support required → RxSwift
- One-shot async calls → async/await
- Simple callbacks → closures/delegates

## Core Concepts Quick Reference

| Type | Role | Equivalent in RxSwift |
|------|------|----------------------|
| `Publisher` | Emits values over time | `Observable` |
| `Subscriber` | Receives values | `Observer` |
| `Subject` | Both publisher and subscriber | `Subject` |
| `Cancellable` | Subscription lifecycle | `Disposable` |
| `AnyPublisher` | Type-erased publisher | `Observable` (erased) |

### Subject Types

| Type | Behavior | Use Case |
|------|----------|----------|
| `PassthroughSubject` | No replay, only new values | Events, triggers |
| `CurrentValueSubject` | Replays current value | State with initial value |

## Memory Management

### Storing Cancellables

```swift
class FeatureViewModel {
    private var cancellables = Set<AnyCancellable>()

    func bind() {
        somePublisher
            .sink { value in
                // handle value
            }
            .store(in: &cancellables)
    }
}
```

### Weak Self in Closures

Always use `[weak self]` in sink/receive closures:

```swift
publisher
    .sink { [weak self] value in
        self?.handleValue(value)
    }
    .store(in: &cancellables)
```

## Publisher Patterns

### Transforming Data

```swift
userPublisher.map { user in user.displayName }
userIdPublisher.flatMap { [weak self] id -> AnyPublisher<User, Error> in
    guard let self else { return Empty().eraseToAnyPublisher() }
    return self.userService.fetchUser(id: id)
}
optionalUserPublisher.compactMap { $0 }
```

### Combining Publishers

```swift
Publishers.CombineLatest(namePublisher, emailPublisher)
    .map { name, email in FormData(name: name, email: email) }
Publishers.Zip(requestA, requestB)
Publishers.Merge(source1, source2)
```

### Filtering & Timing

```swift
textPublisher
    .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
    .removeDuplicates()
scrollOffsetPublisher
    .throttle(for: .milliseconds(100), scheduler: RunLoop.main, latest: true)
```

### Error Handling

```swift
apiPublisher.catch { error in Just(fallbackValue) }
apiPublisher.replaceError(with: fallbackValue)
apiPublisher.retry(3)
apiPublisher.mapError { AppError.network($0) }
```

### Thread Management

```swift
backgroundPublisher
    .receive(on: DispatchQueue.main)
    .sink { [weak self] value in self?.updateUI(value) }
    .store(in: &cancellables)
```

## ViewModel Pattern with @Published

```swift
class FeatureViewModel: ObservableObject {
    @Published var items: [Item] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    private let service: ServiceProtocol
    private var cancellables = Set<AnyCancellable>()

    init(service: ServiceProtocol) {
        self.service = service
    }

    func load() {
        isLoading = true
        service.fetchItems()
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    self?.isLoading = false
                    if case .failure(let error) = completion {
                        self?.errorMessage = error.localizedDescription
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

## UIKit Integration

Combine has no built-in UIKit bindings. Create extensions:

```swift
extension UITextField {
    var textPublisher: AnyPublisher<String, Never> {
        NotificationCenter.default
            .publisher(for: UITextField.textDidChangeNotification, object: self)
            .compactMap { ($0.object as? UITextField)?.text }
            .eraseToAnyPublisher()
    }
}
```

## Common Mistakes

1. Missing `.store(in: &cancellables)` — subscription immediately cancelled
2. Strong self in `.sink` — retain cycle
3. UI updates on background thread — use `.receive(on: DispatchQueue.main)`
4. Not type-erasing — use `.eraseToAnyPublisher()` for clean APIs
5. Forgetting `.share()` — expensive publisher re-executed per subscriber

## Testing Combine Code

```swift
func testItemsLoad() {
    let expectation = XCTestExpectation(description: "Items loaded")
    let viewModel = FeatureViewModel(service: MockService(items: [Item(id: 1)]))
    var cancellables = Set<AnyCancellable>()

    viewModel.$items
        .dropFirst()
        .sink { items in
            XCTAssertEqual(items.count, 1)
            expectation.fulfill()
        }
        .store(in: &cancellables)

    viewModel.load()
    wait(for: [expectation], timeout: 1.0)
}
```

## RxSwift Migration Guide

| RxSwift | Combine |
|---------|---------|
| `Observable` | `AnyPublisher` |
| `Single` | `Future` |
| `PublishSubject` | `PassthroughSubject` |
| `BehaviorSubject` | `CurrentValueSubject` |
| `DisposeBag` | `Set<AnyCancellable>` |
| `disposed(by:)` | `store(in:)` |
| `subscribe` | `sink` |
| `bind(to:)` | `assign(to:on:)` |
| `Driver` | `AnyPublisher` + `.receive(on: DispatchQueue.main)` |
| `distinctUntilChanged()` | `removeDuplicates()` |
| `do(onNext:)` | `handleEvents(receiveOutput:)` |
