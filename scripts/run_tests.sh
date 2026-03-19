#!/bin/bash
set -e

# Test runner for Lean Kernel Arena tutorial tests.
#
# To download test files from the arena site:
#   Visit https://arena.lean-lang.org and download the tutorial test NDJSON/YAML
#   files into tests/data/. Each test has a .ndjson input file and a .yaml file
#   specifying the expected outcome (accept or reject).

CHECKER="./lean_checker"
TESTS_DIR="tests/data"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --checker)
            CHECKER="$2"
            shift 2
            ;;
        --tests-dir)
            TESTS_DIR="$2"
            shift 2
            ;;
        *)
            echo "Usage: $0 [--checker PATH] [--tests-dir PATH]"
            exit 1
            ;;
    esac
done

mkdir -p "$TESTS_DIR"

PASS=0
FAIL=0
SKIP=0
TOTAL=0

for ndjson in "$TESTS_DIR"/*.ndjson; do
    [ -f "$ndjson" ] || continue

    TOTAL=$((TOTAL + 1))
    base="${ndjson%.ndjson}"
    name="$(basename "$base")"
    yaml="${base}.yaml"

    if [ ! -f "$yaml" ]; then
        echo "SKIP  $name (no .yaml file)"
        SKIP=$((SKIP + 1))
        continue
    fi

    expected=$(grep -oP 'outcome:\s*\K\w+' "$yaml" | head -1)
    if [ -z "$expected" ]; then
        echo "SKIP  $name (no outcome in .yaml)"
        SKIP=$((SKIP + 1))
        continue
    fi

    set +e
    "$CHECKER" < "$ndjson" > /dev/null 2>&1
    exit_code=$?
    set -e

    if [ "$exit_code" -eq 2 ]; then
        echo "SKIP  $name (declined)"
        SKIP=$((SKIP + 1))
        continue
    fi

    case "$expected" in
        accept) expected_code=0 ;;
        reject) expected_code=1 ;;
        *)
            echo "SKIP  $name (unknown outcome: $expected)"
            SKIP=$((SKIP + 1))
            continue
            ;;
    esac

    if [ "$exit_code" -eq "$expected_code" ]; then
        echo "PASS  $name (expected $expected)"
        PASS=$((PASS + 1))
    else
        echo "FAIL  $name (expected $expected/exit $expected_code, got exit $exit_code)"
        FAIL=$((FAIL + 1))
    fi
done

echo ""
echo "Results: $PASS passed, $FAIL failed, $SKIP skipped out of $TOTAL tests"

if [ "$TOTAL" -eq 0 ]; then
    echo "No test files found in $TESTS_DIR"
    echo "Download test files from https://arena.lean-lang.org"
fi

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
