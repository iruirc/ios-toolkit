#!/usr/bin/env bats
load "$(dirname "$BATS_TEST_FILENAME")/../helpers/ws-test-helpers"

setup() { WS_TEST_TMPDIRS=(); }
teardown() { ws_cleanup_tmpdirs; }

@test "wsmark::read returns content between matching markers" {
  run zsh -c "source '$(ws_lib_path workspace-doc-markers.zsh)'; wsmark::read '$(ws_fixture_path markers/well-formed.md)' PKG_LIST"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "- A (api-contract)" ]
  [ "${lines[1]}" = "- B (engine)" ]
}

@test "wsmark::write replaces section content, leaves outside intact" {
  local tmp="$(ws_mktemp_dir)/file.md"
  cp "$(ws_fixture_path markers/well-formed.md)" "$tmp"
  run zsh -c "source '$(ws_lib_path workspace-doc-markers.zsh)'; printf '%s\n' '- C (library)' | wsmark::write '$tmp' PKG_LIST"
  [ "$status" -eq 0 ]
  run grep '^- C' "$tmp"
  [ "$status" -eq 0 ]
  run grep '^- A ' "$tmp"
  [ "$status" -eq 1 ]
  run grep '^Manual content' "$tmp"
  [ "$status" -eq 0 ]
  run grep '^More manual content' "$tmp"
  [ "$status" -eq 0 ]
}

@test "wsmark::lint passes well-formed.md" {
  run zsh -c "source '$(ws_lib_path workspace-doc-markers.zsh)'; wsmark::lint '$(ws_fixture_path markers/well-formed.md)'"
  [ "$status" -eq 0 ]
}

@test "wsmark::lint flags missing END" {
  run zsh -c "source '$(ws_lib_path workspace-doc-markers.zsh)'; wsmark::lint '$(ws_fixture_path markers/missing-end.md)'"
  [ "$status" -eq 2 ]
  [[ "$output" == *"missing WORKSPACE_PKG_LIST_END"* ]]
}

@test "wsmark::lint flags orphan END" {
  run zsh -c "source '$(ws_lib_path workspace-doc-markers.zsh)'; wsmark::lint '$(ws_fixture_path markers/orphan-end.md)'"
  [ "$status" -eq 2 ]
  [[ "$output" == *"orphan WORKSPACE_PKG_LIST_END"* ]]
}

@test "wsmark::lint flags duplicate BEGIN" {
  run zsh -c "source '$(ws_lib_path workspace-doc-markers.zsh)'; wsmark::lint '$(ws_fixture_path markers/duplicate-begin.md)'"
  [ "$status" -eq 2 ]
  [[ "$output" == *"duplicate WORKSPACE_PKG_LIST_BEGIN"* ]]
}

@test "wsmark::lint flags cross-nested pairs" {
  run zsh -c "source '$(ws_lib_path workspace-doc-markers.zsh)'; wsmark::lint '$(ws_fixture_path markers/cross-nested.md)'"
  [ "$status" -eq 2 ]
  [[ "$output" == *"crosses"* ]]
}

@test "wsmark::repair fixes missing END (auto-confirm)" {
  local tmp="$(ws_mktemp_dir)/file.md"
  cp "$(ws_fixture_path markers/missing-end.md)" "$tmp"
  run zsh -c "source '$(ws_lib_path workspace-doc-markers.zsh)'; printf 'y\n' | wsmark::repair '$tmp'"
  [ "$status" -eq 0 ]
  run zsh -c "source '$(ws_lib_path workspace-doc-markers.zsh)'; wsmark::lint '$tmp'"
  [ "$status" -eq 0 ]
}

@test "wsmark::repair declines on user 'n'" {
  local tmp="$(ws_mktemp_dir)/file.md"
  cp "$(ws_fixture_path markers/missing-end.md)" "$tmp"
  run zsh -c "source '$(ws_lib_path workspace-doc-markers.zsh)'; printf 'n\n' | wsmark::repair '$tmp'"
  [ "$status" -eq 1 ]
}
