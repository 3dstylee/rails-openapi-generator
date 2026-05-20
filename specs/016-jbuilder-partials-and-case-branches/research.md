# Phase 0 Research: jbuilder Partials & case/when Branches

The spec carried no `[NEEDS CLARIFICATION]` markers. Three small
decisions are documented below; no `data-model.md` / `contracts/`
/ `quickstart.md` artifacts are produced (this is a one-file
change).

## R1. Detecting `partial:` in a `json.<key>` call's argument hash

**Decision**: In `add_property(properties, call, seen)`, before
the existing block/value-schema branch, check whether
`call[:args]` contains a `:bare_assoc_hash` AST node whose
evaluated value has a literal `:partial` key. If so, delegate to
the existing `partial_schema(call, seen)` helper and emit:

- `{type: array, items: <partial schema>}` when the call has a
  positional (non-hash) argument BEFORE the hash — the typical
  collection form.
- `<partial schema>` directly when the call has no positional
  argument before the hash — the single-object form (rarer in
  jbuilder but valid: `json.user partial: "user"`).

The existing `partial_name` helper already handles both forms:
it iterates the args and picks the first `:partial` value from a
hash. We reuse it as-is.

The block-precedence rule (FR-004) is naturally preserved
because `add_property` already checks `call[:block]` first; the
new branch only runs when no block is present.

**Rationale**: Symmetrical with the existing `array!` /
`partial!` paths, which already use `partial_schema`. The same
`schema_for_file`'s `seen` list prevents cycles, so recursive
partials inside the partial work transparently.

**Alternatives considered**:
- *Add a new top-level handler in `build_schema`*: would
  duplicate the existing dispatch. Rejected — `add_property` is
  the right home.
- *Resolve the partial eagerly at file-load time*: the existing
  cache already memoizes per-file schemas; eager resolution adds
  no benefit and risks loading partials that aren't actually
  referenced.

## R2. `:case` AST shape and walking

**Decision**: Verified the AST shape via Ripper:

```text
case x
when 1
  json.a 1
when 2
  json.b 2
else
  json.c 3
end
```

parses as:

```text
[:case, <expr>,
  [:when, [conditions], [body_stmts],
    [:when, [conditions], [body_stmts],
      [:else, [else_body_stmts]]]]]
```

i.e. `:case` has `node[2]` as the first `:when` chain head;
each `:when` has its body at `node[2]` and its tail (next
`:when`, `:else`, or `nil`) at `node[3]`.

Implementation:

1. `visit_statement` adds `:case` to the conditional-shape list.
2. A new `case_branch_bodies(node)` helper walks the chain:
   - For a `:case` node → recurse on `node[2]` (the first `:when`).
   - For a `:when` node → collect `node[2]` (this branch's body)
     and recurse on `node[3]` (the next link).
   - For an `:else` node → collect `node[1]` (the else body) and
     stop.
   - For `nil` (no else) → stop.

Each collected body is walked through the existing
`each_json_call`, producing the union merge.

**Rationale**: Mirrors the existing `conditional_bodies` walk
for `:if` / `:elsif` / `:else`. A separate helper keeps the
case-specific recursion clean; alternatively we could fold it
into `conditional_bodies` with extra branches. Separate helper
is clearer — `:case` is a distinct shape.

**Alternatives considered**:
- *Extend `conditional_bodies` to handle `:case`/`:when`*: more
  branches in one method; less clear. Rejected.
- *Walk `:when` bodies but skip `:else`*: would lose properties
  declared only in the `else` branch. Rejected.

## R3. Block-vs-partial precedence

**Decision**: When a `json.<key>` call has BOTH a body block AND
a `partial:` option in its argument hash, the block takes
precedence. This matches jbuilder's runtime behavior (when the
block is present, jbuilder ignores `partial:`).

Implementation: `add_property`'s existing check `if call[:block]`
runs first; the new `partial:` branch only runs in the else
branch. Zero new logic needed beyond the new `partial:`
detection.

**Rationale**: Matches Rails reality. Avoids documenting a
shape the runtime wouldn't actually emit.

**Alternatives considered**:
- *Union the block's schema with the partial's schema*: misleading
  (the runtime emits only one of them). Rejected.
- *Prefer `partial:` over block when both present*: contradicts
  jbuilder runtime. Rejected.

## Test surface

Three unit-test additions to `spec/unit/jbuilder_parser_spec.rb`:

1. `json.<key> @c, partial: "name"` (no block) → resolves the
   partial and emits `{type: array, items: <partial schema>}`.
2. `json.<key> partial: "name"` (no block, no positional) →
   emits the partial's schema directly (single-object form).
3. `json.<key> @c, partial: "name" do |x| ... end` (block AND
   partial) → block wins.
4. `case x; when 1; json.a 1; when 2; json.b 2; else; json.c 3; end`
   → emits `{a, b, c}` (union of all branch keys).
5. `case x; when 1; json.a 1; when 2; json.b 2; end`
   (no else) → emits `{a, b}`.

One new partial fixture
(`spec/fixtures/dummy/app/views/api/activity_logs/_activity_log.json.jbuilder`)
plus a small index view that uses
`json.today_logs @c, partial: "activity_logs/activity_log", as: :activity_log`.
An existing controller can be repointed at the new view OR a
new controller can be added. Either way, one integration
assertion confirms the index endpoint's response body schema
shows `today_logs.items.properties.id` (and other partial keys).

## Quickstart (inline)

```bash
# Run the parser specs (should still pass before any change):
bundle exec rspec spec/unit/jbuilder_parser_spec.rb

# Write new failing test cases for the three partial shapes and
# the two case shapes (5 examples). Run — they fail.

# Apply the two production-code changes in
# lib/rails_openapi_generator/jbuilder_parser.rb:
#   1. add_property gains a `partial:` detection branch.
#   2. visit_statement + case_branch_bodies handle :case.
# Run — new tests pass.

# Run the full suite to confirm 471/471 + new examples still pass:
bundle exec rspec

# Lint:
bundle exec rubocop lib spec
```
