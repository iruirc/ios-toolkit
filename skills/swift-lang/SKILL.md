---
name: swift-lang
description: |
  Change the project language for swift-toolkit user-facing prompts. Updates `## Language` in CLAUDE-swift-toolkit.md. Currently supported: en, ru.
  Use when (en): "switch language to en", "switch language to ru", "change toolkit language", "/swift-lang"
  Use when (ru): "переключи язык на en", "смени язык на русский", "поменяй язык toolkit", "/swift-lang"
---

# Swift Lang

Updates the `## Language` section of the project's `CLAUDE-swift-toolkit.md`. Pure configuration skill: no project state mutated besides this one section.

## Language Resolution

Before producing any user-facing string:

1. Read `CLAUDE-swift-toolkit.md` from the project root.
2. Find the `## Language` section.
3. Take the first non-empty line in that section, lowercase and trim it. That is `<lang>`.
4. If `<lang>` is `en` or `ru`, use it. Otherwise default to `en`.
5. Read this skill's `locales/<lang>.md`. Look up keys by H2 header.
6. If a key is missing, fall back to the same key in `locales/en.md`. If still missing, that's a bug — fail loudly with key name.

Caching: resolve `<lang>` once per skill invocation; do not re-read CLAUDE-swift-toolkit.md per string.

## Algorithm

```
1. Locate CLAUDE-swift-toolkit.md in the current project root.
   ↓ If not found → print error using key `error_no_toolkit_file`. Stop.

2. Parse $ARGUMENTS:
   ↓ If empty → print current value (read ## Language section) and supported list using keys
       `report_current_language` + `report_supported_languages`. Stop.
   ↓ If value not in {en, ru} → print error using key `error_unsupported_language`. Stop.

3. Update CLAUDE-swift-toolkit.md:
   - Locate the `## Language` section (regex: starts with `## Language`).
   - Replace its body (until next H2) with a single line containing the new value.
   - If the section is missing → insert it at the top (right after the H1 and any blockquote).

4. Print success using key `report_language_changed` with placeholders {old}, {new}.
```

## Edge cases

- CLAUDE-swift-toolkit.md missing → key `error_no_toolkit_file`.
- Argument missing → print current state (not an error).
- Argument unsupported → key `error_unsupported_language`, list supported.
- Argument equals current value → still OK; print success message anyway.

## What this skill does NOT do

- Does NOT translate any existing files.
- Does NOT validate that locales for the chosen language exist for every skill (that's a contributor concern, not user concern).
- Does NOT touch any other CLAUDE-swift-toolkit.md section.
