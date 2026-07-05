#!/bin/bash
set -euo pipefail

# Test runner for the Lean Kernel Arena tutorial fixtures.
#
# By default it runs the committed fixtures under tests/good/ and tests/bad/,
# inferring the expected outcome from the directory: anything under a good/
# path must ACCEPT (exit 0), anything under a bad/ path must REJECT (exit 1).
# A checker that DECLINES (exit 2) is reported as a skip, matching the arena
# exit-code protocol (see CLAUDE.md).
#
# Arena test bundles downloaded from https://arena.lean-lang.org pair each
# .ndjson with a sibling .yaml carrying `outcome: accept|reject`. When such a
# sibling exists it takes precedence over the directory heuristic, so this
# runner also drives a downloaded `--tests-dir <dir>` tree unchanged.

CHECKER="./lean_checker"
# Virtual-memory cap (KiB) applied per checker invocation. 8 GiB by default —
# deeper proof terms need it (see CLAUDE.md); override with --mem-limit.
MEM_LIMIT=8388608
DIRS=()

usage() {
    echo "Usage: $0 [--checker PATH] [--mem-limit KB] [--tests-dir DIR]... [DIR]..."
    echo "  With no directories, runs tests/good and tests/bad."
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --checker)    CHECKER="$2"; shift 2 ;;
        --mem-limit)  MEM_LIMIT="$2"; shift 2 ;;
        --tests-dir)  DIRS+=("$2"); shift 2 ;;
        -h|--help)    usage; exit 0 ;;
        -*)           echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
        *)            DIRS+=("$1"); shift ;;
    esac
done

if [[ ${#DIRS[@]} -eq 0 ]]; then
    DIRS=("tests/good" "tests/bad")
fi

# Print the expected outcome (accept|reject) for a fixture, or nothing if it
# cannot be determined. A sibling .yaml wins; otherwise the path decides.
expected_outcome() {
    local ndjson="$1"
    local yaml="${ndjson%.ndjson}.yaml"
    if [[ -f "$yaml" ]]; then
        # Tolerate a YAML with no parseable outcome: emit nothing and let the
        # caller's skip branch handle it, rather than aborting under set -e.
        grep -m1 -oP 'outcome:\s*\K\w+' "$yaml" || true
        return 0
    fi
    case "/$ndjson/" in
        */good/*) echo accept ;;
        */bad/*)  echo reject ;;
    esac
}

PASS=0
FAIL=0
SKIP=0
TOTAL=0

for dir in "${DIRS[@]}"; do
    [[ -d "$dir" ]] || { echo "SKIP  $dir (no such directory)"; continue; }
    while IFS= read -r -d '' ndjson; do
        TOTAL=$((TOTAL + 1))
        name="${ndjson#./}"

        expected="$(expected_outcome "$ndjson")"
        case "$expected" in
            accept) want=0 ;;
            reject) want=1 ;;
            *) echo "SKIP  $name (cannot determine expected outcome)"; SKIP=$((SKIP + 1)); continue ;;
        esac

        set +e
        ( ulimit -v "$MEM_LIMIT" && "$CHECKER" "$ndjson" >/dev/null 2>&1 )
        rc=$?
        set -e

        if [[ "$rc" -eq 2 ]]; then
            echo "SKIP  $name (declined)"
            SKIP=$((SKIP + 1))
        elif [[ "$rc" -eq "$want" ]]; then
            echo "PASS  $name (expected $expected)"
            PASS=$((PASS + 1))
        else
            echo "FAIL  $name (expected $expected/exit $want, got exit $rc)"
            FAIL=$((FAIL + 1))
        fi
    done < <(find "$dir" -type f -name '*.ndjson' -print0 | sort -z)
done

echo ""
echo "Results: $PASS passed, $FAIL failed, $SKIP skipped out of $TOTAL tests"

if [[ "$TOTAL" -eq 0 ]]; then
    echo "No .ndjson fixtures found under: ${DIRS[*]}"
    exit 1
fi

[[ "$FAIL" -eq 0 ]]
