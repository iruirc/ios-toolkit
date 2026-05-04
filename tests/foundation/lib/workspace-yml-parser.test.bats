#!/usr/bin/env bats

load "$(dirname "$BATS_TEST_FILENAME")/../helpers/ws-test-helpers"

setup() {
  WS_TEST_TMPDIRS=()
}

teardown() {
  ws_cleanup_tmpdirs
}

@test "wsyml::load on minimal.yml succeeds" {
  run zsh -c "source '$(ws_lib_path workspace-yml-parser.zsh)'; wsyml::load '$(ws_fixture_path workspace-yml/minimal.yml)'"
  [ "$status" -eq 0 ]
}

@test "wsyml::get returns workspace.name" {
  run zsh -c "source '$(ws_lib_path workspace-yml-parser.zsh)'; wsyml::load '$(ws_fixture_path workspace-yml/minimal.yml)'; wsyml::get '.workspace.name'"
  [ "$status" -eq 0 ]
  [ "$output" = "minimal-ws" ]
}

@test "wsyml::get returns 1 when key missing" {
  run zsh -c "source '$(ws_lib_path workspace-yml-parser.zsh)'; wsyml::load '$(ws_fixture_path workspace-yml/minimal.yml)'; wsyml::get '.nope.missing'"
  [ "$status" -eq 1 ]
}

@test "wsyml::packages echoes one name per line" {
  run zsh -c "source '$(ws_lib_path workspace-yml-parser.zsh)'; wsyml::load '$(ws_fixture_path workspace-yml/grouped.yml)'; wsyml::packages"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "AKit" ]
  [ "${lines[1]}" = "BEngine" ]
  [ "${lines[2]}" = "CFeature" ]
}

@test "wsyml::groups echoes group names" {
  run zsh -c "source '$(ws_lib_path workspace-yml-parser.zsh)'; wsyml::load '$(ws_fixture_path workspace-yml/grouped.yml)'; wsyml::groups"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "common" ]
  [ "${lines[1]}" = "domain" ]
}

@test "wsyml::remotes echoes remote names" {
  run zsh -c "source '$(ws_lib_path workspace-yml-parser.zsh)'; wsyml::load '$(ws_fixture_path workspace-yml/grouped.yml)'; wsyml::remotes"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "origin" ]
  [ "${lines[1]}" = "originLocal" ]
}

@test "wsyml::package_field returns archetype for a package" {
  run zsh -c "source '$(ws_lib_path workspace-yml-parser.zsh)'; wsyml::load '$(ws_fixture_path workspace-yml/grouped.yml)'; wsyml::package_field BEngine archetype"
  [ "$status" -eq 0 ]
  [ "$output" = "engine" ]
}

@test "validate accepts grouped.yml" {
  run zsh -c "source '$(ws_lib_path workspace-yml-parser.zsh)'; wsyml::load '$(ws_fixture_path workspace-yml/grouped.yml)' && wsyml::validate"
  [ "$status" -eq 0 ]
}

@test "validate rejects missing workspace.name" {
  run zsh -c "source '$(ws_lib_path workspace-yml-parser.zsh)'; wsyml::load '$(ws_fixture_path workspace-yml/missing-name.yml)' && wsyml::validate"
  [ "$status" -eq 2 ]
  [[ "$output" == *"workspace.name is required"* ]]
}

@test "validate rejects empty packages" {
  run zsh -c "source '$(ws_lib_path workspace-yml-parser.zsh)'; wsyml::load '$(ws_fixture_path workspace-yml/empty-packages.yml)' && wsyml::validate"
  [ "$status" -eq 2 ]
  [[ "$output" == *"packages must have"* ]]
}

@test "validate rejects duplicate package name" {
  run zsh -c "source '$(ws_lib_path workspace-yml-parser.zsh)'; wsyml::load '$(ws_fixture_path workspace-yml/duplicate-pkg.yml)' && wsyml::validate"
  [ "$status" -eq 2 ]
  [[ "$output" == *"duplicate package name"* ]]
}

@test "validate rejects unknown group reference" {
  run zsh -c "source '$(ws_lib_path workspace-yml-parser.zsh)'; wsyml::load '$(ws_fixture_path workspace-yml/bad-group-ref.yml)' && wsyml::validate"
  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown group"* ]]
}

@test "validate rejects unknown deps reference" {
  run zsh -c "source '$(ws_lib_path workspace-yml-parser.zsh)'; wsyml::load '$(ws_fixture_path workspace-yml/bad-dep-ref.yml)' && wsyml::validate"
  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown package 'Nope'"* ]]
}

@test "validate rejects git remote key not in top-level remotes" {
  run zsh -c "source '$(ws_lib_path workspace-yml-parser.zsh)'; wsyml::load '$(ws_fixture_path workspace-yml/bad-remote-key.yml)' && wsyml::validate"
  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown remote 'gitolite'"* ]]
}

@test "validate rejects bad archetype" {
  run zsh -c "source '$(ws_lib_path workspace-yml-parser.zsh)'; wsyml::load '$(ws_fixture_path workspace-yml/bad-archetype.yml)' && wsyml::validate"
  [ "$status" -eq 2 ]
  [[ "$output" == *"invalid archetype 'widget'"* ]]
}

@test "validate rejects non-semver version" {
  run zsh -c "source '$(ws_lib_path workspace-yml-parser.zsh)'; wsyml::load '$(ws_fixture_path workspace-yml/bad-version.yml)' && wsyml::validate"
  [ "$status" -eq 2 ]
  [[ "$output" == *"invalid version 'v1'"* ]]
}

@test "validate rejects deps not in allowed_deps when allowed_deps non-empty" {
  run zsh -c "source '$(ws_lib_path workspace-yml-parser.zsh)'; wsyml::load '$(ws_fixture_path workspace-yml/disallowed-deps.yml)' && wsyml::validate"
  [ "$status" -eq 2 ]
  [[ "$output" == *"package 'C' dep 'A' not in allowed_deps"* ]]
}

@test "validate rejects commit symlink_mode with absolute external path" {
  run zsh -c "source '$(ws_lib_path workspace-yml-parser.zsh)'; wsyml::load '$(ws_fixture_path workspace-yml/symlink-mode-mismatch.yml)' && wsyml::validate"
  [ "$status" -eq 2 ]
  [[ "$output" == *"symlink_mode 'commit' requires relative path"* ]]
}

@test "validate rejects example_app without example_platform" {
  run zsh -c "source '$(ws_lib_path workspace-yml-parser.zsh)'; wsyml::load '$(ws_fixture_path workspace-yml/example-app-no-platform.yml)' && wsyml::validate"
  [ "$status" -eq 2 ]
  [[ "$output" == *"example_app: true requires example_platform"* ]]
}

@test "validate rejects malformed git_author" {
  run zsh -c "source '$(ws_lib_path workspace-yml-parser.zsh)'; wsyml::load '$(ws_fixture_path workspace-yml/bad-author.yml)' && wsyml::validate"
  [ "$status" -eq 2 ]
  [[ "$output" == *"git_author"* ]]
}
