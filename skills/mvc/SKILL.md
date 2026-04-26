---
name: mvc
description: "Use when implementing classic Apple MVC (Model-View-Controller) in iOS apps. Covers component responsibilities, communication patterns (target-action, delegate, NotificationCenter), Massive ViewController anti-pattern, when MVC is appropriate, and migration paths to MVVM or VIPER."
---

# MVC (Model-View-Controller) — Apple Flavor

Стандартный паттерн Apple-фреймворков (UIKit, AppKit). View пассивна, Model независима, Controller связывает их и обрабатывает события. Прост, но без дисциплины быстро вырождается в Massive ViewController.

> **Related skills:**
> - `mvvm` — следующая ступень при росте логики (extract бизнес-логики из VC в ViewModel)
> - `coordinator` — extract навигации из VC, ортогонален MVC (можно использовать MVC + Coordinator)
> - `clean-architecture`, `viper` — для крупных проектов с явными слоями

## When Appropriate

| Сценарий | Использовать MVC |
|---|---|
| Прототип / proof-of-concept | ✅ |
| App на 1-3 экрана без серьёзной бизнес-логики | ✅ |
| CRUD-утилита (форма + список) | ✅ |
| Simple settings / preferences screen | ✅ |
| Учебный проект, демо | ✅ |
| App с 5+ экранами и навигацией между фичами | ⚠️ Думай о MVVM+Coordinator |
| Реактивные потоки данных, сложные состояния | ❌ MVVM/VIPER/Clean |
| Команда > 2 разработчиков, активная разработка > 6 мес | ❌ MVVM/VIPER/Clean |

**Правило:** MVC — это не «упрощённый MVVM». Это паттерн с собственным набором компромиссов. Не стесняйся использовать его для подходящих задач, но и не тяни в проект, который явно из него вырос.

## Structure

```
Feature/
├── FeatureViewController.swift   # Controller
├── FeatureView.swift             # Custom UIView (опционально)
├── Models/
│   ├── FeatureModel.swift        # Domain entity
│   └── FeatureModelStore.swift   # Хранение/загрузка модели
└── Cells/
    └── FeatureItemCell.swift
```

## Component Responsibilities

### Model

- Чистые данные и доменная логика
- Никаких UIKit-импортов (можно `Foundation`)
- Никаких ссылок на View или Controller
- Уведомляет об изменениях через `NotificationCenter`, KVO, delegate, или closure

```swift
struct Item {
    let id: UUID
    var title: String
    var isDone: Bool
}

final class ItemStore {
    private(set) var items: [Item] = []

    var onItemsChanged: (([Item]) -> Void)?

    func add(_ item: Item) {
        items.append(item)
        onItemsChanged?(items)
    }

    func toggle(itemId: UUID) {
        guard let idx = items.firstIndex(where: { $0.id == itemId }) else { return }
        items[idx].isDone.toggle()
        onItemsChanged?(items)
    }
}
```

### View

- Только отображение
- Не знает про Model
- Сообщает о действиях пользователя через target-action / delegate / closure
- Custom subview-ы — отдельные UIView, не вшитые в VC

```swift
final class ItemCell: UITableViewCell {
    private let titleLabel = UILabel()
    private let checkmark = UIImageView()

    var onToggleTap: (() -> Void)?

    func configure(with item: Item) {
        titleLabel.text = item.title
        titleLabel.attributedText = item.isDone
            ? NSAttributedString(string: item.title, attributes: [.strikethroughStyle: 1])
            : NSAttributedString(string: item.title)
        checkmark.image = item.isDone ? UIImage(systemName: "checkmark.circle.fill") : UIImage(systemName: "circle")
    }

    @IBAction private func didTapCheckmark() {
        onToggleTap?()
    }
}
```

### Controller (UIViewController)

- Связывает Model и View
- Подписывается на изменения Model, обновляет View
- Получает события View, обновляет Model
- Управляет жизненным циклом экрана (`viewDidLoad`, `viewWillAppear`, ...)
- Координирует переходы (или делегирует Coordinator-у — см. ниже)

```swift
final class ItemListViewController: UIViewController {

    private let store: ItemStore
    private let tableView = UITableView()

    init(store: ItemStore) {
        self.store = store
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        bindStore()
    }

    private func setupUI() {
        view.addSubview(tableView)
        tableView.dataSource = self
        tableView.register(ItemCell.self, forCellReuseIdentifier: "Item")
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .add, target: self, action: #selector(didTapAdd)
        )
    }

    private func bindStore() {
        store.onItemsChanged = { [weak self] _ in
            self?.tableView.reloadData()
        }
    }

    @objc private func didTapAdd() {
        let alert = UIAlertController(title: "New item", message: nil, preferredStyle: .alert)
        alert.addTextField()
        alert.addAction(.init(title: "Add", style: .default) { [weak self, weak alert] _ in
            guard let title = alert?.textFields?.first?.text, !title.isEmpty else { return }
            self?.store.add(Item(id: UUID(), title: title, isDone: false))
        })
        present(alert, animated: true)
    }
}

extension ItemListViewController: UITableViewDataSource {
    func tableView(_ tv: UITableView, numberOfRowsInSection section: Int) -> Int {
        store.items.count
    }

    func tableView(_ tv: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tv.dequeueReusableCell(withIdentifier: "Item", for: indexPath) as! ItemCell
        let item = store.items[indexPath.row]
        cell.configure(with: item)
        cell.onToggleTap = { [weak self] in
            self?.store.toggle(itemId: item.id)
        }
        return cell
    }
}
```

## Communication Patterns

### View → Controller

| Способ | Когда |
|---|---|
| **Target-action** | UIControl-наследники (UIButton, UISwitch). `addTarget(_:action:for:)` |
| **Delegate** | Сложные subview-ы со множеством событий (UITableView, UICollectionView, custom views) |
| **Closure** | Простой одноразовый callback, особенно в ячейках |
| **Notification** | Очень редко — когда ничего другого не подходит (системные события: keyboard, app lifecycle) |

### Model → Controller

| Способ | Когда |
|---|---|
| **Closure** (`onItemsChanged`) | Один наблюдатель, простая зависимость |
| **Delegate** | Несколько разных событий, один наблюдатель |
| **NotificationCenter** | Несколько наблюдателей, слабая связанность |
| **KVO / @Observable** | iOS 17+ — для plain observable полей. Но это уже шаг к MVVM |

### Controller → Controller (навигация)

В чистом MVC переходы делает сам VC:

```swift
private func showDetail(for item: Item) {
    let detailVC = ItemDetailViewController(item: item, store: store)
    navigationController?.pushViewController(detailVC, animated: true)
}
```

Для проектов 4+ экранов **лучше использовать Coordinator** (см. `coordinator` skill) — он не противоречит MVC и решает проблему расползания навигации по контроллерам.

## Massive ViewController Anti-Pattern

Без дисциплины VC накапливает всё подряд: data source, бизнес-логику, сетевые запросы, форматирование, навигацию, валидацию. Признаки:

- VC > 500 строк
- > 5 ответственностей в одном файле (UI setup, data fetch, validation, navigation, formatting, ...)
- Тяжело покрыть тестами — приходится поднимать UIKit-стек
- Дублирование кода между похожими экранами
- Изменение в одной фиче ломает соседнюю

### Что вытаскивать из VC

| Ответственность | Куда |
|---|---|
| Сетевые запросы, бизнес-логика | Service / Store / Repository |
| Сложное форматирование | Formatter / Presenter struct |
| TableView/CollectionView data source | Отдельный `UITableViewDataSource`-класс |
| Валидация форм | Validator struct |
| Навигация между фичами | Coordinator (см. `coordinator`) |
| Подписки / реактивные потоки | ViewModel — это уже миграция на MVVM |

Вытаскивание data source и validator — **всё ещё MVC**. Вытаскивание ViewModel — **переход на MVVM**.

### Сигналы, что MVC исчерпан

- Любой VC > 400 строк после вытаскивания data sources
- Тесты на бизнес-логику требуют поднятия VC и UI
- Появились реактивные потоки (RxSwift / Combine / async/await) — Controller не справляется с binding
- Команда > 2 человек активно работает с одним и тем же VC

→ Мигрируй на MVVM (см. `mvvm` skill) или MVVM+Coordinator (для крупных).

## DI

VC получает зависимости через init — никаких синглтонов, никаких `MyService.shared`.

```swift
final class ItemListViewController: UIViewController {
    private let store: ItemStore
    private let analytics: AnalyticsServiceProtocol

    init(store: ItemStore, analytics: AnalyticsServiceProtocol) {
        self.store = store
        self.analytics = analytics
        super.init(nibName: nil, bundle: nil)
    }
}
```

Сборку графа делает Composition Root (см. `composition-root` skill). Для маленьких MVC-app достаточно manual DI без контейнера.

Storyboard / XIB-based VC не позволяют init-инъекцию напрямую — для них либо property injection после `instantiateViewController`, либо переход на программный init.

## Testing

### Тестирование Model — легко

Model — это plain Swift, тесты обычные:

```swift
final class ItemStoreTests: XCTestCase {
    func test_add_appendsItemAndNotifies() {
        let store = ItemStore()
        var receivedItems: [Item]?
        store.onItemsChanged = { receivedItems = $0 }

        store.add(Item(id: UUID(), title: "Test", isDone: false))

        XCTAssertEqual(store.items.count, 1)
        XCTAssertEqual(receivedItems?.count, 1)
    }
}
```

### Тестирование Controller — сложнее

Если Controller содержит бизнес-логику — её невозможно протестировать без поднятия VC и UI. Это и есть цена MVC. Способы смягчить:

- Вытащить логику в отдельные классы (Validator, Formatter, Store) — там тесты лёгкие
- Не тестировать сам Controller — оставить на UI-тесты или snapshot-тесты
- Если хочется юнит-тестировать логику Controller — это сигнал, что пора в MVVM

## Migration Paths

### MVC → MVVM (постепенно)

1. Создай `FeatureViewModel` рядом с VC, оставь VC на месте
2. Перемести бизнес-логику и обработку событий из VC в ViewModel
3. VC получает `viewModel: FeatureViewModel` в init, делегирует ему действия
4. Подпишись на изменения ViewModel (closure / Combine / async stream — см. `mvvm`)
5. Удали из VC всё, кроме UI-кода

### MVC → MVC + Coordinator

1. Вынеси `pushViewController` / `present` из VC в Coordinator
2. VC сообщает Coordinator-у о намерении перехода через delegate / closure
3. Coordinator решает, куда переходить
4. См. `coordinator` skill

Эти миграции **независимы** — можно сначала вынести Coordinator, потом ViewModel, или наоборот.

## Common Mistakes

1. **Massive ViewController** — основная проблема. Применяй extract-стратегии до того, как VC раздуется
2. **VC знает про конкретные сервисы** — `URLSession.shared.dataTask(...)` в VC = непротестировать. Через DI и протоколы
3. **Model импортирует UIKit** — отрезает портируемость и тесты. Forматирование `UIColor`, `UIImage` — в VC или отдельном Presenter-е
4. **Singleton-ы для общения между VC** — `AppState.shared`. Это не MVC, это глобальное состояние. Используй DI
5. **Storyboard segues для всей навигации** — теряется типобезопасность параметров перехода. Для всего, кроме совсем простых, лучше программный push/present
6. **Прямые ссылки между VC** — `let parentVC = parent as? ParentVC`. Через delegate или closure
7. **Бизнес-логика в `prepare(for segue:)`** — segue должна только передать модель в следующий VC, не вычислять её
