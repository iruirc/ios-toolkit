#!/usr/bin/env bash
# Shared bats helpers for Foundation tests.
# Source from each .bats file via:
#   load "$(dirname "$BATS_TEST_FILENAME")/../helpers/ws-test-helpers"

# Absolute path to the toolkit repo root, regardless of cwd.
ws_repo_root() {
  cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd
}

# Path to a Foundation lib script.
ws_lib_path() {
  echo "$(ws_repo_root)/templates/workspace/lib/$1"
}

# Path to a Foundation fixture directory or file.
ws_fixture_path() {
  echo "$(ws_repo_root)/tests/foundation/fixtures/$1"
}

# Create a temp directory; trap-cleaned at end of test.
ws_mktemp_dir() {
  local d
  d="$(mktemp -d -t wsfound.XXXXXX)"
  WS_TEST_TMPDIRS+=("$d")
  echo "$d"
}

# Hook to invoke from `teardown` for cleanup.
ws_cleanup_tmpdirs() {
  local d
  for d in "${WS_TEST_TMPDIRS[@]:-}"; do
    [[ -d "$d" ]] && rm -rf -- "$d"
  done
  WS_TEST_TMPDIRS=()
}

# Run a zsh script under test with stdin/stdout captured.
# Usage: ws_run_zsh "$(ws_lib_path workspace-yml-parser.zsh)" wsyml::load /path/to/yml
ws_run_zsh() {
  zsh -c 'source "$1"; shift; "$@"' "ws_run_zsh" "$@"
}
