# Nested recursor structure eta (#72)

`tests/good/symbolic-sizeof.ndjson` is the dependency-only export of the actual
`Cedar.Spec.Value._sizeOf_5_eq` from Cedar commit
`f36af0f9fc038b9e6a340960fc24f3b610a84aee`, using Lean 4.29.1. It contains
449 declarations. The baseline declines the final theorem at kernel fuel 781;
the fixed checker accepts it. `Value.rec_5` eliminates `Prod String Value`,
whose constructor parameters/universes differ from those of `Value.rec_5`.

To regenerate, check out that Cedar commit, enter `cedar-lean`, and run:

```sh
lake build Cedar.Spec.Value:olean
lake env /path/to/lean4export Cedar.Spec.Value -- Cedar.Spec.Value._sizeOf_5_eq > symbolic-sizeof.ndjson
```

`tests/bad/symbolic-sizeof-wrong.ndjson` preserves every dependency and the
original proof. Only the final theorem's declared conclusion is changed from
`_sizeOf_5 x = sizeOf x` to `_sizeOf_5 x = Nat.succ (sizeOf x)`, by copying its
forall/application nodes to new expression IDs. It must reject, exit 1.

`tests/bad/nested-list-eta.ndjson` comes from `Single.lean`, also Lean 4.29.1.
Export `Single -- tagRefl`, then replace the right side of the final theorem's
equality with a new `natVal: "0"` node, retaining its original reflexivity proof.
This claims `∀ xs, nestedTag xs = 0`. The `tagNotAlwaysZero` theorem in the
source exhibits a counterexample. The baseline incorrectly accepts the mutated
export because it eta-expands the symbolic list using `Tree`'s structure shape
and `List.nil`'s rule. The fixed checker must reject, exit 1.

CI checks both file and stdin paths and exact verdicts, because the general
fixture runner treats declines as skips.

`tests/bad/recursive-structure-eta.ndjson` comes from `Recursive.lean`.
Export `Recursive -- rootRefl`, then replace the right side of the final
equality with a fresh `natVal: "0"` node while retaining the reflexivity proof.
The ordinary recursor eliminates the recursive `Tree` itself. Lean rejects
that reflexivity proof because reduction must remain stuck on the symbolic
major. Before the review fix, the ordinary fallback manufactured a constructor
and incorrectly accepted it. Both ordinary and nested eta now exclude recursive
constructor fields, including references to other types in a mutual block.

The conclusion `rootTag t = 0` does have a valid proof by eliminating `t`.
`tests/good/recursive-structure-eta.ndjson` exports `Recursive -- rootByCases`
and must accept, preserving support for that valid recursive proof.
