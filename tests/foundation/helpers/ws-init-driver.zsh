#!/usr/bin/env zsh
# Minimal driver for batch workspace-init, used by integration tests.
# Mirrors the skill's "shared execution" steps. NOT shipped to users.
set -euo pipefail

source "${0:A:h}/../../../templates/workspace/lib/workspace-yml-parser.zsh"
source "${0:A:h}/../../../templates/workspace/lib/workspace-graph.zsh"
source "${0:A:h}/../../../templates/workspace/lib/workspace-doc-markers.zsh"
source "${0:A:h}/../../../templates/workspace/lib/workspace-archetypes.zsh"

ws_yml="${1:?usage: ws-init-driver.zsh <workspace.yml> <workspace-parent-dir>}"
ws_parent="${2:?}"

wsyml::load "$ws_yml" || exit $?
wsyml::validate >&2 || exit $?
wsgraph::check_acyclic >&2 || exit $?

ws_name="$(wsyml::get '.workspace.name')"
meta_dir="$ws_parent/${ws_name}-meta"
mkdir -p "$meta_dir"

# Copy meta-repo templates with placeholder substitution. Walk recursively so any
# subdirs in the template tree are preserved.
templates_root="${0:A:h}/../../../templates/workspace"
while IFS= read -r src; do
  rel="${src#$templates_root/meta-repo/}"
  rel="${rel%.tmpl}"
  # Skip LLM-driven workspace artifacts (rendered/filled by the skill body, not the driver).
  case "$rel" in
    xcworkspace-contents.xml|code-workspace.json) continue ;;
  esac
  dst="$meta_dir/$rel"
  mkdir -p "${dst:h}"
  sed "s|{{WORKSPACE_NAME}}|$ws_name|g" "$src" > "$dst"
done < <(find "$templates_root/meta-repo" -type f -name '*.tmpl')

cp "$ws_yml" "$meta_dir/workspace.yml"
( cd "$meta_dir" && git init -q -b main && touch .gitkeep )

# Per package
for p in $(wsyml::packages); do
  arch="$(wsyml::package_field "$p" archetype)"
  group="$(wsyml::package_field "$p" group 2>/dev/null || echo '')"
  ver="$(wsyml::package_field "$p" version)"
  if [[ -n "$group" ]]; then
    group_dir="$(wsyml::get ".package_groups[] | select(.name == \"$group\") | .dir")"
    pkg_dir="$ws_parent/$group_dir/$p"
  else
    pkg_dir="$ws_parent/packages/$p"
  fi
  mkdir -p "$pkg_dir"
  while IFS= read -r src; do
    rel="${src#$templates_root/package/}"
    rel="${rel%.tmpl}"
    rel="${rel//PACKAGE_NAMETests/${p}Tests}"
    rel="${rel//PACKAGE_NAME/$p}"
    dst="$pkg_dir/$rel"
    mkdir -p "${dst:h}"
    sed -e "s|{{PACKAGE_NAME}}|$p|g" \
        -e "s|{{ARCHETYPE}}|$arch|g" \
        -e "s|{{GROUP}}|${group:-—}|g" \
        -e "s|{{VERSION}}|$ver|g" \
        -e "s|{{WORKSPACE_NAME}}|$ws_name|g" \
        -e "s|{{META_REPO_DIR}}|${ws_name}-meta|g" \
        -e "s|{{ALLOWED_DEPS_CSV}}|—|g" \
        -e "s|{{EXTERNAL_DEPS_CSV}}|—|g" \
        -e "s|{{ARCHETYPE_BOUNDARY_TEXT}}|$(wsarch::boundary_text "$arch" | sed 's/|/\\|/g')|g" \
        "$src" > "$dst"
  done < <(find "$templates_root/package" -type f -name '*.tmpl')
  ( cd "$pkg_dir" && git init -q -b main )
done
