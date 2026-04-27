---
description: "Create a new Swift project (iOS/macOS app or SPM package) / Создать новый Swift-проект (iOS/macOS app или SPM package)"
argument-hint: <project description>
---

Activate agent `@swift-toolkit:swift-init` via the Task tool (`subagent_type=swift-toolkit:swift-init`) with arguments: $ARGUMENTS

The agent generates **a single artifact** — an application (iOS/macOS) or an SPM package — and configures SwiftLint plus the toolkit-owned `CLAUDE-swift-toolkit.md` and a minimal user-owned `CLAUDE.md` (with the `@./CLAUDE-swift-toolkit.md` import line). App modes use **XcodeGen** (`project.yml` → `xcodegen generate`); if it's not installed, the agent will ask about `brew install xcodegen`. SPM packages don't need XcodeGen. For a **multi-module project**, run the command several times in the relevant folders (packages can live anywhere on disk); assemble the `.xcworkspace` in Xcode (`File → New → Workspace`). To attach swift-toolkit to an **already existing** project use `/swift-setup`.
