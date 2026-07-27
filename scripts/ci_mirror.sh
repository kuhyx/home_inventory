#!/bin/bash

# ============================================================================
# CI mirror: reproduce what CI runs, locally, before push.
#
# `flutter clean` first, for the same reason the Python repos build a throwaway
# venv: a stale incremental build can hide a real failure, and a pre-push gate
# that only passes on an already-warm tree is not a gate.
#
# Two checks here have no equivalent in the sibling Flutter repos:
#   * the 100% line-coverage gate, which is this repo's hard bar;
#   * `flutter build web`, which is the only thing that catches a `dart:io`
#     import creeping into anything reachable from lib/main.dart. The analyzer
#     and the (VM-hosted) test suite are both perfectly happy with one.
# ============================================================================

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly REPO_DIR

log() { printf '==> %s\n' "$1"; }

# Fails unless every line in the lcov report was hit. Parsed from LF/LH totals
# rather than lcov --summary so the check needs no extra tool on a CI runner.
enforce_full_coverage() {
    local file="$REPO_DIR/coverage/lcov.info"
    if [[ ! -f "$file" ]]; then
        echo "error: $file is missing; did the test run fail?" >&2
        exit 1
    fi
    local found hit
    found="$(awk -F: '/^LF:/{s+=$2} END{print s+0}' "$file")"
    hit="$(awk -F: '/^LH:/{s+=$2} END{print s+0}' "$file")"
    echo "Lines covered: $hit / $found"
    if [[ "$found" != "$hit" ]]; then
        echo "error: line coverage is below 100% ($hit/$found)" >&2
        exit 1
    fi
}

main() {
    cd "$REPO_DIR"

    log "flutter clean"
    flutter clean

    log "flutter pub get"
    flutter pub get

    log "flutter analyze --fatal-infos --fatal-warnings"
    flutter analyze --fatal-infos --fatal-warnings

    log "dart format --set-exit-if-changed"
    dart format --set-exit-if-changed lib/ test/ tool/ bin/

    log "flutter test --coverage"
    flutter test --coverage

    log "coverage gate"
    enforce_full_coverage

    log "flutter build web --release"
    flutter build web --release

    echo "CI mirror passed."
}

main "$@"
