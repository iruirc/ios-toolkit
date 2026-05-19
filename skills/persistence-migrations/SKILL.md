---
name: persistence-migrations
description: "Use when designing or shipping a schema migration in an iOS app — Core Data lightweight vs heavyweight + NSEntityMigrationPolicy, SwiftData VersionedSchema/MigrationStage, GRDB DatabaseMigrator, Realm migration block; transformable Codable payloads (evolutionary / lazy / proactive / envelope); progressive multi-step migrations; long-migration UX and atomic backup; failure recovery and telemetry; fixture-based migration tests; Codable snapshot tests."
---

# Persistence Migrations

Design, ship, test, and recover from local-store migrations across Core Data,
SwiftData, GRDB, Realm, and Codable payloads stored as `Data`.

Detailed framework examples live in `references/detailed-guide.md`. Load only
the relevant section with
`rg -n "^## " skills/persistence-migrations/references/detailed-guide.md`.

## When To Load The Reference

| Need | Reference sections |
|---|---|
| Core Data lightweight/heavyweight migration | `Core Data — lightweight vs heavyweight` |
| SwiftData migration plan | `SwiftData — VersionedSchema + MigrationPlan` |
| GRDB migrations | `GRDB — DatabaseMigrator` |
| Realm migration block | `Realm — migration block` |
| Evolve Codable blobs | `Migrating transformable Codable payloads` |
| Chain old versions to current | `Progressive migration` |
| Long migration UX and backup | `Long migrations` |
| Failure UI, telemetry, recovery | `Failure recovery` |
| App Group / extension first launch | `Cross-process migration` |
| Fixture and snapshot tests | `Testing` |

## Discipline

Migration rules for every framework:

1. Schema versions are checked into git.
2. Never edit a shipped schema in place.
3. Never edit a shipped migration; corrections are new migrations.
4. Use adjacent migration pairs/chains. Do not rely on one v1 -> current mega
   mapping.
5. Add fixture tests for every shipped migration.
6. Back up before heavyweight or chained migrations.
7. Surface typed migration failures to UI.
8. Emit telemetry for success/failure, duration, source/destination versions,
   and relevant system state.
9. Run migration on the foreground launch path. Defer background launches.

## Core Data

Lightweight migration handles additive/optional changes, relationship changes,
and renames with a renaming identifier. Configure:

```swift
description.shouldMigrateStoreAutomatically = true
description.shouldInferMappingModelAutomatically = true
```

Heavyweight migration is needed for splits, merges, type conversions, computed
defaults, and entity renames. For heavyweight migrations:

- Add a new `.xcdatamodeld` version.
- Create a mapping model for the adjacent source/destination pair.
- Use `NSEntityMigrationPolicy` only where custom transformation is needed.
- Set inference to false so Core Data uses your mapping:

```swift
description.shouldMigrateStoreAutomatically = true
description.shouldInferMappingModelAutomatically = false
```

Always back up before the migration and test against a fixture store.

## SwiftData

Use `VersionedSchema` and `SchemaMigrationPlan`.

- `.lightweight(fromVersion:toVersion:)` for additive/automatic changes.
- `.custom(fromVersion:toVersion:willMigrate:didMigrate:)` for splits, merges,
  value transforms, and computed defaults.

`willMigrate` sees the old schema; `didMigrate` sees the new schema. For
split/merge, capture source data during `willMigrate`, then materialize new
models during `didMigrate`.

## GRDB

Use `DatabaseMigrator` with named, ordered migrations:

```swift
var migrator = DatabaseMigrator()
migrator.registerMigration("v1_create_items") { db in
    try db.create(table: "item") { t in
        t.column("id", .text).primaryKey()
        t.column("title", .text).notNull()
    }
}
try migrator.migrate(dbPool)
```

Each migration runs once. Never edit a migration that has shipped; add a new
named migration.

## Realm

Bump `schemaVersion` and add cumulative guarded blocks:

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

## Transformable Codable Payloads

Blob payloads are a separate migration axis. Core Data, SwiftData, GRDB, and
Realm do not understand the JSON inside `Data`.

Choose one approach:

- Evolutionary Codable: new fields optional/defaulted, no destructive renames or
  type changes, snapshot tests for every released JSON shape.
- Lazy migration on read: decoder accepts old and new shapes, then writes the
  new shape on next save.
- Proactive rewrite inside migration: decode old payload and write new payload
  for every row during schema migration.
- Versioned envelope: store explicit payload version and migrate v1 -> v2 -> v3
  in code.

Never `try?` decode and silently default. That is data loss.

## Progressive Migration

Users can be on any previously shipped version. Migrate adjacent versions:

- Core Data: mapping model per pair and a helper that walks the chain.
- SwiftData: ordered adjacent stages in `MigrationPlan`.
- GRDB: named migrations already run in order.
- Realm: cumulative `if oldVersion < N` blocks.

Do not delete old model versions from the app bundle. Users who skipped releases
still need them.

## Long Migrations And Recovery

For heavyweight/chained migrations:

- Show a foreground migration UI when the operation can take visible time.
- Defer if launched in the background.
- Copy a backup before touching the store.
- Replace atomically on success.
- Restore or preserve the backup on failure.
- Keep the backup available for support even when the user chooses "Start fresh".

User-facing recovery should usually offer retry, send report, and start fresh.
Do not auto-delete a failed store.

## Cross-Process Stores

For App Group stores shared with extensions/widgets:

- Migration must be idempotent; either process may launch first after update.
- Extensions must run the same warm-up/migration gate before writing.
- Core Data shared stores need Persistent History Tracking.
- Test the extension-first launch path.

## Testing

- Keep fixture databases for old released versions under tests.
- For each migration, open the old fixture with current code and assert row
  counts, transformed values, relationships, indexes, and no data loss.
- Freeze transformable Codable JSON samples and test old-shape decode plus
  stable round-trip.
- Never regenerate an old fixture from current code.

## Common Mistakes

- No migration plan until the first breaking schema change.
- Editing a shipped migration.
- Leaving Core Data inference enabled for a heavyweight migration.
- Shipping heavyweight migration without a fixture test.
- Running long migrations during background launch.
- Auto-deleting a user's database on migration failure.
- One mega mapping model from old version to current.
- Changing Codable payloads without legacy decode/snapshot tests.
- Deleting old `.xcdatamodel` versions.
- Sharing an App Group store without idempotent migration.
