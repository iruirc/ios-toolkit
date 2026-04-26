---
name: composition-root
description: "Use when designing where and how an app's object graph is wired — SceneDelegate / AppDelegate / @main App. Covers what belongs in Composition Root (CR), what doesn't, sync vs async bootstrap, scope strategies (app/scene/flow), and testing. DI-framework agnostic."
---

# Composition Root

Composition Root (CR) — единственное место в приложении, где **создаются и связываются конкретные типы**. Всё остальное приложение работает через протоколы и не знает о реализациях.

> **Related skills:**
> - `swinject` — конкретные техники регистрации, если выбран Swinject как DI-framework
> - `module-assembly` — как UI-фичи получают свои зависимости из CR через Factory-паттерн
> - `spm-package-design` — как SPM-пакеты вписываются в CR через `Dependencies` структуры

## Зачем нужен Composition Root

Без CR конкретные типы создаются разбросанно — внутри ViewModel, Coordinator, Service. Это даёт:

- Скрытые зависимости (не видно из публичного API)
- Жёсткую связку слоёв (ViewModel знает про конкретный сервис, не протокол)
- Невозможность подменить реализацию (для тестов или другой среды)
- Циклические импорты модулей

CR решает это: **только он** импортирует все конкретные типы и связывает их в граф. Остальной код видит только протоколы/абстракции.

## Где живёт Composition Root

| Точка | Когда |
|---|---|
| `SceneDelegate.scene(_:willConnectTo:options:)` | UIKit, multi-scene apps (стандарт с iOS 13+) |
| `AppDelegate.application(_:didFinishLaunchingWithOptions:)` | UIKit, single-scene или legacy |
| `@main struct App: App { init() { ... } }` | SwiftUI lifecycle |
| `main.swift` / `@main` actor/struct | macOS CLI / sandboxed scripts |

Для multi-scene UIKit: **AppDelegate** = bootstrap общих app-scope ресурсов (БД, кеши, аналитика); **SceneDelegate** = создание per-scene графа (UI, навигация). Не путать.

## Что обязательно делает CR

1. **Создаёт DI-контейнер** или ручной граф зависимостей
2. **Регистрирует/инициализирует все сервисы** (или вызывает их Assembly)
3. **Создаёт Factory-объекты** (`CoordinatorFactory`, `ModuleFactory` — см. `module-assembly`)
4. **Создаёт root-объект приложения** (RootCoordinator / RootView / TabBarController)
5. **Связывает root с window** и стартует UI

## Что CR **не должен** делать

| Анти-паттерн | Почему плохо | Куда вынести |
|---|---|---|
| Бизнес-логика, маппинг данных | CR не должен расти с фичами | В соответствующий сервис |
| Сетевые запросы, загрузка данных | Блокирует старт, прячет ошибки | В сервис, вызываемый из root view |
| Навигация (push/present) | Это работа Coordinator-а | RootCoordinator.start() |
| Условные ветвления по фиче-флагам | Засоряет CR — превращается в god-class | Factory с ветвлением + протокольная подмена |
| Регистрация после старта app | CR должен закончить работу до первого frame | Lazy property + on-demand creation |

## Bootstrap: sync vs async

### Sync bootstrap (типовой случай)

```swift
final class AppDependencyContainer {
    private let container = Container()

    func bootstrap() {
        registerServices()      // только регистрация — без async-операций
        registerViewModels()
        registerFactories()
    }
}

// SceneDelegate
let appContainer = AppDependencyContainer()
appContainer.bootstrap()
// 100% готово к использованию сразу
```

**Используй когда:** все зависимости создаются мгновенно, без I/O.

### Async bootstrap (БД с миграцией, прогрев кэша, валидация лицензии)

Два подхода:

**A) Ждать на splash-экране**

```swift
@MainActor
final class AppDependencyContainer {
    func bootstrapAsync() async throws {
        registerServices()
        try await migrationService.runPendingMigrations()
        try await cacheWarmer.preload()
    }
}

// SceneDelegate показывает splash, ждёт, потом создаёт root
window.rootViewController = SplashViewController()
window.makeKeyAndVisible()

Task { @MainActor in
    do {
        try await appContainer.bootstrapAsync()
        startMainFlow()
    } catch {
        showFatalError(error)
    }
}
```

**B) Сразу показать root, сервис публикует Ready-сигнал**

```swift
final class DatabaseService {
    @Published private(set) var state: ReadyState = .initializing

    func bootstrap() {
        Task {
            await runMigrations()
            state = .ready
        }
    }
}

// ViewModel ждёт сигнал
viewModel.$databaseState
    .filter { $0 == .ready }
    .sink { _ in self.loadData() }
```

Подход A — для случаев, когда без сервиса вообще ничего не работает (auth-токен, конфиг). Подход B — для опциональных сервисов (analytics, кэш картинок).

## Scopes: app / scene / flow / request

Разные объекты живут разное время — CR должен это явно различать.

| Scope | Длительность | Примеры | Где регистрировать |
|---|---|---|---|
| **app** | от старта до kill app | NetworkClient, DatabaseService, AnalyticsService, FeatureFlags | AppDelegate / @main App |
| **scene** | пока scene активна (iPad multi-window) | NavigationCoordinator, scene-specific cache | SceneDelegate |
| **flow** | пока активен один user-flow (онбординг, чекаут) | OnboardingState, CheckoutSession | Coordinator-родитель flow |
| **request** | один сетевой запрос / экран | RequestParameters, ScreenLogger | Создаётся inline, не регистрируется |

**В Swinject:** `.container` ≈ app/scene scope (в зависимости от того, чей это контейнер); `.transient` ≈ request scope; `.weak` ≈ опциональный shared. См. `swinject` skill, секция «Object Scopes».

**При ручном DI:** scope = время жизни ссылки. Hold strong → жив; weak/optional → может быть выгружен.

## Bootstrap order: что от чего зависит

CR должен регистрировать сервисы в порядке зависимостей. Циклы запрещены.

Типичный порядок (сверху вниз):

```
1. Logger / Crash reporter            ← никаких зависимостей
2. Configuration / FeatureFlags       ← Logger
3. Persistence (DB, Keychain, Cache)  ← Logger, Config
4. Network (HTTPClient, Auth)         ← Persistence (для токенов), Config
5. Domain services (User, Catalog)    ← Network, Persistence
6. UI services (ImageLoader, Theme)   ← Network
7. Factories (Coordinator, Module)    ← всё выше
8. RootCoordinator                    ← Factories
```

Если возник цикл (A нужен B, B нужен A) — это **архитектурный дефект**, не повод использовать lazy injection как костыль. Нужно ввести третий тип C, или property injection (см. `swinject` skill, «Circular Dependencies»).

## Множественные Composition Root

Иногда нужен **не один CR**, а несколько:

| Сценарий | Решение |
|---|---|
| iPad multi-scene | App-scope CR в AppDelegate + per-scene CR в SceneDelegate, scene получает ссылки на app-scope сервисы |
| App + extensions (widget, share, intents) | Каждый extension имеет свой CR, общий код вынесен в SPM-пакет (см. `spm-package-design`) |
| App + UITests host app | Тестовый CR подменяет сервисы на mock-и через переменную окружения |
| App с несколькими product-modes (full/lite) | Один CR, но через FeatureFlags подменяет реализации в registerServices() |

## Тестирование Composition Root

CR редко покрывают unit-тестами (он сам — тестовая инфра), но **smoke-тест на регистрации полезен**:

```swift
final class CompositionRootSmokeTests: XCTestCase {
    func test_allCriticalServicesResolve() {
        let container = AppDependencyContainer()
        container.bootstrap()

        // Проверяем, что критические сервисы резолвятся
        XCTAssertNotNil(container.userService)
        XCTAssertNotNil(container.networkClient)
        XCTAssertNotNil(container.appSettingsManager)
    }

    func test_bootstrapDoesNotCrash() {
        let container = AppDependencyContainer()
        XCTAssertNoThrow(container.bootstrap())
    }
}
```

Для async bootstrap — проверка, что граф собирается в разумное время:

```swift
func test_asyncBootstrapCompletesInReasonableTime() async throws {
    let container = AppDependencyContainer()
    let start = Date()
    try await container.bootstrapAsync()
    let elapsed = Date().timeIntervalSince(start)
    XCTAssertLessThan(elapsed, 2.0)  // не должно занимать >2с
}
```

## Common Mistakes

1. **CR как singleton** — `static let shared = AppContainer()`. Это Service Locator, теряется вся ценность DI.
2. **CR импортирует UIKit views напрямую** — должен работать через Factory/Assembly, чтобы UI слой можно было переключить.
3. **CR-методы зовутся из произвольных мест кода** — `AppDependencyContainer.shared.userService` где попало = anti-pattern. CR доступен только корневым объектам (Coordinator, RootView).
4. **Bootstrap делает сетевые запросы синхронно** — блокирует main thread, app выглядит зависшим. Используй async bootstrap (вариант A или B выше).
5. **Регистрация в нескольких местах** — часть в AppDelegate, часть в SceneDelegate, часть в каком-то Manager. Должен быть один (или явно несколько с понятными scope) CR.

## File Structure (типовая)

```
App/
├── SceneDelegate.swift                  # CR (UIKit) — запускает bootstrap, создаёт root
├── AppDelegate.swift                    # app-scope bootstrap (опционально)
└── DependencyInjection/
    ├── AppDependencyContainer.swift     # CR-фасад, owns DI container
    ├── AppDependencies.swift            # composite protocol для feature-deps
    └── Registrations/
        ├── ServicesRegistration.swift   # сервисы по группам
        ├── ViewModelsRegistration.swift
        └── FactoriesRegistration.swift
```

Для SwiftUI-приложений:

```
App/
├── MyApp.swift                          # @main + init() — CR
└── DependencyInjection/
    └── AppDependencyContainer.swift
```

## Когда CR не нужен

- Прототип на 1 экран — manual DI прямо в `@main App.init()` достаточно
- Скрипт/CLI без графа объектов — обычная функция main()
- Когда весь функционал — это статические утилиты без состояния

Во всех остальных случаях явный CR окупается с первого изменения архитектуры.
