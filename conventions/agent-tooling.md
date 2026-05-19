# Agent Tooling Compatibility

Use these terms when a skill needs host capabilities. They keep the toolkit
portable across Claude Code, Codex, and other agent hosts.

## Structured Questions

`structured question mechanism` means the active host's UI for asking the user
one or more bounded questions with options.

- If the host exposes a native question tool, use it.
- In Claude Code compatibility mode this may be `AskUserQuestion`; if that tool
  is lazy-loaded, discover/load it using the host's documented mechanism.
- If no structured question tool is available, ask a numbered question in plain
  text and parse the user's reply.
- Locale keys with the `auq_` prefix are historical names. They mean "question
  prompt/options" and are not tied to a specific host tool.

## File Access

`file-read mechanism`, `file-write mechanism`, and `file-edit mechanism` mean the
active host's approved way to read, create, or patch files.

- Follow the host's safety policy for writes and destructive operations.
- For template-based artifacts, preserve all bytes outside documented
  placeholders or insertion points.
- For Markdown artifacts parsed by the toolkit, preserve structural anchors from
  `conventions/i18n.md`.

## Toolkit Root And Templates

`toolkit root` means the directory that contains this repository's `skills/`,
`templates/`, and `conventions/` directories.

When a skill needs a bundled template, search in this order:

1. `<toolkit-root>/templates/...`
2. Installed plugin/cache paths exposed by the active host.
3. Claude Code compatibility paths such as `~/.claude/plugins/...`.

Host-specific paths are fallbacks, not the canonical source.
