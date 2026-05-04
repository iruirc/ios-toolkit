#!/usr/bin/env zsh
# Minimal driver for workspace-docs-regen WORKSPACE_PKG_LIST in meta README.
set -euo pipefail
source "${0:A:h}/../../../templates/workspace/lib/workspace-yml-parser.zsh"
source "${0:A:h}/../../../templates/workspace/lib/workspace-doc-markers.zsh"

meta_dir="${1:?usage: ws-docs-regen-driver.zsh <meta-repo-dir>}"
wsyml::load "$meta_dir/workspace.yml" >&2 || exit $?

content=""
while IFS= read -r p; do
  arch="$(wsyml::package_field "$p" archetype)"
  group="$(wsyml::package_field "$p" group 2>/dev/null || echo '—')"
  content+="- $p ($arch) — $group"$'\n'
done < <(wsyml::packages)

print -r -- "${content%$'\n'}" | wsmark::write "$meta_dir/README.md" PKG_LIST
print "regenerated PKG_LIST in $meta_dir/README.md"
