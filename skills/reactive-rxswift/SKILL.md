---
name: reactive-rxswift
description: "Use when working with RxSwift — a binding/event-stream tool, not an architecture. Covers observables, operators, memory management, Driver/Signal UI bindings, ViewModel binding patterns, and testing with RxTest/RxBlocking. Architecture is chosen separately (see arch-mvvm / arch-clean / arch-viper)."
---

# RxSwift Patterns & Best Practices

> **Category:** binding/event-stream framework, **not** an architectural pattern.
> RxSwift is the "wiring" between layers (View ↔ ViewModel, Service ↔ Repository), not a way to organize the layers themselves. Pick the architecture separately: `arch-mvvm` / `arch-clean` / `arch-viper` / `arch-tca` — RxSwift can be used with any of them (for TCA this is a rare choice).

This skill provides guidelines for using RxSwift effectively in iOS applications.

## When to Use RxSwift

**Good fit**:
- Complex async flows with multiple data sources
- Real-time UI updates from data streams
- Coordinating multiple async operations
- Debouncing, throttling, combining user inputs
- Projects already using RxSwift

**Consider alternatives**:
- Simple one-shot async calls → async/await
- New projects targeting iOS 13+ → Combine
- Simple state management → closures/delegates

## Core Concepts Quick Reference

| Type | Emits | Terminates | Use Case |
|------|-------|------------|----------|
| `Observable` | 0...∞ items | Yes (complete/error) | General streams |
| `Single` | 1 item or error | Yes | API calls, DB queries |
| `Completable` | Nothing or error | Yes | Fire-and-forget operations |
| `Maybe` | 0-1 item or error | Yes | Optional result operations |
| `Driver` | 0...∞ items, no errors, main thread | No | UI bindings |
| `Signal` | Like Driver, no replay | No | UI events (taps, gestures) |

## Memory Management

### The DisposeBag Pattern

Every subscription must be disposed. Use `DisposeBag` tied to component lifecycle:

```swift
class FeatureViewModel {
    private let disposeBag = DisposeBag()

    func bind() {
        someObservable
            .subscribe(onNext: { value in
                // handle value
            })
            .disposed(by: disposeBag)  // Always dispose
    }
}
```

### Weak Self in Closures

**Always use `[weak self]`** in escaping closures to prevent retain cycles:

```swift
// Correct
observable
    .subscribe(onNext: { [weak self] value in
        self?.handleValue(value)
    })
    .disposed(by: disposeBag)

// Wrong - creates retain cycle
observable
    .subscribe(onNext: { value in
        self.handleValue(value)  // Strong capture
    })
    .disposed(by: disposeBag)
```

### When to Use `[unowned self]`

Rarely. Only when you're certain `self` will outlive the subscription:

```swift
// Only in controlled scenarios like view controller binding to its own view
button.rx.tap
    .subscribe(onNext: { [unowned self] in
        self.handleTap()  // VC owns button, button won't outlive VC
    })
    .disposed(by: disposeBag)
```

**Default to `[weak self]`** — it's safer.

## Operator Patterns

### Transforming Data

```swift
// Map: transform each element
userObservable
    .map { user in user.displayName }

// FlatMap: transform to new Observable (use for async operations)
userIdObservable
    .flatMapLatest { [weak self] id in
        self?.userService.fetchUser(id: id) ?? .empty()
    }

// CompactMap: filter nil values
optionalUserObservable
    .compactMap { $0 }  // Observable<User?> → Observable<User>
```

### Combining Streams

```swift
// CombineLatest: emit when any source emits (need all sources to have emitted once)
Observable.combineLatest(nameObservable, emailObservable) { name, email in
    FormData(name: name, email: email)
}

// Zip: pair elements 1:1
Observable.zip(requestA, requestB) { a, b in
    CombinedResult(a: a, b: b)
}

// Merge: combine into single stream
Observable.merge(source1, source2, source3)

// WithLatestFrom: take latest from another when source emits
submitButton.rx.tap
    .withLatestFrom(formDataObservable)
    .subscribe(onNext: { formData in
        // Submit form
    })
```

### Filtering & Timing

```swift
// Debounce: wait for pause in emissions
searchTextField.rx.text
    .debounce(.milliseconds(300), scheduler: MainScheduler.instance)
    .distinctUntilChanged()

// Throttle: limit emission rate
scrollView.rx.contentOffset
    .throttle(.milliseconds(100), scheduler: MainScheduler.instance)

// Filter: only pass matching elements
valueObservable
    .filter { $0 > 0 }

// DistinctUntilChanged: skip consecutive duplicates
stateObservable
    .distinctUntilChanged()
```

### Error Handling

```swift
// CatchError: recover with fallback
apiObservable
    .catch { error in
        return .just(fallbackValue)
    }

// Retry: retry on error
apiObservable
    .retry(3)

// RetryWhen: retry with custom logic
apiObservable
    .retry(when: { errors in
        errors.delay(.seconds(1), scheduler: MainScheduler.instance)
    })

// Materialize/Dematerialize: handle errors in stream
apiObservable
    .materialize()
    .map { event -> Event<Result> in
        switch event {
        case .next(let value): return .next(.success(value))
        case .error(let error): return .next(.failure(error))
        case .completed: return .completed
        }
    }
    .dematerialize()
```

## UI Binding Patterns

### Using Driver for Safe UI Binding

`Driver` guarantees: no errors, main thread, shares side effects.

```swift
// In ViewModel
var title: Driver<String> {
    titleSubject
        .asDriver(onErrorJustReturn: "")
}

// In ViewController
viewModel.title
    .drive(titleLabel.rx.text)
    .disposed(by: disposeBag)
```

### Creating Driver from Observable

```swift
// From Observable
observable
    .asDriver(onErrorJustReturn: defaultValue)

// From Observable with error handling
observable
    .asDriver(onErrorRecover: { error in
        return .just(fallbackValue)
    })
```

### Binding User Input

```swift
// Text field
textField.rx.text.orEmpty
    .bind(to: viewModel.searchQuery)
    .disposed(by: disposeBag)

// Button tap
button.rx.tap
    .bind(to: viewModel.submitTrigger)
    .disposed(by: disposeBag)

// Two-way binding is not a standard RxSwift/RxCocoa operator.
// Bind both directions explicitly unless the project defines its own `<->`.
textField.rx.text.orEmpty
    .distinctUntilChanged()
    .bind(to: viewModel.text)
    .disposed(by: disposeBag)

viewModel.text
    .distinctUntilChanged()
    .bind(to: textField.rx.text)
    .disposed(by: disposeBag)
```

## ViewModel Patterns

### Input/Output Pattern

Clean separation of inputs and outputs:

```swift
protocol FeatureViewModelProtocol {
    // Inputs
    var viewDidLoad: PublishRelay<Void> { get }
    var itemSelected: PublishRelay<IndexPath> { get }
    var refreshTrigger: PublishRelay<Void> { get }

    // Outputs
    var items: Driver<[Item]> { get }
    var isLoading: Driver<Bool> { get }
    var error: Signal<Error> { get }
}

class FeatureViewModel: FeatureViewModelProtocol {
    // Inputs
    let viewDidLoad = PublishRelay<Void>()
    let itemSelected = PublishRelay<IndexPath>()
    let refreshTrigger = PublishRelay<Void>()

    // Outputs
    let items: Driver<[Item]>
    let isLoading: Driver<Bool>
    let error: Signal<Error>

    init(service: ServiceProtocol) {
        let loadingRelay = BehaviorRelay<Bool>(value: false)
        let errorRelay = PublishRelay<Error>()

        let loadTrigger = Observable.merge(
            viewDidLoad.asObservable(),
            refreshTrigger.asObservable()
        )

        let itemsObservable = loadTrigger
            .flatMapLatest { _ in
                service.fetchItems()
                    .catch { error in
                        errorRelay.accept(error)
                        return .just([])
                    }
                    .do(
                        onSubscribe: { loadingRelay.accept(true) },
                        onDispose: { loadingRelay.accept(false) }
                    )
            }
            .share(replay: 1)

        self.items = itemsObservable.asDriver(onErrorJustReturn: [])
        self.isLoading = loadingRelay.asDriver()
        self.error = errorRelay.asSignal()
    }
}
```

### Subjects & Relays

| Type | Replays | Accepts Error | Use Case |
|------|---------|---------------|----------|
| `PublishSubject` | No | Yes | Events, triggers |
| `BehaviorSubject` | Last value | Yes | State with initial value |
| `ReplaySubject` | N values | Yes | Buffered events |
| `PublishRelay` | No | No | UI events (safe) |
| `BehaviorRelay` | Last value | No | UI state (safe) |

**Prefer Relays** for UI-related streams — they never error or complete.

## Common Mistakes

### 1. Missing Disposal

```swift
// Subscription leaks
observable.subscribe(onNext: { _ in })

// Always dispose
observable.subscribe(onNext: { _ in }).disposed(by: disposeBag)
```

### 2. Strong Self Capture

```swift
// Retain cycle
.subscribe(onNext: { self.update() })

// Weak capture
.subscribe(onNext: { [weak self] in self?.update() })
```

### 3. UI Updates on Background Thread

```swift
// Crashes or undefined behavior
backgroundObservable
    .subscribe(onNext: { self.label.text = $0 })

// Observe on main thread
backgroundObservable
    .observe(on: MainScheduler.instance)
    .subscribe(onNext: { self.label.text = $0 })

// Or use Driver (guarantees main thread)
backgroundObservable
    .asDriver(onErrorJustReturn: "")
    .drive(label.rx.text)
```

### 4. Not Sharing Side Effects

```swift
// API called twice
let response = apiService.fetch()
response.subscribe(onNext: { handleA($0) })
response.subscribe(onNext: { handleB($0) })

// Share the subscription
let response = apiService.fetch().share(replay: 1)
response.subscribe(onNext: { handleA($0) })
response.subscribe(onNext: { handleB($0) })
```

### 5. Nested Subscriptions

```swift
// Subscribe inside subscribe
outerObservable
    .subscribe(onNext: { value in
        innerObservable
            .subscribe(onNext: { innerValue in
                // Messy and hard to manage disposal
            })
    })

// Use flatMap
outerObservable
    .flatMapLatest { value in
        innerObservable
    }
    .subscribe(onNext: { innerValue in
        // Clean single subscription
    })
```

## Testing RxSwift Code

Use `RxTest` and `RxBlocking`:

```swift
import RxTest
import RxBlocking

func testViewModel() {
    let scheduler = TestScheduler(initialClock: 0)
    let disposeBag = DisposeBag()

    // Create mock input
    let input = scheduler.createHotObservable([
        .next(100, "query"),
        .next(200, "updated query")
    ])

    // Create observer for output
    let output = scheduler.createObserver(String.self)

    // Bind
    viewModel.results
        .bind(to: output)
        .disposed(by: disposeBag)

    // Run
    scheduler.start()

    // Assert
    XCTAssertEqual(output.events, [
        .next(100, "result for query"),
        .next(200, "result for updated query")
    ])
}

// Simple blocking test
func testSingleValue() throws {
    let result = try viewModel.fetchUser(id: 1).toBlocking().single()
    XCTAssertEqual(result.name, "Expected Name")
}
```
