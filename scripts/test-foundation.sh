#!/usr/bin/env bash
# Run Foundation bats tests.
# Usage: scripts/test-foundation.sh [unit|integration|all]
set -euo pipefail

target="${1:-all}"
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

if ! command -v bats >/dev/null 2>&1; then
  echo "error: bats-core not on PATH. install: brew install bats-core" >&2
  exit 3
fi

case "$target" in
  unit)        bats "$root/tests/foundation/lib" ;;
  integration) bats "$root/tests/foundation/integration" ;;
  all)         bats "$root/tests/foundation/lib" "$root/tests/foundation/integration" ;;
  *)           echo "usage: $0 [unit|integration|all]" >&2; exit 2 ;;
esac
