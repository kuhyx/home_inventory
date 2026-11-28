#!/bin/bash
# Sourced by ci_mirror.sh: sharded test run. Expects REPO_DIR, GATE_SHARDS, log().
# Pattern from screen-locker/scripts/flutter_coverage_lib.sh.

die() {
    echo "error: $*" >&2
    exit 1
}

# Bucket INDEX of TOTAL: every TOTAL-th tracked test file; buckets partition the suite.
shard_files() {
    local index=$1 total=$2 i=0 file
    while IFS= read -r file; do
        if ((i % total == index)); then
            printf '%s\n' "$file"
        fi
        i=$((i + 1))
    done < <(cd "$REPO_DIR" && git ls-files -- 'test/*_test.dart' | LC_ALL=C sort)
}

# flutter's default is one test isolate per core: 16 here, which the gate's
# 4 GiB cap OOM-kills (signal 15 on shard 1/6, Flutter 3.50). Two keeps a
# shard well under the cap; FLUTTER_TEST_CONCURRENCY is the shared knob the
# ~/.claude finish gate also honours.
TEST_CONCURRENCY="${FLUTTER_TEST_CONCURRENCY:-2}"
readonly TEST_CONCURRENCY

require_clean_tree() {
    [[ -z "$(git -C "$REPO_DIR" status --porcelain --untracked-files=no)" ]] \
        || die "working tree differs from HEAD; commit first, then run the gate."
}

require_hooks_match() {
    local n
    n="$(grep -c '^      - id: ci-mirror-test-[0-9]' "$REPO_DIR/.pre-commit-config.yaml" || true)"
    ((n == GATE_SHARDS)) \
        || die ".pre-commit-config.yaml declares $n ci-mirror-test-N hooks, GATE_SHARDS is $GATE_SHARDS"
}

# One bucket on a clean tree. Usage: I/N
test_shard() {
    [[ ${1:-} =~ ^([0-9]+)/([1-9][0-9]*)$ ]] || die "test --shard wants I/N, got '${1:-}'"
    local index=${BASH_REMATCH[1]} total=${BASH_REMATCH[2]}
    ((index < total)) || die "shard index $index is not below $total"
    ((total == GATE_SHARDS)) || die "shard total $total != GATE_SHARDS $GATE_SHARDS"
    require_hooks_match
    require_clean_tree
    local files
    mapfile -t files < <(shard_files "$index" "$total")
    ((${#files[@]} > 0)) || die "shard $index/$total has no test files"
    log "flutter test, shard $index/$total (${#files[@]} files)"
    # GIT_*: git exports them to hooks; flutter would then read this repo as its SDK.
    env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE \
        flutter test --concurrency "$TEST_CONCURRENCY" "${files[@]}"
}
