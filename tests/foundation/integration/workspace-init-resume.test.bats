#!/usr/bin/env bats
load "$(dirname "$BATS_TEST_FILENAME")/../helpers/ws-test-helpers"

setup() { WS_TEST_TMPDIRS=(); }
teardown() { ws_cleanup_tmpdirs; }

@test "rerunning ws-init-driver is a no-op when artifacts exist (idempotent)" {
  local parent="$(ws_mktemp_dir)"
  run "$(ws_repo_root)/tests/foundation/helpers/ws-init-driver.zsh" \
    "$(ws_fixture_path workspace-yml/grouped.yml)" "$parent"
  [ "$status" -eq 0 ]
  local before_hash="$(find "$parent" -type f -not -path '*/.git/*' -exec md5 -q {} + | md5 -q)"
  run "$(ws_repo_root)/tests/foundation/helpers/ws-init-driver.zsh" \
    "$(ws_fixture_path workspace-yml/grouped.yml)" "$parent"
  [ "$status" -eq 0 ]
  local after_hash="$(find "$parent" -type f -not -path '*/.git/*' -exec md5 -q {} + | md5 -q)"
  [ "$before_hash" = "$after_hash" ]
}
