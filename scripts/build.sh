#!/bin/bash
set -e

VOWC="${VOWC:-vowc}"
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

cd "$PROJECT_ROOT"

# Limit virtual memory to 4GB to avoid memory explosion
ulimit -v 4194304

"$VOWC" build --no-verify -o lean_checker main.vow
