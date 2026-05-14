#!/usr/bin/env zsh
# Per-app driver for project integration (s06b/c/d/e equivalent).
# NOT shipped to users — testing only. Stubs swift-init output with a minimal project.yml,
# then exercises wsproj::* functions + xcodegen against real templates.

set -euo pipefail

ws_yml="${1:?usage: ws-project-init-driver.zsh <workspace.yml> <workspace-parent-dir> <platform> <repo-name>}"
ws_parent="${2:?}"
platform="${3:?}"
repo_name="${4:?}"

source "${0:A:h}/../../../templates/workspace/lib/workspace-yml-parser.zsh"
source "${0:A:h}/../../../templates/workspace/lib/workspace-project.zsh"

wsyml::load "$ws_yml" >&2 || exit $?

repo_dir="$ws_parent/$repo_name"
mkdir -p "$repo_dir/Sources" "$repo_dir/Tests"

case "$platform" in
  ios)
    sdk_platform="iOS"
    deployment_target="$(wsyml::get ".project.apps.ios.stack.min_platforms.ios" 2>/dev/null || echo '17.0')"
    ;;
  macos)
    sdk_platform="macOS"
    deployment_target="$(wsyml::get ".project.apps.macos.stack.min_platforms.macos" 2>/dev/null || echo '14.0')"
    ;;
  *)
    print -u2 "ws-project-init-driver: unknown platform '$platform'"
    exit 2
    ;;
esac

proj_name="$(wsyml::get '.project.name' 2>/dev/null || echo "$repo_name")"

cat > "$repo_dir/project.yml" <<EOF
name: $proj_name
options:
  bundleIdPrefix: com.example
  deploymentTarget:
    iOS: "$deployment_target"
    macOS: "$deployment_target"
targets:
  $repo_name:
    type: application
    platform: $sdk_platform
    sources: [Sources]
    dependencies: []
EOF

cat > "$repo_dir/CLAUDE-swift-toolkit.md" <<EOF
# Toolkit configuration — $repo_name

## Stack

(stub stack section — populated by swift-init in production)
EOF

touch "$repo_dir/.swift-init.done"

# s06c: inject deps + run xcodegen
wsproj::inject_deps "$repo_dir" "$repo_name"
( cd "$repo_dir" && xcodegen generate >&2 ) || {
  print -u2 "ws-project-init-driver: xcodegen generate failed in $repo_dir"
  exit 1
}

# s06d: append workspace meta
wsproj::append_workspace_meta "$repo_dir"

# s06e: git init
( cd "$repo_dir" && git init -q -b main )

print "ws-project-init-driver: done $repo_dir"
