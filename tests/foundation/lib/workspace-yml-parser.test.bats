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

@test "validate rejects tasks.path that is absolute" {
  run zsh -c "source '$(ws_lib_path workspace-yml-parser.zsh)'; wsyml::load '$(ws_fixture_path workspace-yml/tasks-absolute-path.yml)' && wsyml::validate"
  [ "$status" -eq 2 ]
  [[ "$output" == *"tasks.path must be relative"* ]]
}

@test "validate rejects tasks.enabled that is not a boolean" {
  run zsh -c "source '$(ws_lib_path workspace-yml-parser.zsh)'; wsyml::load '$(ws_fixture_path workspace-yml/tasks-bad-enabled.yml)' && wsyml::validate"
  [ "$status" -eq 2 ]
  [[ "$output" == *"tasks.enabled must be boolean"* ]]
}

@test "validate accepts tasks.enabled: false" {
  run zsh -c "source '$(ws_lib_path workspace-yml-parser.zsh)'; wsyml::load '$(ws_fixture_path workspace-yml/tasks-disabled.yml)' && wsyml::validate"
  [ "$status" -eq 0 ]
}

@test "validate rejects tasks.mode that is not sibling|path|symlink" {
  run zsh -c "source '$(ws_lib_path workspace-yml-parser.zsh)'; wsyml::load '$(ws_fixture_path workspace-yml/tasks-bad-mode.yml)' && wsyml::validate"
  [ "$status" -eq 2 ]
  [[ "$output" == *"tasks.mode must be one of sibling|path|symlink"* ]]
}

@test "validate rejects tasks.mode=symlink without symlink_target" {
  run zsh -c "source '$(ws_lib_path workspace-yml-parser.zsh)'; wsyml::load '$(ws_fixture_path workspace-yml/tasks-symlink-no-target.yml)' && wsyml::validate"
  [ "$status" -eq 2 ]
  [[ "$output" == *"tasks.mode=symlink requires non-empty tasks.symlink_target"* ]]
}

@test "validate rejects docs.path that is absolute" {
  run zsh -c "source '$(ws_lib_path workspace-yml-parser.zsh)'; wsyml::load '$(ws_fixture_path workspace-yml/docs-absolute-path.yml)' && wsyml::validate"
  [ "$status" -eq 2 ]
  [[ "$output" == *"docs.path must be relative"* ]]
}

@test "validate rejects docs.mode that is not sibling|path|symlink" {
  run zsh -c "source '$(ws_lib_path workspace-yml-parser.zsh)'; wsyml::load '$(ws_fixture_path workspace-yml/docs-bad-mode.yml)' && wsyml::validate"
  [ "$status" -eq 2 ]
  [[ "$output" == *"docs.mode must be one of sibling|path|symlink"* ]]
}

@test "validate rejects docs.mode=symlink without symlink_target" {
  run zsh -c "source '$(ws_lib_path workspace-yml-parser.zsh)'; wsyml::load '$(ws_fixture_path workspace-yml/docs-symlink-no-target.yml)' && wsyml::validate"
  [ "$status" -eq 2 ]
  [[ "$output" == *"docs.mode=symlink requires non-empty docs.symlink_target"* ]]
}

@test "validate accepts docs.enabled: false" {
  run zsh -c "source '$(ws_lib_path workspace-yml-parser.zsh)'; wsyml::load '$(ws_fixture_path workspace-yml/docs-disabled.yml)' && wsyml::validate"
  [ "$status" -eq 0 ]
}

@test "validate accepts tasks + docs in symlink mode with targets" {
  run zsh -c "source '$(ws_lib_path workspace-yml-parser.zsh)'; wsyml::load '$(ws_fixture_path workspace-yml/tasks-docs-symlink.yml)' && wsyml::validate"
  [ "$status" -eq 0 ]
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

@test "validate accepts with-project-full.yml" {
  run zsh -c "source '$(ws_lib_path workspace-yml-parser.zsh)'; wsyml::load '$(ws_fixture_path workspace-yml/with-project-full.yml)' && wsyml::validate"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "validate rejects bad app key (watchos)" {
  run zsh -c "source '$(ws_lib_path workspace-yml-parser.zsh)'; wsyml::load '$(ws_fixture_path workspace-yml/with-project-bad-app-key.yml)' && wsyml::validate"
  [ "$status" -eq 2 ]
  [[ "$output" == *"apps.watchos rejected (MVP supports ios|macos only)"* ]]
}

@test "validate rejects repo-package collision" {
  run zsh -c "source '$(ws_lib_path workspace-yml-parser.zsh)'; wsyml::load '$(ws_fixture_path workspace-yml/with-project-repo-pkg-collision.yml)' && wsyml::validate"
  [ "$status" -eq 2 ]
  [[ "$output" == *"repo name 'CoreKit' collides with package name 'CoreKit'"* ]]
}

@test "validate rejects duplicate repo names across apps" {
  run zsh -c "source '$(ws_lib_path workspace-yml-parser.zsh)'; wsyml::load '$(ws_fixture_path workspace-yml/with-project-duplicate-repos.yml)' && wsyml::validate"
  [ "$status" -eq 2 ]
  [[ "$output" == *"duplicate repo name 'MyApp' in project.apps"* ]]
}

@test "validate rejects bad stack.di" {
  run zsh -c "source '$(ws_lib_path workspace-yml-parser.zsh)'; wsyml::load '$(ws_fixture_path workspace-yml/with-project-bad-stack-di.yml)' && wsyml::validate"
  [ "$status" -eq 2 ]
  [[ "$output" == *"stack.di 'nonexistent'"* ]]
}

@test "validate rejects bad stack.min_platforms.ios (non-semver)" {
  local tmp="$(ws_mktemp_dir)/bad-min.yml"
  cat > "$tmp" <<'EOF'
workspace:
  name: BadMin
remotes: [origin]
project:
  name: BadMinApp
  apps:
    ios:
      repo: BadMin-iOS
      stack:
        min_platforms:
          ios: vBadVersion
packages:
  - name: A
    archetype: api-contract
    git: { origin: git@github.com:user/A.git }
    version: 0.1.0
EOF
  run zsh -c "source '$(ws_lib_path workspace-yml-parser.zsh)'; wsyml::load '$tmp' && wsyml::validate"
  [ "$status" -eq 2 ]
  [[ "$output" == *"min_platforms.ios 'vBadVersion'"* ]]
}

@test "validate accepts with-project-shortform.yml (string-form apps.<platform>)" {
  run zsh -c "source '$(ws_lib_path workspace-yml-parser.zsh)'; wsyml::load '$(ws_fixture_path workspace-yml/with-project-shortform.yml)' && wsyml::validate"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "validate accepts with-project-mixed.yml (full + empty stack mix)" {
  run zsh -c "source '$(ws_lib_path workspace-yml-parser.zsh)'; wsyml::load '$(ws_fixture_path workspace-yml/with-project-mixed.yml)' && wsyml::validate"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "validate accepts with-project-partial-stack.yml (single stack field set)" {
  run zsh -c "source '$(ws_lib_path workspace-yml-parser.zsh)'; wsyml::load '$(ws_fixture_path workspace-yml/with-project-partial-stack.yml)' && wsyml::validate"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "wsarch::boundary_text returns text for engine" {
  run zsh -c "source '$(ws_lib_path workspace-archetypes.zsh)'; wsarch::boundary_text engine"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Engine package"* ]]
}

@test "wsarch::boundary_text errors on unknown archetype" {
  run zsh -c "source '$(ws_lib_path workspace-archetypes.zsh)'; wsarch::boundary_text widget"
  [ "$status" -eq 4 ]
}
