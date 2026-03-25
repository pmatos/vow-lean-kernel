# Arena Test Suite: Correctness & Performance

**Status**: 140/141 tests pass. 1 failure: grind-ring-5 (performance/OOM).

**Baseline performance**: init-prelude (3.6 MB, 30K lines) → 61s, 660 MB RAM.

## Test Results Summary

| Test | Size | Expected | Result |
|---|---|---|---|
| Tutorial (126) | small | mixed | PASS |
| init-prelude | 3.6 MB | accept | PASS (61s, 660 MB) |
| eta-expansion | 16 KB | accept | PASS |
| proof-irrel-dep | 3.0 MB | accept | PASS (30s, 1.7 GB) |
| bogus1 | small | reject | PASS |
| constlevels | 16 KB | reject | PASS |
| level-imax-leq | 8 KB | reject | PASS |
| level-imax-normalization | 8 KB | reject | PASS |
| ctor-type-wrong-return | 4 KB | reject | PASS |
| duplicate-level-params | 4 KB | reject | PASS |
| nat-rec-rules | 12 KB | reject | PASS |
| self-referential-def | 4 KB | reject | PASS |
| wrong-k-large-elim | 4 KB | reject | PASS |
| wrong-recursor-nfields | 4 KB | reject | PASS |
| wrong-recursor-numparams | 4 KB | reject | PASS |
| **grind-ring-5** | 9.8 MB | accept | **FAIL** (OOM at 8 GB, timeout at 16 GB) |
| init | 308 MB | accept | OOM at 4 GB, >13 GB at 5 min with 32 GB |
| std | 523 MB | accept | not run (larger than init) |
| cedar, cslib, mlir | large | accept | not built / not run |
| mathlib | 4.9 GB | accept | not built |

---

## Phase 1: Correctness — Recursor & Definition Validation ✓ COMPLETE

All five reject tests now correctly rejected.

### Wave 1A: Self-referential definition detection

**Test**: `self-referential-def` (4 KB, reject)

The export defines `loop : Nat := loop` — the definition body references the constant being defined. A definition's value must not reference the constant being declared (only inductives can self-reference via recursors).

**Fix**: In `check_def` (infer.vow), before or after type-checking, verify that the value expression does not contain a `Const` referencing the declaration's own name. Add a function `expr_references_name(env, expr, name) -> u64` that walks the expression and returns 1 if it finds a Const with that name.

**Files**: `kernel/infer.vow`

### Wave 1B: Recursor numParams validation

**Test**: `wrong-recursor-numparams` (4 KB, reject)

Defines `MyBool : Type` (0 params) but gives the recursor `numParams: 1`. The recursor's `numParams` must match the inductive type's `numParams`.

**Fix**: In `check_inductive` (inductive.vow), after checking types and constructors, validate each recursor's `numParams` matches the inductive's `numParams`. The data is already in `env.rec_num_params[rec_idx]` and `env.ind_type_num_params[type_idx]`.

**Files**: `kernel/inductive.vow`

### Wave 1C: Recursor nfields validation

**Test**: `wrong-recursor-nfields` (4 KB, reject)

`MyNat.succ` has 1 field but the recursor rule claims `nfields: 0`. Each recursor rule's `nfields` must match the constructor's actual non-parameter field count.

**Fix**: In `check_inductive`, for each recursor rule, verify `rule.nfields == ctor.num_fields`. The data is in `env.rec_rule_nfields` and `env.ind_ctor_num_fields`.

**Files**: `kernel/inductive.vow`

### Wave 1D: K-flag / large elimination validation

**Test**: `wrong-k-large-elim` (4 KB, reject)

`MPB : Prop` has two constructors but claims `k: true` on its recursor, enabling large elimination. For a Prop inductive, large elimination (`k: true`) is only valid when there's at most one constructor AND all constructor fields are themselves in Prop.

**Fix**: In `check_inductive`, when the inductive lives in `Prop` (Sort 0), validate the `k` flag:
- If `k: true`, check: exactly 1 constructor, and every field of that constructor has a type in Prop.
- If `k: false`, no extra check needed (conservative is always safe).

**Files**: `kernel/inductive.vow`

### Wave 1E: Recursor rule RHS type checking

**Test**: `nat-rec-rules` (12 KB, reject)

The `Nat.rec` succ rule has a wrong RHS that always returns `hzero`, ignoring the induction hypothesis. This allows proving False. The checker must independently verify that each recursor rule's RHS has the correct type.

This is the most complex fix. For each rule `{ ctor, nfields, rhs }`:
1. Build the expected type for `rhs` from the recursor type, constructor type, and level params
2. Check that `infer(rhs)` is definitionally equal to the expected type

**Reference**: "Type Checking in Lean 4" by Chris Bailey, Section on recursor checking. Also see nanoda_lib's `check_rec_rule` function.

**Files**: `kernel/inductive.vow`, `kernel/infer.vow`

---

## Phase 2: Performance — Large Test Support

### Wave 2A: grind-ring-5 (9.8 MB, 200K lines)

OOM at 8 GB, timeout (>600s) at 16 GB. The test needs "fast reduction" per its description. This is ~3x init-prelude in file size but requires dramatically more resources.

**Likely causes**:
- Expression arena grows without bound (no sharing across declarations)
- WHNF cache grows monotonically
- Nat kernel extensions doing heavy string arithmetic
- Reduction depth on large proof terms

**Investigation**:
- Profile memory: how large is the expression arena at crash point?
- Profile time: which declarations are slow?
- Consider per-declaration arena/cache clearing

**Files**: `kernel/expr.vow`, `kernel/whnf.vow`, `main.vow`

### Wave 2B: init (308 MB, 6M lines)

13 GB+ after 5 minutes with 32 GB ulimit. ~100x more memory than init-prelude for ~100x more lines — near-linear but the constant factor is too high.

**Likely causes** (same as 2A, amplified):
- Expression arena: 6M input lines → possibly hundreds of millions of arena entries from WHNF/substitution
- No garbage collection — arena grows monotonically for the entire run
- Infer cache storing results for all expressions ever seen

**Possible fixes**:
- Clear WHNF and infer caches between declarations (entries from prior decls won't be needed)
- Compact or recycle expression arena entries that are no longer reachable
- Increase hash-consing effectiveness to reduce arena growth
- Limit arena size and exit with code 2 (decline) if exceeded

### Wave 2C: std, mathlib, cedar, cslib, mlir

Depends on 2A/2B. These are even larger and will require the same optimizations. mathlib (4.9 GB input) is the ultimate target — unlikely to be feasible without significant memory management.

---

## Verification

After each wave:
```bash
rm -f lean_checker lean_checker.o && bash scripts/build.sh

# Full test suite (tutorial + non-tutorial from tarball)
pass=0; fail=0
for f in tests/good/**/*.ndjson tests/good/*.ndjson; do
    [ -f "$f" ] || continue
    (ulimit -v 4194304 && timeout 600 ./lean_checker < "$f" > /dev/null 2>&1)
    rc=$?; [ $rc -eq 0 ] || [ $rc -eq 2 ] && pass=$((pass+1)) || { echo "FAIL: $(basename $f)"; fail=$((fail+1)); }
done
for f in tests/bad/**/*.ndjson tests/bad/*.ndjson; do
    [ -f "$f" ] || continue
    (ulimit -v 4194304 && timeout 30 ./lean_checker < "$f" > /dev/null 2>&1)
    rc=$?; [ $rc -eq 1 ] && pass=$((pass+1)) || { echo "FAIL: $(basename $f)"; fail=$((fail+1)); }
done
echo "$pass pass, $fail fail"

# Large tests (after Phase 2)
(ulimit -v 4194304 && timeout 600 ./lean_checker < tests/good/grind-ring-5.ndjson)
(ulimit -v 8388608 && timeout 1200 ./lean_checker < /home/pmatos/dev/lean-kernel-arena/_build/tests/init.ndjson)
```
