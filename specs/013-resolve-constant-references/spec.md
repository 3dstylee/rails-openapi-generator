# Feature Specification: Resolve Constant References

**Feature Branch**: `013-resolve-constant-references`

**Created**: 2026-05-20

**Status**: Draft

**Input**: User request: when a `param!` argument value is a constant
reference — `param! :mood, String, in: AutoPhotoVhs::EnqueueFurniture
GenerationService::MOODS` — the generator drops the constraint today
and emits the warning `non-literal param! arguments for mood`. The
fix is to resolve the constant via Ruby's normal lookup at generation
time and emit the actual values (`enum: ["modern", "classic",
"minimalist", "scandinavian", "industrial"]`) in the OpenAPI doc.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Document a `param!` `in:` enum drawn from a constant (Priority: P1)

A developer's controller does `param! :mood, String, in:
ServiceModule::MOODS` where `MOODS` is a frozen Array of Strings
defined elsewhere. When the document is generated, the `mood`
parameter's `schema` documents `enum: [<MOODS values>]` exactly,
and the "non-literal param! arguments" warning is no longer emitted
for that parameter.

**Why this priority**: This is the entire motivation. Constants are
the idiomatic way to define enum-like sets in Rails apps
(`MOODS`, `STATUSES`, `ROLES`, …); without resolution, the generator
silently drops the most useful constraint a typed client could
consume.

**Independent Test**: Generate the document for a controller whose
`param!` uses `in:` with a qualified constant whose value is a
literal Array. Confirm the parameter schema lists the constant's
values as the `enum` and that the warning is gone.

**Acceptance Scenarios**:

1. **Given** a constant `MOODS = %w[a b c].freeze` defined on a
   service class, and `param! :mood, String, in: ServiceModule::MOODS`
   in a controller, **When** the document is generated, **Then** the
   `mood` parameter's `schema.enum` is `["a", "b", "c"]`.
2. **Given** the same setup, **When** the document is generated,
   **Then** `GenerationReport.warnings` does NOT contain
   `"non-literal param! arguments for mood"` for that route.
3. **Given** a bare constant reference (`param! :x, Integer, in:
   MY_RANGE`) where `MY_RANGE = 1..100`, **When** the document is
   generated, **Then** the `x` parameter's schema documents
   `minimum: 1, maximum: 100` (the existing `param!` range handling
   continues to work, just sourced from the resolved constant).

---

### User Story 2 - Constants used in nested `param!` blocks (Priority: P2)

A developer's controller uses a nested `param!` block (feature 008)
whose inner declaration references the same constant — e.g.
`param! :moods, Array do |p, i|; p.param! i, String, in:
ServiceModule::MOODS; end`. When the document is generated, the
inner `items` schema documents the constant's `enum`, identical to
the top-level case in US1.

**Why this priority**: This is the exact second occurrence in the
user's reported case. Without it, the bulk-input form of the same
parameter would still drop the constraint.

**Acceptance Scenarios**:

1. **Given** the user's reported pattern (`param! :moods, Array,
   ... do |p, i|; p.param! i, String, in: ServiceModule::MOODS; end`),
   **When** the document is generated, **Then** the `moods` request
   body parameter documents `items: { type: "string", enum: [...] }`
   with the constant's values.
2. **Given** the same nested block, **When** the document is
   generated, **Then** the warning is silent for the nested
   parameter too.

---

### Edge Cases

- **Constant not loadable**: A `NameError` on
  `Object.const_get(qualified_name)` is treated as UNRESOLVED. The
  generator does NOT raise; today's warning continues to fire for
  that parameter.
- **Constant resolves to a non-literal value**: A constant whose
  value is a class, a Proc, an instance, a Struct, an Array
  containing non-schema-compatible elements, an Array of Hashes, or
  any other non-schema-compatible shape is treated as UNRESOLVED.
  Today's warning continues to fire.
- **Frozen vs. unfrozen Array**: Both work the same — `[1,
  2].freeze` and `[1, 2]` resolve identically. The `.freeze` method
  call in the source code (e.g. `MOODS = %w[a b c].freeze`) is not
  what's resolved; the resolved value is the constant's actual
  current value at the moment of `const_get`.
- **Constant initialized at runtime**: A constant assigned from a
  method call (`MOODS = Setting.fetch(:moods)`) resolves to whatever
  value that method returns in the generator's process. Documented
  as a known limitation — the generator emits whatever value the
  Rails boot process has set the constant to. If that value is
  schema-compatible, it's used; if not, UNRESOLVED.
- **Top-level constant** (`::MOODS`): resolved via
  `Object.const_get("MOODS")` the same as a bare reference.
- **Constant defined in an autoloaded path**: triggers autoload via
  `Object.const_get(name, true)`. If autoloading fails (`LoadError`
  / cyclic load / any `StandardError`), treated as UNRESOLVED.
- **Constant whose name shadows a method**: `Object.const_get` only
  looks up constants, so `Service.new.moods` (a method call) is
  unaffected — it's not parsed as a constant reference; it's a
  method-call AST node, which evaluates to UNRESOLVED today (and
  continues to).
- **Same constant referenced in many places**: cached per generator
  run — `Object.const_get` is called at most once per qualified
  name, so a repeated reference does not pay the autoload cost
  twice.
- **Hash constants**: `MIN_MAX = { min: 1, max: 100 }`. Resolved if
  the Hash's keys and values are themselves schema-compatible; used
  as the literal Hash value (`param!` constraint mapping handles
  the rest).
- **Constants referenced outside `param!`** (e.g. in `redirect_to`,
  `render`, `respond_to`): out of scope for v1. The feature
  resolves constants for `param!` arguments only.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST resolve a `:var_ref` AST node whose
  child is a `:@const` token (a bare top-level constant like
  `MOODS`) by calling `Object.const_get(name, true)` with autoload
  enabled.
- **FR-002**: The system MUST resolve a `:const_path_ref` AST node
  (`A::B::C`) by recursively reading the chain of constant names
  and calling `Object.const_get(qualified_name, true)`.
- **FR-003**: The system MUST resolve a `:top_const_ref` AST node
  (`::Foo`) by calling `Object.const_get(name, true)`.
- **FR-004**: The system MUST verify the resolved value's shape
  against the "schema-compatible" set before using it:
  - Array whose elements are all `String` / `Symbol` / `Integer` /
    `Float` / `true` / `false`.
  - Range whose ends are both `Integer` or both `Float`.
  - Regexp.
  - `String` / `Integer` / `Float` / `Symbol` (treated as String) /
    `true` / `false`.
  - Hash whose keys are all `String` or `Symbol` AND whose values
    are all themselves schema-compatible (recursive check).
- **FR-005**: When the resolved value's shape is NOT
  schema-compatible (a class, a Proc, an instance, an Array of
  Hashes, etc.), the system MUST treat it as UNRESOLVED — same as
  if the constant could not be loaded.
- **FR-006**: A `NameError` raised by `Object.const_get` MUST be
  rescued and the value treated as UNRESOLVED. Any `LoadError`,
  cyclic-load error, or other `StandardError` raised by the
  autoload chain MUST also be rescued; the generator never raises
  because of this feature.
- **FR-007**: Each qualified constant name MUST be resolved at most
  once per generator run. The cache lives in the
  `LiteralEvaluator` (or a sibling helper) and is reset between
  generator runs (per-process, per-run scope).
- **FR-008**: This feature applies to constants used as `param!`
  argument values — both top-level `param!` calls and the nested
  `p.param! ...` calls inside `param!` block forms (feature 008).
- **FR-009**: Constants referenced outside `param!` (`redirect_to`,
  `render`, `respond_to do |format|`, etc.) are out of scope for
  v1 and MUST continue to evaluate as UNRESOLVED.
- **FR-010**: When the constant resolves to a schema-compatible
  value AND the rest of the `param!` arguments are also literal, the
  parameter MUST be marked `fully_resolved: true`; the
  "non-literal param! arguments" warning MUST NOT fire for that
  parameter.
- **FR-011**: Generation MUST remain deterministic — the resolved
  value at the moment of generation is what's emitted. Repeated
  runs on unchanged input (and unchanged host code) produce
  identical output.
- **FR-012**: The OpenAPI document MUST continue to pass schema
  validation. An `enum` array drawn from a constant must be a JSON-
  serializable list of primitives.

### Key Entities *(include if feature involves data)*

- **Constant Reference**: An AST node — `:var_ref` carrying a
  `:@const`, `:const_path_ref` (multi-segment), or
  `:top_const_ref` — that names a Ruby constant.
- **Resolved Constant**: The Ruby value returned by
  `Object.const_get(qualified_name, true)`, when callable and when
  schema-compatible (FR-004). Sits alongside the existing literal-
  evaluation results in the same `LiteralEvaluator` pipeline.
- **Constant-Resolution Cache**: A per-generator-run map of
  qualified constant name → resolved value (or UNRESOLVED sentinel
  when the lookup failed or the shape was rejected). Prevents
  repeated `const_get` calls and ensures the same constant resolves
  the same way every time within one run.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A `param! :name, Type, in: Module::CONSTANT` whose
  constant is a literal Array of primitives is documented with that
  array as the parameter's `enum`.
- **SC-002**: A nested `p.param! i, Type, in: Module::CONSTANT`
  inside a `param!` block (feature 008) is documented identically
  — the inner items' schema includes the constant's enum.
- **SC-003**: The "non-literal param! arguments for X" warning is
  no longer emitted for a parameter whose only previously-
  unresolved argument was a schema-compatible constant reference.
- **SC-004**: Operations whose `param!` calls have always been
  fully literal in the source emit byte-identical output to
  `0.11.0` (no spurious changes from constant resolution).
- **SC-005**: A constant that cannot be loaded (NameError) or whose
  shape is not schema-compatible MUST NOT cause the generator to
  raise; the warning behavior is unchanged for that parameter, and
  the rest of the document is generated successfully.
- **SC-006**: Repeated runs on unchanged host code produce identical
  output, including the resolved enum order.

## Assumptions

- The generator is being executed in a process that has the host
  Rails application loaded (the standard rake task / CLI entry
  points already trigger this). Constants defined in the host
  application are reachable via `Object.const_get` once their
  defining file is autoloaded.
- "Schema-compatible" is defined narrowly (FR-004) to keep emission
  safe. Hashes nested deeper than one level are checked
  recursively; cycles in the constant value are not expected and
  not specially handled (Ruby itself prevents most such cycles).
- Resolution happens lazily — only constants actually referenced by
  a parsed `param!` argument are `const_get`'d. The generator does
  not eagerly walk the autoload table.
- The constant's value at generation time is what's documented. For
  constants computed from environment variables, settings, or
  database state, the documented value reflects the generator's
  environment — same as any constant initialized at Rails boot.
  This is consistent with how production would see the value at
  boot time; if the production environment differs from the
  generator's environment, the documented value will reflect the
  generator's view.
- Constants referenced from outside `param!` (in `render`,
  `redirect_to`, etc.) are deferred. A future feature can lift the
  scope; this v1 is narrowly aimed at the user's reported
  `param!` enum case to keep the autoload surface small.
- The cache scope is per-`Generator` instance: a new generator
  run starts with an empty cache, so constants whose values
  change between runs are re-evaluated.
- `Object.const_get(qualified_name, true)` is the canonical Ruby
  lookup path; it matches what Rails uses to resolve a class name
  passed as a string, and is consistent with the generator's
  existing controller-class lookup (`Object.const_get(route.
  controller_class_name)`).
