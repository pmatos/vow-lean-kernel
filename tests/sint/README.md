# SInt / Nat reduction regression fixtures

Behavioural fixtures for the fixed-width-integer (`Int8`/`Int16`/`Int32`/`Int64`/
`USize`/`ISize`, `BitVec`) reduction path. They guard the fix for the 2³²
`Nat`-literal sentinel bug: `decide (a < b)` (and hence `BitVec.toInt`'s
`if 2*x.toNat < 2^n`) used to get stuck once an operand's successor reached the
in-band `4294967294` (2³²−2) "not-a-literal" sentinel.

The `.ndjson` inputs are generated (not committed — see `.gitignore`). Each is
expected to **accept** (exit 0).

## Run

```sh
bash tests/sint/run.sh ./lean_checker
```

## Regenerate

Needs the arena-pinned toolchain (`leanprover/lean4:v4.29.0`) and a built
`lean4export`. From a Lean project whose `Test.lean` is `import Init`:

```lean
-- Test.lean
import Init
theorem t_lt_2p32     : decide (4294967296 < 4294967296) = false := rfl  -- 2^32
theorem t_lt_sentinel : decide (4294967293 < 4294967293) = false := rfl  -- succ hits the 2^32-2 sentinel
theorem t_lt_selval   : decide (4294967294 < 4294967295) = true  := rfl  -- sentinel value as operand
theorem t_lt_true     : decide (5 < 4294967296) = true := rfl
theorem t_lt_2p64     : decide (18446744073709551616 < 18446744073709551617) = true := rfl  -- above u64
```

```sh
lake build Test
BIN=.../lean4export/.lake/build/bin/lean4export
for t in t_lt_2p32 t_lt_sentinel t_lt_selval t_lt_true t_lt_2p64; do
  lake env "$BIN" Test -- "$t" > tests/sint/$t.ndjson
done
# Plus a real cluster member that used to *decline*:
lake env "$BIN" Test -- Int32.toInt_ofIntLE > tests/sint/t_int32_toint.ndjson
```
