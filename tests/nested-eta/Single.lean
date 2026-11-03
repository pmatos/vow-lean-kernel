import Init
inductive Tree where
  | node : List Tree → Tree
noncomputable def nestedTag (xs : List Tree) : Nat :=
  @Tree.rec_1 (fun _ => Nat) (fun _ => Nat) (fun _ _ => 0) 0 (fun _ _ _ _ => 1) xs
theorem tagRefl (xs : List Tree) : nestedTag xs = nestedTag xs := rfl

-- This counterexample confirms why replacing tagRefl's right side with 0 is invalid.
theorem tagNotAlwaysZero : ¬ (∀ xs, nestedTag xs = 0) :=
  fun h => Nat.noConfusion (h [.node []])
