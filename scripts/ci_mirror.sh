#!/bin/bash

# ============================================================================
# CI mirror: reproduce what CI runs, locally, before push.
#
# `flutter clean` first, for the same reason the Python repos build a throwaway
# venv: a stale incremental build can hide a real failure, and a pre-push gate
# that only passes on an already-warm tree is not a gate.
#
# Three checks here have no equivalent in the sibling Flutter repos:
#   * the 100% line-coverage gate, which is this repo's hard bar;
#   * the completeness gate that keeps it honest, since a lib/ file no test
#     imports is missing from lcov.info entirely rather than reported at 0%;
#   * `flutter build web`, which is the only thing that catches a `dart:io`
#     import creeping into anything reachable from lib/main.dart. The analyzer
#     and the (VM-hosted) test suite are both perfectly happy with one.
# ============================================================================

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly REPO_DIR

log() { printf '==> %s\n' "$1"; }

# Echoes the path of the lcov report, or exits when the test run never made it.
coverage_report() {
    local file="$REPO_DIR/coverage/lcov.info"
    if [[ ! -f "$file" ]]; then
        echo "error: $file is missing; did the test run fail?" >&2
        exit 1
    fi
    echo "$file"
}

# Files under lib/ that legitimately never appear in lcov.info, each with the
# reason. A file no test imports is simply absent from the report, so the
# percentage gate below cannot see it — "100%" of a denominator that quietly
# excludes half the platform layer is a gate that fails open. Every absence has
# to be listed here, on purpose, or the build stops.
declare -rA COVERAGE_EXEMPT=(
    [lib/data/backup_export.dart]="conditional export only; no executable lines"
    [lib/data/repository_factory.dart]="conditional export only; no executable lines"
    [lib/sync/sync_state_factory.dart]="conditional export only; no executable lines"
    [lib/sync/desktop_wrapper.dart]="two consts; no executable lines (values asserted in desktop_backup_client_test.dart)"
    [lib/data/repository_factory_web.dart]="browser-only: imports idb_browser, which pulls dart:js_interop and will not compile into the VM test binary"
    [lib/data/backup_export_web.dart]="browser-only: XFile.saveTo('') means 'click a synthetic anchor' on web, while cross_file under the VM writes to the literal path '' and throws"
    [lib/sync/google_platform.dart]="conditional export only; no executable lines"
    [lib/sync/google_platform_web.dart]="browser-only: the io/web split always resolves to google_platform_io.dart under the VM test binary, so this file's own line is unreachable from any VM test"
)

# `flutter test --coverage` instruments lib/ only, which is why this walks lib/
# and not bin/ or tool/: those two are entry-point scripts (argument parsing,
# process spawning, stdout), both marked coverage:ignore-file, and the
# decisions they used to make now live in lib/desktop/launcher.dart.
#
# Fails when a lib/ file is missing from the report without being exempt, and
# when an exemption has gone stale — an entry that is now covered, or names a
# file that no longer exists, is a lie the next reader would trust.
enforce_coverage_completeness() {
    local file
    file="$(coverage_report)"
    local status=0 path

    while IFS= read -r path; do
        if grep -qxF "SF:$path" "$file"; then
            continue
        fi
        if [[ -v "COVERAGE_EXEMPT[$path]" ]]; then
            echo "  exempt: $path — ${COVERAGE_EXEMPT[$path]}"
            continue
        fi
        echo "error: $path is in lib/ but absent from lcov.info: no test" \
            "imports it, so the coverage gate never sees it. Add a test, or" \
            "add it to COVERAGE_EXEMPT with the reason." >&2
        status=1
    done < <(find lib -name '*.dart' | sort)

    for path in "${!COVERAGE_EXEMPT[@]}"; do
        if [[ ! -f "$path" ]]; then
            echo "error: COVERAGE_EXEMPT lists $path, which does not exist" >&2
            status=1
        elif grep -qxF "SF:$path" "$file"; then
            echo "error: $path is covered now; drop its COVERAGE_EXEMPT entry" >&2
            status=1
        fi
    done

    return "$status"
}

# Fails unless every line in the lcov report was hit. Parsed from LF/LH totals
# rather than lcov --summary so the check needs no extra tool on a CI runner.
enforce_full_coverage() {
    local file
    file="$(coverage_report)"
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
    enforce_coverage_completeness
    enforce_full_coverage

    log "flutter build web --release"
    flutter build web --release

    echo "CI mirror passed."
}

main "$@"
