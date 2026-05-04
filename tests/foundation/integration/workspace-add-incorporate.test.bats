#!/usr/bin/env bats
load "$(dirname "$BATS_TEST_FILENAME")/../helpers/ws-test-helpers"

setup() { WS_TEST_TMPDIRS=(); }
teardown() { ws_cleanup_tmpdirs; }

@test "incorporate bare package: CLAUDE.md is created" {
  local target="$(ws_mktemp_dir)/BareKit"
  mkdir -p "$target"
  echo "fake Package.swift" > "$target/Package.swift"
  run "$(ws_repo_root)/tests/foundation/helpers/ws-add-driver.zsh" "$target" engine BareKit
  [ "$status" -eq 0 ]
  [ -f "$target/CLAUDE.md" ]
  run grep -F '**Archetype**: engine' "$target/CLAUDE.md"
  [ "$status" -eq 0 ]
}

@test "incorporate package with existing CLAUDE.md: it is preserved + warning emitted" {
  local target="$(ws_mktemp_dir)/HasCLAUDE"
  mkdir -p "$target"
  echo "fake Package.swift" > "$target/Package.swift"
  echo "USER_OWNED_CONTENT" > "$target/CLAUDE.md"
  run "$(ws_repo_root)/tests/foundation/helpers/ws-add-driver.zsh" "$target" engine HasCLAUDE
  [ "$status" -eq 0 ]
  run cat "$target/CLAUDE.md"
  [[ "$output" == *"USER_OWNED_CONTENT"* ]]
}
