---
name: persistence-migrations
description: "Use when designing or shipping a schema migration in an iOS app — Core Data lightweight vs heavyweight + NSEntityMigrationPolicy, SwiftData VersionedSchema/MigrationStage, GRDB DatabaseMigrator, Realm migration block; transformable Codable payloads (evolutionary / lazy / proactive / envelope); progressive multi-step migrations; long-migration UX and atomic backup; failure recovery and telemetry; fixture-based migration tests; Codable snapshot tests."
---

# Persistence Migrations

Schema evolution is a low-frequency but high-blast-radius activity. This skill covers how to design, ship, and recover from migrations across Core Data, SwiftData, GRDB, and Realm — plus the orthogonal axis of evolving Codable payloads stored as transformable `Data`.

> **Related skills:**
> - `persistence-architecture` — Repository boundary, threading, write patterns, DI; this skill is its migration counterpart
> - `error-architecture` — typed migration errors, failure surfacing, recoverable vs fatal classification
> - `arch-clean`, `arch-mvvm` — where the migration UI fits in the launch sequence

## Why This Skill Exists

Apps live for years. Schema changes are not optional — and they fail in the wild in ways that are silent without explicit planning:

- Half of users get `Cannot create NSManagedObjectModel: model is not loadable` on launch after `v3` ships.
- Heavyweight migration loads 50K records into memory on a 3-year-old device — process killed, store half-baked.
- A Codable payload field gets renamed; `try? JSONDecoder().decode(...)` silently returns `nil`; users see blank projects.
- One mega mapping model `v1 → v5` works in the test (where the dev was on `v4`); breaks every user who hadn't opened the app since `v1`.
- Migration fails for one user; their data is gone with no recovery path because `try? fs.remove(dbURL)` was the «recovery».

Fix: **adjacent-pair migrations, atomic backup before any heavyweight step, fixture tests for every migration, typed failure surfaced to UI, telemetry on outcomes.**

## Discipline (any framework)

1. **Schema version is checked into git.** Never edit a shipped schema in place.
2. **Never edit a shipped migration.** Once a migration ran on a user's device, it's frozen. Corrections go in a **new** migration.
3. **Adjacent pairs only.** No mega mapping models from version N to current — see *Progressive migration*.
4. **Every migration has a fixture test** — see *Testing / Migration tests*.
5. **Backup before any heavyweight or chained migration** — see *Long migrations*.
6. **Telemetry on every migration outcome** — see *Failure recovery*. Migration failures in the wild are silent without it.
7. **Plan a recovery path explicitly** — what does the user see if migration fails? Does «Start fresh» still leave them with a useful app, or is the data the entire app? If data is unrecoverable without the server, document the dependency.
8. **Run migration on the foreground launch path.** Defer if launched in background.

## Core Data — lightweight vs heavyweight

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

### Step-by-step

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

## SwiftData — VersionedSchema + MigrationPlan

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

## GRDB — DatabaseMigrator

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

## Realm — migration block

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

## Migrating transformable Codable payloads

A category that standard migration mechanics do **not** cover: an entity has an attribute `payload: Data` that holds JSON-encoded Codable. The Codable struct evolves between releases. Core Data / SwiftData / GRDB don't see inside the blob — to them the column type didn't change. A naïve `JSONDecoder().decode(NewPayload.self, from: oldData)` throws on the first old row.

This is a separate axis of migration, layered on top of schema migration. Four approaches, choose by situation:

### Approach 1 — Evolutionary Codable (prevention)

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

### Approach 2 — Lazy migration on read

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

### Approach 3 — Proactive rewrite inside the schema migration

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

### Approach 4 — Versioned envelope from the start

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

### Choosing

| Situation | Approach |
|---|---|
| Changes are small (additions, optional fields), team can hold convention rules | **1** — evolutionary Codable + snapshot tests |
| Breaking change already done, want to avoid a heavyweight schema migration | **2** — lazy on read |
| All rows must be on the new shape (field is being indexed / queried) | **3** — proactive rewrite inside heavyweight migration |
| New project, blob holds an evolving business model | **4** — versioned envelope from day one |

Common combination: Approach 1 by default, Approach 3 for breaking changes that need full conversion.

### What NOT to do

- **`try?` on decode + a fallback default** — silent data loss; you'll discover it months later when a user asks why their old projects are blank.
- **`catch { ctx.delete(entity); save() }`** — actively destroys data.
- **Changing a Codable struct without checking** for legacy payloads on disk.
- **Removing old `PayloadV1` types** before all users have rolled forward (breaks Approaches 2 and 4).
- **Trusting that lightweight schema migration «does something»** to the blob — it does literally nothing.

## Progressive migration — v1 → v2 → v3 → … → current

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

## Long migrations — UX and performance

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

## Failure recovery — what to show the user

Heavyweight migration **will** fail in production. Disk pressure, OOM kill, corrupted store from a previous crash, mapping model bug that escaped tests. Plan it like network failure:

- **Don't silently delete the store.** `try fs.remove(dbURL); try migrate(emptyStore)` looks like recovery, actually it's data loss.
- **Persist the backup.** The backup file from *Long migrations* becomes the user's only recovery path.
- **Surface a typed error to the UI.** `MigrationFailure(fromVersion:, toVersion:, underlying:, backupURL:)` — the presentation layer decides what to show.
- **Three-button dialog** is the usual UX:
  1. **Retry** — useful if the failure was transient (low disk, low memory).
  2. **Send report** — package the backup file + last log + version metadata, send to support. Don't auto-upload PII without consent.
  3. **Start fresh** — delete the broken store, start with empty DB, but **keep the backup** so the user can recover later if support helps.
- **Telemetry**: from-version / to-version / duration / error-domain / error-code / available-disk / memory-pressure-at-failure → SwiftyBeaver / Firebase non-fatal / your stack. Without this you don't know that 0.4% of users on v3→v4 fail with `disk full`.

## Cross-process migration (App + Extension)

If a Core Data / SwiftData store lives in an App Group and is shared between the main app and an Extension (Share / Widget / Notification Service), **either side may launch first after install or update**. The Extension might trigger migration before the user opens the app.

Rules:

- **Migration logic must be idempotent** — running it again from the main app on the next launch must be a no-op (`DatabaseMigrator` and SwiftData `MigrationPlan` already are).
- **No Extension may write to the store before migration completes.** Wrap any Extension write in the same `warmUp()` call the main app uses.
- **Persistent History Tracking is mandatory** if the store is shared — see `persistence-architecture` / *Persistent History Tracking*. Otherwise the main app won't see writes the Extension made before/during migration.
- **Test the «Extension launched first» path explicitly** — boot a fresh simulator, install, trigger the Extension before opening the app, observe the store on first app launch.

## Testing

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

For any Codable struct stored in a `Data` attribute, freeze the JSON form and assert decode + round-trip on every CI run. This is the only thing that catches accidental schema drift inside blobs (see *Migrating transformable Codable payloads*).

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

## Common Mistakes

Each entry one line + cross-reference to the body section that explains the fix.

1. **No migration plan from day one** — first user upgrade crashes the app. See *Discipline*.
2. **Editing a shipped migration** — never change a migration that ran on a user's device. See *Discipline*.
3. **`shouldInferMappingModelAutomatically = true` with a heavyweight schema change** — see *Core Data*.
4. **No fixture test for heavyweight migration** — see *Testing / Migration tests*.
5. **No backup before destructive migration** — see *Long migrations*.
6. **One mega mapping model from version N to current** — see *Progressive migration*.
7. **Running heavyweight migration on background launch** — defer to next foreground launch. See *Long migrations*.
8. **Auto-deleting the user's database on migration failure** — see *Failure recovery*.
9. **Changing a Codable struct stored in a transformable attribute without a payload-migration plan** — see *Migrating transformable Codable payloads*.
10. **`try?` on decode of a transformable Codable** — silent data loss. See *Migrating transformable Codable payloads / What NOT to do*.
11. **Removing an old `.xcdatamodel` version to «clean up»** — breaks every user still on that version. See *Progressive migration*.
12. **Shared App Group store without idempotent migration** — Extension launches first, runs migration, main app crashes on duplicate. See *Cross-process migration*.
