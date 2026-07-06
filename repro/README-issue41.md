# issue #41 regression fixtures

Minimal `lean4export` exports pinning the def_eq term-size blowup on the SInt
`HasSize_eq` family (init.ndjson decl 26993) and the completeness/crash guards
that a fix must not regress. Each must produce the stated exit code.

| Fixture | Target decl | Expect | Guards |
|---|---|---|---|
| `rxi16_hang.ndjson` | `Int16.instRxiHasSize_eq` | **accept** (exit 0) | the blowup: was a multi-hour hang / 13 GB OOM, now ~4 s / ~125 MB |
| `rxi16_reject.ndjson` | same, proof `value` corrupted | **reject** (exit 1) | soundness — a broken proof must still fail |
| `postcond.ndjson` | `Std.Iterators.PostconditionT.map_eq_pure_bind` | **accept** (exit 0) | completeness + re-entrancy: a monad-law rewrite that only unifies under full delta; the naive PR #40 hybrid OOM'd/crashed here |

Run (self-hosted `vow`-built `lean_checker`, under a memory cap):

```
ulimit -v 16777216 && ./lean_checker repro/rxi16_hang.ndjson   ; echo $?  # 0
ulimit -v 16777216 && ./lean_checker repro/rxi16_reject.ndjson ; echo $?  # 1
ulimit -v 16777216 && ./lean_checker repro/postcond.ndjson     ; echo $?  # 0
```

Regenerate (needs the lean4export checkout from CLAUDE.md):

```
cd /home/pmatos/leanexport/proj/src
lake env /home/pmatos/leanexport/lean4export/.lake/build/bin/lean4export Test -- "<full.decl.name>"
```
