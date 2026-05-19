---
name: persistence-architecture
description: "Use when designing local data storage in an iOS app — choosing between Core Data, SwiftData, GRDB/SQLite, Realm, UserDefaults, file storage; Repository as the boundary that hides the framework; background contexts and threading; reactive queries; write patterns and conflict handling; CloudKit sync; encryption / file protection; in-memory testing strategies. For schema migrations see `persistence-migrations`."
---

# Persistence Architecture

Design the local data layer: where data lives, how it survives app launches, and
how the rest of the app talks to it. This is an architecture skill, not a Core
Data tutorial.

Detailed examples and framework-specific code live in
`references/detailed-guide.md`. Load that reference only for the section you
need; use `rg -n "^## "` or the section names below.

## When To Load The Reference

Read `references/detailed-guide.md` selectively:

| Need | Reference sections |
|---|---|
| Pick Core Data / SwiftData / GRDB / Realm / files | `Choosing the Framework`, `Storage Location and Sharing` |
| Model identities, timestamps, soft deletes, transformable values | `Schema Design` |
| Write repository implementations | `The Repository Boundary`, `Threading and Contexts`, `Sendable and Swift Concurrency` |
| Design transactions, child collection updates, conflicts | `Repository Write Patterns` |
| Add observations / reactive lists | `Querying and Reactivity` |
| Plan migrations | `Migrations`; then switch to `persistence-migrations` |
| Add CloudKit / offline sync | `CloudKit and Sync`, `Persistent History Tracking (Core Data)` |
| Protect sensitive local data | `Encryption and File Protection` |
| Wire persistence into DI | `Dependency Injection` |
| Reduce mapper boilerplate | `Generic Mappers — What's Universal, What Isn't` |
| Test repositories and concurrency | `Testing` |

## Core Decision

Use a Repository boundary:

```
View / ViewModel
      |
      v
Repository (Domain in/out, persistence framework hidden)
      |
      v
Storage primitive (NSPersistentContainer / ModelContainer / DatabasePool / Realm)
      |
      v
Disk
```

Rules:

- ViewModels and UseCases import Domain types only. They do not import CoreData,
  SwiftData, GRDB, or Realm.
- Repositories return Domain value snapshots (`struct`, `Sendable`), not
  `NSManagedObject`, `@Model`, Realm `Object`, or SQL records.
- The persistence layer owns mapping, threading/context rules, and error
  mapping.
- The container/pool is created once in the Composition Root and registered as a
  process-wide singleton.
- Framework-specific objects never cross actor/thread boundaries. Pass IDs
  (`NSManagedObjectID`, `PersistentIdentifier`, UUID/server ID) or Domain
  snapshots.

## Framework Choice

Pick the framework by data shape and access pattern:

- Core Data: large relational graph, iOS 13+, CloudKit integration, mature
  tooling.
- SwiftData: iOS 17+ SwiftUI greenfield, simple-to-medium model, acceptable
  newer-tooling risk.
- GRDB/SQLite: performance, explicit SQL, complex queries, precise migration
  control, custom sync.
- Realm: mostly existing projects or cross-platform/Atlas commitments; be strict
  about live-object thread confinement.
- UserDefaults: small preferences and flags only.
- Files: user-owned documents, media, attachments, exports.
- Keychain: tokens, secrets, encryption keys.

Mixing stores is normal: database for records, files for blobs, UserDefaults for
flags, Keychain for secrets.

## Schema Rules

- Use stable IDs (`UUID` or server-issued ID). Avoid auto-increment IDs for data
  that may sync.
- Add `createdAt` and `updatedAt`; add `deletedAt` for soft deletes where sync,
  undo, or audit matters.
- Index columns used in hot `WHERE` / `ORDER BY` queries after measuring.
- Store enums as raw strings, not integers.
- Store dates as native date values or ISO 8601, never locale-formatted strings.
- Use separate entities for nested values with identity, queryability,
  relationships, sharing, or independent mutation.
- Use transformable/binary Codable payloads for small leaf value types that are
  not queried and always mutate with the parent.

## Repository Contracts

Repository method signatures use Domain types:

```swift
public protocol ItemRepository {
    func fetch(id: Item.ID) async throws -> Item?
    func list(filter: ItemFilter) async throws -> [Item]
    func observe(filter: ItemFilter) -> AsyncStream<[Item]>
    func upsert(_ item: Item) async throws
    func delete(id: Item.ID) async throws
}

public struct Item: Identifiable, Sendable, Equatable {
    public let id: UUID
    public var title: String
    public var createdAt: Date
    public var updatedAt: Date
}
```

Mapping happens inside the repository. Mappers should be pure functions or
small stateless collaborators and should throw typed mapping errors instead of
returning `nil` as an error signal.

## Threading

Framework rules differ; never flatten them behind a universal storage facade.

- Core Data: use `viewContext` for main-actor reads/UI integration by
  convention; use `performBackgroundTask` for writes; pass object IDs across
  contexts.
- SwiftData: create one `ModelContainer`; use `@ModelActor` or actor-owned
  `ModelContext` for background work; pass `PersistentIdentifier` or snapshots.
- GRDB: use `DatabasePool` for production; reads can run concurrently and writes
  are serialized.
- Realm: live objects are thread-confined; freeze snapshots or map to Domain
  before crossing threads.

Never `await` while holding a framework transaction/context block that expects
synchronous work.

## Write Patterns

- Prefer `upsert(_:)` over separate create/update methods so existence checks and
  writes happen in one transaction.
- Save once per normal repository write. Multiple saves expose intermediate
  states.
- Diff child collections by stable ID; do not delete and recreate all children on
  every parent save.
- Use targeted delta writes for frequently changed single fields.
- Distinguish all-or-nothing bulk writes from resumable chunked imports. Chunked
  imports are intentionally not atomic at repository level.
- Encode optimistic concurrency with a `version` or equivalent conflict token
  when multiple screens/devices can edit the same record.
- Never hide async write errors behind fake `throws`; bridge callbacks to
  `async throws` with a checked continuation or expose completion/result.

## Querying And Reactivity

Repositories may expose observations, but the values emitted are Domain
snapshots:

- Core Data: `NSFetchedResultsController`, `@FetchRequest`, or a custom bridge.
- SwiftData: `@Query` for lists; manual `FetchDescriptor` for detail screens
  where unrelated changes would cause wasteful rerenders.
- GRDB: `ValueObservation`.
- Realm: live results mapped/frozen before crossing boundaries.

## Migrations

Switch to `persistence-migrations` whenever a shipped schema changes, a
transformable Codable payload changes, or a heavyweight migration reaches the
launch path.

Persistence architecture still owns the lifecycle decision: migrations run
during explicit stack warm-up in the Composition Root, before repositories are
resolved.

## Sync, CloudKit, And Multi-Process

- Enable Persistent History Tracking for Core Data stores shared across app
  extensions, background URLSession handlers, or CloudKit.
- Treat CloudKit sync as eventually consistent; show sync state and handle
  quota, offline, and retryable server errors.
- CloudKit-compatible Core Data schemas need optional/defaulted attributes,
  inverse relationships, no unique constraints, concrete attribute types, and
  no `CD_`-prefixed names.
- For remote API + local cache, decide between read-through cache and
  cache-plus-background-refresh. HTTP caching lives in `net-architecture`.

## Security

- Primary databases belong in `Library/Application Support`, not `Documents`.
- Media and user-owned documents live as files; keep paths/metadata in the DB.
- Use `NSFileProtectionComplete` when sensitive local data must be unreadable
  while the device is locked.
- Store secrets and encryption keys in Keychain, not UserDefaults or a plain
  database.
- Use SQLCipher/GRDB or Realm encryption when app-level database encryption is
  required.

## Dependency Injection

Create the persistence container/stack once in the Composition Root.

Use the raw framework container directly in DI when the setup is simple and one
or two repositories consume it. Use a `PersistenceStack` facade when lifecycle
concerns are meaningful: migrations, warm-up, telemetry, multiple repositories,
multiple stores, or in-memory test configuration.

Do not create a universal `Storage.read/write` facade. It hides the API but
cannot hide context confinement, live-object lifetime, error shape, cancellation
semantics, or migration differences. Repository abstracts what is stored; the
storage primitive still owns how the framework works.

## Testing

- Unit-test ViewModels/UseCases with fake repositories.
- Integration-test repository implementations against real in-memory stores.
- Add migration fixture tests in `persistence-migrations`.
- Add concurrency/conflict tests for write methods that allow concurrent edits.
- Use test data builders for complex Domain values so tests mention only the
  fields that matter.

## Common Mistakes

- Returning framework objects from repositories.
- Doing writes on the main context/thread.
- Sharing thread-confined objects across actors or queues.
- Using UserDefaults for collections or secrets.
- Putting database files in `Documents/`.
- Saving multiple times inside a normal repository write.
- Deleting and recreating child collections instead of diffing.
- Letting `@Query` / `@FetchRequest` drive detail screens that should not
  rerender on unrelated writes.
- Treating CloudKit sync as instant or ignoring CloudKit schema constraints.
- Skipping migration tests for shipped schemas.
- Lazy-loading the persistence stack on the first repository call.
