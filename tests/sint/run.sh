#!/bin/bash
# SInt reduction regression fixtures. All expect ACCEPT (exit 0).
# Fixtures generated via lean4export (see project memory). Run from repo root.
CHECKER="${1:-./lean_checker}"
DIR="$(cd "$(dirname "$0")" && pwd)"
pass=0; fail=0
for f in "$DIR"/*.ndjson; do
  name=$(basename "$f" .ndjson)
  (ulimit -v 8388608 && "$CHECKER" "$f" >/dev/null 2>&1)
  rc=$?
  if [ "$rc" = "0" ]; then
    pass=$((pass+1)); echo "PASS  $name (accept)"
  else
    fail=$((fail+1)); echo "FAIL  $name (rc=$rc, want 0=accept)"
  fi
done
echo "---"
echo "sint: $pass passed, $fail failed"
[ "$fail" = "0" ]
