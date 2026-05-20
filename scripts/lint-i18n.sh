#!/usr/bin/env bash
set -euo pipefail

# Allowed cyrillic locations:
#   docs/**                          (free-form reference)
#   skills/*/locales/ru.md           (Russian locale strings)
#   templates/claude-md-stub/ru.md   (Russian template)
#   conventions/i18n.md              (canonical multilingual examples)
#   any *.ru.md anywhere             (Russian-only mirrors)
#   skills/<name>/SKILL.md           (only inside frontmatter description: bilingual triggers)
#   agents/<name>.md                 (only inside frontmatter description: bilingual triggers)
#   commands/<name>.md               (only inside frontmatter description: bilingual one-line)
#
# Anything else with cyrillic chars is a violation.

violations=0
while IFS= read -r -d '' f; do
  case "$f" in
    ./docs/*) continue ;;
    *.ru.md) continue ;;
    ./skills/*/locales/*.md) continue ;;
    ./templates/claude-md-stub/ru.md) continue ;;
    ./conventions/i18n.md) continue ;;
    ./.git/*) continue ;;
  esac

  # For SKILL.md / agents/*.md / commands/*.md, allow cyrillic ONLY inside the
  # frontmatter description block (between the first two --- lines).
  case "$f" in
    ./skills/*/SKILL.md|./agents/*.md|./commands/*.md)
      python3 - "$f" <<'PY' || violations=$((violations + 1))
import sys
path = sys.argv[1]
text = open(path, encoding='utf-8').read()
lines = text.split('\n')
fence_count = 0
for i, line in enumerate(lines, 1):
    if line.strip() == '---':
        fence_count += 1
        continue
    if fence_count >= 2 and any('А' <= c <= 'я' or c in 'ёЁ' for c in line):
        print(f'{path}:{i}: cyrillic outside frontmatter: {line.rstrip()}')
        sys.exit(1)
PY
      ;;
    *)
      python3 - "$f" <<'PY' || violations=$((violations + 1))
import sys
path = sys.argv[1]
text = open(path, encoding='utf-8').read()
for i, line in enumerate(text.split('\n'), 1):
    if any('А' <= c <= 'я' or c in 'ёЁ' for c in line):
        print(f'{path}:{i}: cyrillic in non-localized file: {line.rstrip()}')
        sys.exit(1)
PY
      ;;
  esac
done < <(find . -type f \( -name '*.md' -o -name '*.json' -o -name '*.yml' -o -name '*.yaml' \) -print0)

if [ "$violations" -gt 0 ]; then
  echo
  echo "i18n lint failed: $violations file(s) with disallowed cyrillic"
  exit 1
fi

echo "i18n lint passed: no disallowed cyrillic"
