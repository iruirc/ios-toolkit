#!/usr/bin/env zsh
# workspace-project.zsh — project-repo helpers (deps injection + workspace meta append).
# Public API: wsproj::package_path, wsproj::inject_deps, wsproj::append_workspace_meta

wsproj::package_path() {
  local pkg="$1"
  if [[ -z "$pkg" ]]; then
    print -u2 "wsproj::package_path: missing package name"
    return 4
  fi
  if [[ -z "${_WSYML_STATE[json]:-}" ]]; then
    print -u2 "wsproj::package_path: no document loaded; call wsyml::load first"
    return 4
  fi
  local pkg_group
  pkg_group="$(wsyml::package_field "$pkg" group 2>/dev/null || true)"
  if [[ -z "$pkg_group" ]]; then
    print -r -- "../packages/$pkg"
    return 0
  fi
  local group_dir
  group_dir="$(wsyml::get ".package_groups[] | select(.name == \"$pkg_group\") | .dir" 2>/dev/null || true)"
  if [[ -z "$group_dir" ]]; then
    print -u2 "wsproj::package_path: group '$pkg_group' has no dir"
    return 2
  fi
  print -r -- "../$group_dir/$pkg"
  return 0
}

wsproj::inject_deps() {
  local repo_dir="$1"
  local main_target="$2"
  if [[ -z "$repo_dir" || -z "$main_target" ]]; then
    print -u2 "wsproj::inject_deps: usage: <repo-dir> <main-target-name>"
    return 4
  fi
  local proj_yml="$repo_dir/project.yml"
  if [[ ! -f "$proj_yml" ]]; then
    print -u2 "wsproj::inject_deps: $proj_yml not found"
    return 4
  fi
  if ! command -v yq >/dev/null 2>&1; then
    print -u2 "wsproj::inject_deps: yq not on PATH"
    return 3
  fi
  if [[ -z "${_WSYML_STATE[json]:-}" ]]; then
    print -u2 "wsproj::inject_deps: no workspace.yml loaded"
    return 4
  fi
  local has_target
  has_target="$(yq eval ".targets | has(\"$main_target\")" "$proj_yml" 2>/dev/null || echo false)"
  if [[ "$has_target" != "true" ]]; then
    print -u2 "wsproj::inject_deps: target '$main_target' not found in $proj_yml"
    return 2
  fi
  local pkgs
  pkgs="$(wsyml::packages)"
  local p path_rel already
  for p in ${(f)pkgs}; do
    [[ -z "$p" ]] && continue
    path_rel="$(wsproj::package_path "$p")" || return $?
    yq eval -i ".packages.\"$p\".path = \"$path_rel\"" "$proj_yml" || return 4
    already="$(yq eval ".targets.\"$main_target\".dependencies[]? | select(.package == \"$p\") | .package" "$proj_yml" 2>/dev/null || true)"
    if [[ -z "$already" ]]; then
      yq eval -i ".targets.\"$main_target\".dependencies += [{\"package\": \"$p\"}]" "$proj_yml" || return 4
    fi
  done
  return 0
}

wsproj::append_workspace_meta() {
  local repo_dir="$1"
  if [[ -z "$repo_dir" ]]; then
    print -u2 "wsproj::append_workspace_meta: usage: <repo-dir>"
    return 4
  fi
  local file="$repo_dir/CLAUDE-swift-toolkit.md"
  if [[ ! -f "$file" || ! -w "$file" ]]; then
    print -u2 "wsproj::append_workspace_meta: cannot read+write $file"
    return 4
  fi
  if grep -q '^## Workspace meta' "$file"; then
    return 0
  fi
  if [[ -z "${_WSYML_STATE[json]:-}" ]]; then
    print -u2 "wsproj::append_workspace_meta: no workspace.yml loaded"
    return 4
  fi
  local ws_name
  ws_name="$(wsyml::get '.workspace.name')"
  local meta_dir="${ws_name}-meta"
  cat >> "$file" <<EOF

## Workspace meta

- Workspace name: ${ws_name} (../${meta_dir})
- Available packages: see \`../${meta_dir}/workspace.yml\`
- This project is part of a multi-package SPM workspace
EOF
  return 0
}
