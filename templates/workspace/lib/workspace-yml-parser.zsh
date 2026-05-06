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
  # Hoist all per-iteration locals to the top so subsequent loop assignments
  # don't re-declare. In zsh, a bare `local NAME` (no RHS) for a name that's
  # already declared in the same function prints `name=value` to stdout.
  local errs=0
  local _path="${_WSYML_STATE[path]}"
  local ws_name pkg_count pkgs groups remote_list
  local known_archs="api-contract engine library feature"
  local p g d r k pg deps git_keys arch ver allowed a
  local example_app example_platform tasks_path tasks_mode author
  local -A seen group_set remote_set allowed_set

  # Rule 1: workspace.name required, matches [A-Za-z][A-Za-z0-9-]*
  ws_name="$(wsyml::get '.workspace.name' || true)"
  if [[ -z "$ws_name" ]]; then
    print -u2 "$_path: workspace.name is required"
    ((errs++))
  elif [[ ! "$ws_name" =~ ^[A-Za-z][A-Za-z0-9-]*$ ]]; then
    print -u2 "$_path: workspace.name '$ws_name' must match [A-Za-z][A-Za-z0-9-]*"
    ((errs++))
  fi

  # Rule 2: packages required, >= 1
  pkg_count="$(wsyml::get '.packages | length' || echo 0)"
  if (( pkg_count < 1 )); then
    print -u2 "$_path: packages must have at least 1 entry"
    ((errs++))
  fi

  # Rule 3: package name uniqueness
  pkgs="$(wsyml::packages)"
  for p in ${(f)pkgs}; do
    if (( ${+seen[$p]} )); then
      print -u2 "$_path: duplicate package name '$p'"
      ((errs++))
    fi
    seen[$p]=1
  done

  # Rule 4: package_groups reference check
  groups="$(wsyml::groups || true)"
  if [[ -n "$groups" ]]; then
    for g in ${(f)groups}; do group_set[$g]=1; done
    for p in ${(f)pkgs}; do
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
  remote_list="$(wsyml::remotes || true)"
  for r in ${(f)remote_list}; do remote_set[$r]=1; done

  for p in ${(f)pkgs}; do
    # Rule 5: deps reference
    deps="$(wsyml::package_field "$p" 'deps[]' 2>/dev/null || true)"
    for d in ${(f)deps}; do
      if (( ! ${+seen[$d]} )); then
        print -u2 "$_path: package '$p' depends on unknown package '$d'"
        ((errs++))
      fi
    done

    # Rule 6: git remotes subset
    git_keys="$(wsyml::get ".packages[] | select(.name == \"$p\") | .git | keys | .[]" 2>/dev/null || true)"
    if [[ -z "$git_keys" ]]; then
      print -u2 "$_path: package '$p' git map must be non-empty"
      ((errs++))
    fi
    for k in ${(f)git_keys}; do
      if (( ! ${+remote_set[$k]} )); then
        print -u2 "$_path: package '$p' uses unknown remote '$k' (declare in top-level remotes[])"
        ((errs++))
      fi
    done

    # Rule 7: archetype enum
    arch="$(wsyml::package_field "$p" archetype || true)"
    if [[ -z "$arch" || ! " $known_archs " == *" $arch "* ]]; then
      print -u2 "$_path: package '$p' invalid archetype '$arch' (allowed: $known_archs)"
      ((errs++))
    fi

    # Rule 8: semver M.m.p, no pre-release/build
    ver="$(wsyml::package_field "$p" version || true)"
    if [[ ! "$ver" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      print -u2 "$_path: package '$p' invalid version '$ver' (expected M.m.p)"
      ((errs++))
    fi

    # Rule 10: deps subset of allowed_deps when allowed_deps non-empty
    allowed="$(wsyml::get ".packages[] | select(.name == \"$p\") | .allowed_deps[]?" 2>/dev/null || true)"
    if [[ -n "$allowed" ]]; then
      # Reset per-package allowed_set (assoc arrays don't auto-clear in loop).
      allowed_set=()
      for a in ${(f)allowed}; do allowed_set[$a]=1; done
      for d in ${(f)deps}; do
        if (( ! ${+allowed_set[$d]} )); then
          print -u2 "$_path: package '$p' dep '$d' not in allowed_deps"
          ((errs++))
        fi
      done
    fi

    # Rule 13: example_app/example_platform pairing
    example_app="$(wsyml::package_field "$p" example_app 2>/dev/null || echo '')"
    if [[ "$example_app" == "true" ]]; then
      example_platform="$(wsyml::package_field "$p" example_platform 2>/dev/null || echo '')"
      if [[ ! "$example_platform" =~ ^(ios|macos|both)$ ]]; then
        print -u2 "$_path: package '$p' example_app: true requires example_platform (ios|macos|both); got '$example_platform'"
        ((errs++))
      fi
    fi
  done

  # Rule 11: tasks.symlink_mode consistency
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
  author="$(wsyml::get '.bootstrap.git_author' 2>/dev/null || true)"
  if [[ -n "$author" && "$author" != "null" ]]; then
    if [[ ! "$author" =~ '^[^<]+<[^@]+@[^>]+>$' ]]; then
      print -u2 "$_path: bootstrap.git_author '$author' must match 'Name <email@host>'"
      ((errs++))
    fi
  fi

  # Project block validation (P-rules 1, 2, 3, 3a, 4-8)
  local has_project
  has_project="$(wsyml::get '.project | length' 2>/dev/null || echo 0)"
  if (( has_project > 0 )); then
    # P-rule 1: project.name regex
    local proj_name
    proj_name="$(wsyml::get '.project.name' 2>/dev/null || echo '')"
    if [[ -z "$proj_name" ]]; then
      print -u2 "$_path: project.name is required when project block present"
      ((errs++))
    elif [[ ! "$proj_name" =~ ^[A-Za-z][A-Za-z0-9-]*$ ]]; then
      print -u2 "$_path: project.name '$proj_name' must match [A-Za-z][A-Za-z0-9-]*"
      ((errs++))
    fi

    # P-rule 2: project.apps keys ⊆ {ios, macos} (MVP)
    local app_keys
    app_keys="$(wsyml::get '.project.apps | keys | .[]' 2>/dev/null || true)"
    if [[ -z "$app_keys" ]]; then
      print -u2 "$_path: project.apps must have at least 1 entry (ios|macos)"
      ((errs++))
    fi
    local ak
    for ak in ${(f)app_keys}; do
      case "$ak" in
        ios|macos) ;;
        *)
          print -u2 "$_path: apps.$ak rejected (MVP supports ios|macos only)"
          ((errs++))
          ;;
      esac
    done

    # P-rule 3 + 3a: repo regex, uniqueness, no collision with package names.
    # Normalize short-form (string) to long-form ({repo: <string>}) implicitly via wsyml::get.
    local -A seen_repos
    for ak in ${(f)app_keys}; do
      [[ "$ak" =~ ^(ios|macos)$ ]] || continue
      local app_repo
      # Try long-form first (.project.apps.<key>.repo), fall back to string-form (.project.apps.<key>)
      app_repo="$(wsyml::get ".project.apps.$ak.repo" 2>/dev/null || true)"
      if [[ -z "$app_repo" ]]; then
        app_repo="$(wsyml::get ".project.apps.$ak" 2>/dev/null || true)"
        # Skip if it's not a scalar string (it would be a map without .repo, which is invalid)
        if [[ "$app_repo" == *":"* || "$app_repo" == *"{"* ]]; then
          print -u2 "$_path: project.apps.$ak missing .repo field"
          ((errs++))
          continue
        fi
      fi
      if [[ -z "$app_repo" ]]; then
        print -u2 "$_path: project.apps.$ak.repo is required"
        ((errs++))
        continue
      fi
      if [[ ! "$app_repo" =~ ^[A-Za-z][A-Za-z0-9-]*$ ]]; then
        print -u2 "$_path: project.apps.$ak.repo '$app_repo' must match [A-Za-z][A-Za-z0-9-]*"
        ((errs++))
      fi
      if (( ${+seen_repos[$app_repo]} )); then
        print -u2 "$_path: duplicate repo name '$app_repo' in project.apps"
        ((errs++))
      fi
      seen_repos[$app_repo]=1
      # P-rule 3a: collision with package names (Foundation populates `seen` with package names in rule 3)
      if (( ${+seen[$app_repo]} )); then
        print -u2 "$_path: repo name '$app_repo' collides with package name '$app_repo'"
        ((errs++))
      fi
    done

    # P-rules 4-7: stack enum validation (per app)
    local v mp_keys mpk mpv
    for ak in ${(f)app_keys}; do
      [[ "$ak" =~ ^(ios|macos)$ ]] || continue
      # P-rule 4: ui_framework
      v="$(wsyml::get ".project.apps.$ak.stack.ui_framework" 2>/dev/null || true)"
      if [[ -n "$v" && ! "$v" =~ ^(swiftui|uikit|appkit)$ ]]; then
        print -u2 "$_path: project.apps.$ak.stack.ui_framework '$v' must be swiftui|uikit|appkit"
        ((errs++))
      fi
      # P-rule 5: di
      v="$(wsyml::get ".project.apps.$ak.stack.di" 2>/dev/null || true)"
      if [[ -n "$v" && ! "$v" =~ ^(factory|swinject|manual-factory|plain)$ ]]; then
        print -u2 "$_path: project.apps.$ak.stack.di '$v' must be factory|swinject|manual-factory|plain"
        ((errs++))
      fi
      # P-rule 6: architecture
      v="$(wsyml::get ".project.apps.$ak.stack.architecture" 2>/dev/null || true)"
      if [[ -n "$v" && ! "$v" =~ ^(mvvm-coordinator|mvvm|viper|clean|mvc|tca)$ ]]; then
        print -u2 "$_path: project.apps.$ak.stack.architecture '$v' must be mvvm-coordinator|mvvm|viper|clean|mvc|tca"
        ((errs++))
      fi
      # P-rule 7: async
      v="$(wsyml::get ".project.apps.$ak.stack.async" 2>/dev/null || true)"
      if [[ -n "$v" && ! "$v" =~ ^(async-await|combine|rxswift)$ ]]; then
        print -u2 "$_path: project.apps.$ak.stack.async '$v' must be async-await|combine|rxswift"
        ((errs++))
      fi
      # P-rule 8: min_platforms.<sub-platform> semver (M.m.p flexible: 1, 1.0, 1.0.0)
      mp_keys="$(wsyml::get ".project.apps.$ak.stack.min_platforms | keys | .[]?" 2>/dev/null || true)"
      for mpk in ${(f)mp_keys}; do
        [[ -z "$mpk" ]] && continue
        mpv="$(wsyml::get ".project.apps.$ak.stack.min_platforms.$mpk" 2>/dev/null || true)"
        if [[ -n "$mpv" && ! "$mpv" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]]; then
          print -u2 "$_path: project.apps.$ak.stack.min_platforms.$mpk '$mpv' must match semver M.m.p"
          ((errs++))
        fi
      done
    done
  fi

  if (( errs > 0 )); then
    print -u2 "$errs error(s)."
    return 2
  fi
  return 0
}
