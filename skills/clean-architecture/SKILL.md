---
name: clean-architecture
description: "Use when implementing Clean Architecture in iOS apps. Covers Domain/Data/Presentation layers, Use Cases, Repository pattern, DTOs, dependency rule, and testing each layer."
---

# Clean Architecture for iOS

Uncle Bob's layered architecture adapted for iOS. Strict dependency rules ensure business logic is independent of frameworks, UI, and external services.

## Structure

```
Feature/
├── Presentation/
│   ├── FeatureViewController.swift
│   ├── FeatureViewModel.swift
│   └── Views/
│       └── FeatureItemCell.swift
├── Domain/
│   ├── UseCases/
│   │   ├── GetItemsUseCase.swift
│   │   └── UpdateItemUseCase.swift
│   ├── Entities/
│   │   └── Item.swift
│   └── Repositories/
│       └── ItemRepositoryProtocol.swift  # Interface only
└── Data/
    ├── Repositories/
    │   └── ItemRepositoryImpl.swift
    ├── DataSources/
    │   ├── ItemRemoteDataSource.swift
    │   └── ItemLocalDataSource.swift
    └── DTOs/
        └── ItemDTO.swift
```

## Dependency Rule

Dependencies point **inward only**:

```
Presentation → Domain ← Data
```

- **Domain** knows nothing about Presentation or Data
- **Presentation** depends on Domain (UseCases, Entities)
- **Data** depends on Domain (implements Repository interfaces)
- **Data** never imports Presentation
- **Presentation** never imports Data directly

## Choosing an Async Approach

Clean Architecture is independent of the async mechanism. The return types in Repository/UseCase/DataSource protocols depend on the project's chosen approach.

**IMPORTANT**: If the user did NOT explicitly specify which async approach to use, you MUST ask before writing any code. Analyze the project (existing imports, dependencies, min iOS target) and propose a recommendation with reasoning.

| Approach | Return Types | When |
|----------|-------------|------|
| **async/await** | `async throws -> [Item]` | iOS 15+, no reactive deps |
| **RxSwift** | `Single<[Item]>`, `Completable` | Existing RxSwift codebase |
| **Combine** | `AnyPublisher<[Item], Error>` | Existing Combine codebase |

All examples below show three variants. Use the one matching the project's approach.

## Layers

### Domain Layer (innermost — no dependencies)

Pure business logic. No UIKit, no frameworks, no third-party imports.

#### Entity

```swift
// Domain/Entities/Item.swift
struct Item {
    let id: String
    let title: String
    let description: String
    let status: ItemStatus
    let createdAt: Date
}

enum ItemStatus {
    case active
    case archived
    case deleted
}
```

#### Repository Protocol (interface only)

**async/await**:
```swift
protocol ItemRepositoryProtocol {
    func getItems() async throws -> [Item]
    func getItem(id: String) async throws -> Item
    func save(_ item: Item) async throws
    func delete(id: String) async throws
}
```

**RxSwift**:
```swift
protocol ItemRepositoryProtocol {
    func getItems() -> Single<[Item]>
    func getItem(id: String) -> Single<Item>
    func save(_ item: Item) -> Completable
    func delete(id: String) -> Completable
}
```

**Combine**:
```swift
protocol ItemRepositoryProtocol {
    func getItems() -> AnyPublisher<[Item], Error>
    func getItem(id: String) -> AnyPublisher<Item, Error>
    func save(_ item: Item) -> AnyPublisher<Void, Error>
    func delete(id: String) -> AnyPublisher<Void, Error>
}
```

#### Use Case

Single responsibility — one business operation per use case.

**async/await**:
```swift
protocol GetItemsUseCaseProtocol {
    func execute() async throws -> [Item]
}

class GetItemsUseCase: GetItemsUseCaseProtocol {
    private let repository: ItemRepositoryProtocol

    init(repository: ItemRepositoryProtocol) {
        self.repository = repository
    }

    func execute() async throws -> [Item] {
        let items = try await repository.getItems()
        return items
            .filter { $0.status == .active }
            .sorted { $0.createdAt > $1.createdAt }
    }
}
```

**RxSwift**:
```swift
protocol GetItemsUseCaseProtocol {
    func execute() -> Single<[Item]>
}

class GetItemsUseCase: GetItemsUseCaseProtocol {
    private let repository: ItemRepositoryProtocol

    init(repository: ItemRepositoryProtocol) {
        self.repository = repository
    }

    func execute() -> Single<[Item]> {
        repository.getItems()
            .map { items in
                items.filter { $0.status == .active }
                    .sorted { $0.createdAt > $1.createdAt }
            }
    }
}
```

**Combine**:
```swift
protocol GetItemsUseCaseProtocol {
    func execute() -> AnyPublisher<[Item], Error>
}

class GetItemsUseCase: GetItemsUseCaseProtocol {
    private let repository: ItemRepositoryProtocol

    init(repository: ItemRepositoryProtocol) {
        self.repository = repository
    }

    func execute() -> AnyPublisher<[Item], Error> {
        repository.getItems()
            .map { items in
                items.filter { $0.status == .active }
                    .sorted { $0.createdAt > $1.createdAt }
            }
            .eraseToAnyPublisher()
    }
}
```

### Data Layer (implements Domain interfaces)

#### DTO (Data Transfer Object)

Maps between external formats and Domain entities. DTOs are the same regardless of async approach.

```swift
// Data/DTOs/ItemDTO.swift
struct ItemDTO: Codable {
    let id: String
    let title: String
    let description: String
    let status: String
    let created_at: String

    func toDomain() -> Item {
        Item(
            id: id,
            title: title,
            description: description,
            status: ItemStatus(rawValue: status) ?? .active,
            createdAt: DateFormatter.iso8601.date(from: created_at) ?? Date()
        )
    }

    static func fromDomain(_ item: Item) -> ItemDTO {
        ItemDTO(
            id: item.id,
            title: item.title,
            description: item.description,
            status: item.status.rawValue,
            created_at: DateFormatter.iso8601.string(from: item.createdAt)
        )
    }
}
```

#### Data Sources

**async/await**:
```swift
protocol ItemRemoteDataSourceProtocol {
    func fetchItems() async throws -> [ItemDTO]
    func fetchItem(id: String) async throws -> ItemDTO
    func update(_ dto: ItemDTO) async throws
    func delete(id: String) async throws
}

protocol ItemLocalDataSourceProtocol {
    func getCachedItems() async throws -> [ItemDTO]
    func cache(_ items: [ItemDTO]) async throws
}
```

**RxSwift**:
```swift
protocol ItemRemoteDataSourceProtocol {
    func fetchItems() -> Single<[ItemDTO]>
    func fetchItem(id: String) -> Single<ItemDTO>
    func update(_ dto: ItemDTO) -> Completable
    func delete(id: String) -> Completable
}

protocol ItemLocalDataSourceProtocol {
    func getCachedItems() -> Single<[ItemDTO]>
    func cache(_ items: [ItemDTO]) -> Completable
}
```

**Combine**:
```swift
protocol ItemRemoteDataSourceProtocol {
    func fetchItems() -> AnyPublisher<[ItemDTO], Error>
    func fetchItem(id: String) -> AnyPublisher<ItemDTO, Error>
    func update(_ dto: ItemDTO) -> AnyPublisher<Void, Error>
    func delete(id: String) -> AnyPublisher<Void, Error>
}

protocol ItemLocalDataSourceProtocol {
    func getCachedItems() -> AnyPublisher<[ItemDTO], Error>
    func cache(_ items: [ItemDTO]) -> AnyPublisher<Void, Error>
}
```

#### Repository Implementation

**async/await**:
```swift
class ItemRepositoryImpl: ItemRepositoryProtocol {
    private let remote: ItemRemoteDataSourceProtocol
    private let local: ItemLocalDataSourceProtocol

    init(remote: ItemRemoteDataSourceProtocol, local: ItemLocalDataSourceProtocol) {
        self.remote = remote
        self.local = local
    }

    func getItems() async throws -> [Item] {
        do {
            let dtos = try await remote.fetchItems()
            try? await local.cache(dtos)
            return dtos.map { $0.toDomain() }
        } catch {
            let cached = try await local.getCachedItems()
            return cached.map { $0.toDomain() }
        }
    }

    func getItem(id: String) async throws -> Item {
        let dto = try await remote.fetchItem(id: id)
        return dto.toDomain()
    }

    func save(_ item: Item) async throws {
        try await remote.update(ItemDTO.fromDomain(item))
    }

    func delete(id: String) async throws {
        try await remote.delete(id: id)
    }
}
```

**RxSwift**:
```swift
class ItemRepositoryImpl: ItemRepositoryProtocol {
    private let remote: ItemRemoteDataSourceProtocol
    private let local: ItemLocalDataSourceProtocol
    private let disposeBag = DisposeBag()

    init(remote: ItemRemoteDataSourceProtocol, local: ItemLocalDataSourceProtocol) {
        self.remote = remote
        self.local = local
    }

    func getItems() -> Single<[Item]> {
        remote.fetchItems()
            .do(onSuccess: { [local] dtos in
                local.cache(dtos).subscribe().disposed(by: self.disposeBag)
            })
            .catch { [local] _ in
                local.getCachedItems()
            }
            .map { dtos in dtos.map { $0.toDomain() } }
    }

    func getItem(id: String) -> Single<Item> {
        remote.fetchItem(id: id).map { $0.toDomain() }
    }

    func save(_ item: Item) -> Completable {
        remote.update(ItemDTO.fromDomain(item))
    }

    func delete(id: String) -> Completable {
        remote.delete(id: id)
    }
}
```

**Combine**:
```swift
class ItemRepositoryImpl: ItemRepositoryProtocol {
    private let remote: ItemRemoteDataSourceProtocol
    private let local: ItemLocalDataSourceProtocol
    private var cancellables = Set<AnyCancellable>()

    init(remote: ItemRemoteDataSourceProtocol, local: ItemLocalDataSourceProtocol) {
        self.remote = remote
        self.local = local
    }

    func getItems() -> AnyPublisher<[Item], Error> {
        remote.fetchItems()
            .handleEvents(receiveOutput: { [local] dtos in
                local.cache(dtos).sink(receiveCompletion: { _ in }, receiveValue: {})
                    .store(in: &self.cancellables)
            })
            .catch { [local] _ in
                local.getCachedItems()
            }
            .map { dtos in dtos.map { $0.toDomain() } }
            .eraseToAnyPublisher()
    }

    func getItem(id: String) -> AnyPublisher<Item, Error> {
        remote.fetchItem(id: id).map { $0.toDomain() }.eraseToAnyPublisher()
    }

    func save(_ item: Item) -> AnyPublisher<Void, Error> {
        remote.update(ItemDTO.fromDomain(item))
    }

    func delete(id: String) -> AnyPublisher<Void, Error> {
        remote.delete(id: id)
    }
}
```

### Presentation Layer

ViewModel depends on UseCases (not Repository directly). Binding approach is independent of Clean Architecture — see `mvvm` skill for options.

```swift
// Presentation/FeatureViewModel.swift — example with closures binding
@MainActor
class FeatureViewModel {
    private let getItemsUseCase: GetItemsUseCaseProtocol
    private let updateItemUseCase: UpdateItemUseCaseProtocol

    private(set) var items: [ItemCellModel] = []
    private(set) var isLoading = false

    var onStateChanged: (() -> Void)?
    var onError: ((String) -> Void)?
    var onItemSelected: ((Item) -> Void)?

    private var rawItems: [Item] = []

    init(
        getItemsUseCase: GetItemsUseCaseProtocol,
        updateItemUseCase: UpdateItemUseCaseProtocol
    ) {
        self.getItemsUseCase = getItemsUseCase
        self.updateItemUseCase = updateItemUseCase
    }

    func viewDidLoad() {
        loadItems()
    }

    private func loadItems() {
        Task {
            isLoading = true
            onStateChanged?()
            do {
                rawItems = try await getItemsUseCase.execute()
                items = rawItems.map(ItemCellModel.init)
            } catch {
                onError?(error.localizedDescription)
            }
            isLoading = false
            onStateChanged?()
        }
    }
}
```

> **Note**: This ViewModel example uses async/await + closures. The ViewModel's binding approach (closures, Combine, RxSwift, @Observable) is chosen separately — see `mvvm` skill.

## DI Registration

```swift
class DomainAssembly: Assembly {
    func assemble(container: Container) {
        container.register(GetItemsUseCaseProtocol.self) { r in
            GetItemsUseCase(repository: r.resolve(ItemRepositoryProtocol.self)!)
        }

        container.register(UpdateItemUseCaseProtocol.self) { r in
            UpdateItemUseCase(repository: r.resolve(ItemRepositoryProtocol.self)!)
        }
    }
}

class DataAssembly: Assembly {
    func assemble(container: Container) {
        container.register(ItemRemoteDataSourceProtocol.self) { r in
            ItemRemoteDataSource(networkService: r.resolve(NetworkServiceProtocol.self)!)
        }

        container.register(ItemLocalDataSourceProtocol.self) { _ in
            ItemLocalDataSource()
        }

        container.register(ItemRepositoryProtocol.self) { r in
            ItemRepositoryImpl(
                remote: r.resolve(ItemRemoteDataSourceProtocol.self)!,
                local: r.resolve(ItemLocalDataSourceProtocol.self)!
            )
        }.inObjectScope(.container)
    }
}

class PresentationAssembly: Assembly {
    func assemble(container: Container) {
        container.register(FeatureViewModel.self) { r in
            FeatureViewModel(
                getItemsUseCase: r.resolve(GetItemsUseCaseProtocol.self)!,
                updateItemUseCase: r.resolve(UpdateItemUseCaseProtocol.self)!
            )
        }
    }
}
```

## Testing

### Use Case Tests

**async/await**:
```swift
class GetItemsUseCaseTests: XCTestCase {
    func testExecute_filtersArchivedItems() async throws {
        let mockRepo = MockItemRepository()
        mockRepo.stubbedItems = [
            Item(id: "1", title: "Active", status: .active, ...),
            Item(id: "2", title: "Archived", status: .archived, ...),
        ]
        let sut = GetItemsUseCase(repository: mockRepo)

        let result = try await sut.execute()

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.id, "1")
    }
}
```

**RxSwift**:
```swift
class GetItemsUseCaseTests: XCTestCase {
    func testExecute_filtersArchivedItems() throws {
        let mockRepo = MockItemRepository()
        mockRepo.stubbedItems = [
            Item(id: "1", title: "Active", status: .active, ...),
            Item(id: "2", title: "Archived", status: .archived, ...),
        ]
        let sut = GetItemsUseCase(repository: mockRepo)

        let result = try sut.execute().toBlocking().single()

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.id, "1")
    }
}
```

**Combine**:
```swift
class GetItemsUseCaseTests: XCTestCase {
    var cancellables: Set<AnyCancellable>!

    override func setUp() { cancellables = [] }

    func testExecute_filtersArchivedItems() {
        let mockRepo = MockItemRepository()
        mockRepo.stubbedItems = [
            Item(id: "1", title: "Active", status: .active, ...),
            Item(id: "2", title: "Archived", status: .archived, ...),
        ]
        let sut = GetItemsUseCase(repository: mockRepo)
        let expectation = expectation(description: "items filtered")

        sut.execute()
            .sink(
                receiveCompletion: { _ in },
                receiveValue: { result in
                    XCTAssertEqual(result.count, 1)
                    XCTAssertEqual(result.first?.id, "1")
                    expectation.fulfill()
                }
            )
            .store(in: &cancellables)

        waitForExpectations(timeout: 1)
    }
}
```

### Repository Tests

**async/await**:
```swift
class ItemRepositoryImplTests: XCTestCase {
    func testGetItems_remoteFails_fallsBackToCache() async throws {
        let mockRemote = MockRemoteDataSource()
        mockRemote.shouldFail = true
        let mockLocal = MockLocalDataSource()
        mockLocal.cachedItems = [ItemDTO(id: "cached", ...)]

        let sut = ItemRepositoryImpl(remote: mockRemote, local: mockLocal)
        let result = try await sut.getItems()

        XCTAssertEqual(result.first?.id, "cached")
    }
}
```

**RxSwift**:
```swift
class ItemRepositoryImplTests: XCTestCase {
    func testGetItems_remoteFails_fallsBackToCache() throws {
        let mockRemote = MockRemoteDataSource()
        mockRemote.shouldFail = true
        let mockLocal = MockLocalDataSource()
        mockLocal.cachedItems = [ItemDTO(id: "cached", ...)]

        let sut = ItemRepositoryImpl(remote: mockRemote, local: mockLocal)
        let result = try sut.getItems().toBlocking().single()

        XCTAssertEqual(result.first?.id, "cached")
    }
}
```

**Combine**:
```swift
class ItemRepositoryImplTests: XCTestCase {
    var cancellables: Set<AnyCancellable>!

    override func setUp() { cancellables = [] }

    func testGetItems_remoteFails_fallsBackToCache() {
        let mockRemote = MockRemoteDataSource()
        mockRemote.shouldFail = true
        let mockLocal = MockLocalDataSource()
        mockLocal.cachedItems = [ItemDTO(id: "cached", ...)]

        let sut = ItemRepositoryImpl(remote: mockRemote, local: mockLocal)
        let expectation = expectation(description: "fallback to cache")

        sut.getItems()
            .sink(
                receiveCompletion: { _ in },
                receiveValue: { result in
                    XCTAssertEqual(result.first?.id, "cached")
                    expectation.fulfill()
                }
            )
            .store(in: &cancellables)

        waitForExpectations(timeout: 1)
    }
}
```

## When Appropriate

- Large apps with complex domain logic
- Shared business logic across platforms (iOS + macOS)
- Long-lived projects (5+ years)
- Domain-driven design approach
- Multiple teams working in parallel

## Common Mistakes

1. **Skipping Use Cases** — going directly from ViewModel to Repository. Use Cases are where business rules live.
2. **Domain importing Data** — Domain must have zero external dependencies. Repository protocols live in Domain, implementations in Data.
3. **DTOs leaking into Domain** — always map DTO → Entity at repository boundary.
4. **One Use Case per CRUD** — don't create `GetItemsUseCase`, `GetItemUseCase`, `SaveItemUseCase` if they have no business logic. Group trivial operations or use Repository directly.
5. **Over-engineering simple features** — not every screen needs full Clean Architecture. Simple screens can use MVVM.
