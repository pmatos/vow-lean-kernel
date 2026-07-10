# DAG-aware self-reference scan

**Issue:** #58  
**Status:** Approved for implementation  
**Date:** 2026-07-10

## Problem

`check_def` rejects self-referential definitions by calling
`expr_contains_const` before type inference. The current recursive scan treats
the expression arena as a tree. When two fields point to the same expression
node, it traverses that shared subgraph once per incoming path.

The Lean Kernel Arena `perf/app-lam` test repeats the same lambda in both
arguments at every nesting level. On the unmodified checker, the exact
depth-4,000 input times out after 30.00 seconds at 99% CPU while using only
18,840 KiB max RSS. This confirms a compute-complexity problem rather than an
out-of-memory failure.

## Requirements

- Scan time must be proportional to reachable expression nodes and edges, not
  to the number of expanded tree paths.
- A negative scan over a DAG with shared children must complete quickly and the
  containing definition must be accepted.
- A definition that actually contains its own constant must still be rejected.
- The arena's depth-4,000 `perf/app-lam` test must complete within its 30-second
  containment timeout under the 12 GiB memory cap.
- The change must not add arena-sized persistent storage or per-scan allocation
  churn that could regress large `Init` runs.

## Design

Replace the recursive implementation of `expr_contains_const` with an
iterative graph traversal:

1. Record the current length of `ExprArena.scratch_args` and append the root
   expression index. Existing entries belong to callers and remain untouched.
2. Walk the appended slice with a cursor, so the slice is both the pending
   worklist and the record of nodes encountered during this scan.
3. Normal expression tags occupy values 0 through 10. Add 16 to a node's tag
   when it is first visited; a tag of 16 or greater means that node has already
   been visited by this scan.
4. For each newly visited node, test constants and append the node's expression
   children according to its original tag. Duplicate edges may append duplicate
   indices, but the visit marker prevents re-expanding their children.
5. On both success and failure, walk the scratch slice, subtract 16 from every
   marked tag, and truncate `scratch_args` back to its recorded base.

The checker is single-threaded and the traversal calls no other arena
algorithms while tags are marked. Restoring every marked tag before returning
keeps the temporary marker invisible to callers. Runtime is `O(V + E)` over the
reachable expression DAG, and retained scratch capacity is reused by later
calls.

## Test-driven implementation

The agreed seam is the public checker process: an NDJSON input is observed
through its exit status and bounded runtime.

1. Generate a reduced depth-25 version of the arena `perf/app-lam` input and
   add it as `tests/good/perf-app-lam-dag.ndjson`.
2. Red: show the unmodified checker fails to finish that fixture within a
   10-second timeout.
3. Green: implement only the iterative DAG-aware scan and show the fixture is
   accepted within the same bound.
4. Run `tests/bad/self-referential-def.ndjson` to prove positive detection still
   rejects, then run the complete committed checker suite.
5. Re-run the exact depth-4,000 arena test under the 12 GiB cap and record its
   verdict, wall time, CPU utilization, and max RSS. If another bottleneck still
   causes a timeout, continue profiling and implementation until the arena test
   completes; do not publish a partial fix.

## Scope

The implementation changes `kernel/expr.vow` and adds the generated regression
fixture. It does not change checker exit-code handling, arena timeouts, or the
separate `Init` definitional-equality memory work.
