# grind-ring-5 SIGABRT Investigation Summary

**Date:** 2026-04-09  
**Status:** Open — not yet filed as a Vow bug

## Symptom

`grind-ring-5.ndjson` (10MB, 200K lines, 2439 declarations) crashes with **exit code 134 (SIGABRT)** after successfully processing all 2439 declarations. The checker prints progress up to "Checking decl 2400/2439" and then aborts — the crash happens **after the main loop completes**, during cleanup/return from `main()`.

## Last Known Good

grind-ring-5 passed on **2026-03-26** (~85s, 8GB ulimit). The `vowc` compiler was rebuilt on **2026-04-01** (commits `d7dba6f`, `540ada3` — output path refactoring in the compiler). The crash is present on all builds since.

## Key Findings

### Memory-related, not logic-related
- At **8GB ulimit** (8388608): SIGABRT after ~165s CPU time
- At **10GB ulimit** (10485760): SIGABRT after ~227s CPU time  
- At **12GB ulimit** (12582912): SIGABRT after ~213s CPU time
- At **16GB ulimit** (16777216): **No crash**, exits with code **2** (declined)

The crash is caused by memory exhaustion. With enough memory, the checker doesn't crash but instead declines (exit 2), which is a separate issue (it should accept).

### Not caused by uncommitted hash-lookup changes
Tested with both committed HEAD (`d32e5d5`) and with the uncommitted `kernel/env.vow` hash-optimization changes — same crash on both.

### Reproducer attempts (all failed to trigger crash)
Several standalone Vow programs in `repro/` attempted to reproduce the crash pattern:
1. **Large struct with many Vec fields** (3000+ entries) — no crash
2. **Matching Environment shape** (Vec<String>, Vec<Vec<u64>>, 181K arena entries, 2500 decls, 8K hash buckets) — no crash
3. **Allocation/truncation cycles** (grow arena by 500 entries per decl, pop back to watermark, 2439 cycles) — no crash

The crash appears to require the specific memory allocation patterns of the actual type checker (deep recursive WHNF/def_eq computations generating many temporary expressions).

## Two Separate Issues

1. **SIGABRT crash**: The Vow runtime runs out of memory during cleanup at smaller ulimits. Likely a Vow compiler regression in memory management (allocator, scope-based freeing, or destructor codegen changed between March 26 and April 1).

2. **Exit code 2 (declined) at 16GB**: Even when it doesn't crash, the checker declines instead of accepting. This suggests the checker itself may be hitting an internal limit (kernel_fuel?) or a new code path that returns "declined."

## Arena Size

The arena stays at 181241 throughout (truncation is working correctly). Progress output confirms all 2439 declarations are processed.

## What to Investigate Next

- **Vow compiler diff**: Compare vowc behavior between the March 26 build and the April 1 build. Key suspects: `d7dba6f` (gitignore), `540ada3` (output path refactoring) — the output path change could affect binary layout/linking.
- **Memory profiling**: Run under `valgrind` or `/usr/bin/time -v` to see peak RSS and identify where memory grows unbounded.
- **Exit code 2**: Investigate why the checker returns "declined" at 16GB — grep for code paths that set `declined = 1` or return `2i32`.
- **Kernel fuel**: Check if the `kernel_fuel` safety net is being hit, causing the checker to decline.

## Relevant Files

- `main.vow:170-225` — main loop, progress printing, cleanup
- `kernel/env.vow` — Environment struct, arena truncation
- `kernel/whnf.vow` — WHNF reduction (heavy allocation)
- `kernel/def_eq.vow` — definitional equality (deep recursion)
- `repro/large_struct_exit.vow` — latest reproducer attempt
