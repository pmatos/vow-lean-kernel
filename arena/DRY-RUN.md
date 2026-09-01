# Arena dry-run results

Local characterization of the checker on real `lean4export` NDJSON, to know what
the arena will report before submitting. Inputs match the arena's `init` / `std`
/ `mathlib` test modules. Each run uses the clean-room-built `lean_checker`,
measured with `/usr/bin/time -v`. These numbers were taken under an `ulimit -v
8G` cap; the `run` command's cap has since been **raised to 12 GB** to give the
`init` accept run headroom (see Resource envelope). A later local re-measurement
found `init` peaking well above that cap — see
[Local re-measurement](#local-re-measurement-2026-08-24).

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
(`{"error":"OutOfMemory",...}`), remap it to an **error (exit 3)** instead — an
OOM is a resource-exhaustion abort (the arena's crash / OOM / timeout bucket),
not a claim the proof is invalid. Genuine rejects (exit 1, no OOM marker), real
declines (exit 2) and real crashes (signals) are untouched.

Validated three ways against the clean-room binary:

| scenario | raw exit | OOM marker | mapped exit |
|----------|:--------:|:----------:|:-----------:|
| forced OOM (`init` under a 900 MB cap) | 1 | yes | **3 — error** |
| genuine reject (`tests/bad` fixture)   | 1 | no  | **1 — reject** |
| accept (tutorial fixture)              | 0 | no  | **0 — accept** |

Why the cap is 12 GB: the runtime's graceful OOM detection fires when a Vow
allocation hits the `ulimit -v` ceiling, so the cap must sit *below* the host's
physical RAM — otherwise the OS OOM-killer strikes first (SIGKILL → uncatchable
`error`). 8 GB gave that but left `init` almost no headroom (it needs 7.6 GB);
12 GB keeps the graceful behaviour on any normal arena host (≥16 GB) while giving
`init` comfortable room.

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

> **Toolchain note:** the arena runs `init`/`std` at **v4.29.1** — their
> `leanfile` tests inherit `tests/lean-toolchain` (v4.29.1). These were measured
> at v4.29.0, a Lean *patch* difference: the accept/decline verdicts are robust,
> though the exact RSS/wall figures are indicative. `gen-inputs.sh` now pins
> v4.29.1 for all three so future runs match the arena exactly.

## Results (raw exit codes; OOM→error mapping noted)

| input | verdict | raw exit | arena verdict | wall | max RSS | note |
|-------|---------|:--------:|---------------|------|--------:|------|
| init | **accept** | 0 | accept | 1:22:50 | 7.63 GB | all 54,475 `Init` decls well-typed |
| std | OOM | 1 | **error** (via OOM→3 map) | 2:15:13 | 8.00 GB | OOM at `arena_open` while *checking*, decl 32,900/89,805 (`Std.DTreeMap` region) |
| mathlib | OOM | 1 | **error** (via OOM→3 map) | 33:58 | 7.99 GB | OOM at `arena_open` while *loading* — 0 decls checked; the 5.25 GB / 100M-line environment doesn't fit in 8 GB |

**Tally (arena verdicts):** 1 accept · 0 reject · 0 decline · 2 error.
No false reject and no uncaught crash — the key pre-submission risk check passes.
(The `arena/dry-run.sh` run above predates the OOM→error annotation and tallies
the two OOMs as raw "reject"; the committed harness and `checker.yaml` map them to
errors, as shown in the "arena verdict" column.)

## Resource envelope

- **`init` (the accept test): 7.63 GB max RSS — under the original 8 GB cap that
  was only ~4.7% headroom.** This is heavier than the older ~5 GB figure (the
  clean-room self-hosted `vowc` differs from the local prebuilt one). **Resolved:**
  the `run` cap is now **12 GB**, giving `init` ~57% headroom while staying below
  typical arena host RAM (so an OOM still surfaces as a graceful, detectable
  allocation failure). The 7.63 GB / 8 GB figures here are from the original 8 GB
  measurement run.
  **⚠️ Superseded — the 12 GB cap is not sufficient on this machine.** A local
  re-measurement (2026-08-24, see [Local re-measurement](#local-re-measurement-2026-08-24))
  puts the same `init` export at a **26.92 GB** peak, so a run under the 12 GB cap
  aborts partway and is reported as an error. The 7.63 GB reference has not been
  reproduced locally; that gap is unexplained and tracked in issue #62.
- **`std`**: OOMs while *checking*, at decl ~32,900/89,805 (`Std.DTreeMap`
  region) — reported as an error via the OOM mapping.
- **`mathlib`**: OOMs while *loading* the environment, before checking any
  declaration. The full Mathlib export (5.25 GB / 100M lines) exceeds 8 GB just
  to ingest. This is a distinct scaling limit from `std`'s: whole-library inputs
  won't load regardless of proof difficulty, and raising the cap only defers the
  load OOM. Reported as an error via the OOM mapping.
- **Wall time**: `init` ~83 min on this host (indicative). `std` spends its first
  ~83 min re-checking the `Init` prefix before reaching new declarations;
  `mathlib` never gets past loading (~34 min to OOM).

## Coverage & follow-ups

- All three arena modules were run to a verdict: `init` accepts; `std` and
  `mathlib` both OOM (checking vs. loading, respectively) and map to a graceful
  error (exit 3). No false rejects, no uncaught crashes.
- **Vow runtime**: OOM exiting with code `1` (colliding with a meaningful app
  exit code) is reported upstream as
  [vow-lang/vow#877](https://github.com/vow-lang/vow/issues/877); the `run`
  wrapper is the local mitigation.
- **Arena submission:** opened as
  [leanprover/lean-kernel-arena#68](https://github.com/leanprover/lean-kernel-arena/pull/68)
  (`checkers/vow-lean-kernel.yaml`). Bump its `rev` if a newer known-good kernel
  commit lands before it merges.

## Local re-measurement (2026-08-24)

Re-measured the `init` accept test on the current kernel while investigating
issue #62, which reported a local build dying at decl 3700/54475 under an 8 GB
cap with RSS climbing ~2 MB per checked declaration.

Input: `_build/tests/init.ndjson` — 54,475 declarations, `lean4export` 3.1.0,
Lean 4.29.0, parse watermark `arena=5726477`. That watermark matches the one
quoted in #62 exactly, so this is the same file the report was measured against,
and the same export behind the 7.63 GB reference above.

### The 8 GB run still OOMs, at decl 19500 instead of 3700

Under the same 8 GB cap the current kernel still terminates with an
`OutOfMemory`, so #62's underlying failure is not resolved: it moves from decl
3700 to decl 19500, and from `arena_open` to `arena_alloc`. The left column
below is quoted from #62 and was **not** re-measured here; only the right column
is a measurement from this investigation. Against #62's reported ~2 MB/decl
— itself unconfirmed here — the measured 155 KB/decl is roughly a 13× reduction.

| | #62 as filed (`c251890`) | current kernel (measured) |
|---|---|---|
| dies at decl | 3700 / 54475 | 19500 / 54475 |
| peak RSS | 8.38 GB (cap-pinned) | 7.99 GB (cap-pinned) |
| growth | ~2 MB/decl | ~155 KB/decl |
| error | `arena_open` OOM | `arena_alloc` OOM |

`c251890` predates the strict-int-typing migration (PR #64) and can no longer be
built with the current `vowc`, so its figures above stand as filed rather than
re-measured. The oldest buildable commit, `f2735bb` — the parent of the PR #65
merge, separated from `c251890` by PRs #63 and #64 — does reproduce two of them
independently: it dies at **decl 3700** with
`{"error":"OutOfMemory","operation":"arena_open"}`, matching both the reported
declaration and the failing operation. `a4c3724`, the merge of #65, runs past
it, which places the improvement at the contextual WHNF cache. Per-decl growth
and peak RSS at `f2735bb` were not separately recorded, so the ~2 MB/decl and
8.38 GB rows remain unconfirmed by any build in this investigation.

Nor is the aggregate gap #62 raised closed: the full run below needs **26.92 GB**
against the 7.63 GB reference, i.e. wider than when #62 was filed.

### Full run, cap raised to 32 GB

| metric | value |
|---|---|
| verdict | exit 2 (declined) |
| declarations | reached 54400 / 54475 |
| declines | 33 |
| failures | 0 |
| peak RSS | **26.92 GB** |
| wall time | 7 h 07 m |

Two declaration families account for over half the peak: decls 19530/19531
(`Char.ofOrdinal_ordinal`, +6.75 GB across the 18000–22000 window) and
27420/27437/27440 (`Char.succ?_eq`, +7.89 GB across 26000–30000). Everything
else grows at roughly 1 GB per 4000 declarations. This matches the ratchet
behaviour seen in earlier profiling: peak ≈ parse baseline + the worst single
declaration's transient, not a cumulative leak.

30 of the 33 declines sit at `fuel=50000xx`, i.e. the pre-existing 5M `def_eq`
fuel cap. The largest arena delta anywhere is 5.45M nodes, well under the 16M
per-declaration allocation ceiling from PR #63, so that ceiling never trips. The
remaining 3 (decls 20452 / 22853 / 35291, the SInt `instUpwardEnumerable_eq`
family) give up at 35K–86K fuel through some other path, not yet identified.

The declines are not a regression from the recent kernel work: at `a4c3724` —
immediately after #65, before #66/#68/#69/#73 — decls 4559 and 4628 already
decline exactly as they do now. Before #65 the run never reached them.

### Reference kernel on the same input

The official Lean kernel (`checkers/official`, toolchain v4.29.0) on the same
file:

```
Accepted 54472 declarations.
exit 0   elapsed 0:50.67   max RSS 542 MB
```

54,472 = 54,475 minus the three `Quot` declarations it erases before replay. So
every declaration in this export is well-typed, and all 33 of our declines are
sound abstains on valid input rather than disagreements. It also sets the
performance gap plainly: 50 seconds and 542 MB against 7 hours and 26.92 GB.

Worth re-running first in any future verdict dispute — it builds in about a
minute with `lake build` and is authoritative.
