# Vow Lean Kernel

## Project

A Lean 4 proof checker (kernel) written in Vow, targeting the [Lean Kernel Arena](https://github.com/leanprover/lean-kernel-arena). Reads NDJSON from `lean4export` and verifies declarations are well-typed. This is the first large project in Vow — it serves as a proving ground for the language itself.

## Plan

The implementation plan is in `plan/plan.md`. It covers 9 phases (L1–L9) from NDJSON parsing through large-scale Mathlib validation, each mapped to specific arena tutorial tests.

## Lean Kernel Arena

- **Arena site**: https://arena.lean-lang.org
- **Repo**: https://github.com/leanprover/lean-kernel-arena
- **Tutorial source**: https://github.com/leanprover/lean-kernel-arena/blob/master/tutorial/Tutorial.lean

The arena provides a graduated tutorial test sequence that guides incremental implementation. Each test is a YAML file in `tests/` specifying `outcome: accept` or `outcome: reject`. Tests use NDJSON input produced by `lean4export`.

### Exit code protocol

- `0` — Proof accepted (all declarations well-typed)
- `1` — Proof rejected (a declaration failed type checking)
- `2` — Declined (checker cannot handle this input)
- Anything else — Internal error

### Registering the checker

Create a YAML file in `checkers/` following the `schemas/checker.json` spec. It defines the build command, run command (receives `$IN` with the NDJSON test file path), git ref, and description. Test files can be downloaded from the arena site for offline development.

## Toolchain

- The `vowc` compiler is located at `/home/pmatos/dev/vow-lang/vowc`.
- Always run `vowc` under `ulimit` to avoid memory explosion (e.g., `ulimit -v 4194304 && vowc ...`).
- Always run compiled Vow binaries (e.g., `lean_checker`) under `ulimit` too — Vow-compiled code is also prone to memory issues (e.g., `ulimit -v 8388608 && ./lean_checker ...`). Use 8GB (8388608) for deeper proof terms like grind-ring-5; 4GB may be insufficient.
- Bugs or issues found in Vow during development should be filed directly to the Vow issue tracker: https://github.com/pmatos/vow-lang/issues
