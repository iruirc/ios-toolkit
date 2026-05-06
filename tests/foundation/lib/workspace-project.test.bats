#!/usr/bin/env bats
load "$(dirname "$BATS_TEST_FILENAME")/../helpers/ws-test-helpers"

setup() { WS_TEST_TMPDIRS=(); }
teardown() { ws_cleanup_tmpdirs; }

@test "wsproj::package_path returns flat layout path" {
  run zsh -c "source '$(ws_lib_path workspace-yml-parser.zsh)'; source '$(ws_lib_path workspace-project.zsh)'; wsyml::load '$(ws_fixture_path workspace-yml/with-project-minimal.yml)'; wsproj::package_path CoreKit"
  [ "$status" -eq 0 ]
  [ "$output" = "../packages/CoreKit" ]
}

@test "wsproj::package_path returns grouped path" {
  run zsh -c "source '$(ws_lib_path workspace-yml-parser.zsh)'; source '$(ws_lib_path workspace-project.zsh)'; wsyml::load '$(ws_fixture_path workspace-yml/grouped.yml)'; wsproj::package_path BEngine"
  [ "$status" -eq 0 ]
  [ "$output" = "../commonPackages/BEngine" ]
}

@test "wsproj::inject_deps adds packages: block and target dependencies" {
  local tmpd
  tmpd="$(ws_mktemp_dir)"
  mkdir -p "$tmpd/MyApp-iOS"
  cat > "$tmpd/MyApp-iOS/project.yml" <<'EOF'
name: MyApp-iOS
options:
  bundleIdPrefix: com.example
targets:
  MyApp-iOS:
    type: application
    platform: iOS
    sources: [Sources]
    dependencies: []
EOF
  run zsh -c "
    source '$(ws_lib_path workspace-yml-parser.zsh)'
    source '$(ws_lib_path workspace-project.zsh)'
    wsyml::load '$(ws_fixture_path workspace-yml/with-project-full.yml)'
    cd '$tmpd/MyApp-iOS' && wsproj::inject_deps . MyApp-iOS
  "
  [ "$status" -eq 0 ]
  run yq eval '.packages.CoreKit.path' "$tmpd/MyApp-iOS/project.yml"
  [ "$output" = "../packages/CoreKit" ]
  run yq eval '.packages.Engine.path' "$tmpd/MyApp-iOS/project.yml"
  [ "$output" = "../packages/Engine" ]
  run yq eval '.targets."MyApp-iOS".dependencies | length' "$tmpd/MyApp-iOS/project.yml"
  [ "$output" -eq 2 ]
}

@test "wsproj::inject_deps preserves existing external dependencies" {
  local tmpd
  tmpd="$(ws_mktemp_dir)"
  mkdir -p "$tmpd/MyApp-iOS"
  cat > "$tmpd/MyApp-iOS/project.yml" <<'EOF'
name: MyApp-iOS
packages:
  Alamofire:
    url: https://github.com/Alamofire/Alamofire
    from: 5.0.0
targets:
  MyApp-iOS:
    type: application
    platform: iOS
    sources: [Sources]
    dependencies:
      - package: Alamofire
EOF
  run zsh -c "
    source '$(ws_lib_path workspace-yml-parser.zsh)'
    source '$(ws_lib_path workspace-project.zsh)'
    wsyml::load '$(ws_fixture_path workspace-yml/with-project-full.yml)'
    cd '$tmpd/MyApp-iOS' && wsproj::inject_deps . MyApp-iOS
  "
  [ "$status" -eq 0 ]
  run yq eval '.packages.Alamofire.url' "$tmpd/MyApp-iOS/project.yml"
  [ "$output" = "https://github.com/Alamofire/Alamofire" ]
  run yq eval '.packages.CoreKit.path' "$tmpd/MyApp-iOS/project.yml"
  [ "$output" = "../packages/CoreKit" ]
  run yq eval '.targets."MyApp-iOS".dependencies | length' "$tmpd/MyApp-iOS/project.yml"
  [ "$output" -eq 3 ]
}

@test "wsproj::append_workspace_meta adds Workspace meta section" {
  local tmpd="$(ws_mktemp_dir)/MyApp-iOS"
  mkdir -p "$tmpd"
  cat > "$tmpd/CLAUDE-swift-toolkit.md" <<'EOF'
# Toolkit configuration — MyApp-iOS

## Stack

mvvm-coordinator
EOF
  run zsh -c "
    source '$(ws_lib_path workspace-yml-parser.zsh)'
    source '$(ws_lib_path workspace-project.zsh)'
    wsyml::load '$(ws_fixture_path workspace-yml/with-project-full.yml)'
    wsproj::append_workspace_meta '$tmpd'
  "
  [ "$status" -eq 0 ]
  run grep '^## Workspace meta' "$tmpd/CLAUDE-swift-toolkit.md"
  [ "$status" -eq 0 ]
  run grep -F 'Workspace name: FullProj (../FullProj-meta)' "$tmpd/CLAUDE-swift-toolkit.md"
  [ "$status" -eq 0 ]
}

@test "wsproj::append_workspace_meta is idempotent" {
  local tmpd="$(ws_mktemp_dir)/MyApp-iOS"
  mkdir -p "$tmpd"
  cat > "$tmpd/CLAUDE-swift-toolkit.md" <<'EOF'
# Toolkit configuration — MyApp-iOS
EOF
  zsh -c "
    source '$(ws_lib_path workspace-yml-parser.zsh)'
    source '$(ws_lib_path workspace-project.zsh)'
    wsyml::load '$(ws_fixture_path workspace-yml/with-project-full.yml)'
    wsproj::append_workspace_meta '$tmpd'
  "
  local count_before
  count_before="$(grep -c '^## Workspace meta' "$tmpd/CLAUDE-swift-toolkit.md")"
  zsh -c "
    source '$(ws_lib_path workspace-yml-parser.zsh)'
    source '$(ws_lib_path workspace-project.zsh)'
    wsyml::load '$(ws_fixture_path workspace-yml/with-project-full.yml)'
    wsproj::append_workspace_meta '$tmpd'
  "
  local count_after
  count_after="$(grep -c '^## Workspace meta' "$tmpd/CLAUDE-swift-toolkit.md")"
  [ "$count_before" -eq 1 ]
  [ "$count_after" -eq 1 ]
}
