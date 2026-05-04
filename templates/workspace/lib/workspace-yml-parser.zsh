#!/usr/bin/env zsh
# workspace-yml-parser.zsh — load + query + validate workspace.yml.
# Public API: wsyml::load, wsyml::get, wsyml::validate, wsyml::packages, wsyml::package_field, wsyml::groups, wsyml::remotes

typeset -gA _WSYML_STATE

wsyml::load() {
  # NOTE: do not name this local `path` — in zsh `path` is tied to `PATH`,
  # so `local path=...` clobbers the array used for command lookup and
  # breaks every subsequent `command -v` / external invocation.
  local _path="$1"
  if [[ -z "$_path" ]]; then
    print -u2 "wsyml::load: missing path argument"
    return 4
  fi
  if [[ ! -r "$_path" ]]; then
    print -u2 "wsyml::load: cannot read $_path"
    return 4
  fi
  if ! command -v yq >/dev/null 2>&1; then
    print -u2 "wsyml::load: yq not on PATH (install: brew install yq)"
    return 3
  fi
  local json
  if ! json="$(yq -o=json eval '.' "$_path" 2>&1)"; then
    print -u2 "wsyml::load: yq parse failed: $json"
    return 2
  fi
  _WSYML_STATE[json]="$json"
  _WSYML_STATE[path]="$_path"
  return 0
}

wsyml::get() {
  local expr="$1"
  if [[ -z "${_WSYML_STATE[json]:-}" ]]; then
    print -u2 "wsyml::get: no document loaded; call wsyml::load first"
    return 4
  fi
  local val
  val="$(print -r -- "${_WSYML_STATE[json]}" | yq -p=json -o=tsv eval "$expr" - 2>/dev/null)"
  if [[ -z "$val" || "$val" == "null" ]]; then
    return 1
  fi
  print -r -- "$val"
  return 0
}

wsyml::packages() {
  wsyml::get '.packages[].name'
}

wsyml::groups() {
  wsyml::get '.package_groups[].name'
}

wsyml::remotes() {
  wsyml::get '.remotes[]'
}

wsyml::package_field() {
  local name="$1" key="$2"
  if [[ -z "$name" || -z "$key" ]]; then
    print -u2 "wsyml::package_field: usage: <package-name> <field-key>"
    return 4
  fi
  wsyml::get ".packages[] | select(.name == \"$name\") | .$key"
}

wsyml::validate() {
  if [[ -z "${_WSYML_STATE[json]:-}" ]]; then
    print -u2 "wsyml::validate: no document loaded"
    return 4
  fi
  local errs=0
  local _path="${_WSYML_STATE[path]}"

  # Rule 1: workspace.name required, matches [A-Za-z][A-Za-z0-9-]*
  local ws_name
  ws_name="$(wsyml::get '.workspace.name' || true)"
  if [[ -z "$ws_name" ]]; then
    print -u2 "$_path: workspace.name is required"
    ((errs++))
  elif [[ ! "$ws_name" =~ ^[A-Za-z][A-Za-z0-9-]*$ ]]; then
    print -u2 "$_path: workspace.name '$ws_name' must match [A-Za-z][A-Za-z0-9-]*"
    ((errs++))
  fi

  # Rule 2: packages required, >= 1
  local pkg_count
  pkg_count="$(wsyml::get '.packages | length' || echo 0)"
  if (( pkg_count < 1 )); then
    print -u2 "$_path: packages must have at least 1 entry"
    ((errs++))
  fi

  # Rule 3: package name uniqueness
  local pkgs
  pkgs="$(wsyml::packages)"
  local -A seen
  local p
  for p in ${(f)pkgs}; do
    if (( ${+seen[$p]} )); then
      print -u2 "$_path: duplicate package name '$p'"
      ((errs++))
    fi
    seen[$p]=1
  done

  # Rule 4: package_groups reference check
  local groups
  groups="$(wsyml::groups || true)"
  if [[ -n "$groups" ]]; then
    local -A group_set
    local g
    for g in ${(f)groups}; do group_set[$g]=1; done
    for p in ${(f)pkgs}; do
      local pg
      pg="$(wsyml::package_field "$p" group || true)"
      if [[ -z "$pg" ]]; then
        print -u2 "$_path: package '$p' missing required group (package_groups present)"
        ((errs++))
      elif (( ! ${+group_set[$pg]} )); then
        print -u2 "$_path: package '$p' references unknown group '$pg'"
        ((errs++))
      fi
    done
  fi

  # Rule 5–8: per-package field checks
  local known_archs="api-contract engine library feature"
  local remote_list
  remote_list="$(wsyml::remotes || true)"
  local -A remote_set
  local r
  for r in ${(f)remote_list}; do remote_set[$r]=1; done

  for p in ${(f)pkgs}; do
    # Rule 5: deps reference
    local deps
    deps="$(wsyml::package_field "$p" 'deps[]' 2>/dev/null || true)"
    local d
    for d in ${(f)deps}; do
      if (( ! ${+seen[$d]} )); then
        print -u2 "$_path: package '$p' depends on unknown package '$d'"
        ((errs++))
      fi
    done

    # Rule 6: git remotes subset
    local git_keys
    git_keys="$(wsyml::get ".packages[] | select(.name == \"$p\") | .git | keys | .[]" 2>/dev/null || true)"
    if [[ -z "$git_keys" ]]; then
      print -u2 "$_path: package '$p' git map must be non-empty"
      ((errs++))
    fi
    local k
    for k in ${(f)git_keys}; do
      if (( ! ${+remote_set[$k]} )); then
        print -u2 "$_path: package '$p' uses unknown remote '$k' (declare in top-level remotes[])"
        ((errs++))
      fi
    done

    # Rule 7: archetype enum
    local arch
    arch="$(wsyml::package_field "$p" archetype || true)"
    if [[ -z "$arch" || ! " $known_archs " == *" $arch "* ]]; then
      print -u2 "$_path: package '$p' invalid archetype '$arch' (allowed: $known_archs)"
      ((errs++))
    fi

    # Rule 8: semver M.m.p, no pre-release/build
    local ver
    ver="$(wsyml::package_field "$p" version || true)"
    if [[ ! "$ver" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      print -u2 "$_path: package '$p' invalid version '$ver' (expected M.m.p)"
      ((errs++))
    fi

    # Rule 10: deps subset of allowed_deps when allowed_deps non-empty
    local allowed
    allowed="$(wsyml::get ".packages[] | select(.name == \"$p\") | .allowed_deps[]?" 2>/dev/null || true)"
    if [[ -n "$allowed" ]]; then
      local -A allowed_set
      local a
      for a in ${(f)allowed}; do allowed_set[$a]=1; done
      for d in ${(f)deps}; do
        if (( ! ${+allowed_set[$d]} )); then
          print -u2 "$_path: package '$p' dep '$d' not in allowed_deps"
          ((errs++))
        fi
      done
    fi

    # Rule 13: example_app/example_platform pairing
    local example_app
    example_app="$(wsyml::package_field "$p" example_app 2>/dev/null || echo '')"
    if [[ "$example_app" == "true" ]]; then
      local example_platform
      example_platform="$(wsyml::package_field "$p" example_platform 2>/dev/null || echo '')"
      if [[ ! "$example_platform" =~ ^(ios|macos|both)$ ]]; then
        print -u2 "$_path: package '$p' example_app: true requires example_platform (ios|macos|both); got '$example_platform'"
        ((errs++))
      fi
    fi
  done

  # Rule 11: tasks.symlink_mode consistency
  local tasks_path tasks_mode
  tasks_path="$(wsyml::get '.workspace.tasks.path' 2>/dev/null || echo './Tasks')"
  tasks_mode="$(wsyml::get '.workspace.tasks.symlink_mode' 2>/dev/null || echo 'local')"
  case "$tasks_mode" in
    commit)
      if [[ "$tasks_path" = /* ]]; then
        print -u2 "$_path: tasks.symlink_mode 'commit' requires relative path; got '$tasks_path'"
        ((errs++))
      fi
      ;;
    local)
      ;;
    *)
      print -u2 "$_path: tasks.symlink_mode must be 'local' or 'commit'; got '$tasks_mode'"
      ((errs++))
      ;;
  esac

  # Rule 14: bootstrap.git_author format (when supplied)
  local author
  author="$(wsyml::get '.bootstrap.git_author' 2>/dev/null || true)"
  if [[ -n "$author" && "$author" != "null" ]]; then
    if [[ ! "$author" =~ '^[^<]+<[^@]+@[^>]+>$' ]]; then
      print -u2 "$_path: bootstrap.git_author '$author' must match 'Name <email@host>'"
      ((errs++))
    fi
  fi

  if (( errs > 0 )); then
    print -u2 "$errs error(s)."
    return 2
  fi
  return 0
}
