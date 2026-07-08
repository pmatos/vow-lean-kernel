#!/bin/bash
set -uo pipefail

# Dry-run harness: run lean_checker on one or more NDJSON inputs under the same
# ulimit the arena's run command uses, measuring the verdict, wall time, and max
# RSS per input, then tally accept/reject/decline/error. Mirrors how the arena
# invokes the checker (exit code = verdict) plus /usr/bin/time -v for metrics.
#
# Usage:
#   arena/dry-run.sh [--checker PATH] [--mem-limit KB] [--out FILE] \
#       <label>=<file.ndjson> [<label>=<file.ndjson> ...]

CHECKER="./lean_checker"
MEM_LIMIT=8388608          # 8 GiB, matches checker.yaml's run command
OUT=""                     # markdown results file; default: stdout only
LOGDIR="${TMPDIR:-/tmp}/lean-dry-run"

args=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --checker)   CHECKER="$2"; shift 2 ;;
        --mem-limit) MEM_LIMIT="$2"; shift 2 ;;
        --out)       OUT="$2"; shift 2 ;;
        --logdir)    LOGDIR="$2"; shift 2 ;;
        *)           args+=("$1"); shift ;;
    esac
done

[[ ${#args[@]} -gt 0 ]] || { echo "usage: $0 [--checker P] [--mem-limit KB] [--out F] label=file ..." >&2; exit 1; }
command -v /usr/bin/time >/dev/null || { echo "need /usr/bin/time (GNU time)" >&2; exit 1; }
mkdir -p "$LOGDIR"

emit() { echo "$1"; [[ -n "$OUT" ]] && echo "$1" >> "$OUT"; }

[[ -n "$OUT" ]] && : > "$OUT"
emit "| input | file MB | verdict | exit | wall | max RSS |"
emit "|-------|--------:|---------|-----:|------|--------:|"

acc=0; rej=0; dec=0; err=0
for pair in "${args[@]}"; do
    label="${pair%%=*}"
    file="${pair#*=}"
    if [[ ! -f "$file" ]]; then
        emit "| $label | — | **missing** | — | — | — |"; err=$((err+1)); continue
    fi
    size_mb=$(( ( $(stat -c %s "$file") + 524288 ) / 1048576 ))
    tlog="$LOGDIR/${label}.time"; olog="$LOGDIR/${label}.out"

    ( ulimit -v "$MEM_LIMIT" && exec /usr/bin/time -v "$CHECKER" "$file" ) >"$olog" 2>"$tlog"
    rc=$?

    wall=$(grep -m1 -oP 'Elapsed \(wall clock\) time \(h:mm:ss or m:ss\): \K.*' "$tlog" 2>/dev/null || echo '?')
    rss_kb=$(grep -m1 -oP 'Maximum resident set size \(kbytes\): \K[0-9]+' "$tlog" 2>/dev/null || echo 0)
    rss=$(awk -v k="$rss_kb" 'BEGIN{printf "%.2f GB", k/1048576}')

    # The Vow runtime exits 1 on OutOfMemory (a JSON marker on stderr, captured
    # in $tlog). checker.yaml's run wrapper maps that to a decline; mirror it
    # here so the tally reflects the arena verdict, not the raw exit code.
    oom=""
    grep -q '"error":"OutOfMemory"' "$tlog" 2>/dev/null && oom=" (OOM→2)"
    case "$rc" in
        0) v="accept";  acc=$((acc+1)) ;;
        2) v="decline"; dec=$((dec+1)) ;;
        1) if [ -n "$oom" ]; then v="decline$oom"; dec=$((dec+1)); else v="REJECT"; rej=$((rej+1)); fi ;;
        *) if [ -n "$oom" ]; then v="decline$oom"; dec=$((dec+1)); else v="ERROR"; err=$((err+1)); fi ;;
    esac
    emit "| $label | $size_mb | $v | $rc | $wall | $rss |"
done

emit ""
emit "**Tally:** ${acc} accept · ${rej} reject · ${dec} decline · ${err} error"
emit "_(raw per-input time/stdout logs under \`$LOGDIR\`)_"
