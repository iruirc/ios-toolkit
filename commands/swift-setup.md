---
description: "Configure swift-toolkit in an existing Swift project / Настроить swift-toolkit в существующем Swift-проекте"
argument-hint: (no arguments)
---

Activate `swift-toolkit:swift-setup`.

The skill creates `CLAUDE-swift-toolkit.md` (toolkit-owned) from the template, inserts a single `@./CLAUDE-swift-toolkit.md` import line into your project's `CLAUDE.md` (user-owned, created if absent), asks via AskUserQuestion for the project's stack (UI/Async/DI/architecture/platform/tests) and language, fills placeholders, and (optionally) creates a `Tasks/` structure. Detects and migrates projects on the legacy single-file `CLAUDE.md` format automatically. To generate a **new** Swift project from scratch use `/swift-init`.
