# Phase 0 Research: Implicit Params Detection

## R1. Detecting `params[:key]` index access

**Decision**: In a method body's Ripper AST, an index access is an `:aref`
node — `[:aref, receiver, args]`. When the receiver is the `params` object
(a receiverless `params` reference — `:vcall`/`:var_ref` of `[:@ident,
"params"]`), the literal symbol/string keys in `args` are parameter names.

**Rationale**: `params[:key]` is the dominant input pattern (~1,800 uses in the
reference app). `:aref` is the single, unambiguous node for `[]` access.

## R2. Detecting strong-params calls

**Decision**: Detect calls named `require`, `permit`, `fetch`, or `dig` whose
receiver is the `params` object — or whose receiver is itself a `params`
strong-params call (to catch chains like `params.require(:user).permit(:name)`).
The literal symbol/string arguments of those calls are parameter names.

**Rationale**: Covers the four strong-params methods named in the spec. Handling
a receiver that is itself a `params` chain catches the common
`require(...).permit(...)` form. Per the spec's flattening assumption, every
literal key in the chain is collected as a separate parameter.

## R3. Recursive scanning — the shared `ControllerMethodWalker`

**Decision**: Extract the "walk an action body and the receiverless helper
methods it calls, recursively, depth-bounded and cycle-guarded" traversal from
`WrapperDownloadResolver` into a shared `ControllerMethodWalker`. It returns the
set of reachable method body nodes (the action plus every resolved helper).
`WrapperDownloadResolver` and `ImplicitParamScanner` both consume it.

**Rationale**: This traversal is the common substance of feature 004 and this
feature. One class owns `MethodResolver` use, the depth cap, and the visited-set
cycle guard — removing duplication (Constitution I). The reachable graph is tiny
(depth ≤ the configured cap), so collecting all bodies eagerly is fine; the
`any?` short-circuit `WrapperDownloadResolver` previously had is not needed.

**Alternatives considered**:
- *Duplicating the recursion in `ImplicitParamScanner`*: rejected — ~20 lines
  of duplicated traversal, depth, and cycle-guard logic.

## R4. Configuration rename

**Decision**: Rename `Configuration#download_resolution_depth` to
`method_resolution_depth`. It now bounds two recursive scans (downloads and
params), so the download-specific name is inaccurate.

**Rationale**: One accurately named setting for the shared traversal. The key
was introduced in 0.4.0 and is not widely deployed; the rename is noted in the
CHANGELOG with the 0.6.0 release.

## R5. Deduplication and exclusions

**Decision**: A discovered key is **not** added as an implicit parameter when:

- it matches a path-segment parameter of the route;
- it matches a `param!`-declared parameter (the `param!` definition, with its
  type and constraints, is authoritative);
- it is a Rails-internal key — `controller`, `action`, or `format`.

Each remaining key is added once, even if accessed many times or in several
helpers.

**Rationale**: Satisfies FR-006/FR-007/FR-008 and SC-004. Path and `param!`
parameters carry richer information; the implicit ("any") parameter would only
degrade them.

## R6. Parameter placement and schema

**Decision**: An implicit parameter is placed the same way a `rails_param`
parameter is — a query parameter for `GET`/`DELETE` operations, a request-body
property for `POST`/`PUT`/`PATCH` — and is emitted as optional with a permissive
(`{}`, "any") schema.

**Rationale**: Static `params` access reveals neither query-vs-body nor a type;
mirroring the existing `param!` placement keeps one consistent rule. Recorded as
an assumption open to `/speckit-clarify`.

## R7. Literal keys only

**Decision**: Only literal symbol/string keys are collected. `params[variable]`,
`params[some_expr]`, and computed `permit` arguments are skipped.

**Rationale**: A non-literal key cannot be named statically (FR-003); naming a
guessed key would be worse than omitting it.

## R8. Where scanning plugs into the pipeline

**Decision**: `Generator` runs `ImplicitParamScanner` per resolvable route
(controller class + action node) and passes the discovered key list to
`OperationBuilder#build`, which merges them into the operation's parameters
after path and `param!` parameters are built.

**Rationale**: `OperationBuilder` already assembles parameters and knows the
path and `param!` names, so it is the natural place to merge-and-dedup.

## Resolved unknowns

All Technical Context items are resolved. No new dependency. No
`NEEDS CLARIFICATION` markers — the feature description and the recorded
assumptions (placement, flattening) fully specify the behavior.
