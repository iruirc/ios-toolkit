---
name: persistence-architecture
description: "Use when designing local data storage in an iOS app — choosing between Core Data, SwiftData, GRDB/SQLite, Realm, UserDefaults, file storage; Repository as the boundary that hides the framework; migrations (lightweight/heavyweight/SwiftData VersionedSchema/GRDB DatabaseMigrator); background contexts and threading; reactive queries; CloudKit sync; encryption / file protection; in-memory testing strategies."
---

# Persistence Architecture

Decisions about **where data lives, how it survives app launches, and how the rest of the app talks to it**. Not a tutorial on Core Data fetch requests — this skill tells you **how to wire any persistence framework into a layered architecture** that survives upgrades, threading, and framework swaps.

> **Related skills:**
> - `arch-clean`, `arch-mvvm`, `arch-viper` — which layer the persistence layer reports into
> - `error-architecture` — error mapping at the storage boundary, conflict resolution, recoverable vs fatal classification
> - `net-architecture` — pairing remote source + local cache (offline-first, sync, ETag/conditional GET)
> - `di-composition-root` — where `ModelContainer` / `NSPersistentContainer` / `DatabasePool` are bootstrapped (singleton scope)
> - `di-module-assembly` — registering Repository implementations into feature modules
> - `reactive-combine`, `reactive-rxswift` — bridging persistence queries into reactive pipelines
> - `pkg-spm-design` — when extracting persistence into its own SPM package (and what the public surface should be)

## Why This Skill Exists

Without an architecture, persistence code drifts into:

- **`NSManagedObject` in the ViewModel** — UI binds to thread-confined Core Data objects; one async fetch and you crash with `NSObjectInaccessibleException`.
- **One context for everything** — main-thread `viewContext` does writes too; UI hangs for 400ms during sync.
- **Schema migration roulette** — version 3 ships, half the users get `Cannot create NSManagedObjectModel: model is not loadable` on launch.
- **`UserDefaults` as a database** — 5MB of JSON in a single key, synchronous I/O on every read, lost on iCloud restore in some cases.
- **No Repository boundary** — `NSFetchRequest` literals scattered across 40 files; replacing Core Data with SwiftData requires touching every screen.
- **Thread-confined objects crossing actors** — Realm object captured in a `Task`, accessed on the wrong thread → silent data corruption or crash.
- **No backups before destructive migration** — heavyweight migration fails for one user → data gone, no recovery path.

Fix: **a typed Repository boundary returning Domain models, framework hidden behind it, contexts/threading owned by the persistence layer, migrations versioned and tested.**

## Layering

```
View / ViewModel              ← never imports CoreData / SwiftData / GRDB / Realm
        │
        ▼
Repository (Domain in/out, framework hidden inside)
        │
        ▼
Storage primitive (NSPersistentContainer / ModelContainer / DatabasePool / Realm)
        │
        ▼
Disk (sqlite file / Realm file / .plist / files)
```

**Rules:**

- **ViewModel/UseCase imports only Domain types.** Never `import CoreData` outside the persistence layer.
- **Repository owns mapping** Domain ↔ Storage entity, plus error mapping. See `error-architecture`.
- **Container/pool is a singleton** registered in Composition Root (`scope = .container`). Never created on demand.
- **Domain models are value types (`struct`).** They are snapshots — not references to live database rows.

> **Note on a separate DataSource layer.** Some projects split Repository (Domain-facing) from DataSource (framework-facing) when one Repository combines multiple sources (network + local). For pure local persistence the two collapse into one — the rest of this skill assumes that case. If you need the split, the rules above apply to the DataSource: it owns the framework, Repository owns mapping into the same Domain types.

## Choosing the Framework

There is no universal answer. Match storage to the **shape of the data and the access pattern**, not to fashion.

| Framework | Strengths | Weaknesses | Choose when |
|---|---|---|---|
| **Core Data** | Mature, Apple-supported, `NSFetchedResultsController`, CloudKit sync via `NSPersistentCloudKitContainer`, lightweight migrations free for many changes | Verbose, NSManagedObject is thread-confined and reference-typed, KVO-based (gotchas with Swift Concurrency), schema in `.xcdatamodeld` editor | Large relational graph, iOS 13+ deployment target, need CloudKit sync, willing to wrap NSManagedObject behind Repository |
| **SwiftData** | Modern Swift API (`@Model`, `@Query`), value-like ergonomics, `@ModelActor` for background work, integrated with SwiftUI, CloudKit support | iOS 17+ only, immature (bugs, migration tooling thin), `@Query` re-runs on any model change, schema reflection has edge cases | iOS 17+ only, SwiftUI app, simple-to-medium relational model, willing to live on the bleeding edge |
| **GRDB (SQLite)** | Direct SQL when you need it, `ValueObservation` for reactive queries, fast, full control over schema/indexes, easy migrations via `DatabaseMigrator`, sync API + async wrappers | No CloudKit out of the box, you write your own sync, manual relationship handling | Performance-critical, complex queries (`JOIN`/`GROUP BY`), need precise SQL, no Apple-sync requirement, want value semantics |
| **Realm** | Cross-platform (iOS+Android), live objects auto-update, MongoDB Atlas Device Sync | Thread-confined live objects (footgun), proprietary format, ownership uncertainty since MongoDB acquisition | Cross-platform code sharing, existing MongoDB Atlas backend |
| **UserDefaults** | Trivial API, automatically persisted | Sync I/O, 4KB practical limit per key, no querying, NOT for sensitive data | Simple flags, last-selected-tab, onboarding-shown bool |
| **Plain files (`FileManager`)** | Zero ceremony, full control, easy to inspect | No querying, no transactions, manual concurrency | Documents the user owns (exports, downloads, attachments), large blobs (images, video) |
| **Keychain** | Encrypted, survives reinstall (configurable), iCloud-syncable | Slow, small values only, awkward API | Tokens, passwords, encryption keys — see `swift-security` audit checklist |

**Decision shortcut:**

- **Big relational + CloudKit + iOS 13+** → Core Data
- **iOS 17+ SwiftUI greenfield, simple model** → SwiftData
- **Performance / complex SQL / control freak** → GRDB
- **Just a flag** → UserDefaults
- **Just a file** → `FileManager` + `NSFileProtectionComplete`
- **A secret** → Keychain (never UserDefaults)

Mixing is normal: GRDB for the main store + UserDefaults for flags + Keychain for tokens + files for downloaded media. Don't put media blobs in Core Data — `external storage` or no, the database file balloons.

> **On Realm:** coverage in this skill is intentionally minimal beyond migration and threading specifics. For new projects prefer Core Data / SwiftData / GRDB; the Realm sections here exist for maintenance of existing projects.

## Schema Design

Decisions you make once, regret for years if wrong.

- **Identity** — use `UUID` (or server-issued ID) as primary key, generated at insertion time. Never rely on auto-increment integers if data ever syncs across devices.
- **Timestamps** — `createdAt` and `updatedAt` on every entity. `updatedAt` enables conflict resolution and incremental sync.
- **Soft delete** — for any data the user can «delete» but might want back, store `deletedAt: Date?` instead of removing the row. CloudKit sync, undo, and audit trails depend on it. Filter `deletedAt == nil` at the Repository boundary so callers don't see deleted rows.
- **Indexes** — every column that appears in `WHERE` or `ORDER BY` of a hot query. Profile with the framework's query plan tool before adding speculatively.
- **Relationships** — Core Data and Realm love object graphs; GRDB encourages explicit foreign keys + JOINs. Pick one mental model per project.
- **Denormalization** — fine for read-heavy fields you'd otherwise compute every render (e.g., `commentCount` on a `Post`). Update in the same transaction as the source.
- **Enums as raw strings, not integers** — strings survive reordering, enable schema introspection, and don't break when you insert a new case.
- **Dates as native types, not formatted strings** — store `Date` (Core Data / SwiftData) or ISO 8601 via `ISO8601DateFormatter` (GRDB / blob). Never format with locale-dependent `DateFormatter` — user's locale change garbles all timestamps.

### Nested Types: Separate Entity vs Transformable Attribute

A recurring decision in Core Data / SwiftData / Realm: a domain type has a non-trivial nested value (`TrackBorder`, `MediaTime`, `Sequence`, `Address`). Two ways to store it:

- **Separate entity** with its own table and a relationship — `CDTrack → CDLocation`.
- **Transformable / Binary attribute** — the nested value is JSON-encoded into a `Data` blob inside the parent row.

Both are valid. **«Never use Codable in Core Data»** is wrong as a rule — Core Data ships transformable attributes precisely so you don't have to model every value type as an entity. The decision is by checklist:

| Pull toward separate entity | Pull toward transformable Data |
|---|---|
| Has identity (own `uuid`, referenced from outside) | Pure value type, no identity |
| Searchable / filterable through SQL/predicate | No need to query inner fields |
| Indexed columns (used in `WHERE` / `ORDER BY`) | Not part of any hot query |
| Mutated independently of the parent | Always mutated together with the parent |
| Has outgoing relationships to other entities | Leaf node — no outgoing edges |
| Shared between parents (deduplicated) | One per parent, never shared |
| Large (KBs+) and read selectively | Small (tens to hundreds of bytes) |

If most checks land on the right column → transformable Data. If even one important check lands on the left (especially identity or query-ability) → separate entity. Hybrid is normal: a project usually has both.

### Trade-offs of transformable Codable attributes

Cheap to introduce, but they have specific failure modes you must own:

1. **Schema drift inside the blob** — Core Data sees only bytes; renaming/removing/retyping a Codable field silently breaks decode for all existing rows. See *Migrations / Migrating transformable Codable payloads* for the four mitigation approaches.
2. **Not searchable via predicate** — `predicate = NSPredicate(format: "sequence.startBeat == %d", ...)` returns nothing useful. Decoding the blob in memory just to filter defeats the purpose of a database.
3. **Whole-blob writes** — touching one inner field rewrites the entire payload. Fine at tens of bytes, slow at hundreds of KB.
4. **No referential integrity** — if the blob holds an `id` of another entity, the database can't enforce the foreign key.
5. **NSSecureCoding** — Apple requires secure unarchiving since iOS 12. The cleanest path with Codable is to use a **Binary Data** attribute (not transformable) and do `JSONEncoder` / `JSONDecoder` yourself in the mapper — no `ValueTransformer` registration, no NSSecureCoding gymnastics.

### Anti-patterns at both extremes

- **Entity for every value type** — the «proper Core Data» tutorial trap. You end up with 30 tables, multi-level JOINs on every fetch, N+1 deletes/inserts on every save, and per-table migrations to keep in sync. Often these entities have no identity, no shared usage, no queries — they're just bureaucracy.
- **One mega-blob for everything** — store `Project` as a single Codable JSON in one row. No partial updates, no concurrent writes, no queries, migrations are total-rewrite. Works for a draft / prototype; fails the moment two screens edit the same project.

The healthy answer is **a deliberate hybrid**: separate entities for things with identity / queries / sharing, transformable Data for leaf value types.

## Storage Location and Sharing

### Where the database file lives

iOS gives you four directories with very different semantics. Pick the wrong one and you get backed-up gigabytes, mid-session deletions, or broken iCloud quota.

| Directory | Backed up to iCloud / iTunes? | iOS may delete? | Use for |
|---|---|---|---|
| `Documents/` | ✅ Yes, **visible to user via Files** | No | User-owned content (exported videos, downloaded attachments) — **NOT** the app's primary DB |
| `Library/Application Support/<bundle-id>/` | ✅ Yes, hidden from user | No | **Main DB location.** Core Data / GRDB / Realm files belong here. |
| `Library/Caches/` | ❌ No | ✅ Under memory pressure | Caches that can be re-fetched (image thumbnails, derived assets) |
| `tmp/` | ❌ No | ✅ Anytime | Truly ephemeral (download in progress) |

```swift
let supportURL = try FileManager.default.url(
    for: .applicationSupportDirectory,
    in: .userDomainMask,
    appropriateFor: nil,
    create: true
)
let storeURL = supportURL.appendingPathComponent("Model.sqlite")
```

**Common bug:** Xcode's Core Data template puts the store in `Documents` by default. For a video editor, music app, anything with sizeable local data, this means the user's iCloud quota gets eaten by your DB and the file shows up in the Files app. Move to `Application Support` from day one.

### Sharing data with App Extensions, Widgets, Watch app

When more than the main app process needs the same store (Share Extension importing media, Widget reading current state, Watch Connectivity sync), put the file in an **App Group container**:

1. Add an App Group capability in Xcode for the main app target AND every extension that needs the data (`group.com.example.app`).
2. Put the store inside the group container:

```swift
let groupURL = FileManager.default
    .containerURL(forSecurityApplicationGroupIdentifier: "group.com.example.app")!
let storeURL = groupURL.appendingPathComponent("Model.sqlite")
```

3. Use the same `storeURL` from both the main app and the extension.

Caveats:

- **Multiple processes hitting the same SQLite file** can corrupt it without proper coordination. Core Data handles cross-process notifications **only** if you enable Persistent History Tracking — see the dedicated section below. GRDB uses SQLite WAL mode by default — concurrent reads safe, concurrent writes serialised.
- **Schema migrations across processes** — the extension may launch first after install/update and trigger migration. The main app on next launch will see an already-migrated store. Migration logic must be idempotent.
- **App Group container survives uninstall** in some configurations on iCloud — different from the main bundle's Documents.

## The Repository Boundary

Repository is the **only** type the rest of the app sees. Its method signatures use Domain types and `throws`/`Result`. Never returns framework objects.

```swift
public protocol ItemRepository {
    func fetch(id: Item.ID) async throws -> Item?
    func list(filter: ItemFilter) async throws -> [Item]
    func observe(filter: ItemFilter) -> AsyncStream<[Item]>   // reactive variant
    func upsert(_ item: Item) async throws
    func delete(id: Item.ID) async throws
}

public struct Item: Identifiable, Sendable, Equatable {
    public let id: UUID
    public var title: String
    public var createdAt: Date
    public var updatedAt: Date
    public var isArchived: Bool
}
```

**Why Domain `struct`, not `NSManagedObject` / `@Model` / Realm `Object`:**

- **Sendable across actors** — value types cross isolation safely. See *Sendable and Swift Concurrency*.
- **Snapshot semantics** — caller sees the data as it was at fetch time; later DB writes don't mutate it under their feet.
- **No accidental persistence** — caller cannot save changes by mutating a property; the only write path is `upsert(_:)`.
- **Framework-swappable** — replacing Core Data with GRDB doesn't change a single ViewModel.

The Repository internally maps Storage → Domain on read and Domain → Storage on write. Mappers are pure functions, easy to unit-test.

### Core Data implementation

```swift
final class CoreDataItemRepository: ItemRepository {
    private let container: NSPersistentContainer

    func fetch(id: Item.ID) async throws -> Item? {
        try await container.performBackgroundTask { ctx in
            let req = ItemEntity.fetchRequest()
            req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            req.fetchLimit = 1
            guard let entity = try ctx.fetch(req).first else { return nil }
            return Self.toDomain(entity)
        }
    }

    private static func toDomain(_ entity: ItemEntity) -> Item {
        Item(
            id: entity.id,
            title: entity.title,
            createdAt: entity.createdAt,
            updatedAt: entity.updatedAt,
            isArchived: entity.isArchived
        )
    }
}
```

### SwiftData implementation

The same shape via `@ModelActor` — the actor owns its `ModelContext`, callers get pure value snapshots:

```swift
@ModelActor
actor SwiftDataItemRepository: ItemRepository {
    func fetch(id: Item.ID) async throws -> Item? {
        let descriptor = FetchDescriptor<ItemEntity>(
            predicate: #Predicate { $0.id == id }
        )
        guard let entity = try modelContext.fetch(descriptor).first else { return nil }
        return Self.toDomain(entity)
    }

    nonisolated private static func toDomain(_ entity: ItemEntity) -> Item {
        Item(id: entity.id, title: entity.title, createdAt: entity.createdAt,
             updatedAt: entity.updatedAt, isArchived: entity.isArchived)
    }
}
```

### GRDB implementation

Native value semantics — no actor needed since `DatabasePool` already serialises writes:

```swift
final class GRDBItemRepository: ItemRepository {
    private let dbPool: DatabasePool

    func fetch(id: Item.ID) async throws -> Item? {
        try await dbPool.read { db in
            try ItemRecord.filter(Column("id") == id).fetchOne(db).map(Self.toDomain)
        }
    }

    private static func toDomain(_ record: ItemRecord) -> Item { ... }
}
```

## Threading and Contexts

This is where most persistence bugs live. The rules differ by framework — pick the right model and stay inside it.

### Core Data

- **`viewContext`** — main-actor, read-only by convention. Used for `NSFetchedResultsController` powering UI lists.
- **`performBackgroundTask`** — every write goes through a fresh background context. Save → automatic merge into `viewContext` (set `automaticallyMergesChangesFromParent = true` on viewContext).
- **Never share an `NSManagedObject` across contexts.** Pass `NSManagedObjectID`, re-fetch on the other side.
- **Never `await` while holding a context block** — the `perform` block must complete synchronously inside the closure.

```swift
container.viewContext.automaticallyMergesChangesFromParent = true
container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
```

### SwiftData

- **`ModelContainer`** — created once, singleton.
- **`ModelContext`** — one per actor. The main-actor context is `container.mainContext`; create others with `ModelContext(container)` inside an actor.
- **`@ModelActor`** — the modern way to do background writes:

```swift
@ModelActor
actor ItemBackgroundStore {
    func upsert(_ items: [Item]) throws {
        for item in items {
            modelContext.insert(ItemEntity(from: item))
        }
        try modelContext.save()
    }
}
```

- **`@Query` in SwiftUI** — runs on the main context, re-fires on any insert/update/delete to the model type. For detail screens, prefer manual `FetchDescriptor` + `@State` so unrelated writes don't re-render.

### GRDB

- **`DatabasePool`** — concurrent reads + serialised writes. Use this in production.
- **`DatabaseQueue`** — strict serialisation. Use for testing or constrained environments.
- **Reads** — `dbPool.read { db in ... }` (sync) or `try await dbPool.read { ... }`.
- **Writes** — `try dbPool.write { db in ... }` is serialised automatically.

```swift
let pool = try DatabasePool(path: url.path, configuration: config)
try pool.write { db in
    try ItemRecord(id: item.id, title: item.title).insert(db)
}
```

### Realm

- **Live objects are thread-confined.** Never capture a Realm `Object` in a `Task` and access it elsewhere.
- **Cross threads via `freeze()`** — produces an immutable snapshot safe to read anywhere.
- **Writes** — `try realm.write { realm.add(entity, update: .modified) }` on the thread that owns the Realm instance.

## Sendable and Swift Concurrency

The Domain layer of this skill leans on Sendable `struct`s, but the framework side does not naturally cooperate. Three things to know.

### Domain models must be Sendable

Repository methods cross actor isolation (`fetch` from `@MainActor` ViewModel into a background actor and back). Domain types must be Sendable, otherwise Swift 6 / strict concurrency rejects the call.

```swift
public struct Item: Identifiable, Sendable, Equatable {
    public let id: UUID
    public var title: String
    public var createdAt: Date           // ✅ Sendable
    public var url: URL                  // ✅ Sendable
    public var attributes: [String: String]  // ✅ Sendable element type
    public var image: UIImage            // ❌ NOT Sendable — store as Data / URL instead
}
```

**Rule:** no UIKit / AppKit reference types in Domain models. If you have an image preview, store `Data` or `URL` and convert to `UIImage` at the UI layer.

### NSManagedObject is NOT Sendable

Period. It's reference-typed and context-confined. Even if you mark your subclass `@unchecked Sendable` to silence the compiler, accessing it from the wrong queue still crashes.

The Repository pattern protects you: `NSManagedObject` lives only inside `performBackgroundTask` blocks, never escapes as a return value. The mapping `entity → Item snapshot` happens inside the block; only the snapshot crosses the boundary.

If you absolutely must hand a managed-object reference to another actor, pass the **`NSManagedObjectID`** (which IS Sendable) and re-fetch on the other side via `existingObject(with:)`.

### SwiftData under Swift 6 strict concurrency

`@Model` instances are also context-confined — SwiftData enforces this through `ModelContext` actor isolation. Two consequences:

1. **`@ModelActor`-generated actor** is the canonical pattern for background work — its `modelContext` is isolated to that actor automatically. The Repository implementation example above uses this.
2. **`PersistentIdentifier`** (the SwiftData equivalent of `NSManagedObjectID`) IS Sendable — pass it across actors, re-fetch on the other side:

```swift
let id: PersistentIdentifier = await store.findTrendingItemID()
let entity: ItemEntity? = await mainStore.modelContext.model(for: id) as? ItemEntity
```

Don't pass `@Model` instances themselves — pass identifiers.

### Reactive streams across actors

If your Repository returns `AsyncStream<[Item]>` and the underlying observation runs on a background actor, the `[Item]` values must be Sendable to cross the boundary — which they already are if you followed the Domain-struct rule. No extra work.

## Persistent History Tracking (Core Data)

Without this enabled, the following silently fail:

- **Multi-process updates** — Share Extension writes to the store; the main app on next launch doesn't see the changes.
- **Background URLSession completing** — your handler updates Core Data; UI on next foreground doesn't refresh.
- **CloudKit sync** — `NSPersistentCloudKitContainer` requires history tracking; without it, sync is inconsistent or broken.

Enable it on the store description, before loading:

```swift
let description = container.persistentStoreDescriptions.first!
description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
description.setOption(true as NSNumber,
                     forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
```

Then react to remote changes:

```swift
NotificationCenter.default.addObserver(
    forName: .NSPersistentStoreRemoteChange,
    object: container.persistentStoreCoordinator,
    queue: nil
) { _ in
    container.viewContext.perform {
        container.viewContext.refreshAllObjects()
    }
}
```

**Truncate history periodically** — the history table grows unbounded otherwise. Apple recommends `deleteHistory(before:)` weekly:

```swift
let request = NSPersistentHistoryChangeRequest.deleteHistory(
    before: Date().addingTimeInterval(-7 * 24 * 3600)
)
try ctx.execute(request)
```

If you skip truncation, the history table can reach gigabytes over months.

> The standard `NSManagedObjectContextDidSave` / `NSManagedObjectContextObjectsDidChange` notifications fire **only within a single coordinator instance** — they don't cross processes or even fire across separate `NSPersistentContainer`s in the same process. Persistent History Tracking is the only correct mechanism for cross-process change propagation.

## Repository Write Patterns

Reads are the easy half. Writes are where most subtle bugs live: silent failures, half-applied transactions, child-collection drift, conflict races. Treat each write method as a transaction-shaped contract.

### `upsert` is the default, not separate `create` + `update`

Splitting writes into `create` / `update` forces every caller to know whether the row already exists — and the answer races with concurrent writers. Prefer one `upsert(_:)` that does the right thing inside a single transaction:

```swift
func upsert(_ item: Item) async throws {
    try await container.performBackgroundTask { ctx in
        let req = ItemEntity.fetchRequest()
        req.predicate = NSPredicate(format: "id == %@", item.id as CVarArg)
        req.fetchLimit = 1

        let entity = try ctx.fetch(req).first ?? ItemEntity(context: ctx)
        Self.fill(entity, from: item)

        try ctx.save()                 // ← throw propagates to caller
    }
}
```

**Rules:**

- The fetch + decision + save **must be in the same transaction block.** A `fetch` outside the block followed by a `save` inside is a TOCTOU race — between fetch and save, another writer can insert the same id, you crash on unique-constraint violation.
- **Do not silently `try?` the save.** If save fails, the caller must learn. See *Anti-pattern: silent write failure* below.
- **Mapping happens inside the transaction** for Core Data / Realm — child mappers may need the transaction/context to allocate child entities.

### Updating child collections — diff, don't delete-and-recreate

A common shortcut in Core Data / Realm code: when saving a parent, delete all children and recreate them. It «works», but:

- N delete + N insert per save → slow at 50+ children, painful at 500+.
- Persistent IDs of unchanged children are lost (breaks anything that referenced them: tombstones, sync, undo history).
- CloudKit sync sees N deletes + N inserts as N×2 sync events instead of K updates for K actually-changed rows.
- Atomicity is fragile — if the transaction fails mid-save, you may end up with a parent that has no children.

Diff by stable ID instead:

```swift
func upsertContainer(_ model: PlainContainerVideoTracks, in entity: CDContainer, ctx: NSManagedObjectContext) {
    let existing = Dictionary(uniqueKeysWithValues:
        (entity.tracks?.allObjects as? [CDVideoTrack] ?? []).map { ($0.uuid, $0) }
    )
    let incoming = Dictionary(uniqueKeysWithValues: model.tracks.map { ($0.uuid, $0) })

    let toDelete = existing.keys.subtracting(incoming.keys)
    let toInsert = incoming.keys.subtracting(existing.keys)
    let toUpdate = existing.keys.intersection(incoming.keys)

    for id in toDelete { ctx.delete(existing[id]!) }
    for id in toInsert { fillNewTrack(ctx: ctx, parent: entity, model: incoming[id]!) }
    for id in toUpdate { fillExistingTrack(existing[id]!, from: incoming[id]!) }
}
```

For GRDB this is a non-issue — you write the SQL `UPDATE` / `DELETE WHERE id IN (...)` directly. For SwiftData the diff is similar to Core Data but using `FetchDescriptor` + insert/delete on the context.

### Atomicity

A single Repository call should commit or roll back as a unit — no half-saved entities visible to readers. Use the framework primitive:

| Framework | Transaction primitive |
|---|---|
| Core Data | One `performBackgroundTask` block — single `save()` at the end. If it throws, nothing was persisted. |
| SwiftData | `try modelContext.save()` after a series of `insert/delete`. Same all-or-nothing. |
| GRDB | `try dbPool.write { db in ... }` is a single SQL transaction. |
| Realm | `try realm.write { ... }` block. |

**Never** do:

```swift
try ctx.save()             // first save
mapper.attachChild(...)    // do more work
try ctx.save()             // second save  ← intermediate state visible between saves
```

If you need to compose smaller operations into a larger atomic write, use one transaction and call helper functions inside it that take the context/transaction as a parameter.

### Partial updates (delta) vs full writes

For frequently-changing single fields (e.g. `lastViewedAt` ticked on every screen open), do a targeted update — don't round-trip the whole aggregate:

```swift
func touchLastViewed(id: Item.ID, at date: Date) async throws {
    try await container.performBackgroundTask { ctx in
        let req = ItemEntity.fetchRequest()
        req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        req.fetchLimit = 1
        guard let entity = try ctx.fetch(req).first else { return }
        entity.lastViewedAt = date
        try ctx.save()
    }
}
```

This is faster (no mapping of unchanged fields) and **avoids accidental rollback of concurrent edits** — full upsert of a stale snapshot can clobber another writer's concurrent change to a different field.

For GRDB use `UPDATE ... SET column = ?`. For SwiftData mutate the property on the fetched `@Model` and call `save()`.

### Batch writes

Bulk inserts/updates (sync from server, import) need batching to keep memory bounded and progress visible:

```swift
func upsertMany(_ items: [Item], batchSize: Int = 200) async throws {
    for chunk in items.chunked(into: batchSize) {
        try await container.performBackgroundTask { ctx in
            for item in chunk {
                let entity = try fetchOrCreate(id: item.id, in: ctx)
                fill(entity, from: item)
            }
            try ctx.save()
            ctx.refreshAllObjects()    // free memory between batches
        }
    }
}
```

GRDB has `try Item.insertMany(db, ...)`. Core Data has `NSBatchInsertRequest` / `NSBatchUpdateRequest` — fast, but they bypass the validation/derived-attribute path; use only for cold imports.

### `delete` and cascade

Cascade rules belong in the **schema**, not in the Repository:

- Core Data: set `Delete Rule = Cascade` on the relationship in the model editor. Then `ctx.delete(parent)` automatically removes children.
- SwiftData: `@Relationship(deleteRule: .cascade)`.
- GRDB: `ON DELETE CASCADE` in the foreign-key declaration.
- Realm: cascade is manual — use `List` and delete children explicitly inside the write block.

Repository method stays trivial:

```swift
func delete(id: Item.ID) async throws {
    try await container.performBackgroundTask { ctx in
        let req = ItemEntity.fetchRequest()
        req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        for entity in try ctx.fetch(req) { ctx.delete(entity) }
        try ctx.save()
    }
}
```

For synced data prefer **soft delete** — see *Schema Design / Soft delete*.

### Optimistic concurrency

If two devices (or two screens) can edit the same record, naïve last-write-wins silently loses data. Add a `version: Int` field, bump it inside the same transaction as the upsert, throw `RepositoryError.conflict` on mismatch:

```swift
if let existing = try ctx.fetch(req).first {
    guard existing.version == item.expectedVersion else {
        throw RepositoryError.conflict(stored: existing.version, attempted: item.expectedVersion)
    }
    Self.fill(existing, from: item)
    existing.version += 1
} else {
    let new = ItemEntity(context: ctx)
    Self.fill(new, from: item)
    new.version = 1
}
try ctx.save()
```

ViewModel handles `RepositoryError.conflict` by re-fetching and prompting the user (or by merging). See `error-architecture` for the conflict → `UserMessage` mapping.

### Anti-pattern: silent write failure

Often hidden in async wrappers:

```swift
// ❌ DANGEROUS
func save(_ project: Project) throws {
    dataStack.perform(asynchronous: { tx in
        // ... do save work ...
    }, completion: { _ in })          // ← result ignored
}
```

The function is declared `throws` but **cannot actually throw**, because the work runs on a different thread after the function has already returned. Any error inside is dropped. The UI shows «Saved!», the disk shows nothing.

Fix: bridge to async/await with `withCheckedThrowingContinuation`, or use the framework's synchronous variant if a brief block is acceptable, or expose `async throws` instead of fake `throws`:

```swift
func save(_ project: Project) async throws {
    try await withCheckedThrowingContinuation { cont in
        dataStack.perform(asynchronous: { tx in
            // ... do save work ...
        }, completion: { result in
            switch result {
            case .success:        cont.resume()
            case .failure(let e): cont.resume(throwing: e)
            }
        })
    }
}
```

## Querying and Reactivity

Lists in modern apps are reactive: when data changes, UI updates without manual refresh. Each framework has a primitive for this.

| Framework | Reactive primitive | Notes |
|---|---|---|
| Core Data | `NSFetchedResultsController` (UIKit), `@FetchRequest` (SwiftUI) | Old, battle-tested. Bridges to Combine via `objectWillChange` or custom publisher. |
| SwiftData | `@Query` (SwiftUI), `FetchDescriptor` (manual) | `@Query` re-fires on any change to the model — fine for lists, wasteful for detail screens. |
| GRDB | `ValueObservation` | Returns `AsyncValueObservation` or Combine `Publisher`. Diff-aware. |
| Realm | Live results + `Results.observe(_:)` | Thread-confined; freeze for cross-thread. |

Wrap the framework primitive behind a Repository method that returns `AsyncStream<[Item]>` or `AnyPublisher<[Item], Error>` — same Domain types, framework hidden.

```swift
extension GRDBItemRepository {
    func observe(filter: ItemFilter) -> AsyncStream<[Item]> {
        AsyncStream { continuation in
            let observation = ValueObservation.tracking { db in
                try ItemRecord
                    .filter(filter.gdrbPredicate)
                    .fetchAll(db)
            }
            let cancellable = observation.start(in: dbPool) { error in
                continuation.finish()
            } onChange: { records in
                continuation.yield(records.map(Self.toDomain))
            }
            continuation.onTermination = { _ in cancellable.cancel() }
        }
    }
}
```

ViewModel consumes the stream; never knows GRDB exists.

For SwiftUI + Core Data, `@FetchRequest` is the analogue of SwiftData's `@Query`:

```swift
struct ItemList: View {
    @FetchRequest(sortDescriptors: [SortDescriptor(\.createdAt)])
    var items: FetchedResults<ItemEntity>

    var body: some View { ... }
}
```

Same caveat: re-fires on any change to the entity type — fine for lists, wasteful for detail screens.

> **Spotlight integration:** Core Data has `NSCoreDataCoreSpotlightDelegate` that mirrors entities into the system-wide search index. Configure it on the store description; opt-in only for entities the user might actually search (titles, names — not raw foreign keys).
>
> **Cross-process / multi-coordinator change notifications:** standard `NSManagedObjectContextDidSave` / `ObjectsDidChange` only fire within one coordinator instance. For cross-process notifications, see *Persistent History Tracking*.

## Migrations

Apps live for years. Schema changes are not optional — plan for them on day one.

### Core Data — lightweight vs heavyweight

**Lightweight** (free, automatic) supports:
- Adding/removing optional attributes
- Renaming via «Renaming Identifier» in the model editor
- Adding/removing relationships
- Changing optional ↔ default value

Set both flags when constructing the container:

```swift
let description = container.persistentStoreDescriptions.first!
description.shouldMigrateStoreAutomatically = true
description.shouldInferMappingModelAutomatically = true
```

**Heavyweight** is needed for any change lightweight inference can't figure out:

- Split entity (one `Person` → `User` + `Profile`).
- Merge entities (`HomeAddress` + `WorkAddress` → `Address` with `kind`).
- Type change requiring conversion (`String` storing ISO date → `Date`).
- Polymorphic split (one entity with `kind` enum → 4 entities, or vice versa).
- Computed defaults from existing data (set `displayName` from `firstName + lastName`).
- Renaming an entity (renaming an attribute is lightweight via «Renaming Identifier»).

#### Step-by-step

1. **Add a new model version**: in Xcode select `.xcdatamodeld` → `Editor → Add Model Version` → make it current via the file inspector.
2. **Create a Mapping Model**: `File → New → Mapping Model`, pick source and destination versions. Xcode infers what it can. For each entity that needs custom logic — change its `Custom Policy` to your `NSEntityMigrationPolicy` subclass.
3. **Write the policy** (only for entities that need it):

```swift
final class PersonToUserAndProfilePolicy: NSEntityMigrationPolicy {
    override func createDestinationInstances(forSource sInstance: NSManagedObject,
                                             in mapping: NSEntityMapping,
                                             manager: NSMigrationManager) throws {
        let ctx = manager.destinationContext
        let user = NSEntityDescription.insertNewObject(forEntityName: "User", into: ctx)
        user.setValue(sInstance.value(forKey: "id"), forKey: "id")
        user.setValue(sInstance.value(forKey: "email"), forKey: "email")

        let profile = NSEntityDescription.insertNewObject(forEntityName: "Profile", into: ctx)
        profile.setValue(sInstance.value(forKey: "firstName"), forKey: "firstName")
        profile.setValue(sInstance.value(forKey: "lastName"), forKey: "lastName")
        profile.setValue(user, forKey: "owner")

        manager.associate(sourceInstance: sInstance, withDestinationInstance: user, for: mapping)
    }
}
```

Other override hooks: `endInstanceCreation` (after all create-passes complete), `endRelationshipCreation` (relationships in place), `performCustomValidation` (final sanity check). `manager.userInfo` carries state between hooks.

4. **CRITICAL: turn off automatic inference for heavyweight stores**:

```swift
description.shouldMigrateStoreAutomatically = true
description.shouldInferMappingModelAutomatically = false   // ← false, not true
```

If you leave this `true` with a heavyweight change in the model, Core Data will *attempt* to infer, fail silently or produce broken data, and won't pick up your mapping model. This is one of the most common ways heavyweight migrations «just don't run».

5. **Backup the store before migrating** (see *Long migrations* below).
6. **Test against a fixture** (see *Testing / Migration tests*).

### SwiftData — VersionedSchema + MigrationPlan

Two stage types:

- `.lightweight(fromVersion:toVersion:)` — additive changes, automatic.
- `.custom(fromVersion:toVersion:willMigrate:didMigrate:)` — heavyweight: split, merge, value transform, computed defaults.

```swift
enum SchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] { [PersonV1.self] }

    @Model final class PersonV1 {
        var firstName: String = ""
        var lastName: String = ""
        var email: String = ""
    }
}

enum SchemaV2: VersionedSchema {
    static var versionIdentifier = Schema.Version(2, 0, 0)
    static var models: [any PersistentModel.Type] { [UserV2.self, ProfileV2.self] }

    @Model final class UserV2 { ... }
    @Model final class ProfileV2 { ... }
}

enum AppMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [SchemaV1.self, SchemaV2.self] }
    static var stages: [MigrationStage] { [v1ToV2] }

    static let v1ToV2 = MigrationStage.custom(
        fromVersion: SchemaV1.self,
        toVersion: SchemaV2.self,
        willMigrate: { ctx in
            // Read old V1 instances; snapshot what you need.
            // ctx here speaks SchemaV1 — old @Models are visible.
        },
        didMigrate: { ctx in
            // V2 schema is now active. Build V2 instances from the snapshot.
            // For pure backfill of new fields, only didMigrate is needed.
        }
    )
}
```

**The trick:** during `willMigrate` the context speaks the **old** schema (V1 models accessible); during `didMigrate` it speaks the **new** one (V2 models accessible). For split/merge, capture the source data in `willMigrate`, materialise V2 instances in `didMigrate`. For pure additive backfill — only `didMigrate`.

### GRDB — DatabaseMigrator

```swift
var migrator = DatabaseMigrator()

migrator.registerMigration("v1_create_items") { db in
    try db.create(table: "item") { t in
        t.column("id", .text).primaryKey()
        t.column("title", .text).notNull()
        t.column("createdAt", .datetime).notNull()
    }
}

migrator.registerMigration("v2_add_isArchived") { db in
    try db.alter(table: "item") { t in
        t.add(column: "isArchived", .boolean).notNull().defaults(to: false)
    }
}

try migrator.migrate(dbPool)
```

Each migration is named, ordered, and runs exactly once per database. Never edit a shipped migration — add a new one.

### Realm — migration block

```swift
let config = Realm.Configuration(
    schemaVersion: 2,
    migrationBlock: { migration, oldVersion in
        if oldVersion < 2 {
            migration.enumerateObjects(ofType: "Item") { _, new in
                new?["isArchived"] = false
            }
        }
    }
)
```

### Migrating transformable Codable payloads

A category that standard migration mechanics do **not** cover: an entity has an attribute `payload: Data` that holds JSON-encoded Codable. The Codable struct evolves between releases. Core Data / SwiftData / GRDB don't see inside the blob — to them the column type didn't change. A naïve `JSONDecoder().decode(NewPayload.self, from: oldData)` throws on the first old row.

This is a separate axis of migration, layered on top of schema migration. Four approaches, choose by situation:

#### Approach 1 — Evolutionary Codable (prevention)

Best when applicable. Design Codable so **new versions read old payloads without migration**:

- New fields only `Optional` or with a default via custom `init(from:)`.
- Never **rename** a field (use `CodingKeys` aliases if forced).
- Never **change a field's type** (extend variants, don't replace).
- Never **delete** a field (deprecate, leave for decoding).
- Embed `version: Int` inside the payload as a safety net.
- **Snapshot-test the JSON form** of every released version — see *Testing / Snapshot tests for transformable Codable payloads*.

```swift
struct Payload: Codable {
    var a: String
    var b: Int
    var c: String        // ← added in v2

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        a = try c.decode(String.self, forKey: .a)
        b = try c.decode(Int.self, forKey: .b)
        self.c = try c.decodeIfPresent(String.self, forKey: .c) ?? "default"
    }
}
```

If discipline holds — **no blob migration is ever needed**.

#### Approach 2 — Lazy migration on read

When a real breaking change is already in flight (rename, restructure, derive a field) and you don't want a heavyweight Core Data migration just for the blob:

- Custom `init(from:)` recognises **both** old and new shapes, converts on decode.
- On the next save, the entity's payload is written in the new shape («lazy backfill»).

```swift
struct PayloadV2: Codable {
    var fullName: String       // was: firstName + lastName

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let combined = try c.decodeIfPresent(String.self, forKey: .fullName) {
            fullName = combined
        } else {
            let first = try c.decode(String.self, forKey: .firstName)
            let last  = try c.decode(String.self, forKey: .lastName)
            fullName = "\(first) \(last)"
        }
    }
}
```

**Trade-offs.** Old shapes linger on disk until each row is saved — no index, no query can find values that haven't been backfilled. Custom `init(from:)` grows over time (v1 + v2 + v3 + …); deleting old branches is hard because some users are still on v1.

#### Approach 3 — Proactive rewrite inside the schema migration

When you need a hard guarantee that **all rows** are on the new payload shape — typically because a payload field is being promoted to an indexed/queryable column.

The blob conversion lives inside the heavyweight Core Data policy / SwiftData `MigrationStage.custom.didMigrate` / GRDB migration block. Even if the Core Data entity structure didn't formally change, the blob change forces you onto the heavyweight path:

```swift
final class ItemPayloadV1ToV2Policy: NSEntityMigrationPolicy {
    override func createDestinationInstances(forSource sInstance: NSManagedObject,
                                             in mapping: NSEntityMapping,
                                             manager: NSMigrationManager) throws {
        let oldData = sInstance.value(forKey: "payload") as! Data
        let oldPayload = try JSONDecoder().decode(PayloadV1.self, from: oldData)
        let newPayload = PayloadV2(
            a: oldPayload.a,
            b: oldPayload.b,
            fullName: "\(oldPayload.firstName) \(oldPayload.lastName)"
        )
        let newData = try JSONEncoder().encode(newPayload)

        let dInstance = NSEntityDescription.insertNewObject(
            forEntityName: "Item", into: manager.destinationContext)
        dInstance.setValue(sInstance.value(forKey: "id"), forKey: "id")
        dInstance.setValue(newData, forKey: "payload")
        manager.associate(sourceInstance: sInstance,
                          withDestinationInstance: dInstance,
                          for: mapping)
    }
}
```

GRDB equivalent is plain SQL: `SELECT id, payload FROM item` → decode old → encode new → `UPDATE item SET payload = ? WHERE id = ?` inside a single `db.write` block.

#### Approach 4 — Versioned envelope from the start

For projects where the blob holds an evolving business model (editor snapshots, document state, complex configs) — wrap every payload in an envelope with an explicit version:

```swift
struct PayloadEnvelope: Codable {
    let version: Int
    let payload: Data       // raw, decoded based on version
}

enum AnyPayload {
    case v1(PayloadV1), v2(PayloadV2), v3(PayloadV3)

    init(envelopeData: Data) throws {
        let env = try JSONDecoder().decode(PayloadEnvelope.self, from: envelopeData)
        switch env.version {
        case 1: self = .v1(try JSONDecoder().decode(PayloadV1.self, from: env.payload))
        case 2: self = .v2(try JSONDecoder().decode(PayloadV2.self, from: env.payload))
        case 3: self = .v3(try JSONDecoder().decode(PayloadV3.self, from: env.payload))
        default: throw PayloadError.unknownVersion(env.version)
        }
    }
}
```

Plus mappers V1→V2, V2→V3 composed into `migrate(to: .vCurrent)`. Trivial to unit-test, easy to reason about chains. Cost: extra decode layer on every read; introducing it later requires a one-time wrap-existing-data migration.

#### Choosing

| Situation | Approach |
|---|---|
| Changes are small (additions, optional fields), team can hold convention rules | **1** — evolutionary Codable + snapshot tests |
| Breaking change already done, want to avoid a heavyweight schema migration | **2** — lazy on read |
| All rows must be on the new shape (field is being indexed / queried) | **3** — proactive rewrite inside heavyweight migration |
| New project, blob holds an evolving business model | **4** — versioned envelope from day one |

Common combination: Approach 1 by default, Approach 3 for breaking changes that need full conversion.

#### What NOT to do

- **`try?` on decode + a fallback default** — silent data loss; you'll discover it months later when a user asks why their old projects are blank.
- **`catch { ctx.delete(entity); save() }`** — actively destroys data.
- **Changing a Codable struct without checking** for legacy payloads on disk.
- **Removing old `PayloadV1` types** before all users have rolled forward (breaks Approaches 2 and 4).
- **Trusting that lightweight schema migration «does something»** to the blob — it does literally nothing.

### Progressive migration — v1 → v2 → v3 → … → current

The most common production migration disaster: you assume everyone is on v(current-1) and write a single mapping model from there. In reality, your users are on **all past versions** — someone hasn't opened the app in a year and is still on v1. A direct v1→v5 mapping model rarely exists; even if you write one, you've doubled the surface area.

**Right approach: chain.** Each migration goes from version N to N+1. Multi-version users walk the chain step by step.

Per framework:

| Framework | Chain mechanics |
|---|---|
| Core Data | One mapping model per **adjacent** pair (v1→v2, v2→v3, …). Detect current store version via `NSPersistentStoreCoordinator.metadataForPersistentStore`, find the path, run each step manually with `NSMigrationManager`. Ship one helper that owns this loop. |
| SwiftData | Add adjacent stages to `MigrationPlan.stages` in order. SwiftData walks them automatically when opening an old store. |
| GRDB | Bread-and-butter case: `DatabaseMigrator` already tracks which named migrations have been applied; missing ones run in registration order. Free progressive migration. |
| Realm | The migration block receives `oldVersion`; you write `if oldVersion < 2 { ... } if oldVersion < 3 { ... }` cumulatively. |

Core Data «manual chain» pattern:

```swift
func migrateStoreIfNeeded(at storeURL: URL) throws {
    let metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(
        type: .sqlite, at: storeURL)

    let modelVersions: [NSManagedObjectModel] = [.v1, .v2, .v3, .v4]   // ordered
    guard let startIndex = modelVersions.firstIndex(where: { $0.isConfiguration(withName: nil, compatibleWith: metadata) }) else {
        throw MigrationError.unknownSourceVersion
    }
    guard startIndex < modelVersions.count - 1 else { return }   // already current

    var currentURL = storeURL
    for i in startIndex..<(modelVersions.count - 1) {
        let from = modelVersions[i]
        let to = modelVersions[i + 1]
        let mapping = try mappingModel(from: from, to: to)        // adjacent pair
        let intermediateURL = tmpDir.appendingPathComponent("step-\(i).sqlite")

        let manager = NSMigrationManager(sourceModel: from, destinationModel: to)
        try manager.migrateStore(from: currentURL, type: .sqlite, mapping: mapping,
                                 to: intermediateURL, type: .sqlite)
        currentURL = intermediateURL
    }

    try FileManager.default.replaceItem(at: storeURL, withItemAt: currentURL, ...)
}
```

**Anti-pattern: one mega mapping model v1→vCurrent.** Looks economical (only one file), breaks every user who isn't exactly on v(current-1). Always adjacent pairs.

**Anti-pattern: deleting old model versions to «clean up».** Once a model version shipped, it stays in `.xcdatamodeld` forever. Removing it breaks all users still on that version.

### Long migrations — UX and performance

Heavyweight migration loads source instances into memory and creates destination ones. For 50K+ records on mobile this can take **tens of seconds to minutes**, during which:

- The app appears frozen if you migrate on the launch path with no UI.
- iOS may kill the process if migration runs from a background launch (push, background fetch).
- A foreground crash in the middle leaves you with a half-baked store on next launch.

What to do:

- **Show a migration UI.** A dedicated launch screen («Updating your library… N of M»). KVO-observe `NSMigrationManager.migrationProgress` (0.0–1.0) for Core Data; for SwiftData/GRDB you wrap the call yourself with progress reporting.
- **Run on the foreground launch path, not background.** Detect `UIApplication.shared.applicationState == .background` and **defer migration to the next foreground launch** — back out cleanly, don't risk the process kill.
- **Backup first, atomically replace on success:**

  ```swift
  let backup = storeURL.appendingPathExtension("bak.\(Int(Date().timeIntervalSince1970))")
  try FileManager.default.copyItem(at: storeURL, to: backup)
  do {
      try migrateStoreIfNeeded(at: storeURL)
      try FileManager.default.removeItem(at: backup)
  } catch {
      // store is still partially migrated — restore from backup
      try? FileManager.default.removeItem(at: storeURL)
      try FileManager.default.moveItem(at: backup, to: storeURL)
      throw MigrationError.failed(underlying: error, backupRestoredAt: storeURL)
  }
  ```

  This is the **single canonical backup pattern** for the skill — every other section refers back here.

- **Set `description.shouldAddStoreAsynchronously = true`** for Core Data when you need to keep the launch responsive (the `loadPersistentStores` callback fires on a background queue). The migration itself still runs serially — but the main thread isn't blocked while it does.
- **Skip-the-shore option for very large stores:** if the migration is too long to be reasonable, ship the new app with the **old schema still readable** for a release or two, and migrate lazily (one row per access) or in background batches. Cost: complexity in repository code that handles both schemas.

### Failure recovery — what to show the user

Heavyweight migration **will** fail in production. Disk pressure, OOM kill, corrupted store from a previous crash, mapping model bug that escaped tests. Plan it like network failure:

- **Don't silently delete the store.** `try fs.remove(dbURL); try migrate(emptyStore)` looks like recovery, actually it's data loss.
- **Persist the backup.** The backup file from *Long migrations* becomes the user's only recovery path.
- **Surface a typed error to the UI.** `MigrationFailure(fromVersion:, toVersion:, underlying:, backupURL:)` — the presentation layer decides what to show.
- **Three-button dialog** is the usual UX:
  1. **Retry** — useful if the failure was transient (low disk, low memory).
  2. **Send report** — package the backup file + last log + version metadata, send to support. Don't auto-upload PII without consent.
  3. **Start fresh** — delete the broken store, start with empty DB, but **keep the backup** so the user can recover later if support helps.
- **Telemetry**: from-version / to-version / duration / error-domain / error-code / available-disk / memory-pressure-at-failure → SwiftyBeaver / Firebase non-fatal / your stack. Without this you don't know that 0.4% of users on v3→v4 fail with `disk full`.

### Migration discipline (any framework)

1. **Schema version is checked into git.** Never edit a shipped schema in place.
2. **Never edit a shipped migration.** Once a migration ran on a user's device, it's frozen. New corrections go in a **new** migration.
3. **Adjacent pairs only.** No mega mapping models from version N to current — see *Progressive migration*.
4. **Every migration has a fixture test** — see *Testing / Migration tests*.
5. **Backup before any heavyweight or chained migration** — see *Long migrations*.
6. **Telemetry on every migration outcome** — see *Failure recovery*. Migration failures in the wild are silent without it.
7. **Plan a recovery path explicitly** — what does the user see if migration fails? Does «Start fresh» still leave them with a useful app, or is the data the entire app? If data is unrecoverable without the server, document the dependency.
8. **Run migration on the foreground launch path.** Defer if launched in background.

## CloudKit and Sync

When data must follow the user across devices, you have three choices:

| Option | When |
|---|---|
| `NSPersistentCloudKitContainer` (Core Data + CloudKit) | Apple-only, want zero backend, willing to live with CloudKit's quirks (slow first sync, schema deploys via Xcode) |
| SwiftData + CloudKit | iOS 17+ greenfield; same trade-offs as above, less mature |
| Custom sync (server + GRDB/SQLite) | Cross-platform, want push-based delta sync, willing to write conflict resolution |

**Conflict resolution** must be explicit:
- **Last-write-wins** — simple, loses data. OK for low-stakes (preferences, caches).
- **Per-field merge** — keep both sides where they don't conflict. Requires field-level `updatedAt`.
- **CRDT** — operational, complex. Worth it for collaborative editing.

CloudKit-specific: handle `CKError.quotaExceeded`, `CKError.networkUnavailable`, `CKError.zoneBusy` explicitly. Show a sync-status indicator; never silently fail.

### Schema constraints under NSPersistentCloudKitContainer

CloudKit imposes hard schema rules on top of Core Data. Violate them and the store «works» locally but never syncs. The constraints, in priority order:

- **All attributes optional or with a default value.** CloudKit's eventual-consistency model can't accept «required» — newly synced records may arrive partial.
- **All relationships must have an inverse.** Even if you logically don't need one. No exceptions.
- **No `Unique` constraints** in the model editor. CloudKit can't enforce them across devices.
- **Entity and attribute names cannot start with `CD_`** — that prefix is reserved for CloudKit's internal mirror.
- **Cannot use `Undefined` attribute type.** Each attribute must have a concrete type.
- **`Transformable` attributes must use `NSSecureUnarchiveFromData`** transformer.
- **Persistent History Tracking is mandatory** — see the dedicated section.

Violations don't fail loudly — `loadPersistentStores` succeeds, but the next sync attempt is silently broken. Test it explicitly in CI:

```swift
#if DEBUG
try container.initializeCloudKitSchema(options: [.dryRun])
#endif
```

This validates the schema against CloudKit's rules without actually deploying it.

## Caching: Persistence as a Cache

A common pattern: remote API + local persistence as cache. Two architectures:

**Read-through cache** — Repository tries cache first, falls back to network, populates cache.

```swift
func fetch(id: Item.ID) async throws -> Item {
    if let cached = try await store.fetch(id: id), !cached.isStale {
        return cached
    }
    let fresh = try await api.fetch(id: id)
    try await store.upsert(fresh)
    return fresh
}
```

**Cache + observe** — Repository always returns the cache (possibly stale), and triggers a background refresh that updates the cache, which the observer sees.

```swift
func observe(id: Item.ID) -> AsyncStream<Item> {
    Task { try? await refresh(id: id) }   // fire-and-forget refresh
    return store.observe(id: id)          // UI sees cached data immediately
}
```

**TTL / invalidation** — store `fetchedAt: Date` on the cached entity. Stale = `Date.now - fetchedAt > ttl`. Invalidate on logout, on user-triggered pull-to-refresh, on push notification of a server-side change.

See `net-architecture` for HTTP-level caching (`Cache-Control`, `ETag`) — that's a separate layer that complements persistence-level caching.

## Encryption and File Protection

By default, iOS encrypts files when the device is locked (`NSFileProtectionCompleteUntilFirstUserAuthentication`). For sensitive data, raise the bar:

- **`NSFileProtectionComplete`** — file unreadable when device is locked. Set on the persistent store file:

  ```swift
  try (storeURL as NSURL).setResourceValue(
      URLFileProtection.complete,
      forKey: .fileProtectionKey
  )
  ```

- **Keychain for keys, encryption library for data** — if you need at-rest encryption above iOS defaults, use SQLCipher (with GRDB) or a Realm encryption key stored in Keychain.
- **Never store secrets in Core Data / SwiftData / SQLite without encryption** — the file is readable by anyone with filesystem access (jailbroken device, backup).
- **Keychain access control** — `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` prevents iCloud sync of the key. See `swift-security` skill / agent.

## Dependency Injection

Persistence stack is **process-wide singleton scope**. Bootstrap once in Composition Root. The next decision — what exactly you put into DI: the raw framework container, or a thin facade.

### Pattern A — Container directly in DI

```swift
container.register(NSPersistentContainer.self) { _ in
    let c = NSPersistentContainer(name: "Model")
    c.loadPersistentStores { _, _ in }
    return c
}.inObjectScope(.container)

container.register(ItemRepository.self) { r in
    CoreDataItemRepository(container: r.resolve(NSPersistentContainer.self)!)
}
```

**Use when:** one container, one or two Repositories, simple bootstrap. The Repository is the only consumer and already isolates the framework (returns Domain types, never leaks `NSManagedObject`). One point of contact with the framework — encapsulation already achieved.

### Pattern B — `PersistenceStack` facade

```swift
final class PersistenceStack {
    private let container: NSPersistentContainer

    init(location: StoreLocation) {
        container = NSPersistentContainer(name: "Model")
        configureLocation(location)
    }

    func warmUp() async throws {
        try await container.loadPersistentStoresAsync()
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }

    var viewContext: NSManagedObjectContext { container.viewContext }
    func performBackgroundTask<T>(_ block: @escaping (NSManagedObjectContext) throws -> T) async throws -> T { ... }
}

container.register(PersistenceStack.self) { _ in
    PersistenceStack(location: .disk(Self.dbURL))
}.inObjectScope(.container)

container.register(ItemRepository.self) { r in
    CoreDataItemRepository(stack: r.resolve(PersistenceStack.self)!)
}
```

The facade owns lifecycle and startup configuration. The container still surfaces through `viewContext` / `performBackgroundTask` — **deliberately**, because the difference between «main context» and «background context» is part of the contract, not an implementation detail.

**Use when:**

- Multiple Repositories share one container — single place for merge policy, retention, warm-up coordination.
- Async bootstrap is non-trivial: migrations, indexes, restore-from-backup, telemetry. `try await stack.warmUp()` is an explicit step in Composition Root, before any Repository resolves.
- Multiple stores under one lifecycle (Core Data + Keychain + GRDB grouped in one «persistence layer»).
- Centralised telemetry (transaction duration, rollback frequency) or error wrapping.
- Tests: `PersistenceStack(location: .inMemory)` vs `.disk(URL)` — one parameter switches the mode app-wide.

### Anti-pattern: «universal storage facade»

The temptation to hide the framework completely:

```swift
// ❌
protocol Storage {
    func read<T>(_ block: (Reader) throws -> T) async throws -> T
    func write<T>(_ block: (Writer) throws -> T) async throws -> T
}
```

Looks clean. The reason it isn't: **the facade hides the framework's API, but cannot hide its access rules — and the rules leak out as runtime crashes.**

Concrete failure mode:

```swift
let item = try await storage.read { try fetchItem(id: id) }   // returns NSManagedObject
await someOtherWork()
print(item.title)                                              // 💥 NSObjectInaccessibleException
```

The caller did everything right by the contract they saw — `read` returned a value, they used it. The actual Core Data rule («the value is valid only inside the context block») was hidden by the facade but didn't go away. Same shape with Realm (live object thread-confined), with SwiftData (`@Model` instance isolated to its context).

You can't fix this inside the facade:

- Return only value-type snapshots from `read` → the facade is doing mapping, which is what Repository exists for.
- Forbid escaping the value from the block → not expressible in the Swift type system.
- Document the rule → you didn't hide the framework, you only renamed it.

Other things that don't actually abstract:

- **Errors are framework-shaped.** Core Data merge conflicts vs SQLite error codes vs Realm `Error` enum — collapse them into one `StorageError` and you lose «which constraint»; pass them raw and the caller has to know the framework anyway.
- **Cancellation behaviour differs.** Core Data `performBackgroundTask` ignores `Task.cancel()`; GRDB rolls back on throw; Realm has no async cancellation. A single «write semantics» is fiction.
- **The promised swap doesn't happen.** Migrating Core Data → GRDB rewrites every query, every record type, every observation, every migration script. The `read/write` facade saves zero lines — every block body changes.

«I'll hide the framework behind a universal facade so it's easy to swap later» is **YAGNI with a negative**: cost paid today (extra layer, extra docs, hidden invariants leaking as crashes), benefit hypothetical, and at the moment of the hypothetical migration the facade doesn't actually save you.

### What vs how — the formula

The boundary that works: Repository abstracts **what** is stored (`fetch(id:) -> Item`, where `Item` is a value-type snapshot). The boundary that doesn't: a generic facade abstracts **how** to read and write — but cannot abstract the rules around the values it returns. So:

> Hiding the **lifecycle** of a framework is useful (`PersistenceStack`).
> Hiding the **API** of a framework is dishonest (`Storage` with universal `read/write`).
> Hiding the **what is stored** is the goal — and that's `Repository`, which already exists.

### Picking between A and B

| You have | Use |
|---|---|
| 1 container, 1–2 Repositories, simple bootstrap | Pattern A (container in DI) |
| Several Repositories, shared configuration (merge policy, telemetry, warm-up) | Pattern B (PersistenceStack facade) |
| Multiple stores under one lifecycle | Pattern B |
| «Want to easily swap Core Data for SwiftData later» | Neither — the difference between them is real, not implementation-level. Migration will rewrite Repositories regardless. |

### Common rules (both patterns)

- **One container per process.** Never `try ModelContainer(...)` inside a Repository factory.
- **Repository scope = `.transient`** if stateful, `.container` if stateless — but the underlying container/stack is always `.container` singleton.
- **In-memory variant for tests** — Composition Root (or `PersistenceStack.init`) accepts a `StoreLocation` parameter (`.disk(URL)` / `.inMemory`). Test setup passes `.inMemory`; the rest of the bootstrap is identical.
- **Async bootstrap explicit in Composition Root.** Warm-up belongs to a `try await stack.warmUp()` step before features resolve — never lazy-on-first-call inside a Repository, where the first user save eats a 3-second migration with no UI feedback.

See `di-composition-root` for the full pattern; `di-module-assembly` for registering Repositories into feature modules.

## Generic Mappers — What's Universal, What Isn't

> **Optional reading.** Skip unless you maintain 10+ entity-pair mappers and are looking for a way to reduce boilerplate.

A recurring question on any project with 10+ entity pairs: *can we write the mapping once, generically?* The honest answer has four levels — only two of them work, and most «generic mapper» attempts in real codebases blur them into a mess.

### Level 1 — Universal contract ✅

One protocol describing «a mapper» in general:

```swift
protocol EntityMapping {
    associatedtype Domain
    associatedtype Entity
    func toDomain(_ entity: Entity) throws -> Domain
    func toEntity(_ model: Domain, in tx: Transaction) throws -> Entity
    func update(_ entity: Entity, from model: Domain, in tx: Transaction) throws
}
```

This is correct and recommended. It gives you:

- a common type for DI / tests / composition,
- compile-time check that all methods are implemented,
- associated types instead of generics — you can't accidentally instantiate `EntityMapping<String, Int>` without conformance.

**But** the body of each conformance — the actual «which field maps where» — is hand-written per pair. The contract is universal; the implementation isn't.

> **Anti-pattern often seen here:** abstract base class with `func toDomain(...) -> Domain { fatalError("must override") }`. The shape is the same as the protocol, but you trade compile-time safety for runtime crashes. Use a protocol.

### Level 2 — Generic helpers for primitive fields ⚠️

`KeyPath`-based copy machinery for plain fields:

```swift
struct FieldCopy<Domain, Entity, Value> {
    let domainKeyPath: WritableKeyPath<Domain, Value>
    let entityKeyPath: ReferenceWritableKeyPath<Entity, Value>
}
```

The idea works for **flat, type-aligned fields**. It breaks down on every realistic Core Data / SwiftData / Realm specifics:

| You want | What stops you |
|---|---|
| `Int → Int32` (Core Data prefers Int32) | Different `Value` types — generic doesn't unify, you need a transformer |
| Enum ↔ String / Int | Per-type transformer |
| One-to-many: `[Track] ↔ NSSet` | Need to call child mapper, then wrap into `NSSet` — generic doesn't express this |
| Transformable attributes (`MediaTime → Data`) | `encode/decode` per type |
| Optional Domain → non-optional Entity | Per-field decision: default? throw? skip? |
| Inverse relationships | Two-sided assignment — generic can't express |

In practice, KeyPath-machinery saves ~10–20% of code in average mappers and adds a new abstraction layer to learn. Worth it only when you have 30+ very flat mappers — not for typical app domains.

### Level 3 — Universal mapping body via Codable / Mirror ❌

«Make Entity also `Codable`, round-trip Domain through `JSONEncoder` → `JSONDecoder`». Tempting; doesn't work for Core Data / Realm / SwiftData:

- `NSManagedObject` isn't naturally `Codable` — writing the encoder *is* writing the mapper.
- Relationships become nested JSON — you can't update an existing entity in place, only recreate (and you've already seen why that's bad — see *Updating child collections*).
- Field names must match byte-for-byte; renames silently break.
- No place for validation, type migration, defaults, derived fields.
- JSON round-trip on every save — performance hit visible at 100+ rows.
- **No diagnostics** — failure surfaces as `DecodingError` deep in the stack with no field context.

`Mirror`-based reflection has the same problems plus weaker type safety and no `@Codable`-style derivation help.

### Level 4 — Codegen or Swift macros ✅

This is the modern answer when manual mapping pain is real and recurring. Annotate the snapshot:

```swift
@Mappable(entity: ItemEntity.self, fields: [
    .copy(\.id),
    .copy(\.title),
    .transform(\.startTime, encoder: AttributeConverter.encode, decoder: AttributeConverter.decode),
    .nested(\.location, mapper: LocationMapper.self),
    .collection(\.tracks, on: \.tracks, mapper: TrackMapper.self),
])
struct ItemSnapshot { ... }
```

The macro expands at compile time to a full `toDomain` / `toEntity` / `update` body — type-safe, zero runtime cost, generated code is inspectable. Pre-macro alternative: **Sourcery** (template-based codegen, Stencil files + annotations).

**When this pays off:**

- ≥15 mapper pairs of similar shape, and the count is growing.
- You actively add new entity types (effects, presets, plugins, content types).
- The team owns toolchain choices — adding a build-time generator or macro target is acceptable.

**When NOT to invest in codegen:**

- <10 mappers — manual code is shorter than the macro DSL.
- Mappers have very irregular shapes (each one does something unique) — the macro DSL becomes too rich and you lose readability.
- You're on Swift < 5.9 and don't want to add Sourcery — wait for the macro option.

### Pragmatic Recommendation

| Make generic | Write by hand or generate |
|---|---|
| Mapper **contract** — protocol with associated types | Mapper **bodies** — fields, types, validation |
| Repository **contract** — `protocol XxxRepository` | Type-by-type **dispatch** — never `<M>` + `as!` |
| Storage primitive contract (if needed) | Per-entity Repository |

Two failure modes to watch:

1. **«Universal repository» via runtime type-switch** (`func fetchAll<M>(type: M.Type) -> [M]` with `as! [M]` inside). This isn't generic mapping — it's type-erased dispatch, and it breaks open-closed: every new entity edits the central switch. Replace with **one repository per entity type** behind a typed protocol.

2. **«Generic mapper that does it all» via reflection / Codable.** See Level 3 — the universality you save in code is paid back in lost diagnostics, broken relationships, and silent renames.

If hand-written mappers feel painful at scale, the answer is **codegen / macros (Level 4)** — not «smarter generics» (Levels 2–3).

## Testing

Five layers of tests, in order of how often they run:

### Unit tests — mock the Repository

ViewModels and UseCases depend on `protocol ItemRepository` — pass a `FakeItemRepository` with in-memory dictionary state.

```swift
final class FakeItemRepository: ItemRepository {
    var items: [Item.ID: Item] = [:]
    func fetch(id: Item.ID) async throws -> Item? { items[id] }
    func upsert(_ item: Item) async throws { items[item.id] = item }
    // ...
}
```

### Integration tests — real framework, in-memory store

Test the Repository implementation against a real DB but in-memory:

| Framework | In-memory store |
|---|---|
| Core Data | `NSPersistentStoreDescription(url: URL(fileURLWithPath: "/dev/null"))` + `NSInMemoryStoreType` |
| SwiftData | `ModelConfiguration(isStoredInMemoryOnly: true)` |
| GRDB | `DatabasePool(path: ":memory:")` or `DatabaseQueue()` (no path) |
| Realm | `Realm.Configuration(inMemoryIdentifier: "test-\(UUID())")` |

Each test gets a fresh store — no inter-test pollution.

#### SwiftData testing under @MainActor

SwiftData's `ModelContainer` and `mainContext` are `@MainActor`. Tests that interact with them must be:

```swift
@MainActor
final class ItemRepositoryTests: XCTestCase {
    var container: ModelContainer!
    var sut: SwiftDataItemRepository!

    override func setUp() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: ItemEntity.self, configurations: config)
        sut = SwiftDataItemRepository(modelContainer: container)
    }
    ...
}
```

For testing background actors (`@ModelActor`), test methods are non-isolated by default and `await` into the actor naturally.

### Migration tests

Ship the schema versions of past releases. For each migration:

1. Load a fixture DB at version N (committed in `Tests/Fixtures/v1.sqlite`).
2. Open it with the current schema (triggers migration).
3. Assert: row count preserved, new columns populated correctly, no data loss.

This is the only way to catch heavyweight migration bugs before users hit them.

```swift
func test_migrationFromV1_addsIsArchivedDefaultingFalse() throws {
    let url = copyFixture("items-v1.sqlite")
    let pool = try DatabasePool(path: url.path)
    try ItemMigrator.migrate(pool)
    let items = try pool.read { try ItemRecord.fetchAll($0) }
    XCTAssertEqual(items.count, 100)
    XCTAssertTrue(items.allSatisfy { $0.isArchived == false })
}
```

Generate fixtures **once from the old code** and freeze. Once a fixture is committed for version N, it must never change.

### Snapshot tests for transformable Codable payloads

For any Codable struct stored in a `Data` attribute, freeze the JSON form and assert decode + round-trip on every CI run. This is the only thing that catches accidental schema drift inside blobs (see *Migrations / Migrating transformable Codable payloads*).

```swift
final class PayloadSnapshotTests: XCTestCase {
    func test_payloadV2_decodesFrozenJSON() throws {
        let json = """
        {"a":"hello","b":42,"c":"backfilled"}
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(Payload.self, from: json)
        XCTAssertEqual(decoded.a, "hello")
        XCTAssertEqual(decoded.b, 42)
        XCTAssertEqual(decoded.c, "backfilled")
    }

    func test_payloadV2_roundTripIsStable() throws {
        let original = Payload(a: "hello", b: 42, c: "world")
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys

        let encoded = try encoder.encode(original)
        let decoded = try JSONDecoder().decode(Payload.self, from: encoded)

        XCTAssertEqual(decoded, original)
    }

    func test_payloadV2_decodesV1JSON_withDefaultForNewField() throws {
        let v1JSON = """
        {"a":"hello","b":42}
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(Payload.self, from: v1JSON)
        XCTAssertEqual(decoded.c, "default")    // backfill from custom init
    }
}
```

The third test is the critical one — it pins the contract «v1 payload still decodes», which is what protects users on older versions.

### Concurrency tests

Repository methods that allow concurrent writes need explicit conflict tests:

```swift
func test_concurrentUpsert_oneSucceedsOneConflicts() async throws {
    let id = UUID()
    try await repo.upsert(Item.makeFixture(id: id, title: "original"))   // version=1

    let edit1 = Item.makeFixture(id: id, title: "device A", expectedVersion: 1)
    let edit2 = Item.makeFixture(id: id, title: "device B", expectedVersion: 1)

    async let r1: Void = try repo.upsert(edit1)
    async let r2: Void = try repo.upsert(edit2)

    let outcomes = await [
        Result { try await r1 },
        Result { try await r2 }
    ]

    let successes = outcomes.compactMap { try? $0.get() }
    let conflicts = outcomes.compactMap { result -> Bool? in
        if case .failure(let e as RepositoryError) = result, case .conflict = e { return true }
        return nil
    }

    XCTAssertEqual(successes.count, 1)
    XCTAssertEqual(conflicts.count, 1)
}
```

### Test data builders

For complex Domain types, hand-rolled `Item(...)` constructors in every test get unwieldy. A builder pattern keeps tests focused on the field that matters:

```swift
extension Item {
    static func makeFixture(
        id: UUID = UUID(),
        title: String = "test",
        createdAt: Date = .now,
        updatedAt: Date = .now,
        isArchived: Bool = false
    ) -> Item {
        Item(id: id, title: title, createdAt: createdAt, updatedAt: updatedAt, isArchived: isArchived)
    }
}

func test_archive_setsIsArchived() async throws {
    let item = Item.makeFixture(isArchived: false)   // ← only the relevant field
    try await repo.upsert(item)
    try await sut.archive(id: item.id)
    let reloaded = try await repo.fetch(id: item.id)
    XCTAssertTrue(reloaded?.isArchived == true)
}
```

Default values mean each test mentions only the fields it cares about — readable assertions about behaviour, not setup noise.

## Common Mistakes

Each entry one line + cross-reference to the body section that explains the fix.

1. **Returning `NSManagedObject` / `@Model` / Realm `Object` from Repository** — leaks the framework, thread-confined. See *Repository Boundary*.
2. **One context for reads and writes on the main thread** — UI freezes. See *Threading and Contexts*.
3. **Sharing `NSManagedObject` / Realm object across threads** — silent crashes/corruption. See *Sendable and Swift Concurrency*.
4. **No migration plan from day one** — first user upgrade crashes the app. See *Migrations*.
5. **Editing a shipped migration** — never change a migration that ran on a user's device.
6. **No fixture test for heavyweight migration** — see *Testing / Migration tests*.
7. **No backup before destructive migration** — see *Migrations / Long migrations*.
8. **`UserDefaults` for «real» data** — sync I/O, 4KB practical limit, NOT encrypted. Use Keychain for secrets, a real DB for collections.
9. **Storing PII / tokens unencrypted** — see *Encryption and File Protection*.
10. **`@Query` / `@FetchRequest` in detail screens** — re-renders on any model change. Use manual fetch + `@State`.
11. **Mixing remote and local errors at the Repository boundary** — see `error-architecture`.
12. **Treating CloudKit sync as instant** — first sync can take minutes; show sync-status UI.
13. **No identity strategy** — auto-increment IDs collide on cross-device sync. Use `UUID`.
14. **Hard delete with no audit / sync** — see *Schema Design / Soft delete*.
15. **Loading large blobs into the database** — store as files, keep path in DB.
16. **Fake `throws` over async work** — see *Repository Write Patterns / Anti-pattern: silent write failure*.
17. **Delete-and-recreate children on every parent save** — see *Updating child collections — diff*.
18. **Returning `Optional<Domain>` from a mapper as an error signal** — make mappers `throws` with typed `MappingError(field:, reason:)`.
19. **Mutable shared state inside a mapper** (`var transaction`) — pass context as a parameter to each call.
20. **Auto-deleting the user's database on migration failure** — see *Migrations / Failure recovery*.
21. **`NSPredicate` / `NSSortDescriptor` in the abstract storage protocol** — leaks Core Data; use a domain-level `Filter`.
22. **«Universal storage facade»** — see *Dependency Injection / Anti-pattern*.
23. **Lazy bootstrap inside the first Repository call** — run `try await stack.warmUp()` explicitly in Composition Root.
24. **`shouldInferMappingModelAutomatically = true` with a heavyweight schema change** — see *Migrations / Core Data*.
25. **One mega mapping model from version N to current** — see *Migrations / Progressive migration*.
26. **Running heavyweight migration on background launch** — defer to next foreground launch.
27. **Changing a Codable struct stored in a transformable attribute without a payload-migration plan** — see *Migrations / Migrating transformable Codable payloads*.
28. **DB file in `Documents/`** — backed up to iCloud, eats user quota, visible in Files. Use `Library/Application Support/`. See *Storage Location and Sharing*.
29. **Sharing Core Data between app and Extension without Persistent History Tracking** — extension writes invisible to main app. See *Persistent History Tracking*.
30. **Storing `Date` as locale-formatted `String`** — `DateFormatter` without `.iso8601` is locale-dependent; user travelling between locales gets garbled timestamps. Use `Date` natively or `ISO8601DateFormatter`.
31. **Domain model with non-Sendable types (`UIImage`, `NSAttributedString`)** — Swift 6 rejects, or silently passes corrupt data across actors. Store as `Data` / `URL` and convert at the UI layer. See *Sendable and Swift Concurrency*.
32. **CloudKit-incompatible schema** (required attributes without defaults, missing inverse relationships, `Unique` constraints) — local store works, sync silently broken. See *CloudKit / Schema constraints*.
