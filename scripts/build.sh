#!/bin/bash
set -e

VOWC="/home/pmatos/dev/vow-lang/vowc"
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

cd "$PROJECT_ROOT"

# Limit virtual memory to 4GB to avoid memory explosion
ulimit -v 4194304

$VOWC build -o lean_checker main.vow
