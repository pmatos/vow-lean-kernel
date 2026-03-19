# Lean Proof Checker in Vow — Implementation Plan

**Status:** Proposed
**Date:** 2026-03-19 (revised)
**Prerequisite:** Vow self-hosting compiler (Phases 12–16 complete or substantially complete)

## 1. Context

### What is a Lean kernel?

A Lean proof checker (kernel) is a small, standalone program that reads a stream of declarations exported from the Lean theorem prover and determines whether each declaration is well-typed according to Lean's type theory. It does **not** find proofs — it only verifies them. The Lean architecture separates proof *search* (elaborator, tactics, AI) from proof *checking* (the kernel). Only the kernel needs to be trusted.

The reference independent implementation, **Nanoda** (Rust), implements the full verification logic in under 5,000 lines of code. Multiple independent kernels written in different languages cross-validate each other through the **Lean Kernel Arena** (https://arena.lean-lang.org/).

### Input format

The checker reads NDJSON (newline-delimited JSON) produced by `lean4export` (https://github.com/leanprover/lean4export). Each line is a self-contained JSON object. The format uses **integer IDs** for names, levels, and expressions: earlier lines define `in` (name), `il` (level), and `ie` (expression) entries by ID, and later lines reference them. Declaration lines (`def`, `ax`, `thm`, `ind`, etc.) reference these IDs. The format is still evolving (see https://github.com/leanprover/lean4export/issues/3).

### Exit code protocol

- `0` — Proof accepted (all declarations well-typed)
- `1` — Proof rejected (a declaration failed type checking)
- `2` — Declined (checker cannot handle this input, e.g. `native_decide`)
- Anything else — Internal error in the checker

### Why this is a good Vow demonstration

1. **Pure systems programming with formal contracts.** Every kernel function has a precise specification — "if the input is well-typed, the output is its type." Vow blocks are not decoration; they are the point.
2. **No generics, traits, or closures needed.** The algorithms are naturally monomorphic: one expression type, one level type, one name type. WHNF reduction is a big match statement. Definitional equality is a recursive function on concrete types.
3. **Right-sized.** ~5k lines in Rust. Large enough to be a real exercise, small enough for agent-driven development.
4. **External test oracle.** The Lean Kernel Arena provides 133+ test cases with known accept/reject outcomes, including all of Mathlib. The tutorial test suite (126 cases) is a graduated implementation guide.
5. **Uses exactly Vow's feature set.** Structs, enums, pattern matching, `Vec<T>`, `HashMap<K,V>`, `String`, `Option<T>`, `Result<T,E>`, while loops, file I/O through effects, and vow blocks. Nothing more.

### Key references

- **"Type Checking in Lean 4"** by Chris Bailey: https://ammkrn.github.io/type_checking_in_lean4/ — Practical guide to writing a Lean kernel.
- **"The Type Theory of Lean"** by Mario Carneiro: https://github.com/digama0/lean-type-theory/releases — Thorough formal description of Lean's theory.
- **Nanoda** (Rust reference kernel): https://github.com/ammkrn/nanoda_lib — ~5k lines, complete implementation.
- **Lean Kernel Arena**: https://github.com/leanprover/lean-kernel-arena — Test framework, tutorial tests, checker registration.
- **Arena tutorial source**: https://github.com/leanprover/lean-kernel-arena/blob/master/tutorial/Tutorial.lean — The graduated test sequence.
- **lean4export**: https://github.com/leanprover/lean4export — The exporter that produces NDJSON input.
- **Leo de Moura's blog post**: https://leodemoura.github.io/blog/2026-3-16-who-watches-the-provers/ — Motivation and architecture rationale.

---

## 2. Core data structures

These are the fundamental types the checker must define. All are concrete — no generics required.

### 2.1 Arena-based encoding

Vow does not support recursive enum types (no `Box` or heap-allocated indirection). Instead, we use an **arena-based encoding**: names, levels, and expressions are stored in flat `Vec` arrays, referenced by `u64` index. This is a natural fit because the lean4export NDJSON format already assigns integer IDs to all names, levels, and expressions.

Each arena stores enum variants with `u64` indices pointing to other entries:

```
enum NameData {
    Anonymous,
    Str { parent: u64, field: String },
    Num { parent: u64, field: u64 },
}

enum LevelData {
    Zero,
    Succ { pred: u64 },
    Max { lhs: u64, rhs: u64 },
    IMax { lhs: u64, rhs: u64 },
    Param { name: u64 },
}

enum ExprData {
    BVar { idx: u64 },
    Sort { level: u64 },
    Const { name: u64, levels: Vec<u64> },
    App { fun: u64, arg: u64 },
    Lambda { binder_name: u64, ty: u64, body: u64 },
    Forall { binder_name: u64, ty: u64, body: u64 },
    Let { binder_name: u64, ty: u64, val: u64, body: u64 },
    Lit { val: LitData },
    Proj { struct_name: u64, idx: u64, expr: u64 },
    MData { expr: u64 },
}

enum LitData {
    Nat { val: u64 },
    Str { val: String },
}
```

The arenas themselves:

```
struct NameArena { entries: Vec<NameData> }
struct LevelArena { entries: Vec<LevelData> }
struct ExprArena { entries: Vec<ExprData> }
```

Key operations (substitution, free variable checking, WHNF) allocate new entries in the arena and return new indices. The arena grows monotonically — no deallocation during checking.

### 2.2 Names

Lean names are hierarchical: `Lean.Expr.app` is `Str(Str(Str(Anonymous, "Lean"), "Expr"), "app")`. Also numeric suffixes for internal names.

Key operations: stringification (for HashMap keys and diagnostics), equality comparison.

### 2.3 Universe levels

Universe levels form a small algebra: `Zero`, `Succ(l)`, `Max(l1, l2)`, `IMax(l1, l2)`, `Param(name)`.

Key operations: normalization, comparison (`leq`), substitution of level parameters.

The `imax` function has special semantics: `imax a b = 0` when `b = 0`, otherwise `imax a b = max a b`. This is what makes `Prop` (Sort 0) impredicative.

### 2.4 Expressions

The core term language. ~10 variants (see `ExprData` above).

`MData` (metadata) expressions wrap another expression. The checker should handle these by unwrapping to the inner expression.

Key operations: substitution (instantiate/abstract), free variable checking, weak head normal form (WHNF) reduction.

### 2.5 Declarations

What the checker receives and validates:

```
struct DefinitionDecl {
    name: u64,
    level_params: Vec<u64>,
    ty: u64,
    val: u64,
    hints: DefHint,
    is_unsafe: bool,
}

enum DefHint {
    Opaque,
    Abbrev,
    Regular { height: u64 },
}

struct InductiveDecl {
    name: u64,
    level_params: Vec<u64>,
    ty: u64,
    num_params: u64,
    constructors: Vec<ConstructorDecl>,
    is_recursive: bool,
    is_unsafe: bool,
}

struct ConstructorDecl { name: u64, ty: u64 }

struct RecursorDecl {
    name: u64,
    level_params: Vec<u64>,
    ty: u64,
    num_params: u64,
    num_indices: u64,
    num_motives: u64,
    num_minors: u64,
    rules: Vec<RecursorRule>,
    is_k: bool,
}

struct RecursorRule { ctor_name: u64, num_fields: u64, rhs: u64 }

enum QuotKind { Type, Ctor, Lift, Ind }
struct QuotDecl { name: u64, kind: QuotKind }
```

**Definition hints** control delta reduction: `Opaque` definitions are never unfolded, `Abbrev` definitions are always unfolded, `Regular { height }` definitions are unfolded lazily (lower height = unfold first). This is critical for Phase L4's definitional equality.

### 2.6 Environment

The accumulated state of checked declarations:

```
struct Environment {
    names: NameArena,
    levels: LevelArena,
    exprs: ExprArena,
    decls: HashMap<String, DeclEntry>,
}
```

`DeclEntry` is an enum tagging which kind of declaration was stored, with its data.

---

## 3. Core algorithms

### 3.1 Type inference (`infer`)

Given an expression index and an environment, compute the type (as a new expression index). This is a recursive function over the expression structure:

- `BVar` — look up in local context
- `Sort u` — returns `Sort (u + 1)` (allocates new level and expression in arena)
- `Const` — look up in environment, substitute level parameters
- `App f a` — infer type of `f`, ensure it's a `Forall`, check `a` matches the domain, substitute
- `Lambda` — infer body type under extended context, form `Forall`
- `Forall` — check domain and codomain are sorts, compute resulting sort level
- `Let` — check value has declared type, infer body under extended context
- `Proj` — infer struct type, look up field type
- `Lit` — `Nat` or `String` type
- `MData` — unwrap and infer inner expression

### 3.2 Definitional equality (`is_def_eq`)

The core of the kernel. Two expressions are definitionally equal if they reduce to the same normal form. The algorithm interleaves reduction and structural comparison:

1. Cheap checks first: index equality (same arena node), syntactic equality
2. WHNF reduce both sides
3. Compare heads structurally
4. Handle eta expansion (functions and structures)
5. Handle proof irrelevance (any two proofs of the same `Prop` are equal)
6. Unfold definitions lazily (using `DefHint` heights — unfold the one with lower height first)

### 3.3 WHNF reduction (`whnf`)

Reduce an expression to weak head normal form — reduce only until the outermost constructor is visible. Reduction rules:

- **Beta:** `(fun x => b) a` → `b[x := a]`
- **Delta:** unfold definitions (constants → their values), respecting hints
- **Zeta:** reduce let-bindings
- **Iota:** recursor applied to a constructor → reduce according to computation rule
- **Nat literal reduction:** `Nat.succ (Nat.succ Nat.zero)` ↔ `2`
- **Projection reduction:** `(Prod.mk a b).1` → `a`
- **Quot reduction:** quotient lift/ind applied to `Quot.mk`
- **Rule K:** `Eq.rec` reduces when major premise type matches constructor

### 3.4 Inductive type validation

When an inductive declaration arrives, check:

- The type is a sort (after reduction)
- No duplicate level parameters
- Constructor types are well-formed
- No negative recursive occurrences (critical for soundness)
- Universe constraints are satisfied
- Generate/validate the recursor type

### 3.5 Level arithmetic

- `level_leq(l1, l2)`: is `l1 ≤ l2` for all possible assignments of level parameters?
- `level_normalize(l)`: simplify level expressions
- `level_subst(l, params, args)`: substitute level parameters with arguments

---

## 4. Implementation phases

Each phase corresponds to a subset of the arena tutorial tests. The test numbers reference the tutorial test cases at https://arena.lean-lang.org/. A phase is complete when all listed tests pass (accept the good ones, reject the bad ones).

### Phase L0: Project scaffolding

**Goal:** Set up the project structure, build system, JSON parser, and string utilities. Get a binary that reads input and exits cleanly.

**Delivers:**
- Module structure with `main.vow` entry point
- JSON parser (hand-written, character-by-character using `byte_at`, `substring`, `parse_u64`)
- String utilities for parsing (skip whitespace, parse quoted string, match keyword)
- Exit code logic (0/1/2 based on result)
- Test runner script to download and run arena tutorial tests locally

**Input method:** `stdin_read()` for arena compatibility (`./checker < $IN`), with `args()` + `fs_read()` fallback for local development.

**Arena tests:** None. Validate by parsing a sample NDJSON file without crashing.

**Estimated scope:** ~400 lines

---

### Phase L1: NDJSON parser and expression AST

**Goal:** Parse the lean4export NDJSON format into the arena-based data structures.

**Delivers:**
- Arena types: `NameArena`, `LevelArena`, `ExprArena`
- `NameData`, `LevelData`, `ExprData`, `LitData` enums
- NDJSON line-by-line parser populating arenas from `in`/`il`/`ie` entries
- Declaration parsing (`def`, `ax`, `thm`, `opaque`, `ind`, `ctor`, `rec`, `quot`)
- `MData` expression handling (store and unwrap)
- `QuotDecl` parsing (quotient declaration kind: type/ctor/lift/ind)
- Expression pretty-printer (for diagnostics)

**Vow contracts:**
- Parser produces well-formed AST (all index references point to valid arena entries)

**Arena tests:** None yet (no type checking). Validate by parsing tutorial test files without crashing.

**Estimated scope:** ~500 lines

---

### Phase L2: Basic type inference and checking

**Goal:** Type-check simple definitions. Implement `infer` for BVar, Sort, Const, App, Lambda, Forall. Implement beta reduction and basic WHNF. Implement the environment (HashMap of declarations).

**Delivers:**
- `infer(env, ctx, expr_id) -> Result<u64, TypeError>` (returns expression index)
- `is_def_eq(env, e1, e2) -> bool` (structural + beta reduction only)
- `whnf(env, expr_id) -> u64` (beta + delta + zeta)
- `check_declaration(env, decl) -> Result<(), TypeError>` for definitions/axioms/theorems
- Expression substitution: `instantiate(env, body, arg) -> u64` (replaces BVar 0 with arg)

**Vow contracts:**
- `infer` returns a type that is itself a Sort (after WHNF)
- `is_def_eq` is symmetric and reflexive
- WHNF is idempotent: `whnf(whnf(e)) == whnf(e)`

**Arena tests:**
- `001_basicDef` — accept basic `Type := Prop`
- `002_badDef` — reject mismatched types
- `003_arrowType` — accept `Type := Prop → Prop`
- `004_dependentType` — accept `Prop := ∀ (p: Prop), p`
- `005_constType` — accept lambda expression
- `006_betaReduction` — accept expression requiring beta reduction for equality
- `007_betaReduction2` — beta reduction under binder
- `008_forallSortWhnf` — reduce binding domain before checking it's a sort
- `009_forallSortBad` — reject: binding domain is not a sort
- `010_nonTypeType` — reject: declaration type is not a type
- `011_nonPropThm` — reject: theorem type is not a Prop

**Estimated scope:** ~800 lines

---

### Phase L3: Universe levels

**Goal:** Implement universe level algebra: normalization, comparison, substitution. Handle level parameters on constants.

**Delivers:**
- `level_leq(l1, l2) -> bool`
- `level_normalize(l) -> u64` (returns new level index)
- `level_subst(l, params, args) -> u64`
- Sort inference for `Forall` using `imax`

**Vow contracts:**
- `level_leq` is reflexive and transitive
- `level_normalize` is idempotent
- `imax a Zero == Zero` for all `a`
- `imax Zero b == b` for all `b`

**Arena tests:**
- `012_levelComp1` through `018_levelComp5` — level arithmetic
- `015_levelParams` — level parameters on functions
- `016_tut06_bad01` — reject duplicate universe parameters
- `019_imax1`, `020_imax2` — imax behavior for Prop/Type
- `021_inferVar` — type inference for local variables

**Estimated scope:** ~400 lines

---

### Phase L4: Definitional equality and reduction

**Goal:** Full definitional equality algorithm with delta unfolding, let reduction, and the Peano arithmetic stress tests.

**Delivers:**
- Complete `is_def_eq` with lazy unfolding
- Let-binding reduction (zeta)
- Delta reduction with **definition hints** (`DefHint`): `Opaque` = never unfold, `Abbrev` = always unfold, `Regular { height }` = unfold lower height first

**Vow contracts:**
- Peano `1 + 1 = 2` (tests that the reducer actually computes)
- `is_def_eq` agrees with `whnf` comparison: `is_def_eq(a, b)` iff `whnf(a)` and `whnf(b)` have same head and def-eq subterms

**Arena tests:**
- `022_defEqLambda` — def eq between lambdas
- `023_peano1` — `2 = 2` (trivial)
- `024_peano2` — `1 + 1 = 2` (requires reduction through Church encoding)
- `025_peano3` — `2 * 2 = 4` (deep reduction)
- `026_letType` through `028_letRed` — let-binding type checking and reduction

**Estimated scope:** ~600 lines

---

### Phase L5: Inductive types — well-formedness

**Goal:** Validate inductive type declarations: check the type is a sort, constructors are well-formed, no negative occurrences, universe constraints.

**Delivers:**
- `check_inductive(env, ind_decl) -> Result<(), TypeError>`
- Strict positivity checker (no negative recursive occurrences)
- Universe constraint checking for constructor fields

**Vow contracts:**
- Strict positivity: if constructor has argument `(T → T) → T`, reject
- Universe constraint: constructor field level ≤ inductive type level (for types; no constraint for Prop)

**Arena tests:**
- `029_empty` — Empty type
- `030_boolType` — Bool (two nullary constructors)
- `031_twoBool` — product type (struct)
- `032_andType` through `036_eqType` — parameterized types, Eq
- `037_natDef` — recursive inductive (N)
- `038_rbTreeDef` — indexed recursive type (RBTree)
- `039_inductBadNonSort` through `050_indNegReducible` — all the rejection tests: non-sort types, duplicate level params, wrong constructor params, negative occurrences, universe violations

**Estimated scope:** ~800 lines

---

### Phase L6: Recursors — type checking and reduction

**Goal:** Validate recursor declarations and implement iota reduction (recursor computation rules).

**Delivers:**
- Recursor type validation
- Iota reduction: `Nat.rec base step (Nat.succ n)` → `step n (Nat.rec base step n)`
- Large vs small elimination distinction

**Vow contracts:**
- Recursor applied to constructor produces correct computation
- Small elimination: Props with multiple constructors eliminate only into Prop

**Arena tests:**
- `055_emptyRec` through `068_sortElimProp2Rec` — recursor type assertions
- `069_boolRecEqns` through `073_RBTree.id_spec` — recursor reduction behavior
- `065_boolPropRec`, `066_existsRec`, `067_sortElimPropRec` — elimination restrictions

**Estimated scope:** ~700 lines

---

### Phase L7: Projections

**Goal:** Implement structure projections and their reduction, including the subtle rules for projecting out of propositions.

**Delivers:**
- Projection type checking
- Projection reduction: `(Prod.mk a b).1` → `a`
- Prop-projection restrictions

**Vow contracts:**
- Out-of-range projection → reject
- Projection on non-structure → reject
- Data projection out of Prop after dependent data field → reject

**Arena tests:**
- `074_And.right` through `077_PSigma.snd` — valid projections
- `078_projOutOfRange` — reject out-of-range
- `079_projNotStruct` — reject non-structure projection
- `080_projProp1` through `088_projIndexData2` — Prop projection edge cases
- `089_projRed` — projection reduction

**Estimated scope:** ~400 lines

---

### Phase L8: Eta, Rule K, proof irrelevance

**Goal:** Implement function eta, structure eta, proof irrelevance, Eq.rec Rule K, nat literals, and quotient types.

**Delivers:**
- Function eta: `fun x => f x` ≡ `f`
- Structure eta: `⟨x.1, x.2⟩` ≡ `x`
- Proof irrelevance: any two proofs of the same Prop are def-eq
- Rule K for `Eq.rec`: reduces when major premise type matches constructor
- Nat literal ↔ `Nat.succ`/`Nat.zero` interconversion
- Quotient type checking and reduction (`Quot.mk`, `Quot.lift`, `Quot.ind`)
- Duplicate declaration rejection

**Vow contracts:**
- Eta is sound: only fires when types match
- Rule K does NOT fire for `Acc` (non-K-like inductives)
- Proof irrelevance only for Prop-valued types

**Arena tests:**
- `090_ruleK` — Rule K fires for Eq
- `091_ruleKbad` — Rule K must NOT fire for `true = false`
- `092_ruleKAcc` — Rule K must NOT fire for Acc
- `093_aNatLit`, `094_natLitEq` — nat literal handling
- `095_proofIrrelevance` — proof irrelevance
- `096_unitEta1` through `099_structEta` — eta rules
- `100_funEta` through `104_etaCtor` — function eta and edge cases
- `105_reflOccLeft` through `108_reduceCtorParamRefl2` — subtle reduction cases
- `109_rTreeRec` through `113_accRecNoEta` — recursive type recursor edge cases
- `114_quotMkType` through `119_quotIndReduction` — quotient types
- `120_dup_defs` through `126_DupConCon` — duplicate declaration rejection

**Estimated scope:** ~600 lines

---

### Phase L9: Large-scale validation

**Goal:** Pass the arena's real-world test suites beyond the tutorial.

**Arena tests:**
- `init-prelude` (3.5 MB) — Lean's prelude
- `init` (307 MB) — full Init library
- `std` (523 MB) — standard library
- `mathlib` (4.9 GB) — the ultimate stress test
- `cedar`, `cslib`, `mlir` — other real-world projects
- `bogus1`, `constlevels`, `nat-rec-rules`, `level-imax-leq`, `level-imax-normalization` — edge case tests

**Focus:** Performance (arena benchmarks time and memory), correctness on adversarial edge cases.

**Performance work:**
- Hash consing for expressions (detect structurally identical arena entries)
- WHNF result caching
- Nat literal big-integer support (Mathlib uses nat literals exceeding i64 range — store as strings with string-based arithmetic)

**Estimated scope:** ~500 lines of optimization code.

---

## 5. Total estimated scope

| Phase | Lines (est.) | Cumulative |
|-------|-------------|-----------|
| L0: Scaffolding + JSON parser | 400 | 400 |
| L1: Parser + AST | 500 | 900 |
| L2: Basic type inference | 800 | 1,700 |
| L3: Universe levels | 400 | 2,100 |
| L4: Def eq + reduction | 600 | 2,700 |
| L5: Inductive validation | 800 | 3,500 |
| L6: Recursors | 700 | 4,200 |
| L7: Projections | 400 | 4,600 |
| L8: Eta, Rule K, etc. | 600 | 5,200 |
| L9: Large-scale validation | 500 | 5,700 |

This aligns with Nanoda's ~5k lines in Rust (the extra ~700 lines account for the hand-written JSON parser and string utilities that Rust gets from serde).

---

## 6. Module structure (suggested)

```
main.vow                 // CLI entry point: read stdin, parse, check, exit code
parse/
├── json.vow             // Minimal JSON parser (character-by-character)
├── strutil.vow          // String parsing utilities (skip_ws, parse_int, parse_quoted)
└── export.vow           // lean4export NDJSON → arena population + declarations
kernel/
├── name.vow             // NameData enum, NameArena, stringification
├── level.vow            // LevelData enum, LevelArena, normalization, leq, subst
├── expr.vow             // ExprData enum, ExprArena, substitution, free vars
├── env.vow              // Environment struct, declaration storage, lookup
├── infer.vow            // Type inference
├── def_eq.vow           // Definitional equality
├── whnf.vow             // Weak head normal form reduction
├── inductive.vow        // Inductive type validation
├── recursor.vow         // Recursor validation + iota reduction
├── projection.vow       // Projection checking + reduction
└── quot.vow             // Quotient types
diag/
└── error.vow            // TypeError enum + structured diagnostics
```

---

## 7. Vow-specific design notes

### Arena-based data structures

Since Vow does not support recursive enum types, all recursive data (names, levels, expressions) use an arena encoding: flat `Vec` storage indexed by `u64`. This is idiomatic for Vow and matches how the Vow compiler itself represents its AST. It also naturally aligns with lean4export's index-based format.

Arena operations that construct new expressions (e.g., substitution, WHNF) allocate new entries and return new indices. The arena grows monotonically — no deallocation needed during checking.

### Vow blocks on kernel functions

The kernel functions are ideal vow block targets:

```
fn infer(env: Environment, ctx: Vec<u64>, expr: u64) -> Result<u64, TypeError> vow {
    requires: expr < env.exprs.entries.len()
    ensures:  result == Result::Err(_) || result.unwrap() < env.exprs.entries.len()
} {
    ...
}

fn is_def_eq(env: Environment, e1: u64, e2: u64) -> bool vow {
    ensures: result == is_def_eq(env, e2, e1)
} {
    ...
}
```

### No traits needed

Where Nanoda uses Rust traits (e.g., for expression visitors), Vow uses concrete functions with pattern matching on enum variants:

```
fn expr_has_free_var(env: Environment, expr_id: u64, var_idx: u64) -> bool {
    match env.exprs.entries[expr_id] {
        ExprData::BVar { idx } => idx == var_idx,
        ExprData::App { fun, arg } => {
            expr_has_free_var(env, fun, var_idx) || expr_has_free_var(env, arg, var_idx)
        },
        ...
    }
}
```

### HashMap usage

The environment uses `HashMap<String, DeclEntry>` with stringified names as keys (Vow's HashMap supports String keys natively). Local contexts are `Vec<u64>` of expression indices, indexed by de Bruijn level.

### Effect annotations

- Parser functions: `[read]` (reading stdin/files)
- Kernel functions: pure (no effects) — this is a critical property; type checking must be deterministic
- Main: `[io]`

---

## 8. Success criteria

1. **Tutorial complete:** All 126 tutorial tests pass (accept good, reject bad).
2. **Arena registration:** Checker registered in the Lean Kernel Arena with a `checkers/*.yaml` entry.
3. **Init-prelude passes:** The 3.5 MB prelude test validates successfully.
4. **Agent-written:** The implementation is produced by AI agents using the Vow toolchain, guided by vow blocks and the skill document.
5. **Vow-verified:** Key kernel functions have vow blocks that are checked by ESBMC.
