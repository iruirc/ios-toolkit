#!/usr/bin/env bats
load "$(dirname "$BATS_TEST_FILENAME")/../helpers/ws-test-helpers"

setup() { WS_TEST_TMPDIRS=(); }
teardown() { ws_cleanup_tmpdirs; }

@test "ws-init-driver creates 2 project-repos from with-project-full.yml" {
  if ! command -v xcodegen >/dev/null 2>&1; then
    skip "xcodegen not on PATH"
  fi
  local parent="$(ws_mktemp_dir)"
  run "$(ws_repo_root)/tests/foundation/helpers/ws-init-driver.zsh" \
    "$(ws_fixture_path workspace-yml/with-project-full.yml)" "$parent"
  [ "$status" -eq 0 ]
  [ -d "$parent/FullApp-iOS" ]
  [ -d "$parent/FullApp-macOS" ]
  [ -f "$parent/FullApp-iOS/project.yml" ]
  [ -f "$parent/FullApp-macOS/project.yml" ]
  [ -d "$parent/FullApp-iOS/FullApp.xcodeproj" ]
  [ -d "$parent/FullApp-macOS/FullApp.xcodeproj" ]
  [ -d "$parent/FullApp-iOS/.git" ]
  [ -d "$parent/FullApp-macOS/.git" ]
  run grep '^## Workspace meta' "$parent/FullApp-iOS/CLAUDE-swift-toolkit.md"
  [ "$status" -eq 0 ]
  run grep '^## Workspace meta' "$parent/FullApp-macOS/CLAUDE-swift-toolkit.md"
  [ "$status" -eq 0 ]
  run yq eval '.packages.CoreKit.path' "$parent/FullApp-iOS/project.yml"
  [ "$output" = "../packages/CoreKit" ]
  run yq eval '.packages.Engine.path' "$parent/FullApp-iOS/project.yml"
  [ "$output" = "../packages/Engine" ]
  run yq eval '.targets."FullApp-iOS".dependencies | length' "$parent/FullApp-iOS/project.yml"
  [ "$output" -eq 2 ]
}

@test "xcworkspace contains PROJECT_REFS for both apps" {
  if ! command -v xcodegen >/dev/null 2>&1; then
    skip "xcodegen not on PATH"
  fi
  local parent="$(ws_mktemp_dir)"
  "$(ws_repo_root)/tests/foundation/helpers/ws-init-driver.zsh" \
    "$(ws_fixture_path workspace-yml/with-project-full.yml)" "$parent" >&2
  local xcws="$parent/FullProj-meta/FullProj.xcworkspace/contents.xcworkspacedata"
  [ -f "$xcws" ]
  run grep -F 'group:../FullApp-iOS/FullApp.xcodeproj' "$xcws"
  [ "$status" -eq 0 ]
  run grep -F 'group:../FullApp-macOS/FullApp.xcodeproj' "$xcws"
  [ "$status" -eq 0 ]
}

@test "shortform yml produces same FS shape as long-form" {
  if ! command -v xcodegen >/dev/null 2>&1; then
    skip "xcodegen not on PATH"
  fi
  local parent="$(ws_mktemp_dir)"
  run "$(ws_repo_root)/tests/foundation/helpers/ws-init-driver.zsh" \
    "$(ws_fixture_path workspace-yml/with-project-shortform.yml)" "$parent"
  [ "$status" -eq 0 ]
  [ -f "$parent/ShortApp-iOS/project.yml" ]
  [ -d "$parent/ShortApp-iOS/ShortApp.xcodeproj" ]
  [ -d "$parent/ShortApp-iOS/.git" ]
  run yq eval '.packages.A.path' "$parent/ShortApp-iOS/project.yml"
  [ "$output" = "../packages/A" ]
  run yq eval '.targets."ShortApp-iOS".dependencies | length' "$parent/ShortApp-iOS/project.yml"
  [ "$output" -eq 1 ]
}
