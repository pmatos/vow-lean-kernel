import Init
inductive Tree where
  | node : List Tree → Tree
noncomputable def rootTag (t : Tree) : Nat :=
  @Tree.rec (fun _ => Nat) (fun _ => Nat) (fun _ _ => 0) 0 (fun _ _ _ _ => 1) t
theorem rootRefl (t : Tree) : rootTag t = rootTag t := rfl

-- Eliminating the recursive major is required; reflexivity alone is not a proof.
theorem rootByCases (t : Tree) : rootTag t = 0 := by
  cases t
  rfl
