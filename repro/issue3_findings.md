# Issue #3 — investigation and resolution

The 4 `Nat.Linear.Poly.*cancelAux*` theorems (decls 2035, 2039, 2074, 2080 in
`grind-ring-5.ndjson`) saturated the 5M `kernel_fuel` cap during type-checking.
Two cooperating bugs in `is_def_eq_core` were the cause; both diverge from
Lean 4's reference implementation.

## Diagnosis

Per-call-site counters added to `is_def_eq_core` (App-App, Proj, Eta, etc.)
showed decl 2035 burning all 5M fuel across three branches in roughly equal
proportion. Two compounding bugs:

### Bug 1 — App-App single-level peel

`kernel/def_eq.vow` (pre-fix, ~line 681):

```vow
if t1 == 3 {
    let app_fn_eq = is_def_eq_full(env, env.exprs.f1[w1], env.exprs.f1[w2]);
    if app_fn_eq > 0 {
        let app_arg_eq = is_def_eq_full(env, env.exprs.f2[w1], env.exprs.f2[w2]);
        ...
```

Peeling one App layer at a time spawns two recursive `is_def_eq_full` calls per
level. For an N-arg spine, the function head is re-compared via the recursive
`(f a) =?= (f' a')` chain at every level, triggering O(2^N) WHNF + lazy-delta
work.

**Lean 4 (`type_checker.cpp:815`)** flattens the spine via `get_app_args` and
compares the head **once**:
```cpp
expr t_fn = get_app_args(t, t_args);
expr s_fn = get_app_args(s, s_args);
if (is_def_eq(t_fn, s_fn) && t_args.size() == s_args.size()) { ... }
```

Nanoda (`tc.rs:898`) does the same with `unfold_apps`.

### Bug 2 — Eta-struct cycle (the dominant cost)

`kernel/def_eq.vow` (pre-fix, ~line 851) creates `Proj` nodes on **both**
sides regardless of whether either is a constructor application:

```vow
let p1: u64 = expr_add_proj(env.exprs, eta_name_idx, efi, w1);
let p2: u64 = expr_add_proj(env.exprs, eta_name_idx, efi, w2);
if is_def_eq_full(env, p1, p2) == 0 { ... }
```

When neither side is a constructor, neither `Proj` reduces in WHNF. The
recursive `is_def_eq_full(p1, p2)` reaches the Proj-Proj branch which calls
`is_def_eq_full(f3[p1], f3[p2])` — i.e. `is_def_eq_full(w1, w2)`, the original
inputs. This loop is broken only by the `kernel_fuel` cap.

**Lean 4 (`type_checker.cpp:793`, `try_eta_struct_core`)** requires one side
to be a constructor application:
```cpp
expr f = get_app_fn(s);
if (!is_constant(f)) return false;
constant_info f_info = env().get(const_name(f));
if (!f_info.is_constructor()) return false;
```

The constructor side has known field values, which terminates the recursion
via WHNF reduction of `Proj` on a constructor expression.

## Fix

Two changes to `kernel/def_eq.vow:is_def_eq_core`:

1. **Spine flattening for App-App.** Walk both spines into args buffers, compare
   head once and args linearly. Mirrors `is_def_eq_app` semantics.
2. **Ctor gate on eta-struct field projection.** Require at least one side's
   spine head to be a `Const` with `kind == 6` (constructor). The unit-like
   case (`eta_nf == 0`, no fields to project) keeps its early-return-1 — that
   path corresponds to Lean 4's `is_def_eq_unit_like` and has no cycle risk.

## Results

| Decl | Baseline fuel | Post-fix fuel | Reduction | Outcome |
| --- | ---: | ---: | ---: | --- |
| 2031 `Poly.denote_reverse` | 10,303 | 304 | 33× | declined (preexisting) |
| 2035 `Poly.of_denote_eq_cancelAux` | 5,000,368 (cap) | 2,727 | 1832× | **passes** |
| 2039 `Poly.denote_eq_cancelAux` | 5,000,367 (cap) | 2,693 | 1856× | **passes** |
| 2074 `Poly.of_denote_le_cancelAux` | 5,000,799 (cap) | 2,632 | 1900× | **passes** |
| 2080 `Poly.denote_le_cancelAux` | 5,000,798 (cap) | 2,665 | 1876× | **passes** |
| 2083 `ExprCnstr.denote_toNormPoly` | ~205 | 205 | unchanged | declined (preexisting) |

Tutorial regression check: 86/86 pass.

`grind-ring-5` still exits 2 because decls 2031 and 2083 remain declined for
unrelated reasons (both with low fuel consumption — not cap-bound). Those are
separate issues outside the scope of #3.

## Diagnostic infrastructure (kept in tree)

- Per-decl counters in `Environment` (`cnt_is_def_eq_full`, `cnt_cong_hit`,
  `cnt_dfull_app/proj/eta/...`, `cnt_infer_tag[]`).
- `DIAG` print block in `main.vow` triggered for affected decl range and on
  decline / high-fuel events.
- Useful for future regressions and for verifying the App-App / eta-struct
  paths remain bounded.
