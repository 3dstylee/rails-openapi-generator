# Phase 0 Research: Resolve Constant References

The spec carried no `[NEEDS CLARIFICATION]` markers. Decisions
below were resolved against the existing codebase, the Constitution
(especially Principle II), and Ruby's autoload semantics before
writing the spec.

## R1. Lookup mechanism

**Decision**: `Object.const_get(qualified_name, true)` — the
canonical Ruby class-name-to-value lookup with autoload enabled.
The second argument `true` is the default but stated explicitly
for clarity ("yes, please autoload on demand").

**Rationale**: This is exactly what Rails uses internally to
resolve `String` → `Constant`, and what the generator's existing
`SourceLocator` does to load the controller class from
`route.controller_class_name`. The constitution's "no execution of
host actions" rule (Principle II) refers to running controller
*actions* — invoking the request lifecycle. Reading a constant
value via `const_get` is the same operation as loading a class:
it triggers autoload (potentially requiring a file), but does not
execute the action. The codebase has crossed this line for every
feature since 001.

**Alternatives considered**:
- *Parse the constant's defining file with Ripper and evaluate
  the assignment node*: pure static analysis but enormous in
  scope — every helper, every concern, every initializer that
  could affect the constant's value would need to be re-parsed.
  The resolver becomes a tiny Ruby interpreter. Rejected.
- *Resolve only when the controller's `_load_constants!` returns
  a flag*: nonexistent API; speculative. Rejected.

## R2. AST node shapes

**Decision**: Three node shapes:

| Source form | AST node |
|-------------|----------|
| `FOO` | `[:var_ref, [:@const, "FOO", [line, col]]]` |
| `A::B::CONST` | `[:const_path_ref, [:const_path_ref, [:var_ref, [:@const, "A", ...]], [:@const, "B", ...]], [:@const, "CONST", ...]]` |
| `::Foo` | `[:top_const_ref, [:@const, "Foo", [line, col]]]` |

The `:const_path_ref` shape is right-associative: `A::B::C` parses
as `((A::B)::C)`. To build the qualified name, walk the chain by
recursively unwrapping `:const_path_ref`'s left side and
collecting the `:@const` on the right.

**Rationale**: Verified against `Ripper.sexp` for each form (see
the plan's Technical Context for the literal output). These three
exhaust the syntactic forms of a constant reference; `:var_field`
and `:const_path_field` exist but only appear on the LHS of
assignment, which `param!` arguments never are.

**Alternatives considered**:
- *Pattern-match more shapes (`:var_field`, `:assign`)*: irrelevant
  for the `param!` argument-value context. Rejected.

## R3. Qualified name construction

**Decision**: A simple recursive helper:

```text
qualified_name(:var_ref → [:@const, "X", ...])      → "X"
qualified_name(:top_const_ref → [:@const, "X", ...]) → "X"
qualified_name(:const_path_ref → left, [:@const, "X", ...])
    → "#{qualified_name(left)}::X"
```

Top-level references and bare references produce identical
qualified names — `Object.const_get("X")` searches the top-level
namespace for both. This matches Ruby's semantics: a bare `X`
inside a class body would look up via the enclosing namespace
first, but `Object.const_get("X")` (no enclosing class) is
top-level.

**Rationale**: The generator never has access to the enclosing
namespace at the moment it evaluates a `param!` argument (the
parser sees the raw AST, not the lexical scope). Top-level
lookup is the conservative-but-correct choice for class-fully-
qualified references (which are the vast majority of real
usage — `Service::CONSTANT` is what real codebases write).

**Alternatives considered**:
- *Track the controller's namespace and resolve bare constants
  relative to it (`Api::FoosController` → `Api::FoosController::FOO`
  before `::FOO`)*: significantly more complex; the generator
  would need to thread the controller class through the evaluator,
  which it doesn't today. The win is marginal — `param!` calls
  rarely use bare constants that aren't top-level. Deferred.

## R4. Schema-compatible value check

**Decision**: Implement as a recursive predicate
`schema_compatible?(value)`:

| Value type | Compatible? |
|-----------|-------------|
| `String`, `Symbol`, `Integer`, `Float`, `TrueClass`, `FalseClass` | yes |
| `Range` whose `begin` and `end` are both `Integer` or both `Float` | yes |
| `Regexp` | yes |
| `Array` | yes if every element is schema-compatible (recursive) |
| `Hash` | yes if every key is `String`/`Symbol` and every value is schema-compatible (recursive) |
| anything else (class, Proc, instance, Struct, OpenStruct, IO, etc.) | no |

**Rationale**: This is the same set of types `LiteralEvaluator`
already produces from literal AST nodes (a literal `%w[a b]`
evaluates to `["a", "b"]`; a literal `1..100` to `1..100`; a
literal `/x/` to `/x/`; etc.). Letting the constant resolver
emit the same types keeps the downstream pipeline unchanged.

The recursive check on Arrays and Hashes is to refuse
"shape leakage" — a constant defined as `[User.new, User.new]`
would be `Array` but not safely-emittable, so we treat it as
UNRESOLVED.

**Alternatives considered**:
- *Accept ANY Array, emit `enum: <array.map(&:to_s)>`*: would
  succeed on Array-of-instances but emit `enum: ["#<User:...>",
  "#<User:...>"]` — meaningless. Rejected.
- *Pass through any Hash and stringify keys*: hidden serialization
  decisions, and downstream emitters may not handle arbitrary
  values. Stick to the narrow set.

## R5. Error handling

**Decision**: Wrap every `Object.const_get` call in a `rescue =>
e` that catches **every** `StandardError`, plus `LoadError`
(which is a `ScriptError`, not a `StandardError`). The rescued
result is the same UNRESOLVED sentinel `LiteralEvaluator`
already uses. The error is silently swallowed — no warning, no
log entry.

**Rationale**: The generator's job is best-effort static
documentation. A `NameError` (constant not loaded), `LoadError`
(autoload file missing or broken), `NoMethodError` (a chain
through a method, which shouldn't happen at this layer but might
if the AST shape is mis-classified), or anything else means
"can't resolve this safely" — exactly UNRESOLVED's purpose. The
existing "non-literal param! arguments" warning still fires for
that parameter (because `fully_resolved: false`), so the user
sees the same signal they see today.

Silent-on-failure is consistent with the existing literal
evaluator: a malformed AST node returns UNRESOLVED without
shouting.

**Alternatives considered**:
- *Emit a separate "constant unresolvable" warning*: doubles the
  warning channel for the same observable outcome ("we couldn't
  document this constraint"). Rejected.
- *Re-raise certain errors (e.g. cyclic load)*: a generator that
  raises mid-document because of an autoload edge case is worse
  than one that silently drops a constraint. Rejected.

## R6. Caching scope

**Decision**: One cache per `ConstantResolver` instance.
`Generator#setup_pipeline` constructs a fresh resolver each run
(same lifetime as the other pipeline components). The cache
key is the qualified name string; the value is either the
resolved Ruby value or `UNRESOLVED`. The cache is a plain Hash.

**Rationale**: Per-run scope means constants whose value changes
between runs (e.g. an integration test that redefines a constant)
are re-evaluated correctly. Per-instance lifetime keeps the
resolver lifecycle aligned with everything else in the pipeline.

A global / process-wide cache would survive across `generate`
calls but introduce a hard-to-debug "stale enum" bug if a
host application reloads constants. Rejected for that reason.

**Alternatives considered**:
- *Don't cache*: every `param!` reference to the same constant
  would re-autoload (cheap on second call thanks to Ruby's
  internal load tracking, but the schema-compatibility check
  would also re-run). Caching is the right defensive choice.

## R7. Where the resolver lives

**Decision**: `LiteralEvaluator` (a module today) gains a
module-level instance of `ConstantResolver`, lazily initialized
on first use and reset each generator run by
`Generator#setup_pipeline`.

Actually — refinement: `LiteralEvaluator.evaluate` is called
recursively from MANY places (param extraction, render
extraction, jbuilder parsing). Threading a resolver instance
through every callsite is intrusive. Two cleaner choices:

a) **Module-level resolver, swap-on-setup**: a class-level
`@@resolver` (or `LiteralEvaluator.resolver=`) that the
`Generator` sets at the start of each run. Pro: zero callsite
change. Con: global mutable state.

b) **Resolver passed into LiteralEvaluator**: change
`LiteralEvaluator.evaluate(node)` to
`LiteralEvaluator.evaluate(node, resolver: nil)` and thread it
through all callsites. Pro: explicit; testable in isolation.
Con: large diff across `param_extractor`, `render_extractor`,
`jbuilder_parser`.

**Decision**: Option (a) — module-level resolver, set by the
`Generator` at the start of each run, with a default
no-resolver mode that returns UNRESOLVED for constant nodes (so
unit specs that test `LiteralEvaluator` in isolation are
unaffected unless they explicitly set a resolver).

**Rationale**: Minimal-diff (Principle I). The single shared
resolver mirrors how `LiteralEvaluator` is already used (module
methods, no instance state). The "no resolver → UNRESOLVED"
default preserves byte-identity for unit specs that don't opt
into constant resolution.

**Alternatives considered**:
- *Option (b)*: cleaner architecturally but a much bigger diff.
  Rejected on YAGNI / minimal-diff grounds.
- *Always autoload on demand inside `LiteralEvaluator`* (no
  resolver indirection at all): hides the caching and the
  rescue policy inside the evaluator. The resolver-as-helper
  keeps the resolution policy in one place, testable.

## R8. Order of resolution within a Hash value

**Decision**: When `LiteralEvaluator.assoc_hash` evaluates an
option hash's values, each value (including a constant
reference) is evaluated independently and the result placed
into the hash. If a constant resolves to a non-schema-compatible
value, that single key gets UNRESOLVED while the rest of the
hash keeps its resolved values. The hash is treated as
UNRESOLVED only when EVERY key/value is UNRESOLVED, but the
existing `build_call` in `ParamExtractor` already flags the
whole `param!` call as non-fully-resolved if any option value
is UNRESOLVED — that behavior is preserved exactly.

**Rationale**: The existing fully-resolved logic doesn't need
changing. The constant resolver just plugs in at the leaf
level; everything aggregate keeps working.

## R9. Determinism

**Decision**: For a given host application code state, the same
generator run produces the same resolved values for the same
constant references. `Object.const_get` is deterministic given
unchanged host code. The cache makes repeated lookups
zero-work and consistent within one run.

**Rationale**: Constitution / Principle II / feature-010 FR-013.

**Alternatives considered**: none — Ruby's constant lookup IS
deterministic by construction.

## R10. Backward compatibility — operations without constant references

**Decision**: A `param!` call whose every argument was already
fully literal before this feature emits byte-identical output.
The new evaluator paths are touched ONLY when the AST contains
one of the three constant-reference node shapes. For literal
arrays, ranges, regexes, etc., the existing evaluator branches
fire as before.

**Rationale**: SC-004 — strict guarantee. Verified by the
existing `param_extractor_spec.rb` + `feature_001_regression_
spec.rb` suite remaining byte-identical.
