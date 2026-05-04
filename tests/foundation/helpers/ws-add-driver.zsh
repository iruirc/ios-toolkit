#!/usr/bin/env zsh
# Minimal driver for workspace-add --incorporate (soft-mutate).
set -euo pipefail
source "${0:A:h}/../../../templates/workspace/lib/workspace-doc-markers.zsh"
source "${0:A:h}/../../../templates/workspace/lib/workspace-archetypes.zsh"

target="${1:?usage: ws-add-driver.zsh <target-package-dir> <archetype> <package-name>}"
arch="${2:?}"
name="${3:?}"

templates_root="${0:A:h}/../../../templates/workspace"

# Soft-mutate CLAUDE.md
if [[ ! -f "$target/CLAUDE.md" ]]; then
  sed -e "s|{{PACKAGE_NAME}}|$name|g" \
      -e "s|{{ARCHETYPE}}|$arch|g" \
      -e "s|{{GROUP}}|—|g" \
      -e "s|{{VERSION}}|0.1.0|g" \
      -e "s|{{WORKSPACE_NAME}}|TestWS|g" \
      -e "s|{{META_REPO_DIR}}|TestWS-meta|g" \
      -e "s|{{ALLOWED_DEPS_CSV}}|—|g" \
      -e "s|{{EXTERNAL_DEPS_CSV}}|—|g" \
      -e "s|{{ARCHETYPE_BOUNDARY_TEXT}}|$(wsarch::boundary_text "$arch" | sed 's/|/\\|/g')|g" \
      "$templates_root/package/CLAUDE.md.tmpl" > "$target/CLAUDE.md"
  print "wrote $target/CLAUDE.md"
else
  print "warning: $target/CLAUDE.md already exists; not overwritten"
fi

# Soft-mutate CHANGELOG.md
if [[ ! -f "$target/CHANGELOG.md" ]]; then
  cp "$templates_root/package/CHANGELOG.md.tmpl" "$target/CHANGELOG.md"
  print "wrote $target/CHANGELOG.md"
else
  print "warning: $target/CHANGELOG.md already exists; not overwritten"
fi
