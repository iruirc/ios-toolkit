#!/usr/bin/env bats
load "$(dirname "$BATS_TEST_FILENAME")/../helpers/ws-test-helpers"

setup() { WS_TEST_TMPDIRS=(); }
teardown() { ws_cleanup_tmpdirs; }

@test "docs-regen rewrites PKG_LIST section, preserves manual content" {
  local parent="$(ws_mktemp_dir)"
  "$(ws_repo_root)/tests/foundation/helpers/ws-init-driver.zsh" \
    "$(ws_fixture_path workspace-yml/grouped.yml)" "$parent" >&2

  # Mess with the marker section
  local readme="$parent/GroupedWS-meta/README.md"
  echo "## Packages" >> "$readme"
  printf '<!-- WORKSPACE_PKG_LIST_BEGIN -->\nbogus\n<!-- WORKSPACE_PKG_LIST_END -->\n' >> "$readme"
  echo "MANUAL_OUTSIDE_MARKERS" >> "$readme"

  run "$(ws_repo_root)/tests/foundation/helpers/ws-docs-regen-driver.zsh" "$parent/GroupedWS-meta"
  [ "$status" -eq 0 ]

  run grep '^- AKit (api-contract)' "$readme"
  [ "$status" -eq 0 ]
  run grep "^bogus$" "$readme"
  [ "$status" -eq 1 ]
  run grep '^MANUAL_OUTSIDE_MARKERS$' "$readme"
  [ "$status" -eq 0 ]
}
