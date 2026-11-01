#!/bin/bash
# Sourced by ci_mirror.sh: sharded coverage. Expects REPO_DIR, GATE_SHARDS, log().
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

shards_dir() {
    printf '%s/coverage-shards\n' "$(git -C "$REPO_DIR" rev-parse --git-dir)"
}

require_clean_tree() {
    [[ -z "$(git -C "$REPO_DIR" status --porcelain --untracked-files=no)" ]] \
        || die "working tree differs from HEAD; commit first, then run the gate."
}

require_hooks_match() {
    local n
    n="$(grep -c '^      - id: ci-mirror-cov-[0-9]' "$REPO_DIR/.pre-commit-config.yaml" || true)"
    ((n == GATE_SHARDS)) \
        || die ".pre-commit-config.yaml declares $n ci-mirror-cov-N hooks, GATE_SHARDS is $GATE_SHARDS"
}

# Union of the lcov files: a line is hit if any shard hit it; LF/LH recomputed, not summed.
merge_lcov() {
    local out=$1 file line sf="" rest ln hits key lf lh
    shift
    local -A hit=() lines_of=() seen=()
    local -a order=()
    for file in "$@"; do
        while IFS= read -r line; do
            case $line in
                SF:*)
                    sf=${line#SF:}
                    if [[ -z ${seen[$sf]:-} ]]; then
                        seen[$sf]=1
                        order+=("$sf")
                    fi
                    ;;
                DA:*)
                    rest=${line#DA:}
                    ln=${rest%%,*}
                    rest=${rest#*,}
                    hits=${rest%%,*}
                    key="$sf|$ln"
                    if [[ -z ${hit[$key]:-} ]]; then
                        hit[$key]=$hits
                        lines_of[$sf]+="$ln "
                    else
                        hit[$key]=$((hit[$key] + hits))
                    fi
                    ;;
            esac
        done < "$file"
    done
    mkdir -p "$(dirname "$out")"
    for sf in "${order[@]}"; do
        echo "SF:$sf"
        lf=0
        lh=0
        for ln in ${lines_of[$sf]:-}; do
            echo "DA:$ln,${hit[$sf|$ln]}"
            lf=$((lf + 1))
            if ((hit[$sf|$ln] > 0)); then
                lh=$((lh + 1))
            fi
        done
        echo "LF:$lf"
        echo "LH:$lh"
        echo "end_of_record"
    done > "$out"
}

# One bucket on a clean tree; its lcov is filed under the tree hash. Usage: I/N
coverage_shard() {
    [[ ${1:-} =~ ^([0-9]+)/([1-9][0-9]*)$ ]] || die "coverage --shard wants I/N, got '${1:-}'"
    local index=${BASH_REMATCH[1]} total=${BASH_REMATCH[2]}
    ((index < total)) || die "shard index $index is not below $total"
    ((total == GATE_SHARDS)) || die "shard total $total != GATE_SHARDS $GATE_SHARDS"
    require_hooks_match
    require_clean_tree
    local tree dir files old
    tree="$(git -C "$REPO_DIR" rev-parse 'HEAD^{tree}')"
    dir="$(shards_dir)"
    while IFS= read -r old; do
        rm -rf "${dir:?}/${old:?}"
    done < <(find "${dir:?}" -mindepth 1 -maxdepth 1 -type d ! -name "$tree" -printf '%f\n' 2> /dev/null)
    mkdir -p "${dir:?}/${tree:?}"
    rm -f "${dir:?}/${tree:?}/shard-${index:?}.lcov"
    mapfile -t files < <(shard_files "$index" "$total")
    ((${#files[@]} > 0)) || die "shard $index/$total has no test files"
    log "flutter test --coverage, shard $index/$total (${#files[@]} files, tree ${tree:0:12})"
    rm -f "${REPO_DIR:?}/coverage/lcov.info"
    # GIT_*: git exports them to hooks; flutter would then read this repo as its SDK.
    env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE flutter test --coverage "${files[@]}"
    [[ -s "$REPO_DIR/coverage/lcov.info" ]] || die "flutter produced no coverage/lcov.info"
    require_clean_tree
    [[ "$(git -C "$REPO_DIR" rev-parse 'HEAD^{tree}')" == "$tree" ]] || die "HEAD moved while the shard ran"
    cp "$REPO_DIR/coverage/lcov.info" "$dir/$tree/shard-$index.lcov.tmp"
    mv -f "$dir/$tree/shard-$index.lcov.tmp" "$dir/$tree/shard-$index.lcov"
}

# Unions ALL shards of the current tree into coverage/lcov.info; a missing one is fatal.
coverage_merge() {
    require_hooks_match
    require_clean_tree
    local tree dir i
    tree="$(git -C "$REPO_DIR" rev-parse 'HEAD^{tree}')"
    dir="$(shards_dir)/$tree"
    local -a lcovs=()
    for ((i = 0; i < GATE_SHARDS; i++)); do
        [[ -s "$dir/shard-$i.lcov" ]] \
            || die "no lcov for shard $i of tree ${tree:0:12}; run hook ci-mirror-cov-$((i + 1)) first."
        lcovs+=("$dir/shard-$i.lcov")
    done
    merge_lcov "$REPO_DIR/coverage/lcov.info" "${lcovs[@]}"
}
