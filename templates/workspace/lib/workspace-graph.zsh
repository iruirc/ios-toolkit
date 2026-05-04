#!/usr/bin/env zsh
# workspace-graph.zsh — graph operations over the package dep graph.
# Foundation subset: cycle detection only. Cluster 2 adds topological sort.

wsgraph::check_acyclic() {
  if [[ -z "${_WSYML_STATE[json]:-}" ]]; then
    print -u2 "wsgraph::check_acyclic: no document loaded"
    return 4
  fi
  local pkgs
  pkgs="$(wsyml::packages)"
  typeset -A color   # 0/unset=white, 1=gray, 2=black
  local -a stack

  _wsgraph_dfs() {
    local node="$1"
    color[$node]=1
    stack+=("$node")
    local deps
    deps="$(wsyml::get ".packages[] | select(.name == \"$node\") | .deps[]?" 2>/dev/null || true)"
    local d
    for d in ${(f)deps}; do
      [[ -z "$d" ]] && continue
      case "${color[$d]:-0}" in
        0) _wsgraph_dfs "$d" || return $? ;;
        1)
          local idx="${stack[(I)$d]}"
          local cycle="${(j: -> :)stack[$idx,-1]} -> $d"
          print -u2 "${_WSYML_STATE[path]}: cycle detected: $cycle"
          return 2
          ;;
        2) ;;
      esac
    done
    color[$node]=2
    stack=( "${stack[1,-2]}" )
    return 0
  }

  local p rc=0
  for p in ${(f)pkgs}; do
    if [[ "${color[$p]:-0}" == 0 ]]; then
      _wsgraph_dfs "$p" || rc=$?
      [[ $rc -ne 0 ]] && return $rc
    fi
  done
  return 0
}
