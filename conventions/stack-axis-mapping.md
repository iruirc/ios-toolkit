# Stack-Axis Mapping Convention for swift-toolkit

> Date: 2026-05-15. Companion to `docs/superpowers/specs/2026-05-15-stack-axis-resolution-design.md`.

## Goal

Default mapping from a task's touched file paths to the Stack axes those files
imply. Used by `stack-detect` to narrow the workflow envelope to the axes a
specific task actually depends on. Projects override via
`CLAUDE-swift-toolkit.md → ## Modules`.

## Axes

`ui`, `async`, `di`, `architecture`, `platform`, `tests`.

## Default path-to-axis table

| Path pattern | Implied axes |
|---|---|
| `Views/`, `Screens/`, `*View.swift`, `*Screen.swift` | `ui`, `architecture` |
| `ViewModels/`, `*ViewModel.swift`, `*Presenter.swift`, `*Coordinator.swift` | `architecture` (+ `ui` if SwiftUI binding present) |
| `Networking/`, `API/`, `*Client.swift`, `*Service.swift` | `async` (+ `di` if container-registered) |
| `Persistence/`, `Storage/`, `*Repository.swift`, `*.xcdatamodeld` | `async`, `tests` |
| `*Tests/`, `*Spec.swift`, `*Tests.swift` | `tests` + axis of the system under test |
| `Package.swift`, `project.pbxproj` | `platform` |

## Resolution rules

- A file matching no row implies no axis (does not force AUQ on its own).
- Multi-module project without `## Modules`: pick the axis fitting the
  majority of changed files; a tie on a needed axis → AUQ.
- The `+ if ...` qualifiers are corroborated by the import-scan step (e.g.
  `import SwiftUI` in a `*Coordinator.swift` confirms the `ui` add-on).
