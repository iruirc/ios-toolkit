#!/usr/bin/env zsh
# workspace-archetypes.zsh — archetype boundary text + default-rule lookups.

wsarch::boundary_text() {
  local arch="$1"
  case "$arch" in
    api-contract)
      print "API-contract package. Must declare protocols and DTOs only. Must not depend on any workspace package. May declare external_deps (e.g. swift-collections). \`workspace-check\` will fail any commit that adds a workspace dependency to this package."
      ;;
    engine)
      print "Engine package. May depend only on api-contract packages. Must not import other engines, libraries, or features. \`workspace-check\` will fail any commit that violates this."
      ;;
    library)
      print "Library package. May depend on api-contract, engine, and other library packages. Must not import features. \`workspace-check\` will fail any commit that violates this."
      ;;
    feature)
      print "Feature package. May depend on api-contract, engine, and library packages. Must not import other features. Composes UI + behaviour for a user-facing slice. \`workspace-check\` will fail any commit that violates this."
      ;;
    *)
      print -u2 "wsarch::boundary_text: unknown archetype '$arch'"
      return 4
      ;;
  esac
}

wsarch::default_allowed() {
  local arch="$1"
  case "$arch" in
    api-contract) print "" ;;
    engine)       print "api-contract" ;;
    library)      print "api-contract engine library" ;;
    feature)      print "api-contract engine library" ;;
    *) return 4 ;;
  esac
}
