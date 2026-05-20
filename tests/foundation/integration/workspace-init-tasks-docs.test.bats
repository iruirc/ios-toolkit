#!/usr/bin/env bats
# Coverage for the workspace.tasks / workspace.docs mode matrix (sibling / path / symlink)
# plus preservation of pre-existing Docs symlinks across rerun.
load "$(dirname "$BATS_TEST_FILENAME")/../helpers/ws-test-helpers"

setup() { WS_TEST_TMPDIRS=(); }
teardown() { ws_cleanup_tmpdirs; }

@test "ws-init-driver provisions Docs/ sibling repo by default (no docs block in yml)" {
  local parent="$(ws_mktemp_dir)"
  run "$(ws_repo_root)/tests/foundation/helpers/ws-init-driver.zsh" \
    "$(ws_fixture_path workspace-yml/grouped.yml)" "$parent"
  [ "$status" -eq 0 ]
  [ -d "$parent/Docs" ]
  [ -d "$parent/Docs/.git" ]
  [ -f "$parent/Docs/README.md" ]
  [ -d "$parent/Tasks" ]
  [ -d "$parent/Tasks/.git" ]
}

@test "ws-init-driver provisions Tasks/ + Docs/ as symlinks when mode=symlink" {
  local parent="$(ws_mktemp_dir)"
  # Create the external targets the symlinks should point at.
  mkdir -p "$parent/external-tasks" "$parent/external-docs"
  touch "$parent/external-tasks/.keep" "$parent/external-docs/.keep"

  # Render a workspace.yml that uses absolute symlink targets.
  local yml="$parent/workspace.yml"
  cat > "$yml" <<EOF
workspace:
  name: symlink-ws
  tasks:
    enabled: true
    mode: symlink
    symlink_target: $parent/external-tasks
  docs:
    enabled: true
    mode: symlink
    symlink_target: $parent/external-docs
remotes: [origin]
packages:
  - { name: A, archetype: api-contract, git: {origin: x}, version: 0.1.0 }
EOF
  run "$(ws_repo_root)/tests/foundation/helpers/ws-init-driver.zsh" "$yml" "$parent"
  [ "$status" -eq 0 ]
  [ -L "$parent/Tasks" ]
  [ -L "$parent/Docs" ]
  [ ! -d "$parent/Tasks/.git" ]
  [ ! -d "$parent/Docs/.git" ]
  # Symlinks resolve to the prepared external targets.
  run readlink "$parent/Tasks"
  [ "$status" -eq 0 ]
  [[ "$output" == "$parent/external-tasks" ]]
  run readlink "$parent/Docs"
  [ "$status" -eq 0 ]
  [[ "$output" == "$parent/external-docs" ]]
}

@test "ws-init-driver preserves a pre-existing Docs symlink (does not overwrite)" {
  local parent="$(ws_mktemp_dir)"
  mkdir -p "$parent/manual-docs"
  ln -s "$parent/manual-docs" "$parent/Docs"
  run "$(ws_repo_root)/tests/foundation/helpers/ws-init-driver.zsh" \
    "$(ws_fixture_path workspace-yml/grouped.yml)" "$parent"
  [ "$status" -eq 0 ]
  # Symlink still in place; the driver did NOT mkdir + git init on top of it.
  [ -L "$parent/Docs" ]
  [ ! -d "$parent/Docs/.git" ]
  run readlink "$parent/Docs"
  [ "$status" -eq 0 ]
  [[ "$output" == "$parent/manual-docs" ]]
}

@test "ws-init-driver honors docs.enabled=false" {
  local parent="$(ws_mktemp_dir)"
  local yml="$parent/workspace.yml"
  cat > "$yml" <<'EOF'
workspace:
  name: nodocs-ws
  docs:
    enabled: false
remotes: [origin]
packages:
  - { name: A, archetype: api-contract, git: {origin: x}, version: 0.1.0 }
EOF
  run "$(ws_repo_root)/tests/foundation/helpers/ws-init-driver.zsh" "$yml" "$parent"
  [ "$status" -eq 0 ]
  [ ! -e "$parent/Docs" ]
  [ -d "$parent/Tasks" ]
}
