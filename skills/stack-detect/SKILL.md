---
name: stack-detect
description: |
  Pure side-effect-free per-axis Stack resolver. Computes needed axes (workflow envelope ∩ task scope) and runs the per-axis resolution chain, returning {needed, resolved, unresolved}. Activated by swift-toolkit:orchestrator; not invoked by the user directly.
  Use when (en): orchestrator resolves the Stack for a dispatched task
  Use when (ru): оркестратор резолвит Stack для диспетчеризуемой задачи
---

# Stack Detect

Pure resolver invoked by `swift-toolkit:orchestrator` during Resolution. It
performs **no** user questions, writes **no** files, and mutates **no**
`Task.md`. It returns structured data; the orchestrator owns all user-facing
interaction and caching.

## Input

```
task_files = [path, ...]      # the task's file scope (may be empty)
envelope   = {may: [axis...] | all, never: [axis...] | all}
task_id    = string
```

## Axis Catalog (non-localized)

Axis values are proper nouns — never localized. This catalog is the source of
truth for both detection and the option list the orchestrator renders in AUQ.

| Axis | Valid values |
|---|---|
| `ui` | `SwiftUI`, `UIKit`, `AppKit` |
| `async` | `async/await`, `Combine`, `RxSwift` |
| `di` | `Swinject`, `Factory`, `manual` |
| `architecture` | `MVVM+Coordinator`, `VIPER`, `Clean Architecture`, `MVC` |
| `platform` | `iOS 17+`, `iOS 16+`, `macOS 14+`, `macOS 13+`, `iOS+macOS` |
| `tests` | `XCTest`, `Quick+Nimble` |

## Import-scan heuristics

| Axis | Heuristic |
|---|---|
| `ui` | `import SwiftUI`→`SwiftUI`; `import UIKit` (no SwiftUI)→`UIKit`; `import AppKit`→`AppKit`; mixed→no detection |
| `async` | `import Combine`→`Combine`; `import RxSwift`→`RxSwift`; `await ` token present→`async/await` |
| `di` | none — cannot infer from file-level imports |
| `architecture` | none — structural, not an import |
| `platform` | `Package.swift` `platforms:` line, or app target deployment target |
| `tests` | `import XCTest`→`XCTest`; `import Quick`/`import Nimble`→`Quick+Nimble` |

## Algorithm

```
1. if envelope.never == all:
       return {needed: [], resolved: {}, unresolved: []}
       # orchestrator handles the ambient-info case; stack-detect is a no-op

2. scan := one pass over task_files producing:
       paths_implied   := apply conventions/stack-axis-mapping.md to task_files
       imports_implied := apply import-scan heuristics to task_files
   (the scan result is computed once and reused in step 4)

3. may := (envelope.may == all) ? [ui,async,di,architecture,platform,tests]
                                 : envelope.may
   never := (envelope.never == all) ? [...all...] : envelope.never
   needed := (may ∩ (paths_implied ∪ imports_implied)) − never
   if task_files is empty:
       needed := may          # early-stage fallback; AUQ deferred by orchestrator

4. for axis in needed, resolve via the per-axis chain (first hit wins):
       a. Task.md → ## 4. [Stack] line for axis
       b. CLAUDE-swift-toolkit.md → ## Modules (if a module entry matching a
          task file overrides the axis)
       c. CLAUDE-swift-toolkit.md → ## Stack line for axis
       d. imports_implied[axis] from step 2 (only axes with a heuristic)
   resolved[axis]   := first hit
   unresolved       := needed axes with no hit

5. return {needed, resolved, unresolved}
```

## Output

```
needed     = [axis, ...]
resolved   = {axis: value, ...}     # value ∈ Axis Catalog[axis]
unresolved = [axis, ...]            # subset of needed with no chain hit
```

## Invariants

- Never asks the user. Never writes files.
- `resolved` values are always members of the Axis Catalog for that axis.
- `resolved.keys ∪ unresolved == needed` (every needed axis is accounted for).
- `task_files` empty ⇒ `needed == may`, resolution still attempted from
  `Task.md`/toolkit-file; AUQ deferral is the orchestrator's responsibility.
