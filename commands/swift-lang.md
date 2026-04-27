---
description: "Change project language for swift-toolkit prompts (en/ru) / Сменить язык подсказок swift-toolkit для проекта (en/ru)"
argument-hint: <lang>
---

Activate `swift-toolkit:swift-lang` with arguments: $ARGUMENTS

Updates the `## Language` section of the project's `CLAUDE-swift-toolkit.md` to the specified value (`en` or `ru`). All subsequent skill invocations will use the new language for user-facing strings. If `$ARGUMENTS` is empty, the skill prints the current value and supported options.
