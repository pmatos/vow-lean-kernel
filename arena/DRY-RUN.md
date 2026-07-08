# Arena dry-run results

Local characterization of the checker on real `lean4export` NDJSON, to know what
the arena will report before submitting. Inputs match the arena's `init` / `std`
/ `mathlib` test modules. Each run uses the clean-room-built `lean_checker` under
`ulimit -v 8G` (the cap `checker.yaml`'s `run` command sets), measured with
`/usr/bin/time -v`.

Machine: 24 cores, 124 GB RAM (Linux). Runs were serial (one checker at a time),
so wall time and max RSS are uncontended, but they are still only *indicative* —
the arena measures on its own hardware.

## Headline finding (and fix)

The dry-run caught the one thing it exists to catch: **an out-of-memory abort was
being reported as a false reject.**

`lean_checker` follows the arena protocol (`0` accept / `1` reject / `2`
decline). But the **Vow runtime exits `1` on OutOfMemory** — the same code as a
kernel reject. On the `std` input the checker exhausted the 8 GB budget and
exited `1`, which the arena would score as a **false reject on an accept test**
(the worst possible outcome). See the raw evidence in the `std` row below.

Fix (in `checker.yaml`'s `run` — the kernel cannot intercept a runtime-level OOM
abort): capture stderr, and when a run fails with the Vow OOM marker
(`{"error":"OutOfMemory",...}`), report a **decline (exit 2)** instead — an
honest "exceeded my memory budget", not a claim the proof is invalid. Genuine
rejects (exit 1, no OOM marker) and real crashes (signals) are untouched.

Validated three ways against the clean-room binary:

| scenario | raw exit | OOM marker | mapped exit |
|----------|:--------:|:----------:|:-----------:|
| forced OOM (`init` under a 900 MB cap) | 1 | yes | **2 — decline** |
| genuine reject (`tests/bad` fixture)   | 1 | no  | **1 — reject** |
| accept (tutorial fixture)              | 0 | no  | **0 — accept** |

Why the 8 GB cap stays: the runtime's graceful OOM detection fires when a Vow
allocation hits the `ulimit -v` ceiling. Keeping the cap *below* the host's
physical RAM is what makes an OOM a graceful decline rather than an OS
OOM-kill (SIGKILL → uncatchable `error`). 8 GB gives that on any normal arena
host.

## Build & smoke

- **Clean-room build** (the `checker.yaml` `build` path, from a fresh checkout):
  `git clone vow-lang/vow @ VOW_REF` → `cargo build --all` (82 crates) →
  self-hosted `vowc` (75 MB) → `scripts/build.sh` → `lean_checker` (10 MB).
  0 errors/warnings. Reproducible.
- **Smoke**: `scripts/run_tests.sh` on that binary → **131/131 pass** (tutorial
  accept + reject fixtures), 0 fail, 0 skip.

## Inputs

Generated with `lean4export`, matching the arena's test modules:

| input | module | toolchain | size | decls |
|-------|--------|-----------|-----:|------:|
| init | `Init` | v4.29.0 | 325 MB | 54,475 |
| std | `Std` | v4.29.0 | 502 MB | 89,805 |
| mathlib | `Mathlib` | v4.29.1 | 5.25 GB | (100M lines) |

## Results (raw exit codes; OOM→decline mapping noted)

| input | verdict | raw exit | arena verdict | wall | max RSS | note |
|-------|---------|:--------:|---------------|------|--------:|------|
| init | **accept** | 0 | accept | 1:22:50 | 7.63 GB | all 54,475 `Init` decls well-typed |
| std | OOM | 1 | **decline** (via OOM→2 map) | 2:15:13 | 8.00 GB | OOM at `arena_open` while *checking*, decl 32,900/89,805 (`Std.DTreeMap` region) |
| mathlib | OOM | 1 | **decline** (via OOM→2 map) | 33:58 | 7.99 GB | OOM at `arena_open` while *loading* — 0 decls checked; the 5.25 GB / 100M-line environment doesn't fit in 8 GB |

**Tally (arena verdicts):** 1 accept · 0 reject · 2 decline · 0 error.
No false reject and no uncaught crash — the key pre-submission risk check passes.
(The `arena/dry-run.sh` run above predates the OOM→decline annotation and tallies
the two OOMs as raw "reject"; the committed harness and `checker.yaml` map them to
declines, as shown in the "arena verdict" column.)

## Resource envelope

- **`init` (the accept test): 7.63 GB max RSS under the 8 GB cap — only ~4.7%
  headroom.** This is heavier than the older ~5 GB figure (the clean-room
  self-hosted `vowc` differs from the local prebuilt one). It passes on this
  host, but the margin is thin: a slightly tighter arena host could push `init`
  itself into an OOM→decline, losing the pass. **Decision point for submission:**
  either accept the thin margin at 8 GB, or raise the `run` cap (e.g. 10–12 GB)
  if the arena hosts have the RAM — a one-line change in `checker.yaml`.
- **`std`**: OOMs while *checking*, at decl ~32,900/89,805 (`Std.DTreeMap`
  region) — declines via the OOM mapping.
- **`mathlib`**: OOMs while *loading* the environment, before checking any
  declaration. The full Mathlib export (5.25 GB / 100M lines) exceeds 8 GB just
  to ingest. This is a distinct scaling limit from `std`'s: whole-library inputs
  won't load under an 8 GB cap regardless of proof difficulty. Declines via the
  OOM mapping.
- **Wall time**: `init` ~83 min on this host (indicative). `std` spends its first
  ~83 min re-checking the `Init` prefix before reaching new declarations;
  `mathlib` never gets past loading (~34 min to OOM).

## Coverage & follow-ups

- All three arena modules were run to a verdict: `init` accepts; `std` and
  `mathlib` both OOM (checking vs. loading, respectively) and map to graceful
  declines. No false rejects, no uncaught crashes.
- **Vow runtime**: OOM exiting with code `1` (colliding with a meaningful app
  exit code) is worth reporting upstream (vow-lang/vow); the `run` wrapper is the
  local mitigation.
- **Not done this session (deliberate):** opening the PR against
  `leanprover/lean-kernel-arena`. `arena/checker.yaml` is ready to submit as
  `checkers/vow-lean-kernel.yaml`; bump its `rev` to the merge commit first.
