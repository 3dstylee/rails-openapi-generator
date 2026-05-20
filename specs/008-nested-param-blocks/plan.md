# Implementation Plan: Nested Parameter Blocks

**Branch**: `008-nested-param-blocks` | **Date**: 2026-05-20 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/008-nested-param-blocks/spec.md`

## Summary

Detect `param!` of type `Hash` / `Array` that carry a `do |q| ...
end` block, walk the block body for `<blockvar>.param! ...` calls,
and build a recursive parameter schema: a `Hash` with a block becomes
an `object` schema whose `properties` are the nested declarations;
an `Array` with a block becomes an `array` schema whose `items` is
the (single) nested declaration. Recursion is bounded by the
existing `Configuration#method_resolution_depth` setting (per the
spec's assumption — no new configuration). The change is purely
additive: a `param!` with no block, or a block on a `String` /
other type, emits today's output unchanged (SC-005 / FR-009).

Technical approach: extend `ParamExtractor` so its `find_param_calls`
walker (a) detects the `:method_add_block` form of `param!` (today
it only matches `:command` and `:method_add_arg`), and (b) when a
match is `Hash` / `Array` with a block, captures the block's parameter
name(s) and recursively scans the block body for
`<blockvar>.param! ...` calls (the `:command_call` AST shape). Each
nested call resolves through the existing `LiteralEvaluator` —
which means feature 013's constant resolution applies automatically
to nested-block `in:` constraints (no extra work). The flat
`ParamCall` struct gains an optional `nested:` tree-shaped field
that `OperationBuilder` reads to build the OpenAPI `properties:` /
`items:` schema. No new top-level class.

## Technical Context

**Language/Version**: Ruby 3.1+ (unchanged).

**Primary Dependencies**: `railties`, `yard` — **no new dependency**.
Detection reuses the existing `Ripper` AST walker and
`LiteralEvaluator` (including feature 013's `ConstantResolver` for
nested `in:` arguments that reference constants).

**Storage**: N/A.

**Testing**: RSpec; the dummy Rails app fixture gains a controller
with: a `Hash`-with-block param exercising nested scalar fields;
an `Array`-with-block param exercising nested item declarations
(including the user's reported case — an Array of String items
whose `in:` references a constant); deeply-nested cases for US3;
no-block / non-Hash-Array-block cases for the regression
assertions (FR-007/008/009).

**Target Platform**: Ruby 3.1+ / Rails 7.0+ host applications.

**Project Type**: Ruby gem — library API + rake task + CLI
(unchanged).

**Performance Goals**: One additional AST walk per `param!` with a
block. Recursion is bounded by `method_resolution_depth` (default
5), so worst-case depth is constant. No new I/O.

**Constraints**: No execution of host actions (Principle II);
deterministic output (FR-009 implies — and the integration spec
will assert byte-stability); existing flat `param!` endpoints
emit byte-identical output (SC-005); document still passes
OpenAPI 3.1 validation, including nested-property schemas.

**Scale/Scope**: Narrow extension to one existing class
(`ParamExtractor`) plus a one-field addition on `ParamCall` (the
existing struct) plus a corresponding emission branch in
`OperationBuilder`. No new top-level class. Touches ~2 files in
`lib/`, ~2 unit specs, 1 integration spec, plus fixture additions.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Assessment | Status |
|-----------|------------|--------|
| I. Simplicity & YAGNI | One field on `ParamCall` (`nested:`), one new method-add-block detection arm in `ParamExtractor`, one emission branch in `OperationBuilder`. No new class, no new dependency, no new configuration setting (the depth bound reuses `method_resolution_depth` per the spec's recorded assumption). | PASS |
| II. Specification Correctness | Documents the actual shape of structured request parameters that today are emitted as bare objects/arrays. Nested constraint mapping reuses the existing flat-`param!` rules — same `enum:` / `minimum:` / `maximum:` / `pattern:` logic, including feature 013's constant resolution for `in:` values. Bounded recursion is the safety guarantee. | PASS |
| III. Test-First Discipline | Fixture-driven; the dummy app gains a `nested_params_controller.rb` with one action per scenario (Hash/Array/deep/no-block/non-Hash-block/constant-`in:`-inside-block). Unit and integration specs are written before implementation, asserting both presence (new property/items entries) and absence (no regression on flat `param!`). | PASS |
| IV. Dual Interface Parity | No public interface change — rake task, CLI, and library API all gain the same coverage through the shared `Generator`. | PASS |
| V. Versioned, Backward-Compatible Output | Operations whose `param!` calls have no block (or have a block on a `String`/other non-Hash-Array type) emit byte-identical output to `0.12.0` (SC-005). Operations whose `param!` of `Hash`/`Array` carries a block gain accurate nested property / item schemas — a strict correctness improvement, released as a MINOR bump (0.13.0) with a CHANGELOG entry. Determinism preserved. | PASS (change is versioned) |

No violations — Complexity Tracking section omitted.

*Post-design re-check (after Phase 1): the design adds one optional
field to one existing struct, one detection arm in `ParamExtractor`,
and one emission branch in `OperationBuilder`. Zero changes to
`LiteralEvaluator`, `ConstantResolver`, `SchemaMapper`, or the
response pipeline. Constitution Check still PASSES.*

## Project Structure

### Documentation (this feature)

```text
specs/008-nested-param-blocks/
├── plan.md              # This file
├── spec.md              # Feature specification
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/
│   └── nested-param-output.md
├── checklists/
│   └── requirements.md
└── tasks.md             # Phase 2 output (/speckit-tasks — not created here)
```

### Source Code (repository root)

```text
lib/rails_openapi_generator/
├── param_extractor.rb          # MODIFIED — `param_bang_args` gains a
│                               #   `:method_add_block` arm so a `param!`
│                               #   with a block is detected; new
│                               #   `extract_nested_params` walks the
│                               #   block's body for `:command_call`
│                               #   nodes whose receiver matches the
│                               #   captured block-var name; recursive
│                               #   bounded by `method_resolution_depth`.
├── operation_builder.rb        # MODIFIED — `build_request_body` and
│                               #   `build_parameters` consult the new
│                               #   `ParamCall#nested` tree to emit
│                               #   `properties:` for an object param and
│                               #   `items:` for an array param.
├── schema_mapper.rb            # UNCHANGED — each nested ParamCall maps
│                               #   to a flat schema via today's rules;
│                               #   the tree is assembled at the
│                               #   OperationBuilder layer.
├── literal_evaluator.rb        # UNCHANGED — nested `in:` arguments
│                               #   pass through the same evaluator,
│                               #   so feature 013's constant resolution
│                               #   applies to nested constraints
│                               #   automatically.
└── configuration.rb            # UNCHANGED — the existing
                                #   `method_resolution_depth` setting
                                #   bounds nesting recursion.

spec/
├── unit/
│   ├── param_extractor_spec.rb              # MODIFIED — nested-block cases
│   ├── operation_builder_spec.rb            # MODIFIED — properties/items
│   │                                        #   emission cases (or extended
│   │                                        #   integration coverage)
│   └── schema_mapper_spec.rb                # UNCHANGED unless a test
│                                            #   referenced flat behavior
├── integration/
│   └── nested_param_blocks_spec.rb          # NEW — end-to-end coverage
│                                            #   for US1/US2/US3 + edge
│                                            #   cases + the user's
│                                            #   reported MOODS case
└── fixtures/dummy/
    └── app/controllers/api/
        └── nested_params_controller.rb       # NEW — actions exercising
                                              #   each nested-block shape.
```

**Structure Decision**: The flat `ParamCall` struct gains one
optional field — `nested:` — that carries either `nil` (today's
behavior, a flat parameter) or a small tree describing nested
declarations. For a `Hash` with a block: `nested` is a list of
nested `ParamCall`s. For an `Array` with a block: `nested` is a
single nested `ParamCall` representing the item schema. Recursion
bottoms out naturally: a nested `ParamCall` whose own type is
`Hash`/`Array` with its own block carries its own `nested` field.
`OperationBuilder` reads the tree at emission time to build
`properties:` / `items:` schemas; everything else in the pipeline
is unchanged.

## Complexity Tracking

No constitution violations — section intentionally empty. The
feature is intentionally narrow: one detection arm on one existing
walker, one optional field on one existing struct, one emission
branch in one existing class. Recursion is bounded by an existing
configuration setting; constant resolution inside nested
constraints is inherited from feature 013 with zero extra wiring.
