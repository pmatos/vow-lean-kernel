# Lean Kernel Arena submission

Artifacts for registering this kernel with the
[Lean Kernel Arena](https://github.com/leanprover/lean-kernel-arena).

## `checker.yaml`

The checker definition, tracked here as the source of truth and validated
against the arena's `schemas/checker.json`. Submitted to the arena as
`checkers/vow-lean-kernel.yaml` in
[leanprover/lean-kernel-arena#68](https://github.com/leanprover/lean-kernel-arena/pull/68);
keep this copy and that one in sync.

It is a **`url`-type** checker: the arena clones this repo (`ref: main`, pinned
`rev`), runs `build` in the checkout, then `run` once per test with `$IN` set to
the NDJSON path.

- **build** replicates `.github/workflows/ci.yml`: clone `vow-lang/vow` at the
  pinned `VOW_REF`, `cargo build --all` (Rust bootstrap), self-host the
  Cranelift-backed `vowc`, then `VOWC=… bash scripts/build.sh` to produce
  `lean_checker`. The kernel builds *only* with the self-hosted `vowc`.
- **run** passes the input through `lean_checker` under `ulimit -v 12G` and
  forwards its exit code — except that a Vow-runtime **OutOfMemory** (which
  exits `1`, colliding with "reject") is remapped to a **decline (2)**, so an
  OOM is never reported as a false reject. See `DRY-RUN.md`.

Exit codes follow the arena protocol and map directly (`lka.py`):

| exit | arena status | meaning |
|------|--------------|---------|
| 0    | accepted     | all declarations well-typed |
| 1    | rejected     | a declaration failed type checking |
| 2    | declined     | outside the supported fragment (never scored incorrect) |
| else | error        | crash / OOM / timeout |

A **decline (2)** is always safe; the risk to avoid is a false **reject (1)** on
an `accept` test, or a crash/OOM. See `DRY-RUN.md` for measured behaviour.

Bump `rev` when submitting so the arena builds a known-good commit.

## `dry-run.sh`

Runs `lean_checker` on one or more NDJSON inputs under `ulimit -v 12G` with
`/usr/bin/time -v`, recording exit code, elapsed wall time, and max RSS, and
tallying accept/reject/decline/error. Mirrors how the arena invokes the checker.

```
arena/dry-run.sh <label>=<file.ndjson> [<label>=<file.ndjson> ...]
```

## `DRY-RUN.md`

Results of the local dry-run: per-input verdict, time, and memory, plus the
resource envelope and coverage notes.
