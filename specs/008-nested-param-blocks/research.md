# Phase 0 Research: Nested Parameter Blocks

The spec carried no `[NEEDS CLARIFICATION]` markers. Decisions
below were resolved against the existing codebase (now at v0.12.0,
post-feature-013), the Constitution, and `rails_param`'s public
API before writing the spec.

## R1. AST shapes to detect

**Decision**: Three node patterns:

| Source form | Outer AST | Inner call AST |
|-------------|-----------|----------------|
| `param! :q, Hash do |q| ... end` | `:method_add_block` wrapping `[:command, [:@ident, "param!", ...], args]` | n/a (the outer is the param! call) |
| `q.param! :keyword, String` | n/a (inside the block body) | `[:command_call, [:var_ref, [:@ident, "q", ...]], [:@period, ...], [:@ident, "param!", ...], args]` |
| `array.param! index, String` | n/a (inside the block body) | `:command_call` with the same shape; the first positional argument is an `:@ident` (the array-index block parameter) rather than a symbol literal |

The outer block is `:do_block` (or `:brace_block` for `{ |q| ... }`).
The block parameter list is `[:block_var, [:params, [[:@ident, NAME, ...]], ...], false]`. For an Array block with two block params (`do |p, i|`), the first ident is the param-context block var (`p`) and the second is the array-index (`i`).

**Rationale**: Verified against `Ripper.sexp` for each form. These
three exhaust the nested-`param!` syntactic surface — `Hash` blocks
use a single block parameter, `Array` blocks use two (context + index).

**Alternatives considered**:
- *Match calls inside the block on ANY receiver*: too permissive — a
  `params.param!` inside the block would be mis-detected (FR-006
  rejects this). The receiver MUST match the captured block-var name.

## R2. Outer detection — adding a `:method_add_block` arm

**Decision**: Extend `ParamExtractor#param_bang_args` with a third
case: `:method_add_block`. When the inner call is the `:command`
form of `param!`, return both the args AND the block AST node so
the caller can decide whether to descend.

The today's call sites that don't care about the block (most of
them) continue to work — they look at the args array, ignore the
block. Only `find_param_calls` will descend.

**Rationale**: Minimal touch to the existing detection path. The
`:method_add_block` shape was overlooked when feature 001 was
written because no nested-block use was in scope at that time.

**Alternatives considered**:
- *A separate `find_block_param_calls` walker*: doubles the AST
  traversal for what amounts to the same matching logic. Rejected.

## R3. Inner detection — matching `<blockvar>.param!`

**Decision**: A separate small walker, `extract_nested_calls`,
that takes a body AST plus a Set of block-var names and visits the
AST collecting `:command_call` nodes whose receiver is a `:var_ref`
matching one of the names. Returns the arg-array for each match.

The walker skips `:def` / `:defs` subtrees (a nested method
definition inside the block — exceedingly rare, but safe to guard).
It also skips inner `:method_add_block` whose call is `param!` on
the same var (those are nested-nested declarations, handled by the
outer recursion when that node's ParamCall is being built).

**Rationale**: Mirrors feature 012's `respond_to_block` detection
pattern — known-good. Reusing the same recursion shape keeps the
code consistent.

**Alternatives considered**:
- *Walk the body with the existing `find_param_calls` recursion*:
  the existing recursion would re-detect the OUTER param! call
  inside the nested context (since outer's AST is still in the
  body's parent context). Cleaner to have a dedicated nested-walker.

## R4. Recursion structure

**Decision**: `ParamExtractor.build_call` becomes aware of an
optional `block_node` and a `depth` argument. When the type is
`Hash` or `Array` and a block is present and `depth <
method_resolution_depth`, the builder:

1. Captures the block's parameter names (one for Hash, two for
   Array — but for Array we treat only the first as the "param
   var" receiver; the second is the index ident used in nested
   call's first positional).
2. Invokes `extract_nested_calls(body, block_var_names)`.
3. For each match, recursively calls `build_call(args, block_node:
   inner_block, depth: depth + 1)`.
4. Stores the resulting list (Hash) or single ParamCall (Array)
   in `nested:` on the parent.

When `depth >= method_resolution_depth`, the descent stops at
that level; the parent emits a bare `object` / `array` schema for
the over-depth subtree (FR-005, SC-004).

**Rationale**: Recursion via the existing builder keeps the
constraint-mapping rules consistent at every level. The depth
bound reuses the existing `Configuration#method_resolution_depth`
setting (the spec's Assumptions section calls this out
explicitly).

**Alternatives considered**:
- *A separate `NestedParamBuilder` class*: same logic, more
  boilerplate. The recursion is one method.

## R5. Array `items` schema — single vs. list

**Decision**: For an Array `param!` with a block, the spec lets the
author declare at most one item-shape (`array.param! index, Type`).
If multiple item declarations appear (rare/mistake), take the LAST
in source order — consistent with the rest of the gem's
"last-wins for ambiguous cases" rule.

The first positional argument of the nested `param!` call inside an
Array block is the array-index block parameter name (an `:@ident`,
not a symbol literal). The nested ParamCall's `name` field is set
to `nil` in this case (the item has no name — only a shape).

**Rationale**: OpenAPI 3.1's `items:` is a single schema; an array
can't have heterogeneous items modeled simply. A future feature
could emit `items: { oneOf: [...] }` if needed; YAGNI for v1.

**Alternatives considered**:
- *Reject the array block when nothing declares an item*: harms
  backward compat — a `param! :things, Array do |a, i| end` is
  documented today as `type: array` with no items, and SC-005
  requires byte-identity for such cases. We keep that.

## R6. Hash `required` array — out of scope

**Decision**: Per the spec's Assumptions ("an OpenAPI object-level
`required` array is out of scope for this feature"), we do NOT
build a `required:` list on the parent object schema based on
nested `required: true` constraints. Each nested property's
`required` is treated like a flat `param!`'s — it can be
documented in the property's own schema where applicable, but the
parent object does not get a `required:` array.

**Rationale**: The current ParamCall doesn't carry an explicit
"this is required at the object level" semantic; the existing
`required: true` flag is per-parameter. Lifting it to a
parent-object `required:` array is a separate enhancement.

**Alternatives considered**:
- *Compute the `required:` array from nested `required: true`
  fields*: the spec explicitly defers this. A future feature can
  lift the assumption.

## R7. Constant resolution inside nested blocks

**Decision**: A nested `param! :name, Type, in: Module::CONSTANT`
goes through the same `LiteralEvaluator.evaluate` path as a flat
`param!`. Feature 013's `ConstantResolver` is set on
`LiteralEvaluator` at the start of every generator run, so the
nested constraint resolves the constant automatically. No extra
wiring in this feature.

**Rationale**: This is the architectural payoff for feature 013's
module-level resolver design (research R7 of feature 013) —
nested-block evaluation reuses the same evaluator instance and
inherits the resolver for free.

## R8. Backward compatibility — no-block `param!` calls

**Decision**: A `param!` of type `Hash` / `Array` with NO block,
or a `param!` whose block is on a non-Hash-Array type (e.g.
`String do ... end` — degenerate, but possible), emits today's
output unchanged. The new detection arm sees the block but
`build_call` produces `nested: nil` because the type doesn't
admit nesting.

**Rationale**: SC-005 is a hard guarantee. The new field on
`ParamCall` defaults to `nil`; `OperationBuilder`'s emission
branch only fires when `nested:` is non-nil. By construction,
flat `param!` calls (today's overwhelming majority) emit
byte-identical schemas.

**Alternatives considered**: none — backward-compat is non-negotiable.

## R9. Where the tree is emitted into the OpenAPI document

**Decision**: `OperationBuilder` is the right place. It already
maps each `ParamCall` to a `Parameter` (for query) or to an entry
in the request body's `properties:`. The new logic:

- For a query parameter (non-body method): if the parameter's
  `ParamCall.nested` is set, build the parameter's `schema:` as
  an object/array with the nested tree. (Rare — most query
  parameters aren't structured.)
- For a request body parameter: each `ParamCall`'s flat schema
  becomes a property; if `nested:` is set on a property's call,
  that property's schema is `{type: object, properties: {...}}`
  or `{type: array, items: {...}}`.

The recursion is shallow because the tree depth is bounded.

**Rationale**: OperationBuilder is already the schema-tree
builder. Pushing the recursion there keeps `ParamExtractor` a
flat collector and `SchemaMapper` a flat single-call mapper —
both unchanged in shape, just enriched at the assembly layer.

**Alternatives considered**:
- *Have `SchemaMapper` build nested schemas directly*: would
  require threading the nested tree through SchemaMapper's
  interface. Less clean than building at the OperationBuilder
  layer where the route + parameter context already lives.

## R10. Determinism

**Decision**: Nested params are collected in source order; the
output preserves that order for `properties:`. (OpenAPI consumers
do not rely on property order; this is purely for byte-stable
output.) The descent itself is deterministic given unchanged
host code.

**Rationale**: Constitution-level requirement. Source-order
preservation matches the existing `OperationBuilder` behavior for
flat `param!` calls (they are sorted alphabetically before
emission — see `OperationBuilder#sort_properties`). Nested
properties will also be alphabetically sorted by the same helper
to match the parent emission.

**Alternatives considered**:
- *Insertion order*: would diverge from the flat case. Rejected.
