# Vow Lean Kernel

A [Lean 4](https://lean-lang.org) proof checker (kernel) written in [Vow](https://github.com/pmatos/vow-lang). It reads declarations exported from Lean by [`lean4export`](https://github.com/leanprover/lean4export) and verifies that each one is well-typed according to Lean's type theory.

A kernel does **not** find proofs — it only checks them. Lean separates proof *search* (elaborator, tactics) from proof *checking* (the kernel), and only the kernel needs to be trusted. Multiple independent kernels cross-validate each other through the [Lean Kernel Arena](https://arena.lean-lang.org).

This is the first large project written in Vow, and doubles as a proving ground for the language itself.

## How it works

The checker reads NDJSON (newline-delimited JSON) produced by `lean4export`. Each line is a self-contained JSON object; the format assigns integer IDs to names, levels, and expressions, and later lines reference earlier ones by ID. Declaration lines (`def`, `ax`, `thm`, `ind`, `ctor`, `rec`, `quot`, …) are checked in order against an accumulating environment.

Because Vow has no recursive enum types, names, levels, and expressions are stored in flat, index-addressed **arenas** — a natural fit for the ID-based export format. The core algorithms are type inference (`infer`), definitional equality (`is_def_eq`), and weak-head normal-form reduction (`whnf`), plus inductive/recursor/projection/quotient validation.

### Exit codes

The checker follows the arena's exit-code protocol:

| Code | Meaning |
|------|---------|
| `0`  | Accepted — all declarations are well-typed |
| `1`  | Rejected — a declaration failed type checking |
| `2`  | Declined — the checker cannot handle this input |
| other | Internal error |

## Requirements

- The `vowc` Vow compiler. See [vow-lang](https://github.com/pmatos/vow-lang); the kernel currently requires a self-hosted build from source (a published release may be too old). CI builds `vowc` from a pinned Vow revision.

> **Memory:** Vow-compiled code (both `vowc` and the resulting binaries) is prone to memory blow-ups, so always run under a `ulimit -v` cap. The scripts below do this for you.

## Build

```sh
# Uses vowc from $PATH (override with VOWC=...); caps memory at 4 GB.
./scripts/build.sh
```

This produces the `lean_checker` binary. To build by hand:

```sh
ulimit -v 4194304 && vowc build --no-verify -o lean_checker main.vow
```

## Usage

The checker streams its input line by line, from either stdin or a file argument:

```sh
# From a file
ulimit -v 8388608 && ./lean_checker proof.ndjson

# From stdin (arena-compatible)
ulimit -v 8388608 && ./lean_checker < proof.ndjson

echo "exit code: $?"
```

Generate NDJSON input for a Lean file with [`lean4export`](https://github.com/leanprover/lean4export).

## Testing

The committed fixtures live under `tests/good/` (must accept, exit 0) and `tests/bad/` (must reject, exit 1), and include the full arena tutorial suite:

```sh
./scripts/run_tests.sh
```

Options: `--checker PATH`, `--mem-limit KB`, and `--tests-dir DIR` to point at a downloaded arena bundle (each `.ndjson` paired with a sibling `.yaml` carrying `outcome: accept|reject`). A `DECLINE` (exit 2) is reported as a skip.

## Project layout

```
main.vow            CLI entry point: read input, parse, check, set exit code
parse/
  json.vow          Hand-written JSON parser
  strutil.vow       String-parsing utilities
  export.vow        lean4export NDJSON → arenas + declarations
kernel/
  name.vow          Names (arena, stringification)
  level.vow         Universe levels (normalization, leq, substitution)
  expr.vow          Expression arena, substitution, free-variable checks
  subst.vow         Substitution helpers
  env.vow           Environment (declaration storage and lookup)
  infer.vow         Type inference
  def_eq.vow        Definitional equality
  whnf.vow          Weak-head normal-form reduction
  inductive.vow     Inductive-type validation
bignum.vow          Arbitrary-precision Nat support for literal reduction
diag/               Diagnostics
scripts/            build.sh, run_tests.sh
tests/              good/, bad/ fixtures (incl. arena tutorial)
arena/              Lean Kernel Arena checker submission
plan/plan.md        Full implementation plan (phases L0–L9)
```

## Implementation plan

The design and phased roadmap (L1 NDJSON parsing through L9 large-scale Mathlib validation, each mapped to arena tutorial tests) are in [`plan/plan.md`](plan/plan.md). The full tutorial suite passes; work on the larger arena corpora (`init`, `std`, `cedar`, …) is ongoing.

## Lean Kernel Arena

The arena submission lives in [`arena/`](arena/) — a `checker.yaml` that self-hosts `vowc`, builds the kernel, and runs it under a memory cap, plus dry-run tooling. See [`arena/README.md`](arena/README.md) for details.

- Arena site: https://arena.lean-lang.org
- Arena repo: https://github.com/leanprover/lean-kernel-arena

## References

- [Type Checking in Lean 4](https://ammkrn.github.io/type_checking_in_lean4/) — Chris Bailey
- [The Type Theory of Lean](https://github.com/digama0/lean-type-theory/releases) — Mario Carneiro
- [Nanoda](https://github.com/ammkrn/nanoda_lib) — a ~5k-line Rust reference kernel
- [lean4export](https://github.com/leanprover/lean4export) — the exporter that produces the NDJSON input

## License

[MIT](LICENSE) © 2026 Paulo Matos
