# CLAUDE.md — swift-toolkit (plugin repo)

> This is the repo of the swift-toolkit Claude Code plugin.
> User-project templates live in `templates/claude-md/{en,ru}.md` (NOT here).
> This file just configures Claude when it works on the plugin itself.

## Language

en

## Persona

- This repo's source-of-truth language is English. All files outside `docs/` and explicit translated mirrors must be in English.
- User-facing strings produced by skills are localized via `skills/<name>/locales/<lang>.md`. Editing localized strings requires updating every locale file with parity.
- When changing a skill body, never inline a localized string — always reference a locale key.

## Repository layout

- `agents/` — Claude Code subagents (8 swift-* agents)
- `skills/` — Claude Code skills (32+ skills, organized by topic)
  - process skills: `orchestrator`, `workflow-*`, `task-*`, `swift-setup`, `swift-lang`
  - knowledge skills: `arch-*`, `persistence-*`, `net-*`, `di-*`, etc.
  - each localized skill has `locales/{en,ru}.md`
- `commands/` — slash commands (one Markdown file per command)
- `templates/claude-md/` — CLAUDE.md templates copied into user projects (`en.md`, `ru.md`)
- `docs/` — free-form reference notes and superpowers plans/specs (any language)
- `.claude-plugin/` — plugin manifests (`plugin.json`, `marketplace.json`)

## Conventions

- See `conventions/i18n.md` for the i18n convention reference.

## When working on this repo

- Adding a new user-facing string: add the key to BOTH `locales/en.md` AND `locales/ru.md` for the affected skill, then reference the key from the skill body. Run a parity check (`diff <(grep '^## ' .../en.md | sort) <(grep '^## ' .../ru.md | sort)`) — must be empty.
- Adding a new skill that has user-facing strings: include `locales/en.md` and `locales/ru.md`. Body must contain the `## Language Resolution` section verbatim.
- Adding a new command: bilingual `description:` line. Body in English.
- Adding a new agent: bilingual triggers in `description:` field.
