#!/usr/bin/env bats
load "$(dirname "$BATS_TEST_FILENAME")/../helpers/ws-test-helpers"

setup() { WS_TEST_TMPDIRS=(); }
teardown() { ws_cleanup_tmpdirs; }

@test "wsgraph::check_acyclic accepts grouped.yml" {
  run zsh -c "source '$(ws_lib_path workspace-yml-parser.zsh)'; source '$(ws_lib_path workspace-graph.zsh)'; wsyml::load '$(ws_fixture_path workspace-yml/grouped.yml)'; wsgraph::check_acyclic"
  [ "$status" -eq 0 ]
}

@test "wsgraph::check_acyclic rejects cyclic.yml" {
  run zsh -c "source '$(ws_lib_path workspace-yml-parser.zsh)'; source '$(ws_lib_path workspace-graph.zsh)'; wsyml::load '$(ws_fixture_path workspace-yml/cyclic.yml)'; wsgraph::check_acyclic"
  [ "$status" -eq 2 ]
  [[ "$output" == *"cycle"* ]]
}
