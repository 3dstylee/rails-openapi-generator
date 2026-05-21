# Implementation Plan: Resolve Constant References

**Branch**: `013-resolve-constant-references` | **Date**: 2026-05-20 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/013-resolve-constant-references/spec.md`

## Summary

Extend `LiteralEvaluator` to resolve three new AST node shapes
representing constant references:

- `:var_ref` carrying a `:@const` (bare `FOO`)
- `:const_path_ref` (`A::B::CONST`)
- `:top_const_ref` (`::Foo`)

For each, build the qualified name string, look up the value via
`Object.const_get(qualified_name, true)` (with autoload), and accept
the value when it's "schema-compatible" — Array of primitives,
Range, Regexp, primitive, or recursively-checked Hash. Otherwise
return `UNRESOLVED`. All lookups go through a new
`ConstantResolver` that caches results per-generator-run and rescues
every error to UNRESOLVED. The constant value flows back through
the existing `param!` argument pipeline unchanged — so a constant
that resolves to a literal Array of Strings becomes the `enum:` on
the parameter schema by the same logic that handles a literal array
written inline.

Technical approach: keep the change narrow. The only public surface
that changes is `LiteralEvaluator.evaluate` (gains three new node
cases) and a new `ConstantResolver` class with `resolve(name)` →
value-or-UNRESOLVED. The `param_extractor` already evaluates option
hashes via `LiteralEvaluator.evaluate` — once `LiteralEvaluator`
returns the resolved Array (or Range, etc.) for the constant
node, the existing schema-mapping code (`SchemaMapper`) handles the
rest. No `param_extractor`, no `schema_mapper`, no `Generator`
changes. No new dependency. No new configuration.

## Technical Context

**Language/Version**: Ruby 3.1+ (unchanged).

**Primary Dependencies**: `railties`, `yard` — **no new dependency**.
Constant resolution uses `Object.const_get`, which is part of Ruby
core. Rails autoload is invoked transparently when the constant's
defining file has not been required yet — same mechanism the
generator already uses to load the controller class.

**Storage**: N/A.

**Testing**: RSpec; the dummy Rails app fixture gains a service
module that defines several constants (one Array of Strings, one
Range, one Regexp, one unresolvable name, one non-schema-compatible
value) and a controller that references them in `param!` calls.
The existing `param!` test surface (features 001, 008) is extended
with literal vs. constant cases.

**Target Platform**: Ruby 3.1+ / Rails 7.0+ host applications.

**Project Type**: Ruby gem — library API + rake task + CLI (unchanged).

**Performance Goals**: One `Object.const_get` per unique qualified
constant name per generator run (cached). For a controller that
references the same constant in 5 `param!` calls, the autoload
runs once. The cache is a simple Hash; lookup is O(1).

**Constraints**: No execution of host actions or callbacks (per
Principle II). Reading constant values via `Object.const_get` is
NOT execution of an action — it's the same lookup mechanism the
generator already uses to load the controller class (and the same
mechanism Rails uses for any class-name-as-string). Documented as
an explicit decision in research R1. Generator MUST NOT raise
because of any constant-resolution failure (FR-006). Deterministic
output (FR-011); document still passes OpenAPI 3.1 validation.

**Scale/Scope**: Narrow extension to one existing class
(`LiteralEvaluator`) plus one new helper class (`ConstantResolver`).
Touches ~2 files in `lib/`, ~2 unit specs, 1 integration spec,
plus fixture additions.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Assessment | Status |
|-----------|------------|--------|
| I. Simplicity & YAGNI | One new class (`ConstantResolver`) with a tiny surface (one method, one cache field). `LiteralEvaluator` gains three new node cases, each ~5 lines. No new configuration, no new dependency, no public-API change. The schema-compatible set is the narrow set the param-call constraint surface already accepts; we are NOT adding new schema-emission rules. | PASS |
| II. Specification Correctness | The documented `enum:` matches the constant's actual value at generation time — same value Rails sees at boot. For constants computed at runtime from env/db, the spec records this as a known limitation (consistent with how the generator already handles the host environment). The fallback path (NameError → UNRESOLVED) keeps the document at least as correct as today (the warning continues to fire for that specific parameter, but no spurious `enum:` is emitted). | PASS |
| III. Test-First Discipline | Fixture-driven; the dummy app gains a service module with the constants and a controller that exercises each (schema-compatible Array, Range, Regexp, unresolvable name, non-schema-compatible value). Unit and integration specs cover each shape and the failure modes; tests fail before implementation lands. | PASS |
| IV. Dual Interface Parity | No public interface change — rake task, CLI, and library API all gain the same coverage through the shared `Generator`. | PASS |
| V. Versioned, Backward-Compatible Output | Operations whose `param!` calls have always been fully literal in the source emit byte-identical output to `0.11.0` (the new resolution path activates only for AST nodes whose evaluator previously returned UNRESOLVED). Operations whose `param!` calls referenced schema-compatible constants gain accurate enum/range/regexp documentation — a strict correctness improvement, released as a MINOR bump (0.12.0) with a CHANGELOG entry. Determinism preserved (FR-011). | PASS (change is versioned) |

No violations — Complexity Tracking section omitted.

*Post-design re-check (after Phase 1): the design adds one new
class with one method and one cache, plus three AST-node case
branches in `LiteralEvaluator`. The downstream pipeline (`param_
extractor`, `SchemaMapper`) is touched zero times. Constitution
Check still PASSES.*

## Project Structure

### Documentation (this feature)

```text
specs/013-resolve-constant-references/
├── plan.md              # This file
├── spec.md              # Feature specification
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/
│   └── constant-resolution-output.md
├── checklists/
│   └── requirements.md
└── tasks.md             # Phase 2 output (/speckit-tasks — not created here)
```

### Source Code (repository root)

```text
lib/rails_openapi_generator/
├── constant_resolver.rb        # NEW — wraps `Object.const_get`
│                               #   with the per-run cache, the
│                               #   schema-compatibility check, and
│                               #   the broad rescue (NameError,
│                               #   LoadError, any StandardError →
│                               #   UNRESOLVED). One public method:
│                               #   `resolve(qualified_name)`.
├── literal_evaluator.rb        # MODIFIED — three new node cases:
│                               #   `:var_ref` carrying `:@const`,
│                               #   `:const_path_ref`,
│                               #   `:top_const_ref`. Each builds the
│                               #   qualified name string and delegates
│                               #   to the resolver. Existing literal
│                               #   resolution paths unchanged.
├── param_extractor.rb          # UNCHANGED — `LiteralEvaluator.evaluate`
│                               #   already runs on the option hash; the
│                               #   resolved Array (or Range, etc.) flows
│                               #   in through the existing path.
├── schema_mapper.rb            # UNCHANGED — already maps Array →
│                               #   `enum:`, Range → `minimum:`/
│                               #   `maximum:`, Regexp → `pattern:`.
└── rails_openapi_generator.rb  # MODIFIED — require the new file.

spec/
├── unit/
│   ├── literal_evaluator_spec.rb         # MODIFIED — constant-node cases
│   ├── constant_resolver_spec.rb         # NEW — resolver behavior:
│   │                                     #   cached lookup, error rescue,
│   │                                     #   schema-compatibility filter
│   └── param_extractor_spec.rb           # MODIFIED — integration with
│                                         #   the new evaluator path
├── integration/
│   └── constant_references_spec.rb       # NEW — end-to-end coverage
│                                         #   for US1/US2 + edge cases
└── fixtures/dummy/
    ├── app/services/
    │   └── auto_photo_vhs/
    │       └── enqueue_furniture_generation_service.rb   # NEW — defines
    │                                                     #   MOODS, RANGE,
    │                                                     #   PATTERN, etc.
    └── app/controllers/api/
        └── constant_references_controller.rb            # NEW — actions
                                                         #   using each
                                                         #   constant in
                                                         #   param!.
```

**Structure Decision**: One new class with one method
(`ConstantResolver#resolve`), three new node cases in
`LiteralEvaluator`. The `param!` pipeline is unchanged because
once `LiteralEvaluator` returns a real Ruby value (instead of
UNRESOLVED), all the downstream constraint mapping already
handles it correctly — it's been doing so for inline literal
arrays for the lifetime of the gem. The resolver lives in
`LiteralEvaluator`'s namespace conceptually (it's invoked from
there), but is its own file so the resolver-specific concerns
(autoload, rescue, cache) are testable in isolation.

## Complexity Tracking

No constitution violations — section intentionally empty. The
feature is intentionally narrow: one new class, three new AST
cases, no changes to the downstream pipeline. The autoload
surface is limited to constants actually referenced by parsed
`param!` arguments — lazy, opt-in via source-code reference.
