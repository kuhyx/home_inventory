#!/bin/bash

# ============================================================================
# CI mirror: reproduce what CI runs, locally, before push.
#
# `flutter clean` first, for the same reason the Python repos build a throwaway
# venv: a stale incremental build can hide a real failure, and a pre-push gate
# that only passes on an already-warm tree is not a gate.
#
# One check here has no equivalent in the sibling Flutter repos:
#   * `flutter build web`, which is the only thing that catches a `dart:io`
#     import creeping into anything reachable from lib/main.dart. The (VM-hosted)
#     test suite is perfectly happy with one.
# ============================================================================

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly REPO_DIR

# shellcheck disable=SC2034  # read by ci_mirror_shards.sh
readonly GATE_SHARDS=6

log() { printf '==> %s\n' "$1"; }

# shellcheck source=/dev/null
source "$REPO_DIR/scripts/ci_mirror_shards.sh"

ensure_deps() {
    log "flutter pub get"
    flutter pub get
}

phase_setup() {
    log "flutter clean"
    flutter clean
    ensure_deps
}

phase_format() {
    log "dart format --set-exit-if-changed"
    dart format --set-exit-if-changed lib/ test/ tool/ bin/
}

phase_build() {
    ensure_deps
    log "flutter build web --release $*"
    flutter build web --release "$@"
}

main() {
    cd "$REPO_DIR"

    case "${1:-all}" in
        all)
            phase_setup
            phase_format
            log "flutter test"
            flutter test --concurrency "$TEST_CONCURRENCY"
            phase_build
            ;;
        setup) phase_setup ;;
        format) phase_format ;;
        test)
            [[ "${2:-}" == "--shard" ]] || die "usage: ci_mirror.sh test --shard I/N"
            ensure_deps
            test_shard "${3:-}"
            ;;
        # The wasm dry run only warns; skipping it keeps the gate step under 60 s.
        build) phase_build --no-wasm-dry-run ;;
        *) die "unknown phase '$1' (all|setup|format|test --shard I/N|build)" ;;
    esac

    echo "CI mirror ${1:-all} passed."
}

main "$@"
