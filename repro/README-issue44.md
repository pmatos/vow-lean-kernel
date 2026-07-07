# issue #44 regression fixtures

Minimal `lean4export` exports pinning the `def_eq` false-reject on the SInt
`HasSize_eq` family's `ISize` / `Rxc` member (init.ndjson decl 33671). Each must
produce the stated exit code.

The checker used to **false-reject** (exit 1) `ISize.instRxcHasSize_eq`: the two
size-formula normal forms differ only where the proof side has `ISize.toBitVec lo`
and the def-unfold side has `HasModel.encode … ISize.instHasModelBitVecNumBits lo`
(these are def-eq — both reduce to `(ISize.toUSize lo).toBitVec`). Eager
`is_def_eq` whnf's the symbolic `BitVec.toNat` major of the size `Nat.rec` and
reduces the formula over the concrete 64-bit width, recursing ~1000 deep without
converging cold. The fix adds an eager-first **lazy congruence fallback** for
`has_size_eq` recursor spines (reached only after eager fails, so Rxc members the
eager path already settles — e.g. `Int16.instRxcHasSize_eq` — are untouched).

| Fixture | Target decl | Expect | Guards |
|---|---|---|---|
| `isize_rxc.ndjson` | `ISize.instRxcHasSize_eq` | **accept** (exit 0) | the false-reject: was exit 1 on both `main` and the #42 branch |
| `isize_rxc_reject.ndjson` | same, proof `value` replaced by a `_ = True` subterm | **reject** (exit 1) | soundness — a non-proof of the stated type must still fail |

Run (self-hosted `vow`-built `lean_checker`, under a memory cap):

```
ulimit -v 8388608 && ./lean_checker repro/isize_rxc.ndjson        ; echo $?  # 0
ulimit -v 8388608 && ./lean_checker repro/isize_rxc_reject.ndjson ; echo $?  # 1
```

Regenerate (needs the lean4export checkout from CLAUDE.md):

```
cd /home/pmatos/leanexport/proj/src
lake env /home/pmatos/leanexport/lean4export/.lake/build/bin/lean4export Test -- \
  "_private.Init.Data.Range.Polymorphic.SInt.0.ISize.instRxcHasSize_eq"
```
