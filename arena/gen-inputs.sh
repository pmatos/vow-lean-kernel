#!/bin/bash
set -euo pipefail

# Regenerate the arena dry-run inputs (init / std / mathlib NDJSON) with
# lean4export, matching the arena's init/std/mathlib test modules and toolchains.
#
# These exports are large (~6 GB total) and fully reproducible, so they are NOT
# committed to the repo — regenerate them on demand with this script, then run
# arena/dry-run.sh over them.
#
# Prereqs: elan (provides lake/lean), git, cargo not needed. ~15 GB free (a
# mathlib4 checkout + its cache is ~7 GB; the exports are ~6 GB). The init/std
# exports take seconds; mathlib takes a few minutes (clone + `lake exe cache
# get` + export). The mathlib path needs the real mathlib4 project — a bare
# `import Mathlib` in a throwaway project cannot resolve it.
#
# Usage: arena/gen-inputs.sh [OUT_DIR] [WORK_DIR]
#   OUT_DIR  where the .ndjson land        (default: ~/dry-run-inputs)
#   WORK_DIR scratch: lean4export + projects (default: ~/.cache/lean-arena-gen)

OUT="${1:-$HOME/dry-run-inputs}"
WORK="${2:-$HOME/.cache/lean-arena-gen}"
# arena init.yaml/std.yaml are `leanfile` tests → they inherit the arena's
# tests/lean-toolchain, which pins v4.29.1. Match it so the exports (and their
# memory/verdict characteristics) reflect what the arena actually runs.
INIT_STD_TOOLCHAIN="v4.29.1"
MATHLIB_REF="v4.29.1"          # arena tests/mathlib.yaml
mkdir -p "$OUT" "$WORK"

# Build (once, cached) a lean4export binary for a given Lean toolchain and echo
# its path. lean4export loads oleans, so it must match the export's toolchain.
build_lean4export() { # $1 = toolchain tag (e.g. v4.29.0)
    local tc="$1" dir="$WORK/lean4export-$tc"
    if [ ! -x "$dir/.lake/build/bin/lean4export" ]; then
        [ -d "$dir" ] || git clone -q https://github.com/leanprover/lean4export "$dir"
        echo "leanprover/lean4:$tc" > "$dir/lean-toolchain"
        ( cd "$dir" && lake build ) >&2
    fi
    echo "$dir/.lake/build/bin/lean4export"
}

# Export a core/toolchain module (Init, Std) via a throwaway lake project.
export_core_module() { # $1 = module  $2 = out.ndjson
    local mod="$1" out="$2" proj="$WORK/proj-$mod-$INIT_STD_TOOLCHAIN" l4x
    mkdir -p "$proj"
    printf 'name = "gen"\n[[lean_lib]]\nname = "Root"\n' > "$proj/lakefile.toml"
    echo "leanprover/lean4:$INIT_STD_TOOLCHAIN" > "$proj/lean-toolchain"
    printf 'import %s\n' "$mod" > "$proj/Root.lean"
    ( cd "$proj" && lake build Root ) >&2
    l4x="$(build_lean4export "$INIT_STD_TOOLCHAIN")"
    echo ">> exporting $mod -> $out" >&2
    ( cd "$proj" && lake env "$l4x" "$mod" ) > "$out"
}

# Export the whole Mathlib library (needs the real project + prebuilt cache).
export_mathlib() { # $1 = out.ndjson
    local out="$1" dir="$WORK/mathlib4" l4x
    [ -d "$dir" ] || git clone -q --depth 1 --branch "$MATHLIB_REF" \
        https://github.com/leanprover-community/mathlib4 "$dir"
    ( cd "$dir" && lake exe cache get ) >&2
    l4x="$(build_lean4export "$MATHLIB_REF")"
    echo ">> exporting Mathlib -> $out" >&2
    ( cd "$dir" && lake env "$l4x" Mathlib ) > "$out"
}

case "${3:-all}" in
    init)    export_core_module Init "$OUT/init.ndjson" ;;
    std)     export_core_module Std  "$OUT/std.ndjson" ;;
    mathlib) export_mathlib "$OUT/mathlib.ndjson" ;;
    all)
        export_core_module Init "$OUT/init.ndjson"
        export_core_module Std  "$OUT/std.ndjson"
        export_mathlib          "$OUT/mathlib.ndjson"
        ;;
    *) echo "usage: $0 [OUT] [WORK] [init|std|mathlib|all]" >&2; exit 1 ;;
esac

echo "Done. Inputs in $OUT:" >&2
ls -la "$OUT"/*.ndjson 2>/dev/null >&2 || true
