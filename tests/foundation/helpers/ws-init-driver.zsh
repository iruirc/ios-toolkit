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

# s09_tasks: shared Tasks repo at workspace-parent (sibling to meta-repo / packages / project repos)
tasks_enabled="$(wsyml::get '.workspace.tasks.enabled' 2>/dev/null || echo 'true')"
tasks_path="$(wsyml::get '.workspace.tasks.path' 2>/dev/null || echo './Tasks')"
if [[ "$tasks_enabled" == "true" ]]; then
  tasks_dir="$ws_parent/${tasks_path#./}"
  mkdir -p "$tasks_dir/TODO" "$tasks_dir/ACTIVE" "$tasks_dir/DONE"
  while IFS= read -r src; do
    rel="${src#$templates_root/tasks-repo/}"
    rel="${rel%.tmpl}"
    dst="$tasks_dir/$rel"
    mkdir -p "${dst:h}"
    sed "s|{{WORKSPACE_NAME}}|$ws_name|g" "$src" > "$dst"
  done < <(find "$templates_root/tasks-repo" -type f \( -name '*.tmpl' -o -name '.gitkeep' \))
  ( cd "$tasks_dir" && git init -q -b main )
fi

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

# Detect project block
proj_name="$(wsyml::get '.project.name' 2>/dev/null || true)"
if [[ -n "$proj_name" ]]; then
  # Per-app full chain: ios → macos
  app_keys="$(wsyml::get '.project.apps | keys | .[]' 2>/dev/null || true)"
  for ak in ${(f)app_keys}; do
    [[ "$ak" =~ ^(ios|macos)$ ]] || continue
    # Resolve repo name (long-form or string-form)
    app_repo="$(wsyml::get ".project.apps.$ak.repo" 2>/dev/null || true)"
    if [[ -z "$app_repo" ]]; then
      app_repo="$(wsyml::get ".project.apps.$ak" 2>/dev/null || true)"
    fi
    [[ -z "$app_repo" ]] && continue
    "${0:A:h}/ws-project-init-driver.zsh" "$ws_yml" "$ws_parent" "$ak" "$app_repo"
  done

  # Render WORKSPACE_PROJECT_REFS in xcworkspace (workspace-doc-markers.zsh already sourced at top)
  xcwsfile="$meta_dir/${ws_name}.xcworkspace/contents.xcworkspacedata"
  mkdir -p "$meta_dir/${ws_name}.xcworkspace"
  if [[ ! -f "$xcwsfile" ]]; then
    cp "$templates_root/meta-repo/xcworkspace-contents.xml.tmpl" "$xcwsfile"
  fi
  proj_refs=""
  for ak in ${(f)app_keys}; do
    [[ "$ak" =~ ^(ios|macos)$ ]] || continue
    app_repo="$(wsyml::get ".project.apps.$ak.repo" 2>/dev/null || true)"
    [[ -z "$app_repo" ]] && app_repo="$(wsyml::get ".project.apps.$ak" 2>/dev/null || true)"
    [[ -z "$app_repo" ]] && continue
    proj_refs+="   <FileRef location=\"group:../$app_repo/$app_repo.xcodeproj\"></FileRef>"$'\n'
  done
  print -r -- "${proj_refs%$'\n'}" | wsmark::write "$xcwsfile" PROJECT_REFS
fi
