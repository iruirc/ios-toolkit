#!/usr/bin/env bats
load "$(dirname "$BATS_TEST_FILENAME")/../helpers/ws-test-helpers"

setup() { WS_TEST_TMPDIRS=(); }
teardown() { ws_cleanup_tmpdirs; }

@test "ws-init-driver creates meta-repo + per-package dirs from grouped.yml" {
  local parent="$(ws_mktemp_dir)"
  run "$(ws_repo_root)/tests/foundation/helpers/ws-init-driver.zsh" \
    "$(ws_fixture_path workspace-yml/grouped.yml)" "$parent"
  [ "$status" -eq 0 ]
  [ -d "$parent/GroupedWS-meta/.git" ]
  [ -f "$parent/GroupedWS-meta/workspace.yml" ]
  [ -f "$parent/GroupedWS-meta/README.md" ]
  [ -f "$parent/commonPackages/AKit/Package.swift" ]
  [ -f "$parent/commonPackages/AKit/CLAUDE.md" ]
  [ -f "$parent/domainPackages/CFeature/Package.swift" ]
  [ -d "$parent/commonPackages/AKit/.git" ]
}

@test "ws-init-driver fails on cyclic.yml" {
  local parent="$(ws_mktemp_dir)"
  run "$(ws_repo_root)/tests/foundation/helpers/ws-init-driver.zsh" \
    "$(ws_fixture_path workspace-yml/cyclic.yml)" "$parent"
  [ "$status" -ne 0 ]
}
