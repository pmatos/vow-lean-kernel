# Init.Prelude: Final 10 Failures

**Status**: 2041/2051 declarations pass (99.5%). 10 remain.

## Phase A: u64 Overflow (5 failures)

`nat_value` parses Nat literal strings into `u64` and returns sentinel on overflow. `2^64 = 18446744073709551616` doesn't fit, breaking all UInt64/USize operations.

**Affected declarations:**
- 732: `UInt64.ofNatLT` (def, code=11: infer val fails)
- 733: `instInhabitedUInt64._proof_1` (thm, code=22: cascades from 732)
- 1074: `Lean.Name.hash._proof_1` (thm, code=22: hash uses UInt64)
- 1077: `Lean.Name.hash._proof_2` (thm, code=22: hash uses UInt64)
- 1373: `USize.size_pos` (thm, code=22: USize.size = 2^64 on 64-bit)

### Wave A1: String-based big-nat comparison

Add `nat_str_ble(a: String, b: String) -> u64` and `nat_str_beq(a: String, b: String) -> u64` that compare decimal strings without converting to u64. This lets `Nat.ble` and `Nat.beq` work on arbitrarily large literals.

**Files**: `kernel/whnf.vow`

- Implement digit-by-digit decimal comparison (compare lengths first, then lexicographic)
- In the `Nat.ble`/`Nat.beq` kernel extensions, when `nat_value` returns sentinel for either arg, fall back to whnf both args and try string-based comparison if both are Nat literals (tag==7)

### Wave A2: String-based big-nat arithmetic

Add string-based `nat_str_add`, `nat_str_sub`, `nat_str_mul`, `nat_str_mod` for the remaining kernel extensions. Only needed if Wave A1 doesn't resolve all 5 failures (some proofs may need `Nat.mod 2^64` to compute `Fin` values).

**Files**: `kernel/whnf.vow`, `kernel/expr.vow`

- Implement schoolbook decimal addition/subtraction/multiplication
- `nat_str_mod` for `Nat.mod` on large values (needed for `Fin 2^64`)
- Update kernel extensions to use string-based fallback when u64 overflows

## Phase B: Trans Universe Polymorphism (4 failures)

`Trans` is a typeclass with 6-7 universe parameters. `ensure_sort(infer(ty))` fails — the type can't be inferred to a sort. Likely a level comparison gap in `is_level_eq` for deeply nested imax/max expressions with many parameters.

**Affected declarations:**
- 1174: `Trans.trans` (def, code=10: sort on type fails, 6 universe params)
- 1446: `Trans.noConfusion` (def, code=10: 7 universe params)
- 1447: `Trans.mk.noConfusion` (def, code=10: 7 universe params)
- 1919: `Trans.ctorIdx` (def, code=10: cascades from above)

### Wave B1: Diagnose the level mismatch

Add targeted debug output to capture the failing level comparison for decl 1174 (`Trans.trans`). Record `debug_level_a` / `debug_level_b` in the Sort comparison path of `is_def_eq` (as done previously for decl 463). Identify the exact pair of levels that `is_level_eq` can't prove equal.

**Files**: `kernel/def_eq.vow`, `kernel/env.vow`, `main.vow` (temporary)

### Wave B2: Fix the level comparison

Based on Wave B1's findings, add the missing rule to `is_level_eq` or `level_normalize`. Previous fixes in this area:
- Component-wise comparison for imax/max
- imax distribution fix: `imax(a, imax(b, c)) = imax(max(a,b), c)`
- Bidirectional leq with `is_level_leq_no_eq`

The new fix will likely involve another imax/max simplification or a deeper normalization rule for many-parameter level expressions.

**Files**: `kernel/def_eq.vow` or `kernel/subst.vow`

## Phase C: DecidableRel def_eq (1 failure)

`DecidableRel` is an abbreviation where `is_def_eq_pi(val_ty, ty)` fails — the value's inferred type doesn't match the declared type.

**Affected declarations:**
- 999: `DecidableRel` (def, code=12: def_eq fails)

### Wave C1: Diagnose and fix

Add debug output to capture what `is_def_eq` sees for this declaration (the WHNF'd forms of both sides). The failure is likely either:
- A level comparison gap (similar to Phase B)
- A missing eta rule for a specific pattern
- A reduction that doesn't complete

Fix based on findings. May be resolved as a side effect of Phase B if the root cause is shared.

**Files**: `kernel/def_eq.vow` (temporary debug + fix)

## Verification

After each phase:
```bash
rm -f lean_checker lean_checker.o && bash scripts/build.sh
# Tutorial regression (must stay 126/126)
for f in tests/good/tutorial/*.ndjson; do (ulimit -v 4194304 && ./lean_checker < "$f"); done
for f in tests/bad/tutorial/*.ndjson; do (ulimit -v 4194304 && ./lean_checker < "$f"); done
# Init.Prelude progress
(ulimit -v 4194304 && timeout 600 ./lean_checker < /home/pmatos/dev/lean-kernel-arena/_build/tests/init-prelude.ndjson)
```
